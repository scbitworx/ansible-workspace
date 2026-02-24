# Architecture — Detailed Rationale

This document contains the detailed architectural rationale for decisions
summarized in [CLAUDE.md](../CLAUDE.md).

---

## Why Standalone Roles, Not Collections

We use **standalone Ansible roles** (not collections) as the primary unit of
composition. Each role lives in its own Git repository under a dedicated GitHub
organization.

- A role is a self-contained unit that configures one logical thing. This maps
  directly to our mental model of `base`, `server`, `workstation`, etc.
- Collections add packaging overhead (namespace resolution, `galaxy.yml`
  metadata, stricter directory layout) that provides no benefit for a single
  maintainer managing personal infrastructure.
- The migration path from standalone roles to a collection is straightforward
  if ever needed; the reverse is messy.
- We have no known need for custom Ansible modules or plugins at this time,
  which is the primary reason to reach for collections.

---

## Why No `meta/main.yml` Dependency Chains

All roles are **standalone** — they do not declare `meta/main.yml`
dependencies on each other. The playbook (`local.yml`) is the single place
that defines which roles run on which hosts and in what order.

It may seem natural to declare that `syncthing_server` depends on `server`
which depends on `base` via `meta/main.yml`. However, this creates problems
without solving any that the playbook doesn't already handle:

- **Redundant with playbook ordering.** `local.yml` already runs `base` on
  all hosts, then `server` on servers, then extension roles on specific
  hosts. The `meta/main.yml` chain would just trigger Ansible's deduplication
  logic to skip roles that have already run — adding complexity for no effect.
- **Increases Molecule complexity.** With `meta/main.yml` dependencies, every
  role needs its entire ancestor chain available during testing (via a
  `requirements.yml` pulling parent roles from GitHub). Without them, each
  role is independently testable — Molecule's `prepare.yml` sets up only the
  minimal preconditions the role actually needs.
- **Creates coupling.** Roles cannot be used, tested, or developed in
  isolation. A change to `base` ripples through every downstream role's test
  setup.
- **Not community practice.** The most widely used Galaxy roles (e.g., Jeff
  Geerling's) are standalone. They document prerequisites but let the
  playbook handle composition.

---

## Resource Ownership (No Overlapping Configuration)

Each file, package list, and configuration resource is owned by **exactly
one role**. This prevents idempotency conflicts regardless of run order and
ensures there is only one place to change any given piece of configuration.

| Concern | Owner | Example |
|---------|-------|---------|
| Base packages (ssh, sudo, etc.) | `base` | `base_packages` variable |
| Server packages (fail2ban, etc.) | `server` | `server_packages` variable |
| Workstation packages (git, GUI tools, etc.) | `workstation` | `workstation_packages` variable |
| System-level config for a core concern | The core role that installs it | `server` owns `/etc/ssh/sshd_config` |
| Service-specific packages and config | The extension role for that service | `syncthing_server` owns syncthing package and `/etc/syncthing/` |
| `ansible-pull` wrapper script | Controller repo (`local.yml` `pre_tasks`) | `/usr/local/bin/ansible-pull-wrapper` |
| Cron scheduling for `ansible-pull` | `server` role | `ansible.builtin.cron` calling the wrapper by path |
| User-level personal config | `dotfiles` | `dotfiles` owns `~/.config/git/config` |

**How this handles overlapping requirements:** If both `devbox` and `dotfiles`
need git to be installed, they don't both install it — `workstation` (or
`base`) owns the git package as part of that layer's package list. `devbox`
and `dotfiles` use git but don't install it. If the git package needs to move
between layers, there is exactly one variable to change.

For packages unique to a single extension role (e.g., syncthing, wacom
drivers), the extension role owns both installation and configuration. No
other role touches them.

---

## Version Pinning via Controller `requirements.yml`

The controller's `requirements.yml` is the single source of truth for what
exact versions of all roles are deployed together. It serves the same function
as a lockfile in other ecosystems.

```yaml
# requirements.yml
roles:
  - name: scbitworx.base
    src: git+https://github.com/scbitworx/ansible-role-base.git
    version: v1.0.0

  - name: scbitworx.server
    src: git+https://github.com/scbitworx/ansible-role-server.git
    version: v1.0.0

  # ... every role listed with explicit version pins
```

### Why the Controller Owns Version Pins

`ansible-galaxy` has no dependency resolver — it cannot handle version
conflicts, has no SAT solver, and does not produce a lockfile. If role A
wants `base v1.2.0` and role B wants `base v1.3.0`, whichever installs last
wins silently. There is no error or warning.

Centralizing all version pins in one file provides:

- **Deterministic deployments:** Every `ansible-pull` run installs the exact
  same set of role versions, regardless of when it runs.
- **Atomic updates:** Bumping `base` from v1.2.0 to v1.3.0 is a single
  commit to the controller, not a coordinated update across every downstream
  role repo.
- **No silent version conflicts:** Because all pins live in one file, version
  mismatches are immediately visible and impossible to accidentally introduce.

| Ecosystem | Library declares needs | Application pins versions |
|-----------|------------------------|---------------------------|
| npm       | `package.json`         | `package-lock.json`       |
| Rust      | `Cargo.toml`           | `Cargo.lock`              |
| Python    | `pyproject.toml`       | lockfile / `pip freeze`   |
| **Ours**  | (roles are standalone) | controller `requirements.yml` |

### Why Exact Pins, Not Semver Ranges

`ansible-galaxy` does not support version ranges for roles — this is a
tooling limitation, not a stylistic choice. The `version` field in
`requirements.yml` accepts only three values:

- A **Git tag** (e.g., `v1.0.0`)
- A **commit hash** (e.g., `ee8aa41`)
- A **branch name** (e.g., `main`)

The value is passed directly to `git checkout` under the hood, so it must
resolve to a single concrete Git ref. There is no semver resolution layer.
This has been raised with the Ansible project
([ansible/ansible#83790](https://github.com/ansible/ansible/issues/83790),
[ansible/ansible#68194](https://github.com/ansible/ansible/issues/68194))
and confirmed as by-design.

This means `requirements.yml` simultaneously serves as both the dependency
declaration and the lockfile. Bumping a role version is always a manual edit.
Jeff Geerling maintains
[ansible-requirements-updater](https://github.com/geerlingguy/ansible-requirements-updater)
specifically to automate checking pinned roles for newer versions — evidence
that this manual workflow is the standard practice.

**Key rules:**

- Always pin versions in `requirements.yml`. Never point at `main` branch.
- Every role must be listed, including core roles and all extension roles.

---

## Groups and Host Variables

**How groups and group variables connect:** Groups are defined in
`inventory/hosts.yml` under the `children:` keyword. Ansible automatically
associates a file in `group_vars/` with a group by matching the filename to
the group name — so `group_vars/servers.yml` applies to every host in the
`servers` group.

**YAML inventory keywords:**

- **`children:`** — the entries that follow are **groups** (not hosts).
- **`hosts:`** — the entries that follow are **hosts** (not groups).
- **`vars:`** — the entries that follow are **variables** for this group.

**Where group_vars and host_vars live:** We place them inside `inventory/` so
the inventory and all its associated variables are self-contained as a unit.

**Groups vs. hostnames in `hosts:` directives:** The playbook uses group
names for core roles and individual hostnames for extension roles. Core roles
apply categorically; extension roles are host-specific by nature.
