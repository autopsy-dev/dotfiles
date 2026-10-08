#!/usr/bin/env bash
# One entry point for installing and publishing the desktop dotfiles.
set -euo pipefail
umask 077

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
REPO_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/autopsy-dev/dotfiles.git}"
TOKEN_FILE="$CONFIG_DIR/.dotfiles_github_token"
TRACKED_DIRS=(
    backgrounds boot fastfetch fish fontconfig hypr kitty Kvantum mako
    qt5ct rofi swaylock waybar wlogout
)
# Preserve the old installer's optional folders without expanding the upload
# allowlist (GTK folders, for example, can contain private bookmarks).
INSTALLABLE_DIRS=("${TRACKED_DIRS[@]}" alacritty gtk-3.0 gtk-4.0 themes)
SHARED_FILES=(dotfiles.sh install-dotfiles.sh update-dotfiles.sh README.md)
WORK_DIR=''
BOOT_ONLY=0
COMMIT_MSG=''

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
    cat <<'HELP'
Dotfiles wizard — install from GitHub or upload your current configs.

Usage:
  bash dotfiles.sh                         Interactive menu
  bash dotfiles.sh install                 Install with backup and confirmation
  bash dotfiles.sh update ["message"]      Upload with confirmation
  bash dotfiles.sh update --boot-only ["message"]
  bash dotfiles.sh --help

Install directly (review remote scripts before executing them):
  curl -fsSL https://raw.githubusercontent.com/autopsy-dev/dotfiles/main/dotfiles.sh | bash

Requires git and rsync; uploading boot sources also requires Python 3.
Run as your regular user, not with sudo. No system packages or boot settings
are changed. Prompts use the terminal, so piping the script into Bash works.

Overrides: XDG_CONFIG_HOME, DOTFILES_DIR, DOTFILES_REPO_URL, GITHUB_TOKEN.
Public installs need no token. Existing Git credentials work for uploads;
the wizard can also save a GitHub token privately in your config directory.
HELP
}

require_commands() {
    local dependency
    for dependency in "$@"; do
        command -v "$dependency" >/dev/null || die "Missing dependency: $dependency"
    done
}

# Never read answers from the script stream in `curl ... | bash`.
open_terminal() {
    if { exec 3<>/dev/tty; } 2>/dev/null; then
        return
    fi
    die 'An interactive terminal is required. Download the script, then run bash dotfiles.sh in a terminal.'
}

ask() {
    printf '%s' "$1"
    if ! IFS= read -r -u 3 ANSWER; then
        printf '\nCancelled.\n'
        exit 0
    fi
}

confirm() {
    ask "$1"
    if [[ "$ANSWER" != yes ]]; then
        echo "${2:-Cancelled.}"
        exit 0
    fi
}

prepare_auth() {
    local mode="$1" token
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-wizard.XXXXXXXX")
    if [[ -z "${GITHUB_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
        GITHUB_TOKEN=$(<"$TOKEN_FILE")
    fi
    if [[ "$mode" == update && -z "${GITHUB_TOKEN:-}" && "$REPO_URL" == https://github.com/* ]]; then
        echo 'Authentication: use existing Git credentials, or supply a GitHub token.'
        echo 'A token needs write access to this repository. Input is hidden.'
        printf 'GitHub token (Enter to use existing Git credentials): '
        if ! IFS= read -r -s -u 3 token; then
            printf '\nCancelled.\n'
            exit 0
        fi
        printf '\n'
        if [[ -n "$token" ]]; then
            GITHUB_TOKEN="$token"
            ask 'Save the token privately for future uploads? [y/N]: '
            if [[ "$ANSWER" == y || "$ANSWER" == Y ]]; then
                mkdir -p -- "$CONFIG_DIR"
                [[ ! -L "$TOKEN_FILE" ]] || die 'Refusing to save a token through a symlink.'
                printf '%s\n' "$GITHUB_TOKEN" > "$TOKEN_FILE"
                chmod 600 "$TOKEN_FILE"
            fi
        fi
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
    export GIT_TERMINAL_PROMPT=0
}

install_configs() {
    local directory file source backup_dir
    local -a install_dirs=()
    require_commands git rsync mktemp
    prepare_auth install
    printf '\nDownloading the repository default branch from %s...\n' "$REPO_URL"
    git clone --quiet --depth 1 -- "$REPO_URL" "$WORK_DIR/repo"

    # Refuse incomplete publications before touching the current setup.
    for file in dark-cozy-landscape.png dark-cozy-portrait.png; do
        [[ -s "$WORK_DIR/repo/backgrounds/$file" ]] ||
            die "Missing wallpaper: backgrounds/$file. Upload from the configured PC first."
    done
    for file in "${SHARED_FILES[@]}"; do
        [[ -f "$WORK_DIR/repo/$file" && ! -L "$WORK_DIR/repo/$file" ]] ||
            die "Missing or symlinked wizard file: $file. Publish the new wizard first."
        [[ ! -L "$CONFIG_DIR/$file" && ( ! -e "$CONFIG_DIR/$file" || -f "$CONFIG_DIR/$file" ) ]] ||
            die "Refusing to replace a non-file or symlink: $CONFIG_DIR/$file"
    done
    for directory in "${INSTALLABLE_DIRS[@]}"; do
        source="$WORK_DIR/repo/$directory"
        if [[ -L "$source" || -L "$CONFIG_DIR/$directory" ]]; then
            die "Refusing a symlinked config folder: $directory"
        fi
        if [[ -d "$source" ]]; then
            [[ ! -e "$CONFIG_DIR/$directory" || -d "$CONFIG_DIR/$directory" ]] ||
                die "Expected a config directory: $CONFIG_DIR/$directory"
            install_dirs+=("$directory")
        fi
    done
    (( ${#install_dirs[@]} )) || die 'No recognized config folders in the repository.'
    printf '\nDestination: %s\nFolders to replace:\n' "$CONFIG_DIR"
    printf '  %s\n' "${install_dirs[@]}"
    printf 'Wizard and documentation to install:\n'
    printf '  %s\n' "${SHARED_FILES[@]}"
    cat <<'WARNING'

This replaces the listed configs with the GitHub version, including local
changes not uploaded to GitHub. Files absent from GitHub are removed inside
these folders. Save open editor buffers first: only on-disk files can be backed up.
Other config folders and your existing Git checkout are left alone.
No packages are installed; boot settings are NOT changed.
WARNING
    confirm 'Type yes to back up and install: '

    mkdir -p -- "$CONFIG_DIR/dotfiles-backups"
    backup_dir=$(mktemp -d "$CONFIG_DIR/dotfiles-backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
    printf '\nBacking up to %s\n' "$backup_dir"
    # Complete every backup before replacing anything.
    for directory in "${install_dirs[@]}"; do
        if [[ -d "$CONFIG_DIR/$directory" ]]; then
            mkdir -p -- "$backup_dir/$directory"
            rsync -a -- "$CONFIG_DIR/$directory/" "$backup_dir/$directory/"
        fi
    done
    for file in "${SHARED_FILES[@]}"; do
        if [[ -f "$CONFIG_DIR/$file" ]]; then
            cp -a -- "$CONFIG_DIR/$file" "$backup_dir/$file"
        fi
    done
    for directory in "${install_dirs[@]}"; do
        printf 'Installing %s...\n' "$directory"
        mkdir -p -- "$CONFIG_DIR/$directory"
        rsync -a --delete -- "$WORK_DIR/repo/$directory/" "$CONFIG_DIR/$directory/"
    done
    for file in "${SHARED_FILES[@]}"; do
        rsync -a -- "$WORK_DIR/repo/$file" "$CONFIG_DIR/$file"
    done
    chmod u+x -- "$CONFIG_DIR/dotfiles.sh" "$CONFIG_DIR/install-dotfiles.sh" "$CONFIG_DIR/update-dotfiles.sh"
    if command -v fc-cache >/dev/null; then
        fc-cache -f || echo 'Warning: font cache refresh failed; run fc-cache -f later.'
    fi
    printf '\nInstalled! Backup: %s\n' "$backup_dir"
    echo 'Restart the affected applications or log back into Hyprland.'
    echo 'Desktop packages are not installed automatically (including swaybg and Python 3).'
    printf 'Next time: bash "%s/dotfiles.sh"\n' "$CONFIG_DIR"
    if [[ -d "$CONFIG_DIR/boot" ]]; then
        echo 'Boot sources were downloaded only. To inspect and then apply them separately:'
        printf '  sudo python3 "%s/boot/install.py"\n' "$CONFIG_DIR"
        printf '  sudo python3 "%s/boot/install.py" --apply\n' "$CONFIG_DIR"
    fi
}

check_public_sources() {
    if [[ -d "$CONFIG_DIR/boot" ]]; then
        require_commands python3
        python3 "$CONFIG_DIR/boot/check-public.py" "$CONFIG_DIR/boot" --extra \
            "$CONFIG_DIR/README.md" "$CONFIG_DIR/dotfiles.sh" \
            "$CONFIG_DIR/update-dotfiles.sh" "$CONFIG_DIR/install-dotfiles.sh"
    elif (( BOOT_ONLY )); then
        die 'Missing portable boot sources.'
    fi
}

update_configs() {
    local directory file src dst identity pending
    local -a sync_dirs=("${TRACKED_DIRS[@]}")
    require_commands git rsync mktemp
    for file in "${SHARED_FILES[@]}"; do
        [[ -f "$CONFIG_DIR/$file" && ! -L "$CONFIG_DIR/$file" ]] || die "Missing or symlinked file: $CONFIG_DIR/$file"
    done
    check_public_sources
    if (( BOOT_ONLY )); then
        sync_dirs=(boot)
    fi
    printf '\nSource: %s\nCheckout: %s\nRemote: %s\n' "$CONFIG_DIR" "$REPO_DIR" "$REPO_URL"
    printf 'Folders to sync (when present):\n'
    printf '  %s\n' "${sync_dirs[@]}"
    echo 'Shared wizard scripts and README are also uploaded.'
    if (( ! BOOT_ONLY )); then
        echo 'The screenshot is uploaded when present.'
    fi
    echo 'Missing local folders are restored from the checkout, when available.'
    echo 'Review your configs for private data. The boot check does NOT scan desktop folders.'
    confirm 'Type yes to prepare an upload: '
    prepare_auth update

    if [[ -e "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]]; then
        die "Checkout path exists but is not a supported Git checkout: $REPO_DIR"
    fi
    if [[ -d "$REPO_DIR/.git" ]]; then
        git -C "$REPO_DIR" symbolic-ref --quiet HEAD >/dev/null || die 'Checkout has a detached HEAD; select a branch first.'
        if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
            printf '\nYour checkout has local changes:\n'
            git -C "$REPO_DIR" status --short
            cat <<'STASH'

You can save tracked changes and new files in a Git stash before syncing.
The stash is NOT automatically reapplied or deleted. Checkout-only edits will
not be uploaded; the upload uses your active config folder instead.
STASH
            ask 'Type stash to save those changes and continue, or Enter to cancel: '
            if [[ "$ANSWER" != stash ]]; then
                echo 'Cancelled. Checkout changes were left alone.'
                exit 0
            fi
            git -C "$REPO_DIR" stash push --include-untracked -m "dotfiles wizard backup $(date '+%Y-%m-%d %H:%M:%S')"
            printf 'Backup saved. Inspect later with: git -C "%s" stash show -p --include-untracked\n' "$REPO_DIR"
        fi
        [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || die 'Checkout is still dirty; resolve its changes before syncing.'
        # Tokens never go into the remote URL or process arguments.
        git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
        echo 'Pulling latest changes...'
        git -C "$REPO_DIR" pull --rebase || die 'Pull failed. Resolve the checkout before retrying; any saved stash is still retained.'
    else
        mkdir -p -- "$(dirname -- "$REPO_DIR")"
        git clone -- "$REPO_URL" "$REPO_DIR"
    fi

    # Validate destinations before copying any files into the checkout.
    for file in "${SHARED_FILES[@]}" screenshot.png; do
        [[ ! -L "$REPO_DIR/$file" && ( ! -e "$REPO_DIR/$file" || -f "$REPO_DIR/$file" ) ]] ||
            die "Refusing a non-file or symlink in the checkout: $file"
    done
    for directory in "${sync_dirs[@]}"; do
        src="$CONFIG_DIR/$directory"
        dst="$REPO_DIR/$directory"
        [[ ! -L "$src" && ! -L "$dst" ]] || die "Refusing a symlinked config folder: $directory"
        [[ ! -e "$src" || -d "$src" ]] || die "Expected a config directory: $src"
        [[ ! -e "$dst" || -d "$dst" ]] || die "Expected a checkout directory: $dst"
    done

    # Keep boot-only publications free of personal author details.
    identity=autopsy-dev
    if (( BOOT_ONLY )); then
        export GIT_AUTHOR_NAME="$identity" GIT_AUTHOR_EMAIL="${identity}@users.noreply.github.com"
        export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    else
        git -C "$REPO_DIR" config user.name >/dev/null || git -C "$REPO_DIR" config user.name "$identity"
        git -C "$REPO_DIR" config user.email >/dev/null || git -C "$REPO_DIR" config user.email "${identity}@users.noreply.github.com"
    fi
    for file in "${SHARED_FILES[@]}"; do
        rsync -a -- "$CONFIG_DIR/$file" "$REPO_DIR/$file"
    done
    if (( ! BOOT_ONLY )) && [[ -f "$CONFIG_DIR/screenshot.png" ]]; then
        rsync -a -- "$CONFIG_DIR/screenshot.png" "$REPO_DIR/screenshot.png"
    fi
    for directory in "${sync_dirs[@]}"; do
        src="$CONFIG_DIR/$directory"
        dst="$REPO_DIR/$directory"
        [[ ! -L "$src" && ! -L "$dst" ]] || die "Refusing a symlinked config folder: $directory"
        if [[ ! -d "$src" ]]; then
            if [[ -d "$dst" ]]; then
                printf 'Restoring missing %s from the checkout...\n' "$directory"
                mkdir -p -- "$src"
                rsync -a -- "$dst/" "$src/"
            fi
            continue
        fi
        printf 'Syncing %s...\n' "$directory"
        mkdir -p -- "$dst"
        if [[ "$directory" == boot ]]; then
            rsync -a --delete --delete-excluded --exclude='__pycache__/' --exclude='*.pyc' -- "$src/" "$dst/"
        else
            rsync -a --delete -- "$src/" "$dst/"
        fi
    done
    # Also check restored boot sources before staging them.
    check_public_sources
    pending=$(git -C "$REPO_DIR" log --oneline '@{upstream}..HEAD') ||
        die 'No upstream branch configured. Set the checkout upstream before uploading.'
    if [[ -n "$pending" ]]; then
        printf '\nPreviously committed changes waiting to upload:\n%s\n' "$pending"
    fi
    if [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
        if [[ -z "$pending" ]]; then
            echo 'Everything is already synced. Nothing to upload.'
            return
        fi
        confirm 'Type yes to push these commits: '
    else
        printf '\nChanges to publish:\n'
        git -C "$REPO_DIR" diff --stat
        git -C "$REPO_DIR" status --short
        confirm 'Type yes to commit and push these changes: ' \
            'Cancelled. Prepared changes remain in the checkout; nothing was committed or pushed.'
        if [[ -z "$COMMIT_MSG" ]]; then
            ask 'Commit message (Enter for default): '
            COMMIT_MSG="$ANSWER"
        fi
        COMMIT_MSG="${COMMIT_MSG:-dotfiles: sync $(date '+%Y-%m-%d %H:%M')}"
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -m "$COMMIT_MSG"
    fi
    # Retry a previously committed upload even when there are no new file changes.
    git -C "$REPO_DIR" push
    printf '\nDone! Dotfiles pushed to %s\n' "$REPO_URL"
}

main() {
    local action="${1:-}"
    case "$action" in
        -h|--help) usage; exit 0 ;;
        install|update) shift ;;
        --boot-only) action=update ;;
        '') ;;
        *) usage >&2; die "Unknown action: $action" ;;
    esac
    if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
        usage
        exit 0
    fi
    if [[ "${1:-}" == --boot-only ]]; then
        [[ "$action" == update ]] || die '--boot-only is only available for uploading.'
        BOOT_ONLY=1
        shift
    fi
    if [[ "$action" == update && $# -gt 0 ]]; then
        COMMIT_MSG="$1"
        shift
    fi
    (( $# == 0 )) || die 'Unexpected arguments. Use --help.'
    [[ "${EUID:-$(id -u)}" != 0 ]] || die 'Run this wizard as your regular user, not with sudo.'
    open_terminal
    printf '\n=== Dotfiles wizard ===\n'
    if [[ -z "$action" ]]; then
        printf '\n  1) Install / restore from GitHub (backs up current configs)\n'
        printf '  2) Upload this computer\x27s configs to GitHub\n'
        printf '  3) Upload portable boot sources only\n'
        printf '  q) Quit\n\n'
        while [[ -z "$action" ]]; do
            ask 'Choose [1/2/3/q]: '
            case "$ANSWER" in
                1) action=install ;;
                2) action=update ;;
                3) action=update; BOOT_ONLY=1 ;;
                q|Q|'') echo 'Cancelled.'; exit 0 ;;
                *) echo 'Please choose 1, 2, 3, or q.' ;;
            esac
        done
    fi
    case "$action" in
        install) install_configs ;;
        update) update_configs ;;
    esac
}

main "$@"
