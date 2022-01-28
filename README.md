# Automated Debezium (PostgreSQL®) Connector for Apache Kafka® Test ENV Deployment

#### OVERVIEW
Deploys and configures a __test/validation__ environment for the Debezium (PostgreSQL®) connector with Apache Kafka service integration
- I.e.: this project deploys and configures:
  - Apache Kafka service
  - Apache Kafka Connector service
  - PostgreSQL® service
#### NOTE: For Test/Validation Use Only
- Not suitable for environments higher than test/dev
- This project's Terraform does not leverage remote encrypted locking statefiles, etc.
###### For more information please see:
- [Aiven Help Docs: setting-up-debezium-with-aiven-for-postgresql](https://help.aiven.io/en/articles/1790791-setting-up-debezium-with-aiven-for-postgresql)

---
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

---
#### TL;DR: Deploy the infrastructure with four (4) easy steps:

__1.__ Update terraform/.auto.tfvars with your desired variable values
  - Make sure to use a valid project_id
```console
cat terraform/.auto.tfvars
# Postgres
avn_pg_svc_project_id = "test-demo"
avn_pg_svc_cloud = "google-us-central1"
avn_pg_svc_plan = "business-4"
avn_pg_svc_name = "test-pg-debezium-gcp"
avn_pg_svc_window_dow = "friday"
avn_pg_svc_window_time = "12:00:00"
avn_pg_svc_version = "12"

# Kafka
avn_kafka_svc_version = "2.7"
avn_kafka_svc_project_id = "test-demo"
avn_kafka_svc_cloud = "google-us-central1"
avn_kafka_svc_plan = "business-4"
avn_kafka_connect_svc_plan = "startup-4"
avn_kafka_svc_name = "test-kafka-debezium-gcp"
avn_kafka_connector_svc_name = "test-kafka-connector-debezium-gcp"
```

__2.__ Execute one terraform wrapper script to deploy and configure all requisite resources.
```console
./bin/deploy-terraform-infra.sh
```
#### Monitoring our PostgreSQL Replication Slots

__3.__ start the replication slot monitor lag script in one terminal:

  ```console
  python bin/python_scripts/replication_slot_monitor.py --verbose --sleep 10
  ```

- Note that in the event of a database failover, the script will continue to retry the connection:
```
ERROR replication_slot_monitor: Failed connecting to the PG server. Retrying after 5 seconds...
```

#### Verify that the Debezium connector is capturing change

- There is a helper python script that generates data to a test Postgresql table and verifies that the changes are captured by Debezium. Verification is done simply by consuming from the Kafka topic to which the connector writes the CDC events to and then checking if these records matches the ids of the records that were inserted into the source database table.
- The test database table is called `test` and it is hardcoded in `bin/config-debezium-pg-kafka.sh` and `bin/python_scripts/debezium_pg_producer.py`.

Consuming from the Kafka topic and inserting data into the test table are done in separate Python threads.

__4.__ Start the PG producer script in another terminal:

```console
python bin/python_scripts/debezium_pg_producer.py --verbose --sleep 3
```

Notes
- The script accepts the following _optional_ arguments:

```console
--table TABLE           The table into which we write test data. Default is "test" table.
--sleep SLEEP           Delay between inserts. Default 1 second. Used to control data flow
--iterations ITERATIONS How many inserts before closing program. Defaults to 10000 inserts.
--drop-table            Drop the test table before inserting new data into it. Default false.
--check-debezium-slot   Only insert if the Debezium slot is active, to guarantee no data loss if PG fails over. Default false.
--verbose               Sets the log level to DEBUG. Default log level is WARN
```

- When a database failover event happens and the script cannot connect to the database to insert data, you will see  this log entry:
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

During testing we have noticed that the replication slot can be inactive for ~15-20 minutes: this means that the connector isn't capturing any changes. What is interesting however is that the connector appears to run fine.  It only has failed at the time when the PG database failover happened--with a failing error message like this:

```
ERROR Producer failure
org.postgresql.util.PSQLException: Database connection failed when writing to copy

or

ERROR Could not execute heartbeat action
```

After that the connector's status shows as running, and no more error messages are outputted. But the replication slot to which it consumes is still inactive :-?

We couldn't find a sure way to reproduce this consistently, as it seems to occur randomly during failover events.

---
#### Changing the Debezium connector log level

- To get a more detailed log output, we can change the logging level of the running Debezium connector to TRACE level using this command:

  ```console
  ./bin/set_debezium_connector_logging_level.sh io.debezium.connector.postgresql trace
  ```

- To get the current logging levels of all loggers in our Kafka Connect cluster, just run the above script again with no arguments:

  ```console
  ./bin/set_debezium_connector_logging_level.sh
  ```

---
#### Manual SQL Queries to show the PG replication slots and their status
- In addition to our python test/validation scripts, here are a few SQL examples:
  - We should see 't' (true) under the 'active' column for each slot.
    ```console
    SELECT * from pg_replication_slots;
    ```

  - Show/monitor how much lag we have behind the slots:
    ```console
    SELECT redo_lsn, slot_name,restart_lsn,
    round((redo_lsn-restart_lsn) / 1024 / 1024 / 1024, 2) AS GB_behind
    FROM pg_control_checkpoint(), pg_replication_slots;
    ```

---

#### Destroy all Terraform deployed resources
- Clean up / Destroy All terraform infrastructure deployed via our wrapper script in step 2
```console
./bin/DESTROY-terraform-infra.sh
echo "ensure all resources terminated:"
./bin/show-all-terraform-infra.sh
```

#### Possible Intermittent Known Issues

*Kafka consumer in `debezium_pg_producer.py` not resuming after PG failover*

Fails with:
```
Exception ignored in: <function ConsumerCoordinator.__del__ at 0x7f64090de3a0>
...
RuntimeError: cannot join current thread
```

Solution for now is to re-run the `debezium_pg_producer.py` script.

#####

##### TODO
- continue with pg data scripts and validate data flow through Apache Kafka via debezium.
- possibly automate the triggering of maintenance and or fail-over events with scaling up/down
- use env variables to specify region and project name for use in config-debezium-pg-kafka (right now hardcoded in .auto.tfvars)


## Trademarks

Apache Kafka, Apache Kafka Connect are either registered trademarks or trademarks of the Apache Software Foundation in the United States and/or other countries. Debezium, PostgreSQL and Terraform are trademarks and property of their respective owners. All product and service names used in this website are for identification purposes only and do not imply endorsement.
