# Automated Debezium Kafka PostgreSQL Test ENV Deployment

#### OVERVIEW
Deploys and configures a __test/validation__ environment for the Debezium (PostgreSQL) connector with Kafka service integration
- I.e.: this project deploys and configures:
  - Kafka service
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

- There is also a python script that monitors the lag and warns if the slot becomes inactive:
  ```console
  python bin/python_scripts/replication_slot_monitor.py --verbose --sleep 10
  ```

In the event of a database failover, the script will retry the connection:

```
ERROR replication_slot_monitor: Failed connecting to the PG server. Retrying after 5 seconds...
```

#### Verify that the Debezium connector is capturing change

There is a helper python script that generates data to a test Postgresql table and verify that the changes are captured by Debezium. Verification is done simply by consuming from the Kafka topic to which the connector writes the CDC events and checking if these records matches the ids of the records that were inserted into the source database table. For now the test database table is called `test` and it is hardcoded in `bin/config-debezium-pg-kafka.sh` and `bin/python_scripts/debezium_pg_producer.py`.

Consuming from the Kafka topic and inserting data into the test table are done in separate Python threads.

```console
python bin/python_scripts/debezium_pg_producer.py --verbose --sleep 3
```

The script accepts some arguments:

```console
--table TABLE           The table into which we write test data. Default is "test" table.
--sleep SLEEP           Delay between inserts. Default 1 second. Used to control data flow
--iterations ITERATIONS How many inserts before closing program. Defaults to 10000 inserts.
--verbose               Sets the log level to DEBUG. Default log level is WARN
```

When a database failover event happens and the script cannot connect to the database to insert data, you will see  this log entry:

```
ERROR debezium_pg_producer: Postgres data insert: Failed connecting to the PG server. Retrying after 5 seconds...
```

After 10-15 seconds the insert thread should resume. The Kafka consumer thread however might fail to get new records (will show `INFO debezium_pg_producer: Kafka Consumer exited`) when the Debezium connector fails to resume.

To end the script, press Ctrl + C once: you will then get a log message if Debezium has successfully captured all the changes since the script started, or did it miss some records:

```
Kafka Consumer: Some inserts were not captured by debezium

or

Kafka Consumer: All inserts were captured by debezium
```

---

During testing I have noticed that the replication slot can be inactive for 15-20 minutes: this means that the connector isn't capturing any changes. What is interesting however is that the connector appears to run fine. It only fails at the time when the failover happened, with a failing error message like this:

```
ERROR Producer failure
org.postgresql.util.PSQLException: Database connection failed when writing to copy

or

ERROR Could not execute heartbeat action
```

After that the connector's status shows as running, and no more error messages are outputted. But the replication slot to which it consumes is still inactive :-?

I couldn't find a sure way to reproduce this consistently, seems to happen now and again during a failover.

#### Changing the Debezium connector log level

- To get a more detailed log output, we can change the logging level of the running Debezium connector to TRACE level using this command:

  ```console
  ./bin/set_debezium_connector_logging_level.sh io.debezium.connector.postgresql trace
  ```

- To get the current logging levels of all loggers in our Kafka Connect cluster, just run the above script again with no arguments:

  ```console
  ./bin/set_debezium_connector_logging_level.sh
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
- use env variables to specify region and project name for use in config-debezium-pg-kafka (right now hardcoded in .auto.tfvars)
