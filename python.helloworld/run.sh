#!/bin/bash

set -e

cd src

# clean up
docker container rm VTXPIAOG || true
docker image rm codelog.docker.python.helloworld:GWBEXRKS || true

# build
docker build --tag codelog.docker.python.helloworld:GWBEXRKS .

docker create --name VTXPIAOG codelog.docker.python.helloworld:GWBEXRKS

docker start --attach VTXPIAOG

docker container rm VTXPIAOG

docker image rm codelog.docker.python.helloworld:GWBEXRKS
