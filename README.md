# Automated Debezium Kafka PostgreSQL Test ENV Deployment

#### OVERVIEW
Deploys and configures a __test/validation__ environment for the Debezium (PostgreSQL) connector with Kafka service integration
- I.e.: this project deploys and configures:
  - Kafka service 
    - with a test topic: `demo-topic`
  - Kafka Connector service
  - PostgreSQL service

#### NOTE: For Test/Validation Use Only
- Not suitable for environments higher than test/dev
- This project's Terraform does not leverage remote encrypted locking statefiles, etc.


###### For more information please see: 
- [Aiven Help Docs: setting-up-debezium-with-aiven-for-postgresql](https://help.aiven.io/en/articles/1790791-setting-up-debezium-with-aiven-for-postgresql)

#### REQUIREMENTS

- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) ver 14.x+ installed
- `avien-client` (latest version) installed and configured for use with an [Aiven Authentication token](https://help.aiven.io/en/articles/2059201-authentication-tokens)

  - So, your Aiven Cli config files should look like:
    ```console
    cat ~/.config/aiven/aiven-client.json 
    {
        "default_project": "test-debezium"
    }

    cat ~/.config/aiven/aiven-credentials.json | sed 's/{//g; s/}//g'
    {
        "auth_token": "YOUR_AIVEN_SERVICE_TOKEN_HERE"
        "user_email": "firstname.lastname@company.org"
    }
    ```
  - Note for more information about token use, please see [aiven-client#authenticate-logins-and-tokens](https://github.com/aiven/aiven-client#authenticate-logins-and-tokens)

- Now update the `avn_api_token` variable in the `/terraform/.secrets.tfvars` file
  with your Aiven token (which you just configured in the above step).
  You can just rename the sample file: `cd ./terraform && mv .secrets.tfvars.example .secrets.tfvars` and update it with your token.

#### OPTIONAL
- [tfenv](https://github.com/tfutils/tfenv)

#### TL;DR: Deploy the infrastructure via wrapper script
- You only need to execute one wrapper script which should deploy and configure all requisite resources.
```console
./bin/deploy-terraform-infra.sh
```
#### Kafka Tools 
##### Conduktor Configuration
- We will use [conduktor](https://www.conduktor.io/download/) to create the requisite PKS12 cert keystore and generate random data to the `demo-topic` kafka topic that our terraform created--(see the kafka_connect module).
  - Follow the below steps after running the `deploy-terraform-infra.sh` script.
  - [Download and install the conduktor kafka tool](https://www.conduktor.io/download/)
  - Follow the [Conduktor Cluster Connection docs](https://docs.conduktor.io/kafka-cluster-connection/setting-up-a-connection-to-kafka); it's as simple as pointing the conduktor application to the:
    - `ca.pem`
    - `service.cert`
    - `service.key`
  files in the: `./kafka-config/project-certs` directory.
- Producer: configure the topic for `demo-topic` set `Flow` `Automatic` and select data type, then `Start Producing`.
- Select `Consumer` and topic: `demo-topic` and `Start`.
- We are now producing to and consuming from our `demo-topic`.


##### TODO
- document triggering maintenance and or fail-over events with scaling up/down
- add bug/issue validation process
- add a top-level `DESTROY` ENV wrapper script