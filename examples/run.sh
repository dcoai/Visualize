#!/bin/bash
# Visualize Examples Server
# Run this script to start the examples gallery

set -e

cd "$(dirname "$0")"

echo "Installing dependencies..."
mix deps.get

echo "Compiling..."
mix compile

echo ""
echo "Starting server at http://localhost:4000"
echo "Press Ctrl+C to stop"
echo ""

mix phx.server
