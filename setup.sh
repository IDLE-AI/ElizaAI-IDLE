set -e
set -o pipefail

export NO_COLOR=1
export FORCE_COLOR=0
export CI=true

NVM_VERSION="v0.39.1"
NODE_VERSION="23.3.0"
REPO_URL="https://github.com/ameliazsabrina/eliza-agent"

log_error() { echo "❌ ${1}"; }
log_success() { echo "✅ ${1}"; }
log_info() { echo "ℹ️  ${1}"; }
g
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
