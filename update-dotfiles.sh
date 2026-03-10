#!/usr/bin/env bash
# Syncs tracked ~/.config dirs to the autopsy-dev/dotfiles GitHub repo.

set -euo pipefail

COMMIT_MSG="${1:-}"

GITHUB_USER="autopsy-dev"
REPO_NAME="dotfiles"
REPO_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
CONFIG_DIR="$HOME/.config"
TOKEN_FILE="$HOME/.config/.dotfiles_github_token"

# --- GitHub auth ---
# Load token from file if not already in env
if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -f "$TOKEN_FILE" ]]; then
    GITHUB_TOKEN="$(cat "$TOKEN_FILE")"
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "GitHub personal access token not found."
    echo "Create one at: https://github.com/settings/tokens (needs 'repo' scope)"
    read -rsp "Paste token: " GITHUB_TOKEN
    echo
    echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "Token saved to $TOKEN_FILE"
fi

# Fetch GitHub user info for git identity
GH_API=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/users/$GITHUB_USER")
GIT_NAME=$(echo "$GH_API" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name') or d['login'])")
GIT_EMAIL=$(curl -sSL -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/emails" 2>/dev/null \
    | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(next((e['email'] for e in data if e.get('primary')), ''))
except Exception:
    pass
" 2>/dev/null) || true
GIT_EMAIL="${GIT_EMAIL:-${GITHUB_USER}@users.noreply.github.com}"

REPO_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
REPO_URL_DISPLAY="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

# Directories tracked in the repo (relative to ~/.config/)
TRACKED_DIRS=(
    fastfetch
    fish
    fontconfig
    gtk-3.0
    gtk-4.0
    hypr
    kitty
    Kvantum
    mako
    qt5ct
    rofi
    swaylock
    waybar
    wlogout
)

# --- Clone or update the repo ---
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Pulling latest from remote..."
    git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
    git -C "$REPO_DIR" reset --hard HEAD
    git -C "$REPO_DIR" clean -fd
    git -C "$REPO_DIR" pull --rebase
else
    echo "Cloning $REPO_URL_DISPLAY into $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Set git identity in the repo (local, not global)
git -C "$REPO_DIR" config user.name  "$GIT_NAME"
git -C "$REPO_DIR" config user.email "$GIT_EMAIL"

# --- Copy script itself into repo ---
cp "$CONFIG_DIR/update-dotfiles.sh" "$REPO_DIR/update-dotfiles.sh"

# --- Sync configs ---
for dir in "${TRACKED_DIRS[@]}"; do
    src="$CONFIG_DIR/$dir"
    dst="$REPO_DIR/$dir"

    if [[ ! -d "$src" ]]; then
        if [[ -d "$dst" ]]; then
            echo "Restoring $dir from repo (not found in ~/.config)..."
            rsync -a "$dst/" "$src/"
        else
            echo "Warning: $dir not found locally or in repo, skipping."
        fi
        continue
    fi

    echo "Syncing $dir..."
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
done

# --- Commit and push if there are changes ---
cd "$REPO_DIR"

if [[ -z "$(git status --porcelain)" ]]; then
    echo "No changes detected. Nothing to commit."
    exit 0
fi

git add -A

if [[ -z "$COMMIT_MSG" ]]; then
    read -rp "Commit message (leave blank for default): " COMMIT_MSG
fi
COMMIT_MSG="${COMMIT_MSG:-dotfiles: sync from $(hostname) on $(date '+%Y-%m-%d %H:%M')}"

git commit -m "$COMMIT_MSG"
git push

echo "Done. Dotfiles pushed to $REPO_URL_DISPLAY"
