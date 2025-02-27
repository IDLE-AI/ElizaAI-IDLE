# #!/bin/bash

# set -e
# set -o pipefail

# # export TERM=dumb
# export NO_COLOR=1
# export FORCE_COLOR=0
# export CI=true

# NVM_VERSION="v0.39.1"
# NODE_VERSION="23.3.0"
# REPO_URL="https://github.com/FjrREPO/eliza-agent"

# log_error() { echo "❌ ${1}"; }
# log_success() { echo "✅ ${1}"; }
# log_info() { echo "ℹ️  ${1}"; }

# handle_error() { 
#     log_error "Error occurred in: $1 (Exit Code: $2)"
#     echo "🔴 Error in: $1 (Exit Code: $2)" >> /tmp/eliza-setup.log
#     tail -n 50 ./setup.error.log  
#     exit 1
# }

# trap 'handle_error "${BASH_SOURCE[0]}:${LINENO}" $?' ERR
# install_gum() {
#     if ! command -v gum &> /dev/null; then
#         log_info "Installing gum for better UI..."
#         sudo mkdir -p /etc/apt/keyrings
#         curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
#         echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
#         sudo apt update && sudo apt install -y gum
#     fi
# }
# show_welcome() {
#     # clear
#     cat << "EOF"
# Welcome to

#  EEEEEE LL    IIII ZZZZZZZ  AAAA
#  EE     LL     II      ZZ  AA  AA
#  EEEE   LL     II    ZZZ   AAAAAA
#  EE     LL     II   ZZ     AA  AA
#  EEEEEE LLLLL IIII ZZZZZZZ AA  AA

# Eliza is an open-source AI agent.
#      Createdby ai16z 2024.
# EOF
#     echo
#     gum style --border double --align center --width 50 --margin "1 2" --padding "1 2" \
#         "Installation Setup" "" "This script will set up Eliza for you"
# }
# install_dependencies() {
#     if [[ "$(uname -s)" == "Darwin" ]]; then
#         log_info "Installing system dependencies on macOS..."
#         if ! command -v brew &> /dev/null; then
#             log_error "Homebrew is not installed. Please install it from https://brew.sh/"
#             exit 1
#         fi

#         export HOMEBREW_NO_AUTO_UPDATE=1  # Disable auto-update

#         # Install only if not already installed
#         for pkg in git curl python3 ffmpeg; do
#             if ! brew list "$pkg" &>/dev/null; then
#                 brew install "$pkg" || log_error "Failed to install $pkg"
#             else
#                 log_info "$pkg is already installed"
#             fi
#         done
#     else
#         log_info "Installing system dependencies on Linux..."
#         sudo apt update && sudo apt install -y git curl python3 python3-pip make ffmpeg || log_error "Failed to install dependencies"
#     fi
#     log_success "Dependencies installed"
# }

# install_nvm() {
#     if [ ! -d "$HOME/.nvm" ]; then
#         gum spin --spinner dot --title "Installing NVM..." -- \
#             curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
#         export NVM_DIR="$HOME/.nvm"
#         [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
#         log_success "NVM installed"
#     else
#         log_info "NVM already installed"
#     fi
# }
# setup_node() {
#     gum spin --spinner dot --title "Setting up Node.js ${NODE_VERSION}..." -- \
#         nvm install "${NODE_VERSION}" && nvm alias eliza "${NODE_VERSION}" && nvm use eliza
#     if ! command -v pnpm &> /dev/null; then
#         gum spin --spinner dot --title "Installing pnpm..." -- npm install -g pnpm
#     else
#         log_info "pnpm is already installed"
#     fi
#     log_success "Node.js and pnpm setup complete"
# }
# clone_repository() {
#     if [ ! -d "eliza" ]; then
#         gum spin --spinner dot --title "Cloning Eliza repository..." -- git clone "${REPO_URL}" eliza
#         cd eliza
#         LATEST_TAG=$(git describe --tags --abbrev=0)
#         git checkout "${LATEST_TAG}"
#         log_success "Repository cloned and checked out to latest tag: ${LATEST_TAG}"
#     else
#         log_info "Eliza directory already exists"
#         cd eliza
#     fi
# }
# setup_environment() {
#     log_info "🔍 Entering setup_environment"

#     if [ ! -f .env ]; then
#         log_info "📁 .env file not found, creating..."
#         cp .env.example .env || { log_error "❌ Failed to create .env"; exit 1; }
#         log_success "✅ Environment file created"
#     else
#         log_info "✅ .env file already exists"
#     fi

#     log_info "🔍 Exiting setup_environment"
# }

# build_and_start() {
#     log_info "Preparing to start Eliza on port 3000..."

#     # Ensure `start_eliza.sh` is placed in the correct directory
#     ELIZA_DIR="$(cd "$(dirname "$0")" && pwd)"
#     START_SCRIPT="$ELIZA_DIR/start_eliza.sh"

#     cat > "$START_SCRIPT" << 'EOF'
# #!/bin/bash

# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ELIZA_DIR="$SCRIPT_DIR/eliza"

# if [ ! -d "$ELIZA_DIR" ]; then
#     echo "❌ Eliza directory not found at $ELIZA_DIR"
#     exit 1
# fi

# cd "$ELIZA_DIR" || exit 1
# export PORT=3000
# echo "✅ Starting Eliza in $ELIZA_DIR on port $PORT..."
# pnpm start
# EOF

#     chmod +x "$START_SCRIPT"

#     log_info "Starting Eliza with dedicated script..."
#     "$START_SCRIPT" &

#     # Wait a moment to ensure process starts
#     sleep 5

#     # Check if Eliza is running on port 3000
#     if curl -s --head http://localhost:3000 | grep "200 OK" > /dev/null; then
#         log_success "🎉 Eliza started successfully on port 3000!"
        
#         # Try to open in browser
#         if command -v xdg-open >/dev/null 2>&1; then
#             xdg-open "http://localhost:3000"
#         elif command -v open >/dev/null 2>&1; then
#             open "http://localhost:3000"
#         else
#             log_info "Please open http://localhost:3000 in your browser"
#         fi
        
#         log_info "Eliza is running in the background. To stop it, find and kill the process."
#         exit 0
#     else
#         log_error "❌ Eliza did not start properly on port 3000."
#         log_info "Try running Eliza manually: cd eliza && PORT=3000 pnpm start"
#         exit 1
#     fi
# }


# main() {
#     install_gum
#     show_welcome
    
#     if [[ -z "$CI" ]]; then
#         if ! gum confirm "Ready to install Eliza?"; then
#         log_info "Installation cancelled"
#         exit 0
#     fi
#     else
#         log_info "Skipping confirmation in CI mode"
#     fi

#     install_dependencies
#     install_nvm
#     setup_node
#     clone_repository
#     setup_environment
#     log_info "✅ Environment setup complete"

#     log_info "🔍 Checking if script is still running..."
#     sleep 2 

#     log_info "Starting build and execution..."
#     build_and_start

#     gum style --border double --align center --width 50 --margin "1 2" --padding "1 2" \
#         "🎉 Installation Complete!" "" "Eliza is now running at:" "http://localhost:5173"
# }
# main "$@"

# #!/bin/bash

set -e
set -o pipefail

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
    exit 1
}

trap 'handle_error "${BASH_SOURCE[0]}:${LINENO}" $?' ERR

install_dependencies() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_info "Installing system dependencies on macOS..."
        if ! command -v brew &> /dev/null; then
            log_error "Homebrew is not installed. Install it from https://brew.sh/"
            exit 1
        fi
        export HOMEBREW_NO_AUTO_UPDATE=1  # Disable auto-update
        brew install git curl python3 ffmpeg || log_error "Failed to install dependencies"
    else
        log_info "Installing system dependencies on Linux..."
        sudo apt update && sudo apt install -y git curl python3 python3-pip make ffmpeg || log_error "Failed to install dependencies"
    fi
    log_success "✅ Dependencies installed"
}

setup_node() {
    if ! command -v pnpm &> /dev/null; then
        log_info "Installing pnpm..."
        npm install -g pnpm || log_error "Failed to install pnpm"
    else
        log_info "✅ pnpm is already installed"
    fi
    log_success "✅ Node.js and pnpm setup complete"
}

setup_environment() {
    log_info "🔍 Setting up environment"
    cd "$(dirname "$0")/eliza" || exit 1

    if [ ! -f .env ]; then
        log_info "📁 .env file not found, creating..."
        cp .env.example .env || log_error "❌ Failed to create .env"
        log_success "✅ Environment file created"
    else
        log_info "✅ .env file already exists"
    fi
}

main() {
    install_dependencies
    setup_node
    setup_environment
    log_success "🎉 Setup complete! Run 'start_eliza.sh <character_file.json>' to start Eliza."
}

main "$@"
