import os


def get_pg_and_kafka_connection_info():
    """Get pg and kafka connection information from the terraform state
    """
    config = dict()

    # First, open .auto.tfvars file to get the service names
    file1 = open("terraform/.auto.tfvars", "r")
    lines = file1.readlines()
    for line in lines:
        line = line.strip()
        if not "=" in line:
            continue
        configs = line.split("=")
        if "#" in configs[1]:
            configs[1] = configs[1].split("#")[0]
        configs[1] = configs[1].replace("\"", "")
        config[configs[0].strip()] = configs[1].strip()

    pg_service_name = config["avn_pg_svc_name"]
    kafka_service_name = config["avn_kafka_svc_name"]
    #kafka_connect_service_name = config["avn_kafka_connector_svc_name"]

    # Save current working directory to return later
    current_dir = os.getcwd()

    # Now change the directory
    os.chdir("terraform/kafka_connect/")
    stream = os.popen(
        f"terraform state pull | jq -r '.resources[] | select(.name == \"kafka-service\") | .instances[] | select(.attributes.service_name == \"{kafka_service_name}\").attributes.service_uri'"
    )
    kafka_broker_uri = stream.read().strip()
    os.chdir(current_dir)

    os.chdir("terraform/postgres/")
    stream = os.popen(
        f"terraform state pull | jq -r '.resources[] | select(.name == \"avn-us-pg\") | .instances[] | select(.attributes.service_name == \"{pg_service_name}\").attributes.service_uri'"
    )
    pg_uri = stream.read().strip()
    os.chdir(current_dir)

    return kafka_broker_uri, pg_uri, config
