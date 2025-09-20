#!/bin/bash

sudo apt-get update -y && sudo apt upgrade -y
sudo adduser devops
sudo usermod -aG sudo devops
