#!/usr/bin/env bash

TFVARS=./terraform/.auto.tfvars

# get our project-ID
avn_pg_svc_project_id=$(awk -F "= " '/avn_pg_svc_project_id/ {print $2}' ${TFVARS} | sed 's/"//g')

# get our kafka service vars
avn_kafka_svc_name=$(awk -F "= " '/avn_kafka_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')
avn_kafka_svc_fq_name="$(awk -F "= " '/avn_kafka_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"
avn_kafka_connector_svc_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
avn_kafka_connector_svc_fq_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"

# get our postgres service vars
avn_pg_svc_name="$(awk -F "= " '/avn_pg_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
avn_pg_svc_fq_name="$(awk -F "= " '/avn_pg_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"

echo "#############################################"
echo avn_pg_svc_project_id: $avn_pg_svc_project_id
echo avn_kafka_svc_name: $avn_kafka_svc_name
echo avn_kafka_svc_fq_name: $avn_kafka_svc_fq_name
echo avn_kafka_connector_svc_name: $avn_kafka_connector_svc_name
echo avn_pg_svc_name: $avn_pg_svc_name
echo avn_pg_svc_fq_name: $avn_pg_svc_fq_name
echo "#############################################"

# postgres
avn_pg_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_pg_svc_name | awk '{print $2}')"

echo
echo "executing pgmetrics command:"

# ref: https://pgmetrics.io/docs/invoke.html
PGPASSWORD=$avn_pg_svc_password PGSSLMODE=require PGDATABASE=defaultdb PGUSER=avnadmin pgmetrics -h $avn_pg_svc_fq_name -p 24947 --no-sizes 

