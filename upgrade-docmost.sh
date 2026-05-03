#!/bin/bash

echo "Stopping Docmost containers..."
docker compose stop docmost

echo "Pulling the latest Docmost image..."
docker pull docmost/docmost:latest

echo "Recreating and rebuilding the Docmost container..."
docker compose up --force-recreate --build docmost -d

echo "Cleanup unused Docker resources..."
docker image prune -f

echo "Upgrade complete."
