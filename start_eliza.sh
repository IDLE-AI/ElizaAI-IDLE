# # #!/bin/bash

# # SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# # ELIZA_DIR="$SCRIPT_DIR/eliza"
# # CHARACTER_DIR="$SCRIPT_DIR/eliza/characters"

# # # Check if character parameter is provided
# # if [ -n "$1" ]; then
# #     CHARACTER_NAME="$1"
# #     CHARACTER_FILE="$CHARACTER_DIR/$CHARACTER_NAME.json"
    
# #     # Check if character file exists
# #     if [ ! -f "$CHARACTER_FILE" ]; then
# #         echo "❌ Character file not found: $CHARACTER_FILE"
# #         echo "Available characters:"
# #         ls -1 "$CHARACTER_DIR"/*.json 2>/dev/null | xargs -n 1 basename || echo "No character files found"
# #         exit 1
# #     fi
    
# #     echo "✅ Using character: $CHARACTER_NAME ($CHARACTER_FILE)"
# #     export ELIZA_CHARACTER_FILE="$CHARACTER_FILE"
# # else
# #     echo "ℹ️ No character specified, using default"
# # fi

# # # Check if Eliza directory exists
# # if [ ! -d "$ELIZA_DIR" ]; then
# #     echo "❌ Eliza directory not found at $ELIZA_DIR"
# #     exit 1
# # fi

# # # Start Eliza with the specified character
# # cd "$ELIZA_DIR" || exit 1
# # pkill node
# # rm -rf node_modules/.cache
# # export PORT=3000
# # echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."

# # if [ -n "$CHARACTER_NAME" ]; then
# #     echo "✅ Using character: $CHARACTER_NAME"
# #     pnpm start --character="$CHARACTER_FILE"
# # else
# #     pnpm start
# # fi

# #!/bin/bash


# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ELIZA_DIR="$SCRIPT_DIR/eliza"

# if [ ! -d "$ELIZA_DIR" ]; then
#     echo "❌ Eliza directory not found at $ELIZA_DIR"
#     exit 1
# fi

# if [ -z "$CHARACTER_JSON" ]; then
#     echo "❌ No character data received!"
#     exit 1
# fi

# echo "✅ Character data received for: $(echo "$CHARACTER_JSON" | jq -r '.name')"

# export ELIZA_CHARACTER_JSON="$CHARACTER_JSON"


# cd "$ELIZA_DIR" || exit 1
# pkill node
# rm -rf node_modules/.cache
# # export PORT=3001
# echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."

# pnpm start

#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELIZA_DIR="$SCRIPT_DIR/eliza"

# Database connection
PSQL="psql --username=idle --dbname=idledb --no-align --tuples-only --quiet -c"

# Pastikan karakter dikirim sebagai argumen pertama
CHARACTER_NAME="$1"

if [ -z "$CHARACTER_NAME" ]; then
    echo "❌ No character name provided! Exiting..."
    exit 1
fi

# Ambil data karakter dari database sebagai JSON
CHARACTER_JSON=$($PSQL "SELECT row_to_json(characters) FROM characters WHERE name='$CHARACTER_NAME';")

if [ -z "$CHARACTER_JSON" ]; then
    echo "❌ Character '$CHARACTER_NAME' not found in database!"
    exit 1
fi

echo "✅ Using character: $CHARACTER_NAME"
export ELIZA_CHARACTER_JSON="$CHARACTER_JSON"

# Pastikan direktori Eliza ada
if [ ! -d "$ELIZA_DIR" ]; then
    echo "❌ Eliza directory not found at $ELIZA_DIR"
    exit 1
fi

# Masuk ke folder Eliza dan jalankan dengan karakter yang dipilih
cd "$ELIZA_DIR" || exit 1
pkill node
rm -rf node_modules/.cache

# Set port jika perlu
export PORT=3000
echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."
echo "✅ Using character JSON directly from database!"

# Jalankan Eliza TANPA file JSON lokal
pnpm start
