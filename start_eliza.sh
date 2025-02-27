#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELIZA_DIR="$SCRIPT_DIR/eliza"
CHARACTER_DIR="$SCRIPT_DIR/eliza/characters"

# Check if character parameter is provided
if [ -n "$1" ]; then
    CHARACTER_NAME="$1"
    CHARACTER_FILE="$CHARACTER_DIR/$CHARACTER_NAME.json"
    
    # Check if character file exists
    if [ ! -f "$CHARACTER_FILE" ]; then
        echo "❌ Character file not found: $CHARACTER_FILE"
        echo "Available characters:"
        ls -1 "$CHARACTER_DIR"/*.json 2>/dev/null | xargs -n 1 basename || echo "No character files found"
        exit 1
    fi
    
    echo "✅ Using character: $CHARACTER_NAME ($CHARACTER_FILE)"
    export ELIZA_CHARACTER_FILE="$CHARACTER_FILE"
else
    echo "ℹ️ No character specified, using default"
fi

# Check if Eliza directory exists
if [ ! -d "$ELIZA_DIR" ]; then
    echo "❌ Eliza directory not found at $ELIZA_DIR"
    exit 1
fi

# Start Eliza with the specified character
cd "$ELIZA_DIR" || exit 1
pkill node
rm -rf node_modules/.cache
export PORT=3000
echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."

if [ -n "$CHARACTER_NAME" ]; then
    echo "✅ Using character: $CHARACTER_NAME"
    pnpm start --character="$CHARACTER_FILE"
else
    pnpm start
fi