#!/bin/bash

# https://docs.docker.com/get-started/part2/

set -e

docker swarm init

docker stack deploy -c docker-compose.yml getstartedlab

docker service ls

docker service ps getstartedlab_web

docker container ls -q

sleep 30

curl -4 http://localhost:4000
echo

docker stack rm getstartedlab

docker swarm leave --force
