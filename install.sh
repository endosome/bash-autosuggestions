#!/usr/bin/env bash
# Install bash-autosuggestions
set -euo pipefail

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-autosuggestions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing bash-autosuggestions..."
echo "  Target: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/bash-autosuggestions.sh" "$INSTALL_DIR/"

SOURCE_LINE="source \"$INSTALL_DIR/bash-autosuggestions.sh\""

if ! grep -qF "bash-autosuggestions.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Fish-like autosuggestions for bash" >> "$HOME/.bashrc"
    echo "[[ -f \"$INSTALL_DIR/bash-autosuggestions.sh\" ]] && $SOURCE_LINE" >> "$HOME/.bashrc"
    echo "  Added to ~/.bashrc"
else
    echo "  Already in ~/.bashrc (skipped)"
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  source ~/.bashrc"
