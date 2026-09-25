#!/usr/bin/env bash
# Syncs tracked ~/.config dirs to the autopsy-dev/dotfiles GitHub repo.

set -euo pipefail

BOOT_ONLY=0
if [[ "${1:-}" == --boot-only ]]; then
    BOOT_ONLY=1
    shift
fi
COMMIT_MSG="${1:-}"

GITHUB_USER="autopsy-dev"
REPO_NAME="dotfiles"
REPO_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
CONFIG_DIR="$HOME/.config"
TOKEN_FILE="$HOME/.config/.dotfiles_github_token"

# Check portable boot sources before any network or repository operation.
if [[ -d "$CONFIG_DIR/boot" ]]; then
    python3 "$CONFIG_DIR/boot/check-public.py" "$CONFIG_DIR/boot" --extra \
        "$CONFIG_DIR/README.md" "$CONFIG_DIR/update-dotfiles.sh" "$CONFIG_DIR/install-dotfiles.sh"
elif (( BOOT_ONLY )); then
    echo 'Missing portable boot sources.' >&2
    exit 1
fi

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

# Boot-only publication uses the account handle and a GitHub noreply address.
# Do not fetch or put a personal name/email into these commits.
if (( BOOT_ONLY )); then
    GIT_NAME="$GITHUB_USER"
    GIT_EMAIL="${GITHUB_USER}@users.noreply.github.com"
    export GIT_AUTHOR_NAME="$GIT_NAME" GIT_AUTHOR_EMAIL="$GIT_EMAIL"
    export GIT_COMMITTER_NAME="$GIT_NAME" GIT_COMMITTER_EMAIL="$GIT_EMAIL"
else
# Fetch GitHub user info for the existing full desktop-sync workflow.
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
fi

REPO_URL_DISPLAY="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
REPO_URL="$REPO_URL_DISPLAY"
# Supply credentials without storing them in the Git remote or command line.
AUTH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-auth.XXXXXXXX")
trap 'rm -rf -- "$AUTH_DIR"' EXIT
cat > "$AUTH_DIR/askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
    *Username*) printf '%s\n' x-access-token ;;
    *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
    *) exit 1 ;;
esac
ASKPASS
chmod 700 "$AUTH_DIR/askpass"
export GITHUB_TOKEN GIT_ASKPASS="$AUTH_DIR/askpass" GIT_TERMINAL_PROMPT=0

# Directories tracked in the repo (relative to ~/.config/)
TRACKED_DIRS=(
    backgrounds
    boot
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
if (( BOOT_ONLY )); then
    TRACKED_DIRS=(boot)
fi

# --- Clone or update the repo ---
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Pulling latest from remote..."
    git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
    if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
        echo 'The dotfiles checkout has local changes; save them before syncing.' >&2
        exit 1
    fi
    git -C "$REPO_DIR" pull --rebase
else
    echo "Cloning $REPO_URL_DISPLAY into $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Set git identity in the repo (local, not global)
git -C "$REPO_DIR" config user.name  "$GIT_NAME"
git -C "$REPO_DIR" config user.email "$GIT_EMAIL"

# --- Copy script and readme into repo ---
cp "$CONFIG_DIR/update-dotfiles.sh" "$REPO_DIR/update-dotfiles.sh"
cp "$CONFIG_DIR/install-dotfiles.sh" "$REPO_DIR/install-dotfiles.sh"
cp "$CONFIG_DIR/README.md" "$REPO_DIR/README.md"
if (( ! BOOT_ONLY )); then
    cp "$CONFIG_DIR/screenshot.png" "$REPO_DIR/screenshot.png"
fi

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
    if [[ "$dir" == boot ]]; then
        # Only portable source and theme assets. Machine state stays under /etc.
        python3 "$CONFIG_DIR/boot/check-public.py" "$src"
        rsync -a --delete --delete-excluded --exclude='__pycache__/' --exclude='*.pyc' "$src/" "$dst/"
    else
        rsync -a --delete "$src/" "$dst/"
    fi
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
