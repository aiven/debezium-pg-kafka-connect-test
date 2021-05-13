""" debezium_pg_producer.py

This script inserts data into a test table in a Postgresql database,
and then monitor the CDC event captured into a Kafka topic from a
Debezium connector.
"""

from string import ascii_uppercase
from random import choice
from kafka import KafkaConsumer
from utils import get_pg_and_kafka_connection_info

import psycopg2
import sys
import argparse
import time
import threading
import json
import logging
import traceback

inserted_records = dict()
total_inserted_records = 0

# https://stackoverflow.com/a/56144390
logging.basicConfig(
    level=logging.ERROR,
    format='%(asctime)s.%(msecs)03d %(levelname)s %(module)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('debezium_pg_monitor')

# Kafka

def kafka_consumer(run_event, broker, topic):
    """Consume from the Debezium output topic
    """
    global inserted_records

    while run_event.is_set():
        consumer = KafkaConsumer(topic,
            consumer_timeout_ms=10000,
            security_protocol="SSL",
            auto_offset_reset="earliest",
            group_id="debezium-monitor",
            ssl_cafile="service-creds/ca.pem",
            ssl_certfile="service-creds/service.cert",
            ssl_keyfile="service-creds/service.key",
            bootstrap_servers=[broker])

        try:
            for message in consumer:
            # message value and key are raw bytes -- decode if necessary!
            # e.g., for unicode: `message.value.decode("utf-8")`
                try:
                    value = json.loads(message.value)
                    db_id = value["after"]["id"]
                except json.decoder.JSONDecodeError:
                    logger.error("Kafka Consumer: Value is not valid JSON")
                except KeyError:
                    logger.error("Kafka Consumer: Value does not contain db key. Trying in value[\"after\"][\"id\"]")

                logger.info(f"Kafka Consumer: message received. id: {db_id}")

                if inserted_records.get(db_id):
                    logger.info(f"Kafka Consumer: Inserted id {db_id} is found in Kafka")
                    del inserted_records[db_id]
        except Exception:
            logger.error("Something happened")
            traceback.print_exc()


        logger.info("Kafka Consumer exited")

    if len(inserted_records.keys()) > 0:
        logger.info("Kafka Consumer: Some inserts were not captured by debezium")
        logger.info(inserted_records.keys())
    else:
        logger.info("Kafka Consumer: All inserts were captured by debezium")



# Postgresql

def create_table(cursor, table_name):
    try:
        cursor.execute(
            f"CREATE TABLE IF NOT EXISTS {table_name} (id serial PRIMARY KEY, data varchar);"
        )
    except Exception as e:
        logger.error(e)

def insert_random_records(run_event, conn, cursor, table_name, iterations=10000, sleep=1.0):
    global inserted_records, total_inserted_records

    while run_event.is_set():
        random_data = "".join(choice(ascii_uppercase) for i in range(42))
        try:
            cursor.execute(
                f"INSERT INTO {table_name} (data) VALUES (%s) RETURNING ID",
                (random_data,))
            id_of_new_row = cursor.fetchone()[0]
            inserted_records[id_of_new_row] = True
            total_inserted_records += 1 # For record keeping
            logger.info(f"Postgres data insert: Inserted data into {table_name} with id: {id_of_new_row}")

            conn.commit()
        except (psycopg2.errors.AdminShutdown, psycopg2.InterfaceError):
            logger.error("Postgres data insert: Failed connecting to the PG server. Retrying after 5 seconds...")
            _, pg_uri, _ = get_pg_and_kafka_connection_info()
            try:
                conn = psycopg2.connect(pg_uri)
                cursor = conn.cursor()
            except psycopg2.OperationalError:
                # FATAL: the database system is shutting down
                pass
            finally:
                time.sleep(5.0)
                continue
        except Exception as e:
            traceback.print_exc()
            logger.error("Postgres data insert: Failed. Retrying...")

        logger.info("Postgres data insert: Committing...")
        if total_inserted_records >= iterations:
            break

        time.sleep(sleep)

    logger.info("Postgres data insert: Ended insert_random_records")



parser = argparse.ArgumentParser()
parser.add_argument(
    "--table",
    type=str,
    default="test",
    help="The table into which we write test data. Default is \"test\" table")
parser.add_argument(
    "--sleep",
    type=float,
    default=1.0,
    help="Delay between inserts. Default 1 second. Used to control data flow")
parser.add_argument(
    "--iterations",
    type=int,
    default=10000,
    help="How many inserts before closing program. Defaults to 10000 inserts.")
parser.add_argument(
    "--verbose",
    action="store_true",
    help="Sets the log level to DEBUG. Default log level is WARN"
)


if __name__ == "__main__":
    run_event = threading.Event()
    run_event.set()

    args = parser.parse_args()
    kafka_broker_uri, pg_uri, config = get_pg_and_kafka_connection_info()
    if args.verbose:
        logger.setLevel(logging.INFO)
    else: logger.setLevel(logging.WARN)

    conn = psycopg2.connect(pg_uri)
    cursor = conn.cursor()
    logger.info("Connected!\n")

    create_table(cursor, args.table)
    pg_insert_thread = threading.Thread(target=insert_random_records,
        args=(
            run_event,
            conn,
            cursor,
            args.table,
            args.iterations,
            args.sleep,
        )
    )
    debezium_topic_name = f"{config['avn_pg_svc_name']}.public.{args.table}"
    kafka_consume_thread = threading.Thread(target=kafka_consumer,
        args=(
            run_event,
            kafka_broker_uri,
            debezium_topic_name,
        )
    )

    pg_insert_thread.start()
    kafka_consume_thread.start()

    # Handle keyboard interrupt to gracefully close threads
    # Got this snippet from https://stackoverflow.com/a/11436603

    try:
        while 1:
            time.sleep(.1)
    except KeyboardInterrupt:
        logger.setLevel(logging.INFO)
        run_event.clear()
        pg_insert_thread.join()
        kafka_consume_thread.join()
        logger.info("Threads successfully closed")
