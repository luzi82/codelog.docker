#!/bin/bash

set -e

IMAGE_NAME=hello-world
CONTAINER_NAME=FYRONXJA

cd src

# clean up
docker container rm ${CONTAINER_NAME} || true

# build
docker pull hello-world

docker create --name ${CONTAINER_NAME} hello-world

docker start --attach ${CONTAINER_NAME}

docker container rm ${CONTAINER_NAME}
