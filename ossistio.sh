#!/bin/bash
set -e # Exit on error

ACR_NAME="testossistio"

echo "Logging in to ACR..."
az acr login --name testossistio

export HUB="testossistio.azurecr.io"
export TAG=latest
export ISTIO=$GOPATH/src/istio.io/istio

docker image prune -f

echo "Building the project..."
make build

echo "Building Docker images..."
make docker

echo "Pushing Docker images..."
make docker.push

echo "All steps completed successfully!"