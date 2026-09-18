#!/usr/bin/env bash
# Syncs tracked ~/.config dirs to the autopsy-dev/dotfiles GitHub repo.

set -euo pipefail

COMMIT_MSG="${1:-}"

GITHUB_USER="autopsy-dev"
REPO_NAME="dotfiles"
REPO_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
CONFIG_DIR="$HOME/.config"
TOKEN_FILE="$HOME/.config/.dotfiles_github_token"

# Refuse to discard local work, before authentication or network access.
if [[ -d "$REPO_DIR/.git" ]] && [[ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "Dotfiles checkout has local changes. Commit or stash them before syncing." >&2
    exit 1
fi
if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ ! -s "$TOKEN_FILE" ]]; then
    echo "No credential found. Provision the token file securely or set GITHUB_TOKEN." >&2
    exit 1
fi
[[ ! -f "$TOKEN_FILE" ]] || chmod 600 "$TOKEN_FILE"
export DOTFILES_TOKEN_FILE="$TOKEN_FILE"
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
# Resolve credentials at runtime; never put secrets in URLs or Git config.
CREDENTIAL_HELPER='!f() { if [ "$1" = get ]; then protocol= host= path=; while IFS="=" read -r key value; do case "$key" in protocol) protocol=$value;; host) host=$value;; path) path=$value;; esac; done; if [ "$protocol" = https ] && [ "$host" = github.com ] && [ "$path" = autopsy-dev/dotfiles.git ]; then printf "username=x-access-token\npassword=%s\n" "${GITHUB_TOKEN:-$(cat "$DOTFILES_TOKEN_FILE")}"; fi; fi; }; f'
git_auth() {
    command git -c credential.helper= -c credential.helper="$CREDENTIAL_HELPER" -c credential.useHttpPath=true "$@"
}
GIT_NAME="$(git -C "$CONFIG_DIR" config user.name || true)"
GIT_NAME="${GIT_NAME:-$GITHUB_USER}"
GIT_EMAIL="$(git -C "$CONFIG_DIR" config user.email || true)"
GIT_EMAIL="${GIT_EMAIL:-${GITHUB_USER}@users.noreply.github.com}"
REPO_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
REPO_URL_DISPLAY="$REPO_URL"
EXCLUDES=(--exclude='.claude/' --exclude='nohup.out' --exclude='*.log' --exclude='fish_variables')

# Directories tracked in the repo (relative to ~/.config/)
TRACKED_DIRS=(
    fastfetch
    fish
    fontconfig
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
    git_auth -C "$REPO_DIR" pull --ff-only
else
    echo "Cloning $REPO_URL_DISPLAY into $REPO_DIR..."
    git_auth clone "$REPO_URL" "$REPO_DIR"
fi

# Set git identity in the repo (local, not global)
git -C "$REPO_DIR" config user.name  "$GIT_NAME"
git -C "$REPO_DIR" config user.email "$GIT_EMAIL"

# --- Copy script and readme into repo ---
cp "$CONFIG_DIR/update-dotfiles.sh" "$REPO_DIR/update-dotfiles.sh"
cp "$CONFIG_DIR/README.md" "$REPO_DIR/README.md"
cp "$CONFIG_DIR/screenshot.png" "$REPO_DIR/screenshot.png"

# --- Sync configs ---
for dir in "${TRACKED_DIRS[@]}"; do
    src="$CONFIG_DIR/$dir"
    dst="$REPO_DIR/$dir"

    if [[ ! -d "$src" ]]; then
        if [[ -d "$dst" ]]; then
            echo "Restoring $dir from repo (not found in ~/.config)..."
            rsync -a "${EXCLUDES[@]}" "$dst/" "$src/"
        else
            echo "Warning: $dir not found locally or in repo, skipping."
        fi
        continue
    fi

    echo "Syncing $dir..."
    mkdir -p "$dst"
    rsync -a --delete "${EXCLUDES[@]}" "$src/" "$dst/"
done

# --- Commit and push if there are changes ---
cd "$REPO_DIR"
# Preserve local copies while removing runtime state from the next commit.
git rm --cached --ignore-unmatch -- fish/fish_variables hypr/config/nohup.out
for pattern in '.claude/' 'nohup.out' '*.log' 'fish_variables'; do
    if [[ ! -f .gitignore ]] || ! grep -Fxq -- "$pattern" .gitignore; then
        printf '\n%s\n' "$pattern" >> .gitignore
    fi
done

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
git_auth push

echo "Done. Dotfiles pushed to $REPO_URL_DISPLAY"
