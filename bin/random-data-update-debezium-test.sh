#!/bin/bash

# Note: placeholder this might not be needed if we move fwd with the python testing scripts not yet merged

TFVARS=./terraform/.auto.tfvars

# get our project-ID
avn_pg_svc_project_id=$(awk -F "= " '/avn_pg_svc_project_id/ {print $2}' ${TFVARS} | sed 's/"//g')

# get our postgres service vars
avn_pg_svc_name="$(awk -F "= " '/avn_pg_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
avn_pg_svc_fq_name="$(awk -F "= " '/avn_pg_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')-${avn_pg_svc_project_id}.aivencloud.com"

# get our postgres password
avn_pg_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_pg_svc_name | grep 'avnadmin' | awk '{print $2}')"

# test script for below for running during triggering maint update and debezium outage
for i in {1000..1}; do 
    echo "count: $i"
    PGPASSWORD=$avn_pg_svc_password psql -h $avn_pg_svc_fq_name -U avnadmin -d defaultdb -p 24947 -c "INSERT INTO employees.employee(id, birth_date, first_name, last_name, gender, hire_date)
    SELECT floor(random() * 10 + 10010)::int, clock_timestamp(), 'testFirst', 'testLast', 'M', clock_timestamp();"
    sleep .5
done
