#!/bin/bash

while true; do
    printf '\n'
    read -p "Are you sure you are ready to DESTROY all terraform deployed infrastructure and data?" yn
    case $yn in
        [Yy]* ) echo 'now executing terraform destroy'; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

cd ./terraform/postgres

./bin/destroy

cd ../kafka_connect

./bin/destroy

cd ../../

echo "Terraform Destroy Completed"
echo
