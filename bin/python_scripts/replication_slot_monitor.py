"""replication_slot_monitor.py

This script monitors replication slot lag of the debezium slot. Run this together
with debezium_pg_monitor.py and then simulate service genbump using `avn-test service
recycle <service-id> --no-reason` in order to observe what happens during a genbump
and see if the Debezium connector properly recovers or not.
"""
from utils import get_pg_and_kafka_connection_info

import argparse
import psycopg2
import logging
import time
import datetime
import traceback

logging.basicConfig(
    level=logging.ERROR,
    format='%(asctime)s.%(msecs)03d %(levelname)s %(module)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger("replication_slot_monitor")

Ki: int = 2 ** 10
Mi: int = 2 ** 20
Gi: int = 2 ** 30

WARN_SLOT_INACTIVE_TIMEOUT = 10 # warning when replication slot has been inactive
active_checkpoint = datetime.datetime.now()

def periodic_replication_slot_check(cursor, sleep=5.0):
    global inserted_records, total_inserted_records, active_checkpoint

    while True:
        try:
            cursor.execute(
                """
                SELECT
                    slot_name,
                    active,
                    restart_lsn,
                    sum(pg_catalog.pg_wal_lsn_diff(pg_catalog.pg_current_wal_lsn(), restart_lsn)::BIGINT)::BIGINT AS bytes_diff
                FROM pg_catalog.pg_replication_slots
                GROUP BY slot_name, active, restart_lsn
                """
            )

            for record in cursor:
                if record[0] == "debezium":
                    # check for slot active state
                    active_time_elapsed = round((datetime.datetime.now() - active_checkpoint).total_seconds())
                    active = record[1]
                    if not active and active_time_elapsed > WARN_SLOT_INACTIVE_TIMEOUT:
                        logger.warning(f"Replication slot is not active for {active_time_elapsed} seconds!")

                    if active:
                        active_checkpoint = datetime.datetime.now()

                    bytes_diff = record[3]
                    last_bytes_diff = bytes_diff

                    if bytes_diff < 1000:
                        logger.info(f"Debezium slot lag: {bytes_diff} bytes")
                    elif Mi >= bytes_diff >= Ki:
                        logger.info(f"Debezium slot lag: {bytes_diff // Ki} KiB")
                    elif bytes_diff > Mi:
                        logger.info(f"Debezium slot lag: {bytes_diff // Mi} MiB")

            time.sleep(sleep)

        except (psycopg2.errors.AdminShutdown, psycopg2.InterfaceError):
            logger.error("Failed connecting to the PG server. Retrying after 5 seconds...")
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
            logger.error("Failed. Retrying...")



parser = argparse.ArgumentParser()
parser.add_argument(
    "--verbose",
    action="store_true",
    help="Shows all log levels. Default log level is WARN"
)
parser.add_argument(
    "--sleep",
    type=float,
    default=5.0,
    help="Delay between checks. Default 5 second")

if __name__ == "__main__":
    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)
    else: logger.setLevel(logging.WARN)

    _, pg_uri, config = get_pg_and_kafka_connection_info()

    conn = psycopg2.connect(pg_uri)
    cursor = conn.cursor()
    logger.info("Connected!\n")

    try:
        periodic_replication_slot_check(cursor, args.sleep)
    except KeyboardInterrupt:
        conn.close()
        cursor.close()
        logger.info("Closed connections.")

