#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$HOME/.local/share/sdfm/repo"
readonly WORK_TREE="$REPO_DIR/home"
readonly BACKUP_DIR_BASE="$HOME/.local/share/sdfm/backups"

readonly SENSITIVE_PATTERNS=(
    ".ssh/id_*"
    ".ssh/*_rsa"
    ".ssh/*_ed25519"
    ".ssh/*_ecdsa"
    ".ssh/*_dsa"
    ".env"
    ".env.*"
    "*credentials*"
    "*secret*"
    "*token*"
    ".netrc"
    ".npmrc"
    ".pypirc"
    ".pgpass"
    ".docker/config.json"
    ".config/gh/hosts.yml"
    ".kube/config"
    ".gnupg/*"
)

usage() {
    cat <<EOF
Simple DotFiles Manager (sdfm): one Git branch per machine

  clone <url> <branch>    Clone the repo and check out this machine's branch
                          (created empty if it does not exist yet)
  add <path>...           Copy files or directories from \$HOME into the repo
  rm <path>...            Stop tracking files or directories
  list                    List tracked files
  diff                    Show differences between \$HOME and the repo
  update                  Copy changed tracked files from \$HOME into the repo
  apply                   Copy the repo's files into \$HOME, backing up what changes
  push                    Push this machine's branch
  list-backups            List backups made by apply
  restore <timestamp>     Copy a backup back into \$HOME
  git <args>              Run a git command in the repo
  help                    Show this help
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_repo() {
    [ -d "$REPO_DIR/.git" ] || die "repository not found. Use 'sdfm clone <url> <branch>' first."
}

# Tracked paths, NUL-separated: names may contain spaces or non-ASCII characters.
tracked() {
    git -C "$REPO_DIR" ls-files -z -- home
}

abspath() {
    if [ -d "$1" ] && [ ! -L "$1" ]; then
        (cd "$1" && pwd)
    else
        local dir
        dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd) || return 1
        echo "$dir/$(basename "$1")"
    fi
}

in_home() {
    [[ "$1" == "$HOME"/* ]]
}

exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

# Same content, or the same target for symlinks. Git keeps only the executable bit.
same() {
    if [ -L "$1" ] || [ -L "$2" ]; then
        [ -L "$1" ] && [ -L "$2" ] && [ "$(readlink "$1")" = "$(readlink "$2")" ]
        return
    fi
    cmp -s "$1" "$2" || return 1
    [ -x "$1" ] && [ -x "$2" ] && return
    [ ! -x "$1" ] && [ ! -x "$2" ]
}

# Replaces rather than writes through, so a symlink at the destination is not followed.
copy() {
    mkdir -p "$(dirname "$2")"
    rm -f "$2"
    cp -a "$1" "$2"
}

confirm() {
    local answer
    read -rp "$1 (y/N): " answer || answer=n
    [[ "$answer" =~ ^[Yy]$ ]]
}

warn_sensitive_file() {
    local file="$1" pattern
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if [[ "/$file" == */$pattern ]]; then
            echo "WARNING: '$file' may contain sensitive data (matched pattern: $pattern)"
            confirm "Are you sure you want to add this file?"
            return
        fi
    done
}

commit_changes() {
    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Nothing to commit."
        return
    fi
    git -C "$REPO_DIR" -c core.quotePath=false status --short
    if confirm "Commit changes?"; then
        git -C "$REPO_DIR" commit -qm "$1"
        echo "Committed: $1"
    else
        echo "Commit aborted. Discarding changes..."
        git -C "$REPO_DIR" reset -q --hard 2>/dev/null || git -C "$REPO_DIR" reset -q
        git -C "$REPO_DIR" clean -fdq
    fi
}

command="${1:-help}"
shift || true

case "$command" in

    clone)
        [ "$#" -eq 2 ] || die "usage: sdfm clone <url> <branch>"
        url="$1"
        branch="$2"
        git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name: $branch"
        [ ! -e "$REPO_DIR" ] || die "$REPO_DIR already exists"
        git clone -q --no-checkout "$url" "$REPO_DIR"
        if git -C "$REPO_DIR" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
            git -C "$REPO_DIR" checkout -q -B "$branch" "origin/$branch"
            echo "Checked out $branch. Run 'sdfm diff', then 'sdfm apply'."
        else
            git -C "$REPO_DIR" checkout -q --orphan "$branch"
            echo "Created empty branch $branch. Add files with 'sdfm add', then 'sdfm push'."
        fi
        ;;

    add)
        require_repo
        [ "$#" -gt 0 ] || die "add requires files"
        for p in "$@"; do
            if ! abs=$(abspath "$p") || ! exists "$abs"; then
                echo "Skipping $p (not found)"
                continue
            fi
            in_home "$abs" || { echo "Skipping $p (outside \$HOME)"; continue; }
            while IFS= read -r -d '' -u 3 file; do
                rel="${file#"$HOME"/}"
                warn_sensitive_file "$rel" || { echo "Skipping $rel"; continue; }
                copy "$file" "$WORK_TREE/$rel"
                git -C "$REPO_DIR" add -- "home/$rel"
                echo "Added $rel"
            done 3< <(find "$abs" -name .git -prune -o \( -type f -o -type l \) -print0)
        done
        commit_changes "Added files"
        ;;

    rm)
        require_repo
        [ "$#" -gt 0 ] || die "rm requires files"
        for p in "$@"; do
            abs=$(abspath "$p") || abs="$p"
            in_home "$abs" || { echo "Skipping $p (outside \$HOME)"; continue; }
            rel="${abs#"$HOME"/}"
            if [ -n "$(git -C "$REPO_DIR" ls-files -- "home/$rel")" ]; then
                git -C "$REPO_DIR" rm -rq -- "home/$rel"
                echo "Removed $rel"
            else
                echo "Not tracked: $rel"
            fi
        done
        commit_changes "Removed files"
        ;;

    list)
        require_repo
        while IFS= read -r -d '' f; do
            echo "${f#home/}"
        done < <(tracked)
        ;;

    diff)
        require_repo
        found=false
        while IFS= read -r -d '' f; do
            rel="${f#home/}"
            repo_file="$REPO_DIR/$f"
            home_file="$HOME/$rel"
            if ! exists "$home_file"; then
                echo "--- $rel: missing in \$HOME"
            elif same "$home_file" "$repo_file"; then
                continue
            elif [ -L "$home_file" ] || [ -L "$repo_file" ]; then
                echo "--- $rel: symlink differs"
            elif cmp -s "$home_file" "$repo_file"; then
                echo "--- $rel: executable bit differs"
            else
                echo "=== $rel"
                diff -u "$home_file" "$repo_file" || true
            fi
            found=true
        done < <(tracked)
        $found || echo "No differences."
        ;;

    update)
        require_repo
        while IFS= read -r -d '' f; do
            rel="${f#home/}"
            src="$HOME/$rel"
            if ! exists "$src"; then
                echo "Missing in \$HOME, kept in the repo: $rel (sdfm rm to stop tracking)"
                continue
            fi
            same "$src" "$REPO_DIR/$f" && continue
            copy "$src" "$REPO_DIR/$f"
            git -C "$REPO_DIR" add -- "$f"
            echo "Updated $rel"
        done < <(tracked)
        commit_changes "Updated dotfiles"
        ;;

    apply)
        require_repo
        backup="$BACKUP_DIR_BASE/$(date +%Y%m%d%H%M%S)"
        changed=false
        while IFS= read -r -d '' f; do
            rel="${f#home/}"
            src="$REPO_DIR/$f"
            dest="$HOME/$rel"
            if exists "$dest"; then
                same "$src" "$dest" && continue
                copy "$dest" "$backup/$rel"
            fi
            copy "$src" "$dest"
            echo "Applied $rel"
            changed=true
        done < <(tracked)
        if ! $changed; then
            echo "\$HOME already matches the repo."
        elif [ -d "$backup" ]; then
            echo "Previous versions backed up to $backup"
        fi
        ;;

    push)
        require_repo
        branch=$(git -C "$REPO_DIR" symbolic-ref -q --short HEAD) || die "not on a branch. Use 'sdfm git switch <branch>'."
        git -C "$REPO_DIR" push -u origin "$branch"
        ;;

    list-backups)
        if [ -d "$BACKUP_DIR_BASE" ] && [ -n "$(ls -A "$BACKUP_DIR_BASE")" ]; then
            ls -1r "$BACKUP_DIR_BASE"
        else
            echo "No backups found."
        fi
        ;;

    restore)
        [[ "$#" -eq 1 && "$1" =~ ^[0-9]+$ ]] || die "usage: sdfm restore <timestamp> (see 'sdfm list-backups')"
        backup_path="$BACKUP_DIR_BASE/$1"
        [ -d "$backup_path" ] || die "backup not found: $1. Use 'sdfm list-backups'."
        while IFS= read -r -d '' src; do
            rel="${src#"$backup_path"/}"
            copy "$src" "$HOME/$rel"
            echo "Restored $rel"
        done < <(find "$backup_path" \( -type f -o -type l \) -print0)
        ;;

    git)
        require_repo
        [ "$#" -gt 0 ] || die "git requires arguments, e.g. 'sdfm git log'"
        git -C "$REPO_DIR" "$@"
        ;;

    help|-h|--help)
        usage
        ;;

    *)
        usage >&2
        exit 1
        ;;
esac
