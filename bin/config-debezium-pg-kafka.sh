#!/bin/bash
#set -x

## USAGE: this script is called by the `deploy-terraform-infra.sh` script

## OVERVIEW - see README.md file

## Parse our vars file for requisite vars for use for postgres and kafka etc
# Notes
#   We could also get requisite data from:
#     the statefile info using `terraform state pull | jq . | grep 'host' | grep 'aivencloud.com'`
#     `anv service` commands (but since we have deployed the infra with Terraform we simply use the TF vars file.)
TFVARS=./terraform/.auto.tfvars

# get our project-ID
avn_pg_svc_project_id=$(awk -F "= " '/avn_pg_svc_project_id/ {print $2}' ${TFVARS} | sed 's/"//g')

# get our kafka service vars
avn_kafka_svc_name=$(awk -F "= " '/avn_kafka_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')
avn_kafka_connector_svc_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"

# For the FQDN let's pull from the TF state because we may be using a dev environment so the domain will end with `avns.net` instead of `aivencloud.com`
# The port seems to be different for every service so let's also fetch that from the TF state
pushd ./terraform/kafka_connect/
# Note, had to use jq's --arg to pass in the bash variable avn_pg_svc_name (https://stackoverflow.com/a/40027637)
avn_kafka_svc_fq_name=$(terraform state pull | jq -r --arg avn_kafka_svc_name "$avn_kafka_svc_name" '.resources[] | select(.name == "kafka-service") | .instances[] | select(.attributes.service_name == $avn_kafka_svc_name).attributes.service_host')
avn_kafka_connector_svc_fq_name=$(terraform state pull | jq -r --arg avn_kafka_connector_svc_name "$avn_kafka_connector_svc_name" '.resources[] | select(.name == "kafka_connect") | .instances[] | select(.attributes.service_name == $avn_kafka_connector_svc_name).attributes.service_host')
popd

# get our postgres service vars
avn_pg_svc_name="$(awk -F "= " '/avn_pg_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
pushd ./terraform/postgres/
avn_pg_svc_fq_name=$(terraform state pull | jq -r --arg avn_pg_svc_name "$avn_pg_svc_name" '.resources[] | select(.name == "avn-us-pg") | .instances[] | select(.attributes.service_name == $avn_pg_svc_name).attributes.service_host')
avn_pg_svc_port=$(terraform state pull | jq -r --arg avn_pg_svc_name "$avn_pg_svc_name" '.resources[] | select(.name == "avn-us-pg") | .instances[] | select(.attributes.service_name == $avn_pg_svc_name).attributes.service_port')
popd

echo $avn_kafka_svc_name $avn_kafka_connector_svc_name $avn_kafka_svc_fq_name $avn_kafka_connector_svc_fq_name $avn_pg_svc_name $avn_pg_svc_fq_name $avn_pg_svc_port

echo "#############################################"
echo avn_pg_svc_project_id: $avn_pg_svc_project_id
echo avn_kafka_svc_name: $avn_kafka_svc_name
echo avn_kafka_svc_fq_name: $avn_kafka_svc_fq_name
echo avn_kafka_connector_svc_name: $avn_kafka_connector_svc_name
echo avn_pg_svc_name: $avn_pg_svc_name
echo avn_pg_svc_fq_name: $avn_pg_svc_fq_name
echo "#############################################"

# required if we need to get the cert to later exec kafka commands
avn service user-creds-download --project $avn_pg_svc_project_id --username avnadmin -d ./service-creds $avn_kafka_svc_name

## Get passwords for each requisite svc

# kafka
avn_kafka_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_kafka_svc_name | awk '{print $2}')"

# kafka connector
avn_kafka_connector_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_kafka_connector_svc_name | awk '{print $2}')"

# postgres
avn_pg_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_pg_svc_name | grep 'avnadmin' | awk '{print $2}')"

echo
echo "Uncomment the below lines to show the sensitive passwords"
#echo avn_kafka_svc_password: $avn_kafka_svc_password
#echo avn_kafka_connector_svc_password: $avn_kafka_connector_svc_password
#echo avn_pg_svc_password: $avn_pg_svc_password
echo

## Kafka
echo "kafka topics service update cmd"
# Setting up the topics
# There are two ways to set up the needed Kafka topics.
# The simpler way is to set the service to create topics automatically by running:
avn service update $avn_kafka_svc_name -c "kafka.auto_create_topics_enable=true"
# Note: the other way of setting the topics up is to create them manually beforehand.

echo
echo "Create the publication on the target database before configuring the connector"
echo "Install the aiven-extras extension and create a publication for all tables:"
# Install the aiven-extras extension:
PGPASSWORD=$avn_pg_svc_password psql -h $avn_pg_svc_fq_name -U avnadmin -d defaultdb -p $avn_pg_svc_port -c "CREATE EXTENSION aiven_extras CASCADE; SELECT * FROM aiven_extras.pg_create_publication_for_all_tables('dbz_publication', 'INSERT,UPDATE,DELETE');"

echo "Create a heartbeat table in order to use the heartbeat.action.query config which is what the customer was using. Heartbeats are needed to control the WAL disk space consumption. This Debezium blog post has more detailed information: https://debezium.io/blog/2020/02/25/lessons-learned-running-debezium-with-postgresql-on-rds/"
echo ""
PGPASSWORD=$avn_pg_svc_password psql -h $avn_pg_svc_fq_name -U avnadmin -d defaultdb -p $avn_pg_svc_port -c "CREATE TABLE IF NOT EXISTS public.heartbeat (id SERIAL PRIMARY KEY, updated_at timestamp without time zone DEFAULT now());"

echo "Now setting up the Debezium Connector with 'heartbeats'"
echo "Calling into the Kafka service's Kafka Connect REST API..."
echo -n "Note: if the Debezium connection has already been configured you may see a '409 kafka-connector already exists' error. "
echo "Disregard these errors and proceed"
echo

# Create the connector which uses heartbeats (as our customer also uses this setting)
# and consumes from a single test table
curl -H "Content-type:application/json" -X POST https://avnadmin:$avn_kafka_connector_svc_password@$avn_kafka_connector_svc_fq_name:443/connectors -d '{
"name": "'"$avn_kafka_connector_svc_name"'",
"config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "'"$avn_pg_svc_fq_name"'",
    "database.port": "'"$avn_pg_svc_port"'",
    "database.user": "avnadmin",
    "database.password": "'"$avn_pg_svc_password"'",
    "database.dbname": "defaultdb",
    "database.server.name": "'"$avn_pg_svc_name"'",
    "table.include.list": "public.test",
    "plugin.name": "pgoutput",
    "database.sslmode": "require",
    "heartbeat.topics.prefix": "heartbeats",
    "heartbeat.interval.ms": 10000,
    "heartbeat.action.query": "insert into heartbeat (id, updated_at) values (1, now()) on conflict (id) do update set updated_at = now();",
    "topic.creation.default.cleanup.policy": "delete",
    "topic.creation.default.retention.ms": 1800000,
    "topic.creation.default.replication.factor": 2,
    "topic.creation.default.partitions": 1,
    "_aiven.restart.on.failure": "true"
  }
}'

echo
echo
echo "Monitoring our PostgreSQL Replication Slots:"
echo
echo "Show PG replication slots and their status--we should see 't' (true) under the 'active' column for each slot"
PGPASSWORD=$avn_pg_svc_password psql -h $avn_pg_svc_fq_name -U avnadmin -d defaultdb -p $avn_pg_svc_port -c "select * from pg_replication_slots"
echo

echo "Show/monitor how much lag we have behind the slots:"
PGPASSWORD=$avn_pg_svc_password psql -h $avn_pg_svc_fq_name -U avnadmin -d defaultdb -p $avn_pg_svc_port -c "SELECT redo_lsn, slot_name,restart_lsn,
round((redo_lsn-restart_lsn) / 1024 / 1024 / 1024, 2) AS GB_behind
FROM pg_control_checkpoint(), pg_replication_slots;"
echo
