# Dotfiles Architecture — Detailed Reference

This document contains the full dotfiles architecture, XDG conventions,
runtime detection patterns, and shell drop-in configuration.

---

## Design Principles

Personal configuration is split across two concerns:

- **Infrastructure roles** (`base`, `devbox`, `server`, etc.) install software
  and manage system-level configuration (`/etc/`). They do not deploy personal
  user preferences. This keeps infrastructure roles reusable.
- **The `dotfiles` role** owns all user-level personal configuration files. It
  detects which software is installed at runtime and deploys config only for
  software that is present.

---

## XDG Base Directory Convention

All personal configuration files live under `~/.config/`. When a tool natively
supports `~/.config/<tool>/`, files are deployed there directly. When a tool
only reads from `~/`, the file is deployed to `~/.config/<tool>/` and a
symlink is created.

**Tools with native `~/.config/` support (no symlink needed):**

| Tool   | Config path                    |
| ------ | ------------------------------ |
| `git`  | `~/.config/git/config`         |
| `nvim` | `~/.config/nvim/init.lua`      |
| `tmux` | `~/.config/tmux/tmux.conf` (3.1+) |

**Tools requiring symlinks:**

| Tool       | Symlink                | Target                         |
| ---------- | ---------------------- | ------------------------------ |
| `bash`     | `~/.bashrc`            | `~/.config/bash/bashrc`        |
| `bash`     | `~/.profile`           | `~/.config/bash/profile`       |
| `readline` | `~/.inputrc`           | `~/.config/bash/inputrc`       |

The rule: if a tool hardcodes `~/.<something>` as its config path and does not
support `~/.config/`, deploy to `~/.config/<tool>/` and symlink.

---

## User Variables

Each role that deploys user-level files defines a public variable for the
target username in `defaults/main.yml`:

- **`base` role:** `base_user` — the primary user account created/managed by
  the base role. Used for shell skeleton, home directory structure.
- **`dotfiles` role:** `dotfiles_user` — the user whose personal config is
  managed. Defaults to the same value as `base_user`.

Both default to a sensible value in `defaults/main.yml` and can be overridden
via `group_vars/all.yml` or `host_vars/`.

---

## Shell Configuration Drop-In Pattern

The `base` role deploys a `~/.config/bash/bashrc` that sources fragment files
from `~/.config/bash/conf.d/`:

```bash
# ~/.config/bash/bashrc — managed by ansible-role-base

# Core shell settings
export EDITOR=vim
export HISTSIZE=10000

# Source drop-in fragments
if [ -d ~/.config/bash/conf.d ]; then
  for f in ~/.config/bash/conf.d/*.sh; do
    [ -r "$f" ] && . "$f"
  done
fi
```

What `base` creates:

```yaml
# base/tasks/main.yml (shell skeleton excerpt)
- name: Create bash config directories
  ansible.builtin.file:
    path: "~{{ base_user }}/.config/bash/conf.d"
    state: directory
    recurse: true
    owner: "{{ base_user }}"
    mode: "0755"

- name: Deploy bashrc
  ansible.builtin.template:
    src: bashrc.j2
    dest: "~{{ base_user }}/.config/bash/bashrc"
    owner: "{{ base_user }}"
    mode: "0644"

- name: Symlink bashrc to home directory
  ansible.builtin.file:
    src: ".config/bash/bashrc"
    dest: "~{{ base_user }}/.bashrc"
    state: link
    owner: "{{ base_user }}"

- name: Deploy profile
  ansible.builtin.template:
    src: profile.j2
    dest: "~{{ base_user }}/.config/bash/profile"
    owner: "{{ base_user }}"
    mode: "0644"

- name: Symlink profile to home directory
  ansible.builtin.file:
    src: ".config/bash/profile"
    dest: "~{{ base_user }}/.profile"
    state: link
    owner: "{{ base_user }}"
```

The `base` role knows nothing about downstream tools. The `dotfiles` role
drops fragments into `~/.config/bash/conf.d/` for tool-specific
customizations.

---

## Runtime Detection

The `dotfiles` role uses `ansible.builtin.package_facts` to detect installed
software and deploys configuration conditionally:

```yaml
# dotfiles/tasks/main.yml
- name: Gather package facts
  ansible.builtin.package_facts:
    manager: auto

- name: Deploy git config
  ansible.builtin.template:
    src: git/config.j2
    dest: "~{{ dotfiles_user }}/.config/git/config"
    owner: "{{ dotfiles_user }}"
    mode: "0644"
  when: "'git' in ansible_facts.packages"

- name: Deploy git shell aliases
  ansible.builtin.copy:
    src: bash/conf.d/git.sh
    dest: "~{{ dotfiles_user }}/.config/bash/conf.d/git.sh"
    owner: "{{ dotfiles_user }}"
    mode: "0644"
  when: "'git' in ansible_facts.packages"

- name: Deploy tmux config
  ansible.builtin.copy:
    src: tmux/tmux.conf
    dest: "~{{ dotfiles_user }}/.config/tmux/tmux.conf"
    owner: "{{ dotfiles_user }}"
    mode: "0644"
  when: "'tmux' in ansible_facts.packages"

- name: Deploy nvim config
  ansible.builtin.copy:
    src: nvim/init.lua
    dest: "~{{ dotfiles_user }}/.config/nvim/init.lua"
    owner: "{{ dotfiles_user }}"
    mode: "0644"
  when: "'neovim' in ansible_facts.packages"
```

---

## Distro-Aware Package Name Detection

Package names differ across distros. The `dotfiles` role uses the same
`first_found` variable loading pattern:

```yaml
# dotfiles/vars/Archlinux.yml
__dotfiles_package_names:
  neovim: "neovim"
  tmux: "tmux"
  docker: "docker"

# dotfiles/vars/Debian.yml (shared by Ubuntu and Debian)
__dotfiles_package_names:
  neovim: "neovim"
  tmux: "tmux"
  docker: "docker.io"
```

Then in tasks:

```yaml
- name: Deploy docker config
  ansible.builtin.copy:
    src: docker/config.json
    dest: "~{{ dotfiles_user }}/.docker/config.json"
    owner: "{{ dotfiles_user }}"
    mode: "0644"
  when: "__dotfiles_package_names.docker in ansible_facts.packages"
```

For software not installed via package manager, use `ansible.builtin.stat` or
`ansible.builtin.command` with `which` as a fallback.

---

## Dotfiles Role File Structure

```text
ansible-role-dotfiles/
  defaults/
    main.yml                 # dotfiles_user, etc.
  files/
    bash/
      conf.d/
        git.sh               # git aliases and functions
        docker.sh            # docker aliases
    tmux/
      tmux.conf
    nvim/
      init.lua
  templates/
    git/
      config.j2              # needs name/email templated
  tasks/
    main.yml
  vars/
    Archlinux.yml            # Arch-specific package name mappings
    Debian.yml               # shared Ubuntu/Debian package name mappings
    main.yml                 # cross-distro internal variables
  meta/
    main.yml                 # Galaxy metadata (no dependencies)
  molecule/
    default/
      molecule.yml
      converge.yml
      prepare.yml            # installs sample packages to trigger detection
      verify.yml             # asserts files placed with correct ownership
```

---

## Play Ordering

The `dotfiles` role runs in the **last play** of `local.yml`, after all
infrastructure roles have installed their software. This ensures
`package_facts` sees everything installed during the current converge run.
