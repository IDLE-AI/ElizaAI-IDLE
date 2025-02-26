#!/bin/bash

set -e
set -o pipefail

# export TERM=dumb
export NO_COLOR=1
export FORCE_COLOR=0
export CI=true

NVM_VERSION="v0.39.1"
NODE_VERSION="23.3.0"
REPO_URL="https://github.com/elizaOS/eliza"

log_error() { echo "❌ ${1}"; }
log_success() { echo "✅ ${1}"; }
log_info() { echo "ℹ️  ${1}"; }

handle_error() { 
    log_error "Error occurred in: $1 (Exit Code: $2)"
    echo "🔴 Error in: $1 (Exit Code: $2)" >> /tmp/eliza-setup.log
    tail -n 50 ./setup.error.log  
    exit 1
}

trap 'handle_error "${BASH_SOURCE[0]}:${LINENO}" $?' ERR
install_gum() {
    if ! command -v gum &> /dev/null; then
        log_info "Installing gum for better UI..."
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
        sudo apt update && sudo apt install -y gum
    fi
}
show_welcome() {
    # clear
    cat << "EOF"
Welcome to

 EEEEEE LL    IIII ZZZZZZZ  AAAA
 EE     LL     II      ZZ  AA  AA
 EEEE   LL     II    ZZZ   AAAAAA
 EE     LL     II   ZZ     AA  AA
 EEEEEE LLLLL IIII ZZZZZZZ AA  AA

Eliza is an open-source AI agent.
     Createdby ai16z 2024.
EOF
    echo
    gum style --border double --align center --width 50 --margin "1 2" --padding "1 2" \
        "Installation Setup" "" "This script will set up Eliza for you"
}
install_dependencies() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_info "Installing system dependencies on macOS..."
        if ! command -v brew &> /dev/null; then
            log_error "Homebrew is not installed. Please install it from https://brew.sh/"
            exit 1
        fi

        export HOMEBREW_NO_AUTO_UPDATE=1  # Disable auto-update

        # Install only if not already installed
        for pkg in git curl python3 ffmpeg; do
            if ! brew list "$pkg" &>/dev/null; then
                brew install "$pkg" || log_error "Failed to install $pkg"
            else
                log_info "$pkg is already installed"
            fi
        done
    else
        log_info "Installing system dependencies on Linux..."
        sudo apt update && sudo apt install -y git curl python3 python3-pip make ffmpeg || log_error "Failed to install dependencies"
    fi
    log_success "Dependencies installed"
}

install_nvm() {
    if [ ! -d "$HOME/.nvm" ]; then
        gum spin --spinner dot --title "Installing NVM..." -- \
            curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        log_success "NVM installed"
    else
        log_info "NVM already installed"
    fi
}
setup_node() {
    gum spin --spinner dot --title "Setting up Node.js ${NODE_VERSION}..." -- \
        nvm install "${NODE_VERSION}" && nvm alias eliza "${NODE_VERSION}" && nvm use eliza
    if ! command -v pnpm &> /dev/null; then
        gum spin --spinner dot --title "Installing pnpm..." -- npm install -g pnpm
    else
        log_info "pnpm is already installed"
    fi
    log_success "Node.js and pnpm setup complete"
}
clone_repository() {
    if [ ! -d "eliza" ]; then
        gum spin --spinner dot --title "Cloning Eliza repository..." -- git clone "${REPO_URL}" eliza
        cd eliza
        LATEST_TAG=$(git describe --tags --abbrev=0)
        git checkout "${LATEST_TAG}"
        log_success "Repository cloned and checked out to latest tag: ${LATEST_TAG}"
    else
        log_info "Eliza directory already exists"
        cd eliza
    fi
}
setup_environment() {
    log_info "🔍 Entering setup_environment"

    if [ ! -f .env ]; then
        log_info "📁 .env file not found, creating..."
        cp .env.example .env || { log_error "❌ Failed to create .env"; exit 1; }
        log_success "✅ Environment file created"
    else
        log_info "✅ .env file already exists"
    fi

    log_info "🔍 Exiting setup_environment"
}

# clean_output() {
#     # Remove ANSI escape sequences
#     echo "$1" | sed -r "s/\x1B\[([0-9,A-Z]{1,2}(;[0-9]{1,2})?(;[0-9]{3})?)?[m|K]//g"
# }

build_and_start() {
    clean_output() {
        # Remove ANSI escape sequences
        echo "$1" | sed -r "s/\x1B\[([0-9,A-Z]{1,2}(;[0-9]{1,2})?(;[0-9]{3})?)?[m|K]//g"
    }
    if [ -n "$CHARACTER_FILE" ]; then
        log_info "Using character file: $CHARACTER_FILE"
        
        # Check if character file exists
        if [ ! -f "characters/$CHARACTER_FILE" ]; then
            log_error "Character file does not exist: characters/$CHARACTER_FILE"
            
            # List available character files
            log_info "Available character files:"
            ls -la characters/*.json 2>/dev/null || echo "No character files found"
            exit 1
        fi
        
        # Export the character file path for the app to use
        export ELIZA_CHARACTER_FILE="characters/$CHARACTER_FILE"
    else
        log_info "No character file specified, using default"
    fi

    export PATH="$HOME/.local/bin:$PATH"
    export PNPM_HOME="$HOME/.pnpm-global"
    export PATH="$PNPM_HOME/bin:$PATH"
    # Start the application
    log_info "Executing: pnpm start"
    nohup pnpm start 2> >(grep -v "ExperimentalWarning" >&2) 
    disown

    log_info "Waiting for Eliza to start on port 3000..."

    for i in {1..60}; do
        if curl -s --head http://localhost:3000 | grep "200 OK" > /dev/null; then
            log_success "🎉 Eliza started successfully!"
            exit 0
        fi

        # Check if Eliza crashed
        if ! kill -0 $ELIZA_PID 2>/dev/null; then
            log_error "❌ Eliza process ($ELIZA_PID) has stopped unexpectedly!"
            exit 1
        fi

        sleep 1
    done

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:3000"
    elif command -v open >/dev/null 2>&1; then
        open "http://localhost:3000"
    else
        log_info "Please open http://localhost:3000 in your browser"
    fi
    

    log_error "❌ Eliza did not start within the expected time!"
    cat /setup_log.txt  # Show logs to debug
    exit 1
}
main() {
    install_gum
    show_welcome
    
    if [[ -z "$CI" ]]; then
        if ! gum confirm "Ready to install Eliza?"; then
        log_info "Installation cancelled"
        exit 0
    fi
    else
        log_info "Skipping confirmation in CI mode"
    fi

    install_dependencies
    install_nvm
    setup_node
    clone_repository
    setup_environment
    log_info "✅ Environment setup complete"

    log_info "🔍 Checking if script is still running..."
    sleep 2 

    log_info "Starting build and execution..."
    build_and_start

    gum style --border double --align center --width 50 --margin "1 2" --padding "1 2" \
        "🎉 Installation Complete!" "" "Eliza is now running at:" "http://localhost:5173"
}
main "$@"