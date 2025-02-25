#!/bin/bash
set -e
set -o pipefail
NVM_VERSION="v0.39.1"
NODE_VERSION="23.3.0"
REPO_URL="https://github.com/elizaOS/eliza"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
NC='\033[0m'; BOLD='\033[1m'
log_error() { gum style --foreground 1 "❌ ${1}"; }
log_success() { gum style --foreground 2 "✅ ${1}"; }
log_info() { gum style --foreground 4 "ℹ️  ${1}"; }
handle_error() { log_error "Error occurred in: $1"; log_error "Exit code: $2"; exit 1; }
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
    clear
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
    [ ! -f .env ] && cp .env.example .env && log_success "Environment file created"
}
build_and_start() {
    gum spin --spinner dot --title "Installing project dependencies..." -- \
        pnpm clean && pnpm install --no-frozen-lockfile
    log_success "Dependencies installed"

    gum spin --spinner dot --title "Building project..." -- pnpm build && pnpm rebuild
    log_success "Project built successfully"

    log_info "Starting Eliza services..."
    pnpm start & pnpm start:client &
    sleep 5

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:5173"
    elif command -v open >/dev/null 2>&1; then
        open "http://localhost:5173"
    else
        log_info "Please open http://localhost:5173 in your browser"
    fi
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
    build_and_start

    gum style --border double --align center --width 50 --margin "1 2" --padding "1 2" \
        "🎉 Installation Complete!" "" "Eliza is now running at:" "http://localhost:5173"
}
main "$@"