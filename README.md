# sdfm - Simple DotFiles Manager

A lightweight Bash tool for managing your dotfiles in a Git repository with easy backup and environment switching.

---

## Features

- Initialize or clone a dotfiles repository  
- Track files and directories under `$HOME`  
- Create and switch between environments (branches)  
- Backup existing files before applying new ones  
- Tag and version your configurations  
- Synchronize with remote  
- Minimal dependencies (Bash, Git, rsync)

---

## Installation

You can install **sdfm** automatically with the provided `install.sh` script:

```bash
curl -fsSL https://raw.githubusercontent.com/en9inerd/sdfm/master/install.sh | bash
```

## Usage

```bash
sdfm <command> [options]
```

Run `sdfm help` for a full command list:

```
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
  add <file>...                                  Copy file(s) from $HOME to repo
  rm <file>...                                   Remove file(s) from repo
  list                                           List tracked files
  update [--dry-run]                             Update tracked files from $HOME
  status                                         Show status
  log                                            Show log
  diff                                           Show differences between $HOME and repo
  apply [--dry-run]                              Backup and apply dotfiles to $HOME

Backup Maintenance:
  list-backups                                   List available backups
  restore <timestamp>                            Restore files from a backup
  cleanup-backup [--keep-days <n>] [--dry-run]   Delete old backups (default: 30 days)

Other:
  git <args>                                     Run arbitrary git command in repo
  help                                           Show this help
```

## Example Workflow

1. Initialize a new repository  

```bash
sdfm init --remote git@github.com:yourname/dotfiles.git --branch main
```

2. Add and commit dotfiles  

```bash
sdfm add ~/.bashrc ~/.vimrc ~/.config/nvim
```

3. Push changes

```bash
sdfm push
```

4. Apply configuration

This backs up current files before overwriting them:

```bash
sdfm apply
```

5. Switch environments

Create a new branch:

```bash
sdfm copy work-env
```

Switch to it:

```bash
sdfm switch work-env
```

6. Sync with remote  

```bash
sdfm sync --force
```

7. Tag configuration

```bash
sdfm tag initial-setup
```

List tags:

```bash
sdfm list-tags
```

Checkout a tagged version:

```bash
sdfm checkout-tag initial-setup
```

## Backups

Every `apply` creates a backup in:

```bash
$HOME/.local/share/sdfm/backups/<timestamp>
```

List available backups:

```bash
sdfm list-backups
```

Restore from a backup:

```bash
sdfm restore 20260201143022
```

Clean up old backups (older than 30 days by default):

```bash
sdfm cleanup-backup
sdfm cleanup-backup --keep-days 7
sdfm cleanup-backup --dry-run  # Preview what would be deleted
```

## Dry-Run Mode

Preview changes before applying them:

```bash
sdfm apply --dry-run      # See what files would be overwritten
sdfm update --dry-run     # See what files would be updated in repo
sdfm sync --dry-run       # See what local changes would be discarded
```

## Safety Features

- **Sensitive file warnings**: Adding files matching patterns like `.ssh/id_*`, `.env`, `*credentials*` will prompt for confirmation
- **Sync protection**: `sync` requires `--force` flag if there are local changes to discard
- **Automatic backups**: Every `apply` backs up existing files first

## Requirements

- Bash
- Git
- rsync

## License

MIT
