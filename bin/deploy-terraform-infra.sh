#!/bin/bash

cd ./terraform/postgres

./bin/init
./bin/plan
./bin/apply

cd ../kafka_connect

./bin/init
./bin/plan
./bin/apply

cd ../../

./bin/config-debezium-pg-kafka.sh

echo