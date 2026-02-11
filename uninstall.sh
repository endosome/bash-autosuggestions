#!/usr/bin/env bash
# Uninstall bash-autosuggestions
set -euo pipefail

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-autosuggestions"

echo "Uninstalling bash-autosuggestions..."

# Remove from bashrc
if [[ -f "$HOME/.bashrc" ]]; then
    sed -i '/bash-autosuggestions/d' "$HOME/.bashrc"
    sed -i '/Fish-like autosuggestions for bash/d' "$HOME/.bashrc"
    echo "  Removed from ~/.bashrc"
fi

# Remove installed files
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed $INSTALL_DIR"
fi

echo ""
echo "Done! Restart your shell to complete removal."
