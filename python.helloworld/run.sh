#!/bin/bash

set -e

IMAGE_NAME=codelog.docker.python.helloworld
TAG_NAME=GWBEXRKS
CONTAINER_NAME=VTXPIAOG

cd src

# clean up
docker container rm ${CONTAINER_NAME} || true
docker image rm ${IMAGE_NAME}:${TAG_NAME} || true

# build
docker build --tag ${IMAGE_NAME}:${TAG_NAME} .

docker create --name ${CONTAINER_NAME} ${IMAGE_NAME}:${TAG_NAME}

docker start --attach ${CONTAINER_NAME}

docker container rm ${CONTAINER_NAME}

docker image rm ${IMAGE_NAME}:${TAG_NAME}
