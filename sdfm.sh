#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/.local/share/sdfm/repo"
WORK_TREE="$REPO_DIR/home"
BACKUP_DIR_BASE="$HOME/.local/share/sdfm/backups"

usage() {
    cat <<EOF
Simple Dotfiles Manager (sdfm)

Repository Setup:
  init --remote <url> [--branch <branch>]   Initialize dotfiles repo with remote and optional branch
  clone <url> [--branch <branch>]           Clone remote dotfiles repo
  create-empty-branch <branch>              Create a new empty orphan branch

Environment Management:
  switch <branch>           Switch to environment (Git branch)
  copy <new-branch>         Create and switch to a new branch from current
  sync                      Sync with remote (pull & hard reset)
  tag <name>                Create and push a tag with given name
  list-tags                 List all tags
  checkout-tag <tag>        Checkout a specific tag
  push                      Push current branch to remote

File Tracking:
  add <file>...             Copy file(s) from \$HOME to repo and commit
  rm <file>...              Remove file(s) from repo and commit
  status                    Show repository status
  apply                     Backup existing tracked files and copy dotfiles to \$HOME

Backup Maintenance:
  cleanup-backup [--keep-days <n>]   Delete backups older than the specified number of days (default: 30)

Other:
  help                      Show this help
EOF
}

require_repo() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Error: repository not initialized. Use '$0 init' or '$0 clone' first."
        exit 1
    fi
}

abspath() {
    echo "$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
}

relpath_from_home() {
    local target="$1"
    if [[ "$target" == "$HOME"* ]]; then
        echo "${target#$HOME/}"
    else
        echo "$target"
    fi
}

# Helper: Commit changes with message or notify if nothing to commit
commit_changes() {
    local msg="$1"
    if ! git -C "$REPO_DIR" commit -m "$msg" --; then
        echo "Nothing to commit."
    else
        echo "Committed: $msg"
    fi
}

# Helper: Backup tracked files from HOME to BACKUP_DIR
backup_files() {
    local backup_dir="$1"
    mkdir -p "$backup_dir"
    local files
    files=$(git -C "$REPO_DIR" ls-files "home")

    for f in $files; do
        local relpath="${f#home/}"
        local src="$HOME/$relpath"
        if [ -e "$src" ]; then
            local dest="$backup_dir/$relpath"
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
            echo "Backed up $src -> $dest"
        fi
    done
}

# Helper: Apply tracked dotfiles from repo to HOME
apply_files() {
    local files
    files=$(git -C "$REPO_DIR" ls-files "home")

    for f in $files; do
        local relpath="${f#home/}"
        local src="$WORK_TREE/$relpath"
        local dest="$HOME/$relpath"
        mkdir -p "$(dirname "$dest")"
        cp -au "$src" "$dest"
        echo "Applied $dest"
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
                    echo "Warning: ignoring unknown option $1"
                    shift
                    ;;
            esac
        done

        if [[ -z "$REMOTE_URL" ]]; then
            echo "Error: --remote <url> is required."
            echo "Usage: $0 init --remote <url> [--branch <branch>]"
            exit 1
        fi

        if [ -d "$REPO_DIR/.git" ]; then
            echo "Repository already initialized in $REPO_DIR"
            exit 1
        fi

        mkdir -p "$WORK_TREE"
        git init "$REPO_DIR"

        echo "Renaming default branch to: $DEFAULT_BRANCH"
        git -C "$REPO_DIR" branch -M "$DEFAULT_BRANCH"

        echo "Setting remote origin to: $REMOTE_URL"
        git -C "$REPO_DIR" remote add origin "$REMOTE_URL"

        echo "Dotfiles repository initialized at: $REPO_DIR"
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
                        echo "Warning: ignoring extra argument $1"
                        shift
                    fi
                    ;;
            esac
        done

        if [ -z "$url" ]; then
            echo "Error: clone requires a repository URL"
            echo "Usage: $0 clone <remote-url> [--branch <branch>]"
            exit 1
        fi

        echo "Cloning repository from $url into $REPO_DIR..."
        git clone "$url" "$REPO_DIR"

        if [ -n "$branch" ]; then
            echo "Checking out branch: $branch"
            git -C "$REPO_DIR" checkout "$branch"
        fi

        echo "Repository cloned successfully."
        ;;

    switch)
        require_repo

        branch="${1:-}"
        if [ -z "$branch" ]; then
            echo "Error: switch requires a branch name"
            exit 1
        fi

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)

        if git -C "$REPO_DIR" rev-parse --verify --quiet "$branch"; then
            git -C "$REPO_DIR" checkout "$branch"
            echo "Switched to existing branch: $branch"
            exit 0
        fi

        echo "Local branch not found, trying to fetch from remote..."
        if ! git -C "$REPO_DIR" fetch origin "$branch"; then
            echo "Error: branch '$branch' not found locally or on remote."
            exit 1
        fi

        echo "Creating and tracking remote branch: $branch"
        if ! git -C "$REPO_DIR" checkout -b "$branch" --track "origin/$branch"; then
            echo "Error: failed to create and switch to tracking branch '$branch'."
            exit 1
        fi

        echo "Switched to new tracking branch: $branch"
        ;;

    copy)
        require_repo

        new_branch="${1:-}"
        if [ -z "$new_branch" ]; then
            echo "Error: copy requires a new branch name"
            exit 1
        fi

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/heads/$new_branch" >/dev/null; then
            echo "Error: branch '$new_branch' already exists"
            exit 1
        fi

        git -C "$REPO_DIR" checkout -b "$new_branch" "$current_branch"
        echo "Created and switched to new branch '$new_branch' from '$current_branch'"
        ;;

    create-empty-branch)
        require_repo

        new_branch="${1:-}"
        if [ -z "$new_branch" ]; then
            echo "Error: create-empty-branch requires a branch name"
            exit 1
        fi

        if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/heads/$new_branch" >/dev/null; then
            echo "Error: branch '$new_branch' already exists"
            exit 1
        fi

        echo "Creating empty orphan branch: $new_branch"
        git -C "$REPO_DIR" checkout --orphan "$new_branch"
        git -C "$REPO_DIR" rm -rf .
        git -C "$REPO_DIR" commit --allow-empty -m "Initial empty commit on $new_branch"
        echo "Created empty branch '$new_branch'"
        ;;


    sync)
        require_repo

        echo "Starting sync with remote..."
        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        echo "Current branch: $current_branch"

        git -C "$REPO_DIR" fetch origin

        if ! git -C "$REPO_DIR" rev-parse --verify --quiet "origin/$current_branch"; then
            echo "Error: remote branch origin/$current_branch does not exist."
            exit 1
        fi

        git -C "$REPO_DIR" reset --hard "origin/$current_branch"

        echo "Synchronized with remote: $current_branch"
        ;;

    tag)
        require_repo

        tag="${1:-}"
        if [ -z "$tag" ]; then
            echo "Error: tag requires a tag name"
            exit 1
        fi

        if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
            echo "Error: tag '$tag' already exists"
            exit 1
        fi

        git -C "$REPO_DIR" tag "$tag"
        git -C "$REPO_DIR" push origin --tags

        echo "Created tag: $tag"
        ;;

    list-tags)
        require_repo

        git -C "$REPO_DIR" tag
        ;;

    checkout-tag)
        require_repo

        tag="${1:-}"
        if [ -z "$tag" ]; then
            echo "Error: checkout-tag requires a tag name"
            exit 1
        fi

        if ! git -C "$REPO_DIR" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
            echo "Error: tag '$tag' not found"
            exit 1
        fi

        if git -C "$REPO_DIR" checkout "$tag"; then
            echo "Checked out tag: $tag"
        else
            echo "Error: failed to checkout tag '$tag'"
            exit 1
        fi
        ;;

    add)
        require_repo

        if [ "$#" -eq 0 ]; then
            echo "Error: add requires at least one file"
            exit 1
        fi

        added_paths=()
        added_files=0
        added_dirs=0
        for user_path in "$@"; do
            abs_path="$(abspath "$user_path")"

            if [[ "$abs_path" != "$HOME"* ]]; then
                echo "Skipping $user_path: outside home directory"
                continue
            fi

            relpath="$(relpath_from_home "$abs_path")"
            dest="$WORK_TREE/$relpath"

            [ -e "$dest" ] && rm -rf "$dest"
            mkdir -p "$(dirname "$dest")"
            cp -a "$abs_path" "$dest"
            if [ -d "$abs_path" ]; then
                echo "Copied directory: $relpath"
                ((added_dirs++))
            else
                echo "Copied file: $relpath"
                ((added_files++))
            fi

            git -C "$REPO_DIR" add "home/$relpath"
            added_paths+=("$relpath")
        done

        if [ $added_files -gt 0 ] && [ $added_dirs -gt 0 ]; then
            msg="track: added $added_files files and $added_dirs directories"
        elif [ $added_files -gt 0 ]; then
            msg="track: added $added_files files"
        else
            msg="track: added $added_dirs directories"
        fi

        if [ "${#added_paths[@]}" -eq 0 ]; then
            echo "Nothing was added."
            exit 0
        fi

        commit_changes "$msg"
        ;;

    rm)
        require_repo

        if [ "$#" -eq 0 ]; then
            echo "Error: rm requires at least one file"
            exit 1
        fi

        removed_paths=()
        removed_files=0
        removed_dirs=0

        for user_path in "$@"; do
            abs_path="$(abspath "$user_path")"

            if [[ "$abs_path" != "$HOME"* ]]; then
                echo "Skipping $user_path: outside home directory"
                continue
            fi

            relpath="$(relpath_from_home "$abs_path")"
            repo_path="$WORK_TREE/$relpath"

            if [ -e "$repo_path" ]; then
                git -C "$REPO_DIR" rm -r "home/$relpath"
                echo "Removed and staged deletion: $relpath"
                removed_paths+=("$relpath")
                if [ -d "$repo_path" ]; then
                    ((removed_dirs++))
                else
                    ((removed_files++))
                fi
            else
                echo "Not found in repo: $relpath"
            fi
        done

        if [ $removed_files -gt 0 ] && [ $removed_dirs -gt 0 ]; then
            msg="track: removed $removed_files files and $removed_dirs directories"
        elif [ $removed_files -gt 0 ]; then
            msg="track: removed $removed_files files"
        else
            msg="track: removed $removed_dirs directories"
        fi

        if [ "${#removed_paths[@]}" -eq 0 ]; then
            echo "Nothing removed."
            exit 0
        fi

        commit_changes "$msg"
        ;;

    status)
        require_repo

        git -C "$REPO_DIR" status
        ;;

    apply)
        require_repo

        timestamp=$(date +%Y%m%d%H%M%S)
        backup_dir="$BACKUP_DIR_BASE/$timestamp"

        echo "Backing up files to $backup_dir"
        backup_files "$backup_dir"

        echo "Applying dotfiles..."
        apply_files

        echo "Dotfiles applied."
        ;;

    push)
        require_repo

        current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
        echo "Pushing current branch: $current_branch"
        git -C "$REPO_DIR" push origin "$current_branch"
        ;;

    cleanup-backup)
        keep_days=30

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --keep-days)
                    keep_days="$2"
                    shift 2
                    ;;
                *)
                    echo "Warning: ignoring unknown option $1"
                    shift
                    ;;
            esac
        done

        if ! [[ "$keep_days" =~ ^[0-9]+$ ]]; then
            echo "Error: --keep-days requires a numeric argument"
            exit 1
        fi

        echo "Cleaning up backups older than $keep_days days in $BACKUP_DIR_BASE..."
        deleted=0
        if [ -d "$BACKUP_DIR_BASE" ]; then
            while IFS= read -r -d '' dir; do
                rm -rf "$dir"
                echo "Deleted backup: $dir"
                ((deleted++))
            done < <(find "$BACKUP_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep_days" -print0)
        fi

        if [ "$deleted" -eq 0 ]; then
            echo "No backups older than $keep_days days were found."
        else
            echo "Cleanup completed: $deleted backups removed."
        fi
        ;;

    help|*)
        usage
        ;;
esac
