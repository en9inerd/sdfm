#!/usr/bin/env bash
set -e

# Change this to your script filename
SCRIPT_NAME="sdfm.sh"
TARGET_SCRIPT_NAME="sdfm"

# Change this to your repo URL if you want to download via curl
SCRIPT_URL="https://raw.githubusercontent.com/en9inerd/sdfm/master/$SCRIPT_NAME"

INSTALL_DIR="$HOME/.local/bin"
TARGET_PATH="$INSTALL_DIR/$TARGET_SCRIPT_NAME"

# Create bin directory if needed
mkdir -p "$INSTALL_DIR"

echo "Installing $SCRIPT_NAME to $TARGET_PATH..."

# Download the script
curl -fsSL "$SCRIPT_URL" -o "$TARGET_PATH"

chmod +x "$TARGET_PATH"

echo "Installed $TARGER_SCRIPT_NAME."

# Check if ~/.local/bin is in PATH
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
        # Fallback to .profile
        PROFILE_FILE="$HOME/.profile"
    fi

    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$PROFILE_FILE"
    echo "Added export PATH=\"$INSTALL_DIR:\$PATH\" to $PROFILE_FILE"
    echo "Please restart your shell or run: source \"$PROFILE_FILE\""
    ;;
esac

echo "Done! You can now run '$TARGET_SCRIPT_NAME'"

