#!/usr/bin/env bash
# install.sh — Install aibox CLI
set -euo pipefail

INSTALL_DIR="${HOME}/.aibox"
BIN_DIR="/usr/local/bin"

echo "Installing aibox..."

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create install directory
mkdir -p "${INSTALL_DIR}/lib"
mkdir -p "${INSTALL_DIR}/templates"

# Copy files
cp "${SCRIPT_DIR}/bin/aibox" "${INSTALL_DIR}/aibox"
cp "${SCRIPT_DIR}"/lib/*.sh "${INSTALL_DIR}/lib/"
cp "${SCRIPT_DIR}"/templates/* "${INSTALL_DIR}/templates/"
chmod +x "${INSTALL_DIR}/aibox"

# Update AIBOX_DIR in the entrypoint to point to install location
sed -i '' "s|AIBOX_DIR=.*|AIBOX_DIR=\"${INSTALL_DIR}\"|" "${INSTALL_DIR}/aibox"

# Symlink to PATH
if [[ -w "${BIN_DIR}" ]]; then
    ln -sf "${INSTALL_DIR}/aibox" "${BIN_DIR}/aibox"
    echo "✓ Installed to ${BIN_DIR}/aibox"
else
    sudo ln -sf "${INSTALL_DIR}/aibox" "${BIN_DIR}/aibox"
    echo "✓ Installed to ${BIN_DIR}/aibox (sudo)"
fi

echo ""
echo "Usage: aibox --help"
echo ""
echo "Prerequisites:"
echo "  brew install orbstack   (recommended)"
echo "  brew install lima       (alternative)"
