# sdfm - Simple Dotfiles Manager

A lightweight Bash tool for managing your dotfiles in a Git repository with easy backup and environment switching.

---

## Features

- Initialize or clone a dotfiles repository  
- Track files and directories under `$HOME`  
- Create and switch between environments (branches)  
- Backup existing files before applying new ones  
- Tag and version your configurations  
- Synchronize with remote  
- Simple, dependency-free (just Bash + Git)

---

## Installation

Copy `sdfm` into your `PATH` (e.g., `~/bin`) and make it executable:

```bash
chmod +x sdfm
```

## Usage

```bash
sdfm <command> [options]
```

Run `sdfm help` for a full command list:

```bash
Repository Setup:
  init --remote <url> [--branch <branch>]   Initialize dotfiles repo with remote and optional branch
  clone <url> [--branch <branch>]           Clone remote dotfiles repo
  create-empty-branch <branch>              Create a new empty orphan branch

Environment Management:
  switch <branch>           Switch to environment (Git branch)
  copy <new-branch>         Create and switch to a new branch from current
  sync                      Sync with remote (pull & hard reset)
  pull [--merge]            Pull latest changes from remote (fast-forward by default, use --merge to allow merge commits)
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
sdfm sync
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

You can restore files manually from there if needed.

## Requirements

- Git
- Bash

## License

MIT
