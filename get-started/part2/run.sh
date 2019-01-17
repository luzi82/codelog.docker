#!/bin/bash

# https://docs.docker.com/get-started/part2/

set -e

docker build --tag=friendlyhello .

docker image ls

# docker run -p 4000:80 friendlyhello # blocking

docker run -d -p 4000:80 friendlyhello

docker container ls

curl http://localhost:4000/
echo

docker container stop $(docker container ls -a -q)

docker container rm $(docker container ls -a -q)
