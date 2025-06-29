#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$HOME/.local/share/sdfm/repo"
readonly WORK_TREE="$REPO_DIR/home"
readonly BACKUP_DIR_BASE="$HOME/.local/share/sdfm/backups"

usage() {
    cat <<EOF
Simple Dotfiles Manager (sdfm)

Repository Setup:
  init --remote <url> [--branch <branch>]   Initialize dotfiles repo
  clone <url> [--branch <branch>]           Clone remote repo
  create-empty-branch <branch>              Create new empty orphan branch

Environment Management:
  switch <branch>           Switch to environment (Git branch)
  copy <new-branch>         Create and switch to a new branch
  sync                      Sync with remote
  pull [--merge]            Pull from remote (fast-forward by default)
  tag <name>                Create and push a tag
  list-tags                 List tags
  checkout-tag <tag>        Checkout a tag
  push                      Push current branch

File Tracking:
  add <file>...             Copy file(s) from \$HOME to repo
  rm <file>...              Remove file(s) from repo
  update                    Update tracked files in repo from \$HOME
  status                    Show status
  apply                     Backup and apply dotfiles to \$HOME

Backup Maintenance:
  cleanup-backup [--keep-days <n>]   Delete backups older than n days (default: 30)

Other:
  help                      Show this help
EOF
}

require_repo() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Error: repository not initialized. Use 'init' or 'clone' first."
        exit 1
    fi
}

abspath() {
    (cd "$(dirname "$1")" && pwd)/$(basename "$1")
}

relpath_from_home() {
    local target="$1"
    [[ "$target" == "$HOME"* ]] && echo "${target#$HOME/}" || echo "$target"
}

commit_changes() {
    local msg="$1"
    if git -C "$REPO_DIR" diff --cached --quiet; then
        echo "Nothing to commit."
    else
        git -C "$REPO_DIR" commit -m "$msg"
        echo "Committed: $msg"
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
        cp -au "$src" "$dest"
        echo "Applied $relpath"
    done
}

# Main
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
        git -C "$REPO_DIR" rm -rf .
        git -C "$REPO_DIR" commit --allow-empty -m "Initial empty commit"
        echo "Created empty branch $new_branch"
        ;;

    sync)
        require_repo
        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$REPO_DIR" fetch origin
        git -C "$REPO_DIR" reset --hard "origin/$current_branch"
        echo "Synchronized with origin/$current_branch"
        ;;

    pull)
        require_repo
        merge_mode="--ff-only"
        [[ "${1:-}" == "--merge" ]] && { merge_mode=""; shift; }

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        git -C "$REPO_DIR" pull $merge_mode origin "$current_branch"
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

        for p in "$@"; do
            abs=$(abspath "$p")
            [[ "$abs" != "$HOME"* ]] && { echo "Skipping $p (outside \$HOME)"; continue; }

            rel=$(relpath_from_home "$abs")
            dest="$WORK_TREE/$rel"
            mkdir -p "$(dirname "$dest")"
            cp -a "$abs" "$dest"
            git -C "$REPO_DIR" add "home/$rel"
            echo "Added $rel"
        done

        commit_changes "Added files"
        ;;

    rm)
        require_repo
        [ "$#" -eq 0 ] && { echo "Error: rm requires files"; exit 1; }

        for p in "$@"; do
            abs=$(abspath "$p")
            [[ "$abs" != "$HOME"* ]] && { echo "Skipping $p (outside \$HOME)"; continue; }

            rel=$(relpath_from_home "$abs")
            if [ -e "$WORK_TREE/$rel" ]; then
                git -C "$REPO_DIR" rm -r "home/$rel"
                echo "Removed $rel"
            else
                echo "Not found in repo: $rel"
            fi
        done

        commit_changes "Removed files"
        ;;

    update)
        require_repo

        # Find all tracked files
        git -C "$REPO_DIR" ls-files "home" | while read -r f; do
            relpath="${f#home/}"
            src="$HOME/$relpath"
            dest="$WORK_TREE/$relpath"

            if [ -e "$src" ]; then
                mkdir -p "$(dirname "$dest")"
                cp -a "$src" "$dest"
                git -C "$REPO_DIR" add "home/$relpath"
                echo "Updated $relpath"
            else
                echo "Warning: $src does not exist in \$HOME, skipping"
            fi
        done

        commit_changes "Updated files from \$HOME"
        ;;

    status)
        require_repo
        git -C "$REPO_DIR" status
        ;;

    apply)
        require_repo
        ts=$(date +%Y%m%d%H%M%S)
        backup="$BACKUP_DIR_BASE/$ts"
        echo "Backing up to $backup"
        backup_files "$backup"
        apply_files
        echo "Dotfiles applied"
        ;;

    cleanup-backup)
        keep_days=30
        [[ "${1:-}" == "--keep-days" ]] && { keep_days="$2"; shift 2; }

        find "$BACKUP_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep_days" -print0 | while IFS= read -r -d '' dir; do
            rm -rf "$dir"
            echo "Deleted backup $dir"
        done
        ;;

    help|*)
        usage
        ;;
esac
