# sdfm - Simple DotFiles Manager

A small Bash script that keeps each machine's public dotfiles on its own branch of one Git
repository. Branches share nothing: each one is a complete set of files for one machine.

Files are copied, not symlinked, into a repository at `~/.local/share/sdfm/repo`. It is
meant for files without secrets; Git keeps only the executable bit, so other permissions
are not restored.

Requires Bash 3.2+ and Git.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/en9inerd/sdfm/master/install.sh | bash
```

Run the same command again to update.

Make sure `~/.local/bin` is in your `PATH`. Run the same commands again to update.

## Commands

```
  clone <url> <branch>    Clone the repo and check out this machine's branch
                          (created empty if it does not exist yet)
  add <path>...           Copy files or directories from $HOME into the repo
  rm <path>...            Stop tracking files or directories
  list                    List tracked files
  diff                    Show differences between $HOME and the repo
  update                  Copy changed tracked files from $HOME into the repo
  apply                   Copy the repo's files into $HOME, backing up what changes
  push                    Push this machine's branch
  list-backups            List backups made by apply
  restore <timestamp>     Copy a backup back into $HOME
  git <args>              Run a git command in the repo
  help                    Show this help
```

## Usage

Create an empty repository on your Git host once. Then on each new machine, pick a branch
name for it:

```bash
sdfm clone git@github.com:you/dotfiles.git macbook
sdfm add ~/.zshrc ~/.config/nvim ~/.config/ghostty
sdfm push
```

Day to day:

```bash
sdfm diff          # what changed in $HOME
sdfm update        # copy the changes into the repo and commit
sdfm push
```

Restoring a machine:

```bash
sdfm clone git@github.com:you/dotfiles.git macbook
sdfm diff
sdfm apply
```

Undoing an `apply`:

```bash
sdfm list-backups
sdfm restore 20261119151340
rm -rf ~/.local/share/sdfm/backups/20261119151340   # delete a backup
```

Anything else goes through Git:

```bash
sdfm git status
sdfm git log -p    # review contents before pushing
sdfm git pull      # after editing the branch elsewhere, then sdfm apply
```

## Notes

- A directory is added file by file and nested `.git` directories are skipped. Files
  created in it later need another `sdfm add`.
- A tracked file missing from `$HOME` stays in the repository; `update` reports it.
  Stop tracking it with `sdfm rm`.
- Adding a file whose name looks sensitive (`.ssh/id_*`, `.env`, `*token*`, `.gnupg/*`,
  ...) asks first. Contents are not checked.
- Commits ask for confirmation. Without a terminal the answer is no and the change is
  discarded; use `yes | sdfm update` in scripts.

## License

MIT
