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
- Producing to and consuming from our kafka `demo-topic`.
- We procide an example below using the Conduktor application/tool.  It is not required, but recommended.  Feel free to use the tools and methods of your choice.
##### Conduktor Configuration
- We will use [conduktor](https://www.conduktor.io/download/) to create the requisite PKCS12 cert keystore and generate random data to the `demo-topic` kafka topic that our terraform created--(see the kafka_connect module).
  - Follow the below steps after running the `deploy-terraform-infra.sh` script.
  - [Download and install the conduktor kafka tool](https://www.conduktor.io/download/)
  - Follow the [Conduktor Cluster Connection docs](https://docs.conduktor.io/kafka-cluster-connection/setting-up-a-connection-to-kafka); it's as simple as pointing the conduktor application to the:
    - `ca.pem`
    - `service.cert`
    - `service.key`
  files in the: `./kafka-config/project-certs` directory.
  - Conduktor will create the PKCS12 keystore.
- Producer: configure the topic for `demo-topic` set `Flow` `Automatic` and select data type, then `Start Producing`.
- Select `Consumer` and topic: `demo-topic` and `Start`. 
- We should now see that we are both producing to and consuming from our kafka `demo-topic`.

#### Monitoring our PostgreSQL Replication Slots
- Note these commands are run in the `config-debezium-pg-kafka.sh` script that is called by the `deploy-terraform-infra.sh` script.

- Show the PG replication slots and their status--we should see 't' (true) under the 'active' column for each slot.
  ```console
  SELECT * from pg_replication_slots;
  ```

- Show/monitor how much lag we have behind the slots:
  ```console
  SELECT redo_lsn, slot_name,restart_lsn, 
  round((redo_lsn-restart_lsn) / 1024 / 1024 / 1024, 2) AS GB_behind 
  FROM pg_control_checkpoint(), pg_replication_slots;
  ```


#### Possible Intermittent Known Issues
- Saw this a couple of times where TF errors-out with creating `resource "aiven_kafka_topic" "demo-topic"`
- Looked like timeout issue? `context deadline exceeded`

```console
aiven_kafka_topic.demo-topic: Still creating... [40s elapsed]
aiven_kafka_topic.demo-topic: Still creating... [50s elapsed]

Error: error waiting for Aiven Kafka topic to be ACTIVE: context deadline exceeded

  on services.tf line 52, in resource "aiven_kafka_topic" "demo-topic":
  52: resource "aiven_kafka_topic" "demo-topic" {
```
- Note that immediately re-executing the top-level `./bin/deploy-terraform-infra.sh` script it deployed/created the topic without issue.
```console
aiven_kafka_topic.demo-topic is tainted, so must be replaced
...
Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

##### TODO
- continue with pg data scripts and validate data flow through kafka via debezium.
- document and automate the triggering of maintenance and or fail-over events with scaling up/down
