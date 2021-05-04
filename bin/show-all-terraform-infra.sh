#!/bin/bash

echo "Showing any/all PostgreSQL resources:"
cd ./terraform/postgres
./bin/show

echo "Showing any/all Kafka resources:"
cd ../kafka_connect
./bin/show

cd ../../

echo
