#!/bin/bash
set -e
set -o pipefail

# Make script executable on creation
chmod +x "$0"

NVM_VERSION="v0.39.1"
NODE_VERSION="23.3.0"
ELIZA_BASE_DIR="${ELIZA_BASE_DIR:-$HOME/Documents/eliza-idle}"
ELIZA_DIR="$ELIZA_BASE_DIR/eliza"
CHARACTER_DIR="${CHARACTER_DIR:-$ELIZA_DIR/characters}"
WATCHED_FILE="$CHARACTER_DIR/new_character.json"
PID_FILE="/tmp/eliza.pid"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_error() { 
    echo -e "${RED}❌ $1${NC}" >&2
}

log_success() { 
    echo -e "${GREEN}✅ $1${NC}"
}

log_info() { 
    echo -e "${BLUE}ℹ️  $1${NC}"
}
get_latest_character_file() {
    log_info "Looking for character files in: $CHARACTER_DIR"
    local latest_file
    
    # Check if directory exists
    if [ ! -d "$CHARACTER_DIR" ]; then
        log_error "Character directory does not exist: $CHARACTER_DIR"
        return 1
    fi
    
    # Find latest json file
    latest_file=$(find "$CHARACTER_DIR" -maxdepth 1 -name "*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)
    
    if [ -z "$latest_file" ]; then
        # Try ls as fallback
        latest_file=$(ls -t "$CHARACTER_DIR"/*.json 2>/dev/null | head -n1)
    fi
    
    if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
        log_success "Found latest character file: $latest_file"
        echo "$latest_file"
        return 0
    else
        log_error "No character files found in $CHARACTER_DIR"
        return 1
    fi
}

handle_error() {
    log_error "Error occurred in: $1"
    log_error "Exit code: $2"
    log_error "Command: ${BASH_COMMAND}"
    exit 1
}

trap 'handle_error "${BASH_SOURCE[0]}:${LINENO}" $?' ERR

install_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_info "Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        log_success "Homebrew installed"
    else
        log_info "Homebrew already installed"
    fi
}

install_gum() {
    if ! command -v gum &> /dev/null; then
        log_info "Installing gum..."
        brew install gum || {
            log_error "Failed to install gum"
            return 1
        }
        log_success "gum installed"
    else
        log_info "gum is already installed"
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."
    brew update || log_error "Failed to update Homebrew"

    for dep in git curl "python@3.13" ffmpeg; do
        if ! brew list "$dep" &> /dev/null; then
            brew install "$dep" || {
                log_error "Failed to install $dep"
                return 1
            }
            log_success "$dep installed"
        else
            log_info "$dep is already installed"
        fi
    done
}

install_nvm() {
    if [ ! -d "$HOME/.nvm" ]; then
        log_info "Installing NVM..."
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        log_success "NVM installed"
    else
        log_info "NVM already installed"
    fi
}

setup_node() {
    log_info "Setting up Node.js ${NODE_VERSION}..."
    # Unset npm_config_prefix to avoid conflicts with nvm
    unset npm_config_prefix
    
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    nvm install "${NODE_VERSION}" || {
        log_error "Failed to install Node.js ${NODE_VERSION}"
        return 1
    }
    nvm alias eliza "${NODE_VERSION}" && nvm use eliza
    
    npm install -g corepack || {
        log_error "Failed to install corepack"
        return 1
    }
    corepack enable
    corepack prepare pnpm@latest --activate
    log_success "Node.js setup complete"
}

setup_environment() {
    log_info "Setting up environment..."
    mkdir -p "$CHARACTER_DIR" || {
        log_error "Failed to create character directory"
        return 1
    }
    touch "$CHARACTER_DIR/.test" && rm "$CHARACTER_DIR/.test" || {
        log_error "Character directory is not writable"
        return 1
    }
    log_success "Environment setup complete"
}

stop_existing_eliza() {
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_info "Stopping existing Eliza instance (PID: $old_pid)"
            kill "$old_pid"
            sleep 2
        fi
        rm -f "$PID_FILE"
    fi
}

start_eliza_with_character() {
    local character_file="$1"
    echo "DEBUG: Checking if character file exists: $character_file"
    if [ -f "$character_file" ]; then
    log_success "Character file exists: $character_file"
    else
    log_error "Character file does NOT exist: $character_file"
    ls -l "$(dirname "$character_file")"  # List files in the directory
    exit 1
    fi

    stop_existing_eliza

    log_info "Starting Eliza with character from: $character_file"
    if [ ! -d "$ELIZA_DIR" ]; then
        log_error "Eliza directory not found"
        return 1
    fi
    cd "$ELIZA_DIR" || {
        log_error "Failed to change to Eliza directory"
        return 1
    }

    # Export the character file path for Eliza
    export CHARACTER_FILE="$character_file"
    
    # Start Eliza with the character file
    log_info "Starting Eliza with CHARACTER_FILE=$CHARACTER_FILE"
    pnpm start &
    ELIZA_PID=$!
    echo "$ELIZA_PID" > "$PID_FILE"
    
    # Wait a moment to ensure process started successfully
    sleep 2
    if ! kill -0 "$ELIZA_PID" 2>/dev/null; then
        log_error "Eliza failed to start"
        return 1
    fi
    
    log_success "Eliza started with PID: $ELIZA_PID using character file: $character_file"
}

main() {
    mkdir -p "$(dirname "$0")/logs"
    
    exec 1> >(sed 's/\x1B\[[0-9;]*m//g' | tee "$(dirname "$0")/logs/setup-$(date +%Y%m%d-%H%M%S).log")
    exec 2>&1
    
    install_homebrew
    install_gum
    install_dependencies
    install_nvm
    setup_node
    setup_environment
    
    log_info "Finding latest character file..."
    local latest_file
    latest_file=$(get_latest_character_file)
    sleep 1
    
    if [ -n "$latest_file" ]; then
        log_info "Starting Eliza with latest character file: $latest_file"
        start_eliza_with_character "$latest_file"
    else
        log_error "No character files found in $CHARACTER_DIR"
        exit 1
    fi
    
    log_success "Setup completed successfully!"
}

main "$@"