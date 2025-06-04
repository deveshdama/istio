#!/bin/bash
set -e

ACR_NAME="testossistio"

echo "Logging in to ACR..."
az acr login --name testossistio

export HUB="testossistio.azurecr.io"
export TAG=latest
export ISTIO=$GOPATH/src/istio.io/istio

docker image prune -f

echo "🔨 Building ztunnel locally with certificate fix..."
cd ~/go/src/istio.io/ztunnel
cargo build --release

echo "🔄 Copying enhanced ztunnel binary to istio build..."
cd $ISTIO
mkdir -p out/linux_amd64
cp ~/go/src/istio.io/ztunnel/out/rust/release/ztunnel out/linux_amd64/ztunnel

echo "Building the project..."
make build

echo "Building Docker images..."
make docker

echo "Pushing Docker images..."
make docker.push

echo "All steps completed successfully!"