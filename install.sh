#!/bin/sh
# tckts installer
# Usage: curl -fsSL https://raw.githubusercontent.com/calumpwebb/tckts/main/install.sh | sh

set -e

REPO="calumpwebb/tckts"
INSTALL_DIR="${TCKTS_INSTALL_DIR:-$HOME/.local/bin}"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

error() {
    printf "${RED}error${NC}: %s\n" "$1" >&2
    exit 1
}

info() {
    printf "${GREEN}info${NC}: %s\n" "$1"
}

warn() {
    printf "${YELLOW}warn${NC}: %s\n" "$1"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        *) error "Unsupported operating system: $(uname -s)" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Get latest release tag from GitHub
get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# Download file
download() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        error "Neither curl nor wget found."
    fi
}

main() {
    os=$(detect_os)
    arch=$(detect_arch)

    info "Detected: ${os}-${arch}"

    # Get latest version
    info "Fetching latest version..."
    version=$(get_latest_version)

    if [ -z "$version" ]; then
        error "Could not determine latest version. Check https://github.com/${REPO}/releases"
    fi

    info "Latest version: ${version}"

    # Build download URL
    binary_name="tckts-${os}-${arch}"
    target_name="tckts"

    download_url="https://github.com/${REPO}/releases/download/${version}/${binary_name}"

    # Create install directory if needed
    mkdir -p "$INSTALL_DIR"

    # Download binary
    info "Downloading ${binary_name}..."
    tmp_file=$(mktemp)

    if ! download "$download_url" "$tmp_file"; then
        rm -f "$tmp_file"
        error "Failed to download from ${download_url}"
    fi

    # Install
    target_path="${INSTALL_DIR}/${target_name}"
    mv "$tmp_file" "$target_path"
    chmod +x "$target_path"

    info "Installed to ${target_path}"

    # Check if install dir is in PATH
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            echo ""
            echo "Add it to your shell profile:"
            echo ""
            echo "  # For bash (~/.bashrc or ~/.bash_profile):"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            echo "  # For zsh (~/.zshrc):"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            echo "  # For fish (~/.config/fish/config.fish):"
            echo "  set -gx PATH \$HOME/.local/bin \$PATH"
            echo ""
            ;;
    esac

    echo ""
    info "Installation complete! Run 'tckts help' to get started."
}

main
