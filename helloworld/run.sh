#!/bin/bash

set -e

IMAGE_NAME=hello-world
CONTAINER_NAME=FYRONXJA

cd src

# clean up
docker container rm ${CONTAINER_NAME} || true

# build
docker pull ${IMAGE_NAME}

docker create --name ${CONTAINER_NAME} ${IMAGE_NAME}

docker start --attach ${CONTAINER_NAME}

docker container rm ${CONTAINER_NAME}
