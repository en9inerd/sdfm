#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$HOME/.local/share/sdfm/repo"
readonly WORK_TREE="$REPO_DIR/home"
readonly BACKUP_DIR_BASE="$HOME/.local/share/sdfm/backups"

# Sensitive file patterns to warn about
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
    ".netrc"
    ".npmrc"
    ".pypirc"
    ".aws/credentials"
    ".docker/config.json"
)

check_dependencies() {
    local missing=()
    for cmd in git rsync; do
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

usage() {
    cat <<EOF
Simple DotFiles Manager (sdfm)

Repository Setup:
  init --remote <url> [--branch <branch>]        Initialize dotfiles repo
  clone <url> [--branch <branch>]                Clone remote repo
  create-empty-branch <branch>                   Create new empty orphan branch

Environment Management:
  switch <branch>                                Switch to environment (Git branch)
  copy <new-branch>                              Create and switch to a new branch
  sync [--force] [--dry-run]                     Sync with remote (requires --force)
  pull [--merge]                                 Pull from remote (fast-forward default)
  push                                           Push current branch
  tag <name>                                     Create and push a tag
  list-tags                                      List tags
  checkout-tag <tag>                             Checkout a tag

File Tracking:
  add <file>...                                  Copy file(s) from \$HOME to repo
  rm <file>...                                   Remove file(s) from repo
  list                                           List tracked files
  update [--dry-run]                             Update tracked files from \$HOME
  status                                         Show status
  log                                            Show log
  diff                                           Show differences between \$HOME and repo
  apply [--dry-run]                              Backup and apply dotfiles to \$HOME

Backup Maintenance:
  list-backups                                   List available backups
  restore <timestamp>                            Restore files from a backup
  cleanup-backup [--keep-days <n>] [--dry-run]   Delete old backups (default: 30 days)

Other:
  git <args>                                     Run arbitrary git command in repo
  help                                           Show this help
EOF
}

require_repo() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Error: repository not initialized. Use 'init' or 'clone' first."
        exit 1
    fi
}

abspath() {
    local target="$1"
    if [ -e "$target" ]; then
        if [ -d "$target" ]; then
            (cd "$target" && pwd)
        else
            (cd "$(dirname "$target")" && echo "$(pwd)/$(basename "$target")")
        fi
    else
        # Handle non-existent files: resolve parent dir if it exists
        local dir parent base
        dir="$(dirname "$target")"
        base="$(basename "$target")"
        if [ -d "$dir" ]; then
            parent="$(cd "$dir" && pwd)"
            echo "$parent/$base"
        else
            echo "Error: parent directory does not exist: $dir" >&2
            return 1
        fi
    fi
}

relpath_from_home() {
    local target="$1"
    [[ "$target" == "$HOME"* ]] && echo "${target#$HOME/}" || echo "$target"
}

warn_sensitive_file() {
    local file="$1"
    local basename
    basename="$(basename "$file")"
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if [[ "$file" == *$pattern ]] || [[ "$basename" == $pattern ]]; then
            echo "WARNING: '$file' may contain sensitive data (matched pattern: $pattern)"
            read -rp "Are you sure you want to add this file? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                return 1
            fi
            return 0
        fi
    done
    return 0
}

commit_changes() {
    local msg="$1"
    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Nothing to commit."
    else
        read -rp "Commit changes? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            git -C "$REPO_DIR" commit -m "$msg"
            echo "Committed: $msg"
        else
            echo "Commit aborted. Discarding staged changes..."
            git -C "$REPO_DIR" reset
            git -C "$REPO_DIR" checkout -- "home"
        fi
    fi
}

backup_files() {
    local backup_dir="$1"
    mkdir -p "$backup_dir"
    git -C "$REPO_DIR" ls-files "home" | while read -r f; do
        local relpath="${f#home/}"
        local src="$HOME/$relpath"
        if [ -e "$src" ]; then
            local dest="$backup_dir/$relpath"
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
            echo "Backed up $relpath"
        fi
    done
}

apply_files() {
    git -C "$REPO_DIR" ls-files "home" | while read -r f; do
        local relpath="${f#home/}"
        local src="$WORK_TREE/$relpath"
        local dest="$HOME/$relpath"
        mkdir -p "$(dirname "$dest")"
        rsync -a "$src" "$dest"
        echo "Applied $relpath"
    done
}

command="${1:-help}"
shift || true

case "$command" in

    init)
        DEFAULT_BRANCH="master"
        REMOTE_URL=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --branch)
                    DEFAULT_BRANCH="$2"
                    shift 2
                    ;;
                --remote)
                    REMOTE_URL="$2"
                    shift 2
                    ;;
                *)
                    echo "Warning: unknown option $1"
                    shift
                    ;;
            esac
        done

        if [[ -z "$REMOTE_URL" ]]; then
            echo "Error: --remote <url> is required."
            exit 1
        fi

        if [ -d "$REPO_DIR/.git" ]; then
            echo "Repository already initialized in $REPO_DIR"
            exit 1
        fi

        mkdir -p "$WORK_TREE"
        git init "$REPO_DIR"
        git -C "$REPO_DIR" branch -M "$DEFAULT_BRANCH"
        git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
        echo "Initialized repository at $REPO_DIR (branch: $DEFAULT_BRANCH)"
        ;;

    clone)
        url=""
        branch=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --branch)
                    branch="$2"
                    shift 2
                    ;;
                *)
                    if [ -z "$url" ]; then
                        url="$1"
                        shift
                    else
                        echo "Warning: extra argument $1"
                        shift
                    fi
                    ;;
            esac
        done

        if [ -z "$url" ]; then
            echo "Error: clone requires repository URL"
            exit 1
        fi

        git clone "$url" "$REPO_DIR"
        [ -n "$branch" ] && git -C "$REPO_DIR" checkout "$branch"
        echo "Repository cloned into $REPO_DIR"
        ;;

    switch)
        require_repo
        branch="${1:-}"
        [ -z "$branch" ] && { echo "Error: switch requires a branch name"; exit 1; }

        if git -C "$REPO_DIR" rev-parse --verify --quiet "$branch"; then
            git -C "$REPO_DIR" checkout "$branch"
            echo "Switched to branch $branch"
        else
            echo "Fetching remote branch..."
            git -C "$REPO_DIR" fetch origin "$branch"
            git -C "$REPO_DIR" checkout -b "$branch" --track "origin/$branch"
            echo "Switched to new tracking branch $branch"
        fi
        ;;

    copy)
        require_repo
        new_branch="${1:-}"
        [ -z "$new_branch" ] && { echo "Error: copy requires a branch name"; exit 1; }

        git -C "$REPO_DIR" checkout -b "$new_branch"
        echo "Created and switched to branch $new_branch"
        ;;

    create-empty-branch)
        require_repo
        new_branch="${1:-}"
        [ -z "$new_branch" ] && { echo "Error: create-empty-branch requires a branch name"; exit 1; }

        git -C "$REPO_DIR" checkout --orphan "$new_branch"
        git -C "$REPO_DIR" rm -rf . 2>/dev/null || true
        git -C "$REPO_DIR" commit --allow-empty -m "Initial empty commit"
        echo "Created empty branch $new_branch"
        ;;

    sync)
        require_repo
        dry_run=false
        force=false

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) dry_run=true; shift ;;
                --force) force=true; shift ;;
                *) echo "Warning: unknown option $1"; shift ;;
            esac
        done

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$REPO_DIR" fetch origin

        # Check for local changes that would be lost
        local_changes=$(git -C "$REPO_DIR" status --porcelain)
        local_commits=$(git -C "$REPO_DIR" rev-list "origin/$current_branch"..HEAD 2>/dev/null || true)

        if [ -n "$local_changes" ] || [ -n "$local_commits" ]; then
            echo "WARNING: sync will discard the following local changes:"
            if [ -n "$local_changes" ]; then
                echo ""
                echo "Uncommitted changes:"
                echo "$local_changes"
            fi
            if [ -n "$local_commits" ]; then
                echo ""
                echo "Local commits not on remote:"
                git -C "$REPO_DIR" log --oneline "origin/$current_branch"..HEAD
            fi
            echo ""

            if [ "$dry_run" = true ]; then
                echo "[dry-run] Would reset to origin/$current_branch"
                exit 0
            fi

            if [ "$force" != true ]; then
                echo "Use --force to proceed or --dry-run to preview."
                exit 1
            fi
        fi

        if [ "$dry_run" = true ]; then
            echo "[dry-run] No local changes to discard. Would sync with origin/$current_branch"
            exit 0
        fi

        git -C "$REPO_DIR" reset --hard "origin/$current_branch"
        echo "Synchronized with origin/$current_branch"
        ;;

    pull)
        require_repo
        merge_mode="--ff-only"
        [[ "${1:-}" == "--merge" ]] && { merge_mode=""; shift; }

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$REPO_DIR" pull ${merge_mode:+"$merge_mode"} origin "$current_branch"
        echo "Pulled updates into $current_branch"
        ;;

    push)
        require_repo
        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$REPO_DIR" push origin "$current_branch"
        ;;

    tag)
        require_repo
        tag="${1:-}"
        [ -z "$tag" ] && { echo "Error: tag requires a name"; exit 1; }
        git -C "$REPO_DIR" tag "$tag"
        git -C "$REPO_DIR" push origin --tags
        echo "Created tag $tag"
        ;;

    list-tags)
        require_repo
        git -C "$REPO_DIR" tag
        ;;

    checkout-tag)
        require_repo
        tag="${1:-}"
        [ -z "$tag" ] && { echo "Error: checkout-tag requires a tag"; exit 1; }
        git -C "$REPO_DIR" checkout "$tag"
        echo "Checked out tag $tag"
        ;;

    add)
        require_repo
        [ "$#" -eq 0 ] && { echo "Error: add requires files"; exit 1; }

        added_files=()
        for p in "$@"; do
            abs=$(abspath "$p") || { echo "Skipping $p (invalid path)"; continue; }
            [[ "$abs" != "$HOME"* ]] && { echo "Skipping $p (outside \$HOME)"; continue; }
            rel=$(relpath_from_home "$abs")

            if ! warn_sensitive_file "$rel"; then
                echo "Skipping $rel"
                continue
            fi

            dest="$WORK_TREE/$rel"
            mkdir -p "$(dirname "$dest")"
            if [ -d "$abs" ]; then
                cp -a "$abs"/. "$dest"
            else
                cp -a "$abs" "$dest"
            fi
            git -C "$REPO_DIR" add "home/$rel"
            echo "Added $rel"
            added_files+=("$rel")
        done

        if [ ${#added_files[@]} -gt 0 ]; then
            commit_changes "Added files"
        else
            echo "No files added."
        fi
        ;;

    rm)
        require_repo
        [ "$#" -eq 0 ] && { echo "Error: rm requires files"; exit 1; }

        removed_files=()
        for p in "$@"; do
            abs=$(abspath "$p") || { echo "Skipping $p (invalid path)"; continue; }
            [[ "$abs" != "$HOME"* ]] && { echo "Skipping $p (outside \$HOME)"; continue; }
            rel=$(relpath_from_home "$abs")

            if [ -e "$WORK_TREE/$rel" ]; then
                git -C "$REPO_DIR" rm -rq "home/$rel"
                echo "Removed $rel"
                removed_files+=("$rel")
            else
                echo "Not found in repo: $rel"
            fi
        done

        if [ ${#removed_files[@]} -gt 0 ]; then
            commit_changes "Removed files"
        else
            echo "No files removed."
        fi
        ;;

    update)
        require_repo
        dry_run=false
        [[ "${1:-}" == "--dry-run" ]] && { dry_run=true; shift; }

        changed=0

        while read -r f; do
            relpath="${f#home/}"
            src="$HOME/$relpath"
            dest="$WORK_TREE/$relpath"

            if [ -e "$src" ]; then
                if [ ! -e "$dest" ] || ! cmp -s "$src" "$dest"; then
                    if [ "$dry_run" = true ]; then
                        echo "[dry-run] Would update $relpath"
                    else
                        mkdir -p "$(dirname "$dest")"
                        cp -a "$src" "$dest"
                        git -C "$REPO_DIR" add "home/$relpath"
                        echo "Updated $relpath"
                    fi
                    changed=1
                fi
            else
                if [ "$dry_run" = true ]; then
                    echo "[dry-run] Would remove $relpath (no longer in \$HOME)"
                else
                    git -C "$REPO_DIR" rm -q "home/$relpath"
                    echo "Removed $relpath (no longer in \$HOME)"
                fi
                changed=1
            fi
        done < <(git -C "$REPO_DIR" ls-files "home")

        if [ "$dry_run" = true ]; then
            if [ "$changed" -eq 0 ]; then
                echo "[dry-run] No changes detected."
            fi
        elif [ "$changed" -eq 1 ]; then
            commit_changes "Updated dotfiles"
        else
            echo "No changes to commit."
        fi
        ;;

    log)
        require_repo
        git -C "$REPO_DIR" log
        ;;

    status)
        require_repo
        git -C "$REPO_DIR" status
        ;;

    apply)
        require_repo
        dry_run=false
        [[ "${1:-}" == "--dry-run" ]] && { dry_run=true; shift; }

        if [ "$dry_run" = true ]; then
            echo "[dry-run] The following files would be applied to \$HOME:"
            echo ""
            git -C "$REPO_DIR" ls-files "home" | while read -r f; do
                relpath="${f#home/}"
                repo_file="$WORK_TREE/$relpath"
                home_file="$HOME/$relpath"

                if [ ! -e "$home_file" ]; then
                    echo "  [new]      $relpath"
                elif ! cmp -s "$repo_file" "$home_file"; then
                    echo "  [modified] $relpath"
                else
                    echo "  [same]     $relpath"
                fi
            done
            echo ""
            echo "[dry-run] No changes made. Remove --dry-run to apply."
        else
            ts=$(date +%Y%m%d%H%M%S)
            backup="$BACKUP_DIR_BASE/$ts"
            echo "Backing up to $backup"
            backup_files "$backup"
            apply_files
            echo "Dotfiles applied"
        fi
        ;;

    diff)
        require_repo
        echo "Checking for differences between repo and \$HOME..."

        found_diff=0
        while read -r f; do
            relpath="${f#home/}"
            repo_file="$WORK_TREE/$relpath"
            home_file="$HOME/$relpath"

            if [ -e "$home_file" ]; then
                if ! cmp -s "$repo_file" "$home_file"; then
                    echo "=== Diff for $relpath ==="
                    diff -u "$home_file" "$repo_file" || true
                    echo
                    found_diff=1
                fi
            else
                echo "--- $relpath missing in \$HOME (would be added)"
                found_diff=1
            fi
        done < <(git -C "$REPO_DIR" ls-files "home")

        if [ "$found_diff" -eq 0 ]; then
            echo "No differences found."
        fi
        ;;

    list)
        require_repo
        echo "Tracked files:"
        git -C "$REPO_DIR" ls-files "home" | while read -r f; do
            echo "  ${f#home/}"
        done
        ;;

    list-backups)
        if [ ! -d "$BACKUP_DIR_BASE" ]; then
            echo "No backups found."
            exit 0
        fi

        found=0
        while IFS= read -r -d '' b; do
            if [ "$found" -eq 0 ]; then
                echo "Available backups:"
                found=1
            fi
            ts=$(basename "$b")
            # Format: YYYYMMDDHHMMSS -> YYYY-MM-DD HH:MM:SS
            formatted="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}"
            file_count=$(find "$b" -type f | wc -l | tr -d ' ')
            echo "  $ts  ($formatted)  [$file_count files]"
        done < <(find "$BACKUP_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -zr)

        if [ "$found" -eq 0 ]; then
            echo "No backups found."
        fi
        ;;

    restore)
        timestamp="${1:-}"
        [ -z "$timestamp" ] && { echo "Error: restore requires a timestamp. Use 'list-backups' to see available backups."; exit 1; }

        backup_path="$BACKUP_DIR_BASE/$timestamp"
        if [ ! -d "$backup_path" ]; then
            echo "Error: backup not found: $timestamp"
            echo "Use 'list-backups' to see available backups."
            exit 1
        fi

        echo "Restoring from backup $timestamp..."
        while IFS= read -r -d '' src; do
            relpath="${src#$backup_path/}"
            dest="$HOME/$relpath"
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
            echo "Restored $relpath"
        done < <(find "$backup_path" -type f -print0)
        echo "Restore complete."
        ;;

    cleanup-backup)
        keep_days=30
        dry_run=false

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --keep-days) keep_days="$2"; shift 2 ;;
                --dry-run) dry_run=true; shift ;;
                *) echo "Warning: unknown option $1"; shift ;;
            esac
        done

        if [ ! -d "$BACKUP_DIR_BASE" ]; then
            echo "No backups directory found."
            exit 0
        fi

        found=0
        while IFS= read -r -d '' dir; do
            if [ "$dry_run" = true ]; then
                echo "[dry-run] Would delete backup $(basename "$dir")"
            else
                rm -rf "$dir"
                echo "Deleted backup $(basename "$dir")"
            fi
            found=1
        done < <(find "$BACKUP_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep_days" -print0)

        if [ "$found" -eq 0 ]; then
            echo "No backups older than $keep_days days."
        fi
        ;;

    git)
        require_repo
        if [ "$#" -eq 0 ]; then
            echo "Error: git requires arguments. Example: sdfm git status"
            exit 1
        fi
        git -C "$REPO_DIR" "$@"
        ;;

    help|*)
        usage
        ;;
esac
