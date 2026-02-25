# CLAUDE.md — Ansible Home Infrastructure Project

## Project Overview

This project automates the configuration of personal home and home-lab
infrastructure using Ansible. It manages servers, workstations, laptops,
desktops, and development/testing environments. Any host can be brought to its
desired state by running a single `ansible-pull` command. The entire
configuration is testable against Arch Linux, Ubuntu, and Debian using
Molecule.

## Project Status

**Current Status**: Milestone 4 In Progress

Milestones 1–3 are complete. The controller repo, scaffold role, and base
role are live on GitHub with passing CI. The test-runner sidecar is
operational — Molecule tests run from within Claude Code sessions via SSH.

Milestone 4 (single-VM integration testing with Arch Linux) is in progress.

---

## Active Milestone Workflow

Each milestone has a working document at **`active-milestone.md`** in the
workspace root. This file tracks the current milestone's granular progress:
tasks, subtasks, decisions made during implementation, blockers, and
iteration notes.

- **`docs/milestones.md`** is the stable reference — milestone goals,
  deliverables, and exit criteria. It does not change during implementation.
- **`active-milestone.md`** is the working document — granular task
  tracking that survives across Claude Code sessions. It is overwritten
  when a new milestone begins.
- At the start of each new Claude Code session, read `active-milestone.md`
  to understand where work left off.
- When a milestone is complete, delete `active-milestone.md` (or overwrite
  it with the next milestone's content), update `docs/milestones.md` status
  if needed, and update the Project Status section above.

---

## Architecture Summary

- **Composition unit:** Standalone Ansible roles (not collections). Each role
  lives in its own Git repo under a dedicated GitHub organization.
- **Controller repository:** Single repo (`ansible-controller`) containing the
  playbook (`local.yml`), inventory, and `requirements.yml`. This is what
  `ansible-pull` clones.
- **GitHub organization:** `scbitworx` under a dedicated GitHub org.

> For detailed rationale (roles vs. collections, standalone vs. dependency
> chains, resource ownership), see [docs/architecture.md](docs/architecture.md)

### Role Layers and Composition

```text
Layer 1 (all hosts):       base
Layer 2 (by group):        server, workstation, laptop
Layer 3 (by host):         <extension roles>
Layer 4 (all hosts, last): dotfiles
```

All roles are **standalone** — no `meta/main.yml` dependencies. The playbook
(`local.yml`) is the single place that defines which roles run on which hosts
and in what order.

### Extension Roles (Examples)

| Role                          | Layer       | Purpose                        |
| ----------------------------- | ----------- | ------------------------------ |
| `syncthing_server`            | server      | Syncthing relay/server         |
| `taskchampion_sync_server`    | server      | TaskChampion sync service      |
| `devbox`                      | workstation | Development toolchains         |
| `hypervisor`                  | workstation | Virtualization / containers    |
| `intuos_pro`                  | workstation | Wacom tablet configuration     |
| `darp6`                       | laptop      | System76 darp6 hardware quirks |

---

## Naming Conventions

### Character Rules

| Context                   | Allowed Characters                    | Separator |
| ------------------------- | ------------------------------------- | --------- |
| Ansible role names        | lowercase alphanumeric + underscore   | `_`       |
| Ansible Galaxy namespaces | lowercase alphanumeric + underscore   | `_`       |
| Ansible variables         | lowercase alphanumeric + underscore   | `_`       |
| GitHub org names          | alphanumeric + hyphen                 | `-`       |
| GitHub repo names         | alphanumeric + hyphen + underscore    | mixed     |

### Naming Rules

- **GitHub org:** `scbitworx`
- **Role repos:** `ansible-role-<role_name>` (e.g., `ansible-role-syncthing_server`)
- **Controller repo:** `ansible-controller`
- **Role names:** lowercase alphanumeric + underscores only. Enforced by
  `ansible-lint` (`^[a-z][a-z0-9_]*$`). Set explicitly in `meta/main.yml`
  via `galaxy_info.role_name`.
- **Public variables** (`defaults/main.yml`): `<role_name>_` prefix
  (e.g., `base_packages`, `syncthing_server_port`)
- **Private variables** (`vars/`): `__<role_name>_` prefix
  (e.g., `__base_distro_packages`)
- **Tags:** prefixed with role name
- **Handlers:** `<Role_name> | <action>` (e.g., `Syncthing_server | restart`).
  First letter must be uppercase to satisfy ansible-lint `name[casing]` rule.
- **Task names:** Descriptive sentences starting with a verb

### Complete Naming Map (Template)

```text
GitHub Org:            scbitworx
Galaxy Namespace:      scbitworx

Repo name:             ansible-role-syncthing_server
Role name:             syncthing_server
Galaxy FQDN:           scbitworx.syncthing_server
Variable prefix:       syncthing_server_
Private var prefix:    __syncthing_server_
Tag prefix:            syncthing_server
Handler format:        Syncthing_server | <action>
meta/main.yml:         role_name: syncthing_server
```

> For detailed rationale (hyphens vs. underscores debate, community
> precedents), see [docs/naming-rationale.md](docs/naming-rationale.md)

---

## Hosts and Inventory

| Hostname | Type    | OS         | Groups                | Notes                   |
| -------- | ------- | ---------- | --------------------- | ----------------------- |
| ceres    | Laptop  | Arch Linux | workstations, laptops | System76 darp6 hardware |
| mars     | Desktop | Arch Linux | workstations          | Desktop workstation     |
| jupiter  | Server  | Arch Linux | servers               | Future: migrate to Ubuntu/Debian |

### Inventory Structure

```yaml
all:
  children:
    servers:
      hosts:
        jupiter:
    workstations:
      hosts:
        ceres:
        mars:
    laptops:
      hosts:
        ceres:
```

### Variable Precedence (most specific wins)

1. Role defaults (`defaults/main.yml`) — lowest
2. `group_vars/all.yml`
3. `group_vars/<group>.yml`
4. `host_vars/<host>.yml`
5. Play/task vars, extra vars — highest

### Inventory File Layout

```text
inventory/
  hosts.yml
  group_vars/
    all.yml, servers.yml, workstations.yml, laptops.yml
  host_vars/
    ceres.yml, mars.yml, jupiter.yml
```

---

## Controller Repository Structure

```text
ansible-controller/
  ansible.cfg
  local.yml                          # main playbook
  requirements.yml                   # all roles with version pins (lockfile)
  scripts/
    bootstrap.sh                     # first-run bootstrap
    integration/                     # virsh-based integration testing
      create-base-vms.sh
      run-integration-test.sh
      verify-state.sh
  templates/
    ansible-pull-wrapper.sh.j2       # wrapper deployed to /usr/local/bin/
    ansible-vault-client.sh.j2       # vault password client (pass backend)
    ansible-vault-secret.sh.j2       # encrypt-a-string helper
    ansible-vault-reveal.sh.j2       # decrypt-and-display helper
    ansible-mkpasswd.sh.j2           # interactive password hash generator
  inventory/
    hosts.yml
    group_vars/ ...
    host_vars/ ...
```

> For `local.yml` playbook structure, `ansible-pull` workflow, wrapper script
> details, bootstrap flow, and scheduling policy, see
> [docs/ansible-pull.md](docs/ansible-pull.md)

---

## Role Directory Structure (Template)

```text
ansible-role-<role_name>/
  defaults/main.yml          # public variables (role-name-prefixed)
  files/                     # static files
  handlers/main.yml          # handlers (role-name-prefixed)
  meta/main.yml              # Galaxy metadata (no dependencies)
  molecule/default/          # Docker-based tests
    molecule.yml, converge.yml, prepare.yml, verify.yml
  tasks/
    main.yml                 # entry point
    Archlinux.yml            # distro-specific tasks (if needed)
    Debian.yml               # shared Ubuntu/Debian tasks (if needed)
  templates/                 # Jinja2 templates
  tests/inventory, test.yml  # legacy test dir
  vars/
    Archlinux.yml            # Arch-specific variables
    Debian.yml               # shared Ubuntu/Debian variables
    main.yml                 # cross-distro internal variables
  .github/workflows/ci.yml   # GitHub Actions CI pipeline
  README.md, LICENSE, .ansible-lint, .yamllint, .gitignore
```

### `meta/main.yml` Template

```yaml
galaxy_info:
  role_name: <role_name>
  namespace: scbitworx
  author: bwright
  description: <description>
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Debian
      versions: [all]

dependencies: []
```

> **Note:** Galaxy platform name is `ArchLinux` (capital L), not `Archlinux`.
> Ubuntu/Debian use `all` because the Galaxy schema doesn't include recent
> codenames (`noble`, `bookworm`). The `namespace` field is used by Molecule
> for role resolution.

---

## Distro Compatibility

| Distribution | Use Case                       | Testing |
| ------------ | ------------------------------ | ------- |
| Arch Linux   | Workstations (current primary) | Yes     |
| Ubuntu       | Servers, potential workstations | Yes    |
| Debian       | Servers, potential workstations | Yes    |

Each role uses `first_found` + `include_vars` for distro-specific variables
and `ansible.builtin.package` for package manager abstraction. Most roles
need only `Archlinux.yml`, `Debian.yml`, and `main.yml`.

**Arch Linux package constraint:** All roles must use `state: present`, never
`state: latest`. On Arch, upgrading a single package without a full system
upgrade (`pacman -Syu`) is a partial upgrade that can cause shared library
mismatches. `state: present` is safe — it only installs missing packages.
Unattended full system upgrades on Arch are unsafe and are not performed.

> For the full `first_found` pattern, cascading specificity details, and
> rationale for per-role distro handling, see
> [docs/distro-compatibility.md](docs/distro-compatibility.md)
>
> For detailed Arch partial upgrade rationale, see
> [docs/architecture.md](docs/architecture.md#package-state-and-arch-linux-partial-upgrades)

---

## Version Pinning

- Tag role repos with semver: `v1.0.0`, `v1.1.0`, `v2.0.0`
- Controller `requirements.yml` pins exact tags (no branch names, no ranges)
- `ansible-galaxy` has no semver range support for roles — this is a tooling
  constraint, not a style choice
- `requirements.yml` serves as both dependency declaration and lockfile

> For detailed rationale and tooling constraints, see
> [docs/architecture.md](docs/architecture.md#version-pinning-via-controller-requirementsyml)

---

## Resource Ownership

Each file, package, and config resource is owned by **exactly one role**.

| Concern                      | Owner              | Example                    |
| ---------------------------- | ------------------ | -------------------------- |
| Base packages                | `base`             | `base_packages`            |
| Server packages              | `server`           | `server_packages`          |
| Workstation packages         | `workstation`      | `workstation_packages`     |
| Service-specific packages    | Extension role     | `syncthing_server` owns syncthing |
| `ansible-pull` wrapper       | Controller `pre_tasks` | `/usr/local/bin/ansible-pull-wrapper` |
| Vault scripts                | Controller `pre_tasks` | `/usr/local/bin/ansible-vault-client` |
| `ansible-pull` scheduling    | `base`             | Systemd timer (interval overridable via group_vars) |
| Unattended security upgrades | `base`             | `unattended-upgrades` on Debian/Ubuntu; no-op on Arch |
| User-level personal config   | `dotfiles`         | `~/.config/git/config`     |

---

## Secrets Management

Vault-encrypted variables are stored in the inventory and decrypted at
runtime via `--vault-id`. The vault password is retrieved from `pass`
(password-store), backed by GPG.

- **Vault ID:** `scbitworx`
- **Pass store prefix:** `scbitworx/` (e.g., `scbitworx/vault-password`)
- **Vault client:** `/usr/local/bin/ansible-vault-client` (deployed by controller)
- **Password hashing:** `openssl passwd -6 -rounds 500000` (via `ansible-mkpasswd`)

Helper scripts deployed by the controller to `/usr/local/bin/`:

| Script | Purpose |
|--------|---------|
| `ansible-vault-client` | Retrieves vault password from `pass` |
| `ansible-vault-secret` | Encrypts a string as a vault variable |
| `ansible-vault-reveal` | Decrypts a variable from a YAML file |
| `ansible-mkpasswd` | Generates SHA-512 password hashes interactively |

> For detailed rationale (why `pass`, vault ID strategy, resource ownership),
> see [docs/architecture.md](docs/architecture.md#secrets-management)

---

## Testing Strategy

- **Unit testing:** Molecule + Docker (systemd in container) for all roles.
  Three platforms: Arch, Ubuntu, Debian.
- **Arch image:** Official `archlinux/archlinux:latest` + `prepare.yml` for
  Python and sudo. No third-party dependency.
- **Ubuntu/Debian images:** `geerlingguy/docker-ubuntu2404-ansible`,
  `geerlingguy/docker-debian12-ansible`
- **Integration testing:** Disposable virsh VMs with snapshot-revert for
  full-stack validation (bootstrap through `ansible-pull`). **Never run
  against production hosts** (`ceres`, `mars`, `jupiter`) — only against
  temporary libvirt VMs that model their role stacks.

> For Molecule configuration, Docker image details, `prepare.yml` patterns,
> and precondition handling, see
> [docs/molecule-testing.md](docs/molecule-testing.md)

### Test-Runner Sidecar (Claude Code Sessions)

Molecule requires Docker access to create test containers. The Claude Code
container is hardened (cap-drop=ALL, read-only root, no-new-privileges) and
does **not** have Docker socket access. A **test-runner sidecar** container
handles Molecule execution instead.

**How it works:** Claude Code SSHs into the test-runner to run Molecule.
Both containers share the same `/workspace` bind mount, so file edits are
immediately visible to Molecule.

```bash
# From inside Claude Code — run molecule tests for any role:
ssh test-runner "cd /workspace/ansible-role-<name> && molecule test"

# Fast iteration (keep containers between runs):
ssh test-runner "cd /workspace/ansible-role-<name> && molecule converge"
ssh test-runner "cd /workspace/ansible-role-<name> && molecule verify"
ssh test-runner "cd /workspace/ansible-role-<name> && molecule destroy"
```

**Security model:** The test-runner has Docker access but zero credentials
(no API keys, no GitHub tokens, no `~/.claude`). The Claude Code container
has credentials but no Docker access. Compromise of either container alone
does not grant full access.

> For sidecar architecture, build instructions, and security details, see
> [docs/workspace-setup.md](docs/workspace-setup.md#molecule-testing-test-runner-sidecar)

---

## Dotfiles Architecture

- **Infrastructure roles** install software and manage `/etc/`. They do not
  deploy personal user preferences.
- **The `dotfiles` role** owns all user-level config under `~/.config/`.
  Uses `package_facts` for runtime detection — deploys config only for
  installed software.
- XDG `~/.config/` convention with symlinks for legacy tools.
- Shell `conf.d/` drop-in pattern: `base` deploys `~/.config/bash/bashrc`
  with a sourcing loop; `dotfiles` drops fragments into `conf.d/`.
- Login profile lives at `~/.config/profile` (not under `bash/`) because it
  is sourced by display managers and POSIX shells — not just bash.
  `~/.profile` symlinks to it.
- Bash login profile at `~/.config/bash/bash_profile` ensures bash login
  shells source `~/.profile`. `~/.bash_profile` symlinks to it.

> For full dotfiles architecture, XDG conventions, symlink tables, detection
> patterns, and file structure, see [docs/dotfiles.md](docs/dotfiles.md)

---

## Implementation Milestones

| # | Milestone                          | Summary                                    |
|---|------------------------------------|--------------------------------------------|
| 1 | Foundation                         | GitHub org + controller repo               |
| 2 | Scaffold Role + Testing + CI/CD    | Walking skeleton to validate full pipeline |
| 3 | Base Role                          | Core system configuration                  |
| 4 | Single-VM Integration (Arch)       | Validate controller pipeline end-to-end    |
| 5 | Server + Workstation Roles         | Group-level core roles                     |
| 6 | Laptop Core Role                   | Laptop-specific core role                  |
| 7 | Initial Extension Roles            | First extension roles to validate pattern  |
| 8 | Dotfiles Role                      | Personal config with runtime detection     |
| 9 | Full Integration Matrix            | All distros, all profiles with disposable VMs |

> For detailed task lists, deliverables, and exit criteria for each
> milestone, see [docs/milestones.md](docs/milestones.md)

---

## Key Design Decisions Summary

| Decision               | Choice                    | Rationale                                       |
| ---------------------- | ------------------------- | ----------------------------------------------- |
| Composition unit       | Standalone roles          | Simpler than collections for single maintainer   |
| Repo strategy          | One repo per role         | Independent versioning and testing               |
| Repo hosting           | GitHub Organization       | Keeps personal profile clean                     |
| Org naming             | `scbitworx`               | GitHub does not allow underscores in org names   |
| Repo naming            | `ansible-role-<name>`     | Convention recognized by `ansible-galaxy`         |
| Role naming            | Underscores only          | Required by `ansible-lint`; matches repo name    |
| Variable naming        | `<role_name>_` prefix     | Prevents namespace collisions                    |
| Version pinning        | Controller `requirements.yml` (exact tags) | No range support; lockfile pattern  |
| Role composition       | Playbook-driven, no `meta/main.yml` deps | Standalone; independently testable  |
| Resource ownership     | Each resource owned by exactly one role | No idempotency conflicts            |
| Distro compatibility   | Per-role `first_found` + `include_vars` | Cascading specificity; graceful fallback |
| Entry point            | `ansible-pull`            | Self-contained, no control node needed           |
| Testing (unit)         | Molecule + Docker         | Community standard; seconds to spin up           |
| Testing (integration)  | Disposable virsh VMs      | Full kernel, real systemd, real package manager  |
| Dotfiles               | Single role + runtime detection | Decoupled from infra roles              |
| Shell config           | `conf.d/` drop-ins        | No file conflicts between roles                  |
| Secrets backend        | `pass` + GPG              | No service deps, offline, hardware key support   |
| Package state          | `state: present` only     | Avoids Arch partial upgrades; consistent across distros |
| `ansible-pull` schedule | `base` role (systemd timer) | All hosts converge; interval overridable via group_vars |
| Unattended upgrades    | `base` role (Debian/Ubuntu only) | No-op on Arch; unsafe on rolling release    |

---

## Repository Listing

```text
scbitworx/
  ansible-controller
  ansible-role-scaffold
  ansible-role-base
  ansible-role-server
  ansible-role-workstation
  ansible-role-laptop
  ansible-role-dotfiles
  ansible-role-darp6
  ansible-role-syncthing_server
  ansible-role-taskchampion_sync_server
  ansible-role-devbox
  ansible-role-hypervisor
  ansible-role-intuos_pro
  ...
```

---

## Resolved Values

- **GitHub organization:** `scbitworx`
- **Galaxy namespace:** `scbitworx`
- **Author (Galaxy metadata):** `bwright`
- **Hostnames:** `ceres`, `mars`, `jupiter` (confirmed as actual
  `/etc/hostname` values)

## Tooling Documentation

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Galaxy User Guide](https://docs.ansible.com/projects/galaxy-ng/en/latest/community/userguide)
- [Molecule Documentation](https://docs.ansible.com/projects/molecule/)
- [Docker Documentation](https://docs.docker.com)
- [libvirt Documentation](https://libvirt.org/docs.html)
- [virsh Documentation](https://www.libvirt.org/manpages/virsh.html)
- [GitHub Documentation](https://docs.github.com/en)

## Detailed Reference Documentation

- [active-milestone.md](active-milestone.md) — **Read this first** — current milestone granular task tracking
- [docs/architecture.md](docs/architecture.md) — Architecture rationale, role composition, resource ownership, version pinning
- [docs/naming-rationale.md](docs/naming-rationale.md) — Why underscores, community precedents, variable conventions
- [docs/ansible-pull.md](docs/ansible-pull.md) — Playbook structure, wrapper script, bootstrap, scheduling
- [docs/distro-compatibility.md](docs/distro-compatibility.md) — `first_found` pattern, per-role distro handling
- [docs/molecule-testing.md](docs/molecule-testing.md) — Docker config, image choices, prepare.yml, preconditions
- [docs/dotfiles.md](docs/dotfiles.md) — XDG conventions, runtime detection, shell drop-in pattern
- [docs/milestones.md](docs/milestones.md) — Implementation milestones with full task lists
- [docs/workspace-setup.md](docs/workspace-setup.md) — Claude Code container setup checklist
