#!/bin/bash

# https://docs.docker.com/get-started/

set -e

docker --version

docker run hello-world

docker image ls

docker container ls --all
