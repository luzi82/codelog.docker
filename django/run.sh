#!/bin/bash

set -e

echo sudo for right

sudo true

rm -rf venv
sudo rm -rf composeexample
rm -rf manage.py

virtualenv -p `which python3` venv
source venv/bin/activate
pip install docker-compose

docker-compose run web django-admin.py startproject composeexample .

sudo chown -R $USER:$USER .

patch -p0 < settings.py.patch

docker-compose up -d

sleep 10

curl http://localhost:8000

docker ps

docker-compose down
