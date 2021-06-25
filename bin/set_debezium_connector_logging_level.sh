
TFVARS=./terraform/.auto.tfvars

avn_pg_svc_project_id=$(awk -F "= " '/avn_pg_svc_project_id/ {print $2}' ${TFVARS} | sed 's/"//g')


avn_kafka_connector_svc_name="$(awk -F "= " '/avn_kafka_connector_svc_name/ {print $2}' ${TFVARS} | sed 's/"//g')"
avn_kafka_connector_svc_password="$(avn service user-list --format '{username} {password}' --project $avn_pg_svc_project_id $avn_kafka_connector_svc_name | awk '{print $2}')"

pushd ./terraform/kafka_connect/
avn_kafka_connector_svc_fq_name=$(terraform state pull | jq -r --arg avn_kafka_connector_svc_name "$avn_kafka_connector_svc_name" '.resources[] | select(.name == "kafka_connect") | .instances[] | select(.attributes.service_name == $avn_kafka_connector_svc_name).attributes.service_host')
popd

echo
echo "Current logging levels:"
echo
curl https://avnadmin:$avn_kafka_connector_svc_password@$avn_kafka_connector_svc_fq_name:443/admin/loggers
echo

if [ -z "$2" ] || [ -z "$1" ]
  then
    echo
    echo "To set the log level of a logger, use: ./bin/set_debezium_connector_logging_level.sh LOGGER LEVEL"
    exit 1
fi

echo
echo "Setting log level of logger $1 to $2"
curl -H "Content-type:application/json" -X PUT -d '{"level": "'$2'"}' https://avnadmin:$avn_kafka_connector_svc_password@$avn_kafka_connector_svc_fq_name:443/admin/loggers/$1
echo
