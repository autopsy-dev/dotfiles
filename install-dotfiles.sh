#!/usr/bin/env bash
# Install the GitHub version of the dotfiles into the current user's config.
set -euo pipefail
umask 077

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/autopsy-dev/dotfiles.git}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
TOKEN_FILE="$CONFIG_DIR/.dotfiles_github_token"
TRACKED_DIRS=(
    fastfetch fish fontconfig hypr kitty Kvantum mako qt5ct rofi
    swaylock waybar wlogout
    alacritty backgrounds boot gtk-3.0 gtk-4.0 themes
)

if [[ "${1:-}" == --help ]]; then
    cat <<'HELP'
Usage: ./install-dotfiles.sh

Download autopsy-dev/dotfiles from GitHub and replace the included config
folders in ${XDG_CONFIG_HOME:-$HOME/.config}. Requires git and rsync.
You must confirm the overwrite warning. Existing folders are backed up first.
Optional: DOTFILES_REPO_URL selects a different repository; GITHUB_TOKEN
provides authentication. Existing Git credentials also work.
HELP
    exit 0
fi
if (( $# )); then
    echo 'Unknown argument. Use --help.' >&2
    exit 2
fi
for command in git rsync mktemp; do
    command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/install-dotfiles.XXXXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT

# Keep credentials out of clone URLs, git configuration and command arguments.
if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
    GITHUB_TOKEN=$(<"$TOKEN_FILE")
fi
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GITHUB_TOKEN
    cat > "$WORK_DIR/askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
    *Username*) printf '%s\n' x-access-token ;;
    *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
    *) exit 1 ;;
esac
ASKPASS
    chmod 700 "$WORK_DIR/askpass"
    export GIT_ASKPASS="$WORK_DIR/askpass"
fi

echo 'Downloading dotfiles from the repository default branch...'
GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 -- "$REPO_URL" "$WORK_DIR/repo"

# Do not replace a working setup with a checkout missing its wallpapers.
for image in dark-cozy-landscape.png dark-cozy-portrait.png; do
    if [[ ! -s "$WORK_DIR/repo/backgrounds/$image" ]]; then
        printf 'Missing wallpaper in GitHub checkout: backgrounds/%s\n' "$image" >&2
        echo 'Run update-dotfiles.sh on the configured PC to upload the wallpapers, then retry.' >&2
        exit 1
    fi
done

INSTALL_DIRS=()
for directory in "${TRACKED_DIRS[@]}"; do
    source="$WORK_DIR/repo/$directory"
    if [[ -L "$source" || -L "$CONFIG_DIR/$directory" ]]; then
        echo "Refusing to replace a symlinked config folder: $directory" >&2
        exit 1
    fi
    if [[ -d "$source" ]]; then
        INSTALL_DIRS+=("$directory")
    fi
done
if (( ${#INSTALL_DIRS[@]} == 0 )); then
    echo 'The repository contains no recognized config folders. Nothing installed.' >&2
    exit 1
fi

printf '\nDestination: %s\nFolders to replace:\n' "$CONFIG_DIR"
printf '  %s\n' "${INSTALL_DIRS[@]}"
cat <<'WARNING'

WARNING: This will overwrite your local dotfiles, including any unsaved changes
or changes not uploaded to GitHub. Files absent from GitHub will be removed
inside the folders listed above. Save open editor buffers before continuing.
Existing on-disk configs will be backed up; unsaved editor buffers cannot be.
Other config folders and your existing Git checkout will be left alone.
WARNING
if ! read -r -p 'Type yes to install the GitHub version: ' answer || [[ "$answer" != yes ]]; then
    echo 'Cancelled. Your configs were not changed.'
    exit 0
fi

mkdir -p -- "$CONFIG_DIR/dotfiles-backups"
BACKUP_DIR=$(mktemp -d "$CONFIG_DIR/dotfiles-backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
printf 'Backing up existing configs to %s\n' "$BACKUP_DIR"
# Finish all backups before overwriting any config.
for directory in "${INSTALL_DIRS[@]}"; do
    if [[ -e "$CONFIG_DIR/$directory" ]]; then
        if [[ ! -d "$CONFIG_DIR/$directory" ]]; then
            echo "Expected a config directory: $CONFIG_DIR/$directory" >&2
            exit 1
        fi
        mkdir -p -- "$BACKUP_DIR/$directory"
        rsync -a -- "$CONFIG_DIR/$directory/" "$BACKUP_DIR/$directory/"
    fi
done
for directory in "${INSTALL_DIRS[@]}"; do
    printf 'Installing %s...\n' "$directory"
    mkdir -p -- "$CONFIG_DIR/$directory"
    rsync -a --delete -- "$WORK_DIR/repo/$directory/" "$CONFIG_DIR/$directory/"
done
printf '\nInstalled the GitHub dotfiles. Backups: %s\n' "$BACKUP_DIR"
echo 'Landscape and portrait wallpapers installed in the backgrounds folder.'
if ! command -v swaybg >/dev/null || ! command -v python3 >/dev/null; then
    echo 'Install swaybg and Python 3 to display the wallpapers automatically in Hyprland.'
fi
echo 'Restart the affected applications or log back into Hyprland to apply everything.'
if [[ -d "$CONFIG_DIR/boot" ]]; then
    echo 'Portable boot sources downloaded. Boot settings require a separate installation:'
    printf '  sudo python3 "%s/boot/install.py"          # inspect the plan\n' "$CONFIG_DIR"
    printf '  sudo python3 "%s/boot/install.py" --apply  # build and install\n' "$CONFIG_DIR"
fi
