#!/bin/bash
# Quick test of bootstrap.sh help and structure
# This verifies the script is properly formed

echo "Testing bootstrap.sh structure..."
echo ""

# Check script exists and is executable
if [ ! -x "./bootstrap.sh" ]; then
    echo "❌ bootstrap.sh not found or not executable"
    exit 1
fi

echo "✅ bootstrap.sh exists and is executable"
echo ""

# Check help works
echo "Testing --help option..."
./bootstrap.sh --help 2>&1 | head -20
