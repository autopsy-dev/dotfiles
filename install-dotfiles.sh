#!/usr/bin/env bash
# Compatibility shortcut; all installation logic lives in the wizard.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$SCRIPT_DIR/dotfiles.sh" install "$@"
