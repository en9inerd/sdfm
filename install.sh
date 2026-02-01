#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/en9inerd/sdfm/master/sdfm.sh"
INSTALL_DIR="$HOME/.local/bin"
TARGET_PATH="$INSTALL_DIR/sdfm"

check_dependencies() {
    local missing=()
    for cmd in git rsync curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

check_dependencies

mkdir -p "$INSTALL_DIR"

echo "Installing sdfm to $TARGET_PATH..."

if ! curl -fsSL "$SCRIPT_URL" -o "$TARGET_PATH"; then
    echo "Error: failed to download sdfm"
    exit 1
fi

chmod +x "$TARGET_PATH"

echo "Installed sdfm."

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    echo "$INSTALL_DIR is already in PATH."
    ;;
  *)
    echo "$INSTALL_DIR is not in PATH. Adding it to your shell profile..."

    SHELL_NAME="$(basename "$SHELL")"
    PROFILE_FILE=""

    if [ "$SHELL_NAME" = "bash" ]; then
        PROFILE_FILE="$HOME/.bashrc"
    elif [ "$SHELL_NAME" = "zsh" ]; then
        PROFILE_FILE="$HOME/.zshrc"
    else
        PROFILE_FILE="$HOME/.profile"
    fi

    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$PROFILE_FILE"
    echo "Added export PATH=\"$INSTALL_DIR:\$PATH\" to $PROFILE_FILE"
    echo "Please restart your shell or run: source \"$PROFILE_FILE\""
    ;;
esac

echo "Done! You can now run 'sdfm'"
