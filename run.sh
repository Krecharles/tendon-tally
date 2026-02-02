#!/bin/bash
# Run script for ActivityTracker using Swift Package Manager

set -e

echo "Building ActivityTracker..."
swift build

echo "Running ActivityTracker..."
swift run ActivityTracker
