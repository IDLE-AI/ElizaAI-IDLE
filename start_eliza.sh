#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELIZA_DIR="$SCRIPT_DIR/eliza"

if [ ! -d "$ELIZA_DIR" ]; then
    echo "❌ Eliza directory not found at $ELIZA_DIR"
    exit 1
fi

cd "$ELIZA_DIR" || exit 1
export PORT=3000
echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."
pnpm start
