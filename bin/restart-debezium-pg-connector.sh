#!/bin/bash
#set -x

# Restarts our Project's Debezium PG connector

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
avn_kafka_svc_fq_name="$(awk -F "= " '/avn_kafka_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"
avn_kafka_connector_svc_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
avn_kafka_connector_svc_fq_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"

echo "#############################################"
echo avn_pg_svc_project_id: $avn_pg_svc_project_id
echo avn_kafka_svc_name: $avn_kafka_svc_name
echo avn_kafka_svc_fq_name: $avn_kafka_svc_fq_name
echo avn_kafka_connector_svc_name: $avn_kafka_connector_svc_name
echo "#############################################"

# kafka
avn_kafka_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_kafka_svc_name | awk '{print $2}')"

# kafka connector
avn_kafka_connector_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_kafka_connector_svc_name | awk '{print $2}')"

echo
echo "Show Debezium Kafka Connectors:"
echo
curl -s "https://avnadmin:$avn_kafka_connector_svc_password@$avn_kafka_connector_svc_fq_name:443/connectors?"

# from gitter 
# https://kafka.apache.org/documentation/#connect_rest, specifically the endpoint /connector/<name>/restart
# does he mean 'connectors' with a plural as we see works in above command? even tho nothing exists dont get error
echo
echo "Restart Debezium Connector:"
echo
curl -s "https://avnadmin:$avn_kafka_connector_svc_password@$avn_kafka_connector_svc_fq_name:443/connectors?/$avn_kafka_connector_svc_name/restart"
echo

