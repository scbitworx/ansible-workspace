# Implementation Milestones — Detailed Task Lists

This document contains the full task lists, deliverables, and exit criteria
for each implementation milestone.

---

## Milestone Ordering Rationale

The milestones are ordered to **validate the testing pipeline before building
real roles**. Milestone 2 creates a trivial scaffold role whose only purpose
is to exercise every part of the toolchain end-to-end: Molecule with all
three Docker images, `ansible-lint`, `yamllint`, the `first_found` +
`include_vars` pattern, Galaxy metadata, the controller's `requirements.yml`
installation, `local.yml` execution, and CI/CD via GitHub Actions.

CI/CD is part of Milestone 2, not a late-stage addition. The scaffold role
also serves as a **reference template** for creating new roles.

---

## Milestone 1: Foundation — GitHub Organization and Controller Repo

**Goal:** Establish the GitHub organization and create the controller
repository with inventory, playbook skeleton, `ansible-pull` wrapper, and
shared configuration files.

**Tasks:**

1. Create the GitHub organization (underscore-only name).
2. Create the `ansible-controller` repository under the organization.
3. Write `ansible.cfg` with appropriate `roles_path` configuration.
4. Write `inventory/hosts.yml` with `ceres`, `mars`, and `jupiter` mapped to
   their groups (`servers`, `workstations`, `laptops`).
5. Create stub `group_vars/` and `host_vars/` files. Define
   `controller_repo_url` in `group_vars/all.yml`.
6. Write `local.yml` playbook skeleton with the `pre_tasks` play (role
   installation and wrapper script deployment) followed by all planned roles.
7. Write `requirements.yml` skeleton (role entries can point to placeholder
   versions initially).
8. Write `templates/ansible-pull-wrapper.sh.j2` (the wrapper script template
   with logging, `flock`-based parallel run inhibition, and `ansible-pull`
   invocation).
9. Write `scripts/bootstrap.sh` for first-run bootstrap on fresh hosts
   (installs Ansible and runs the initial `ansible-pull`).
10. Add `README.md` documenting usage, prerequisites, the bootstrap process,
    and the `ansible-pull` workflow.

**Deliverables:** A functional controller repo that can be cloned and run
(it will fail on missing roles, but the structure is complete).

---

## Milestone 2: Scaffold Role, Testing Pipeline, and CI/CD

**Goal:** Create a trivial scaffold role (`ansible-role-scaffold`) that
validates the entire toolchain end-to-end — Molecule, Docker images, linting,
Galaxy metadata, controller integration, and CI/CD — before any real role
logic is written.

**Why a scaffold role:**

Building the `base` role requires simultaneously solving two categories of
problems: "does my Molecule/Docker/linting/CI pipeline work?" and "does my
role logic correctly configure a system?" The scaffold role has intentionally
trivial tasks so that any failure is unambiguously a pipeline problem.

The scaffold role is kept permanently as a reference template.

**What the scaffold role does:**

- Loads distro-specific variables via `first_found` + `include_vars`
- Installs a single trivial package
- Creates a file from a Jinja2 template
- Notifies a handler

**Tasks:**

1. Create the `ansible-role-scaffold` repository under the organization.
2. Initialize the full role directory structure.
3. Write `meta/main.yml` with explicit `role_name: scaffold` and platform
   metadata (`dependencies: []`).
4. Write `.ansible-lint` and `.yamllint` configuration files (canonical
   configs for all roles).
5. Create `defaults/main.yml` with a single public variable using
   `scaffold_` prefix.
6. Create `vars/Archlinux.yml`, `vars/Debian.yml`, and `vars/main.yml`.
7. Implement `tasks/main.yml`:
   - Load distro-specific variables
   - Install a single package via `ansible.builtin.package`
   - Deploy a file from a Jinja2 template
   - Notify a handler (`scaffold | verify`)
8. Write `handlers/main.yml` with the notified handler.
9. Set up `molecule/default/molecule.yml` with three-platform Docker config.
10. Write `molecule/default/prepare.yml` for Arch Python installation.
11. Write `molecule/default/converge.yml` to apply the role.
12. Write `molecule/default/verify.yml` with assertions.
13. Run `molecule test` locally — all three platforms pass.
14. Run `ansible-lint` and `yamllint` — clean output.
15. Create a reusable GitHub Actions workflow for Molecule + linting.
16. Add the CI workflow to the scaffold role repo — passes on push.
17. Configure branch protection rules requiring CI to pass.
18. Set up CI in `ansible-controller` for syntax-check and inventory
    validation.
19. Tag the scaffold role `v0.1.0`.
20. Update `requirements.yml` to point to the scaffold role's tag.
21. Run the controller's `local.yml` end-to-end to verify integration.

**Deliverables:**

- A trivial but fully tested role proving the pipeline works.
- Canonical `.ansible-lint`, `.yamllint`, and CI workflow files.
- A working CI/CD pipeline with branch protection.
- A reference template repository for creating new roles.

**Exit criteria:**

- `molecule test` passes on Arch, Ubuntu, and Debian
- `ansible-lint` and `yamllint` report zero violations
- GitHub Actions CI runs green on push
- The controller can install the role from a Git tag and apply it

---

## Milestone 3: Base Role

**Goal:** Create the `base` role with full Molecule testing across all three
target distributions.

**Prerequisites:** Copy the scaffold role's structure as the starting point.

**Tasks:**

1. Create `ansible-role-base` repository.
2. Copy scaffold structure. Update `meta/main.yml` with `role_name: base`.
3. Implement tasks for:
   - Loading distro-specific variables
   - Installing base packages (distro-aware)
   - Creating admin user accounts
   - Setting timezone and locale
   - Configuring SSH
   - Deploying shell skeleton (`~/.config/bash/bashrc` with `conf.d/`
     sourcing, `profile`, `inputrc`)
   - Creating `~/.config/bash/conf.d/` drop-in directory
   - Creating symlinks (`~/.bashrc`, `~/.profile`, `~/.inputrc`)
4. Create `vars/Archlinux.yml` and `vars/Debian.yml`.
5. Create `defaults/main.yml` with `base_` prefixed variables.
6. Write `prepare.yml` for Arch Python installation.
7. Write `converge.yml` and `verify.yml` with meaningful assertions.
8. Run `molecule test` — all three platforms pass.
9. Verify linting passes.
10. Tag `v0.1.0`.
11. Update controller `requirements.yml`.
12. Add optional `password_hash` property to `base_admin_users` for setting
    user passwords via `/etc/shadow`.
13. Add Ansible Vault integration to the controller:
    - `pass`+GPG-backed vault client script
    - Helper scripts (`ansible-vault-secret`, `ansible-vault-reveal`,
      `ansible-mkpasswd`)
    - `--vault-id` in wrapper and bootstrap scripts
    - Sudo re-exec in the wrapper for admin user invocation
14. Update `ansible.cfg` with `vault_identity_list`.
15. Molecule tests for password_hash (plaintext hashes; full vault pipeline
    deferred to Milestone 8).

**Deliverables:** A fully tested `base` role for Arch, Ubuntu, and Debian,
with optional password management and vault integration in the controller.

---

## Milestone 4: Server and Workstation Roles

**Goal:** Create `server` and `workstation` standalone roles, and extend the
`base` role with automated convergence and unattended security upgrades.

### Base Role Enhancements

The following features apply to all managed hosts and belong in the `base`
role rather than being duplicated across server and workstation:

1. **`ansible-pull` scheduling (systemd timer):**
   - Deploy a systemd timer that runs the `ansible-pull` wrapper periodically.
   - Default interval via `base_pull_interval` variable (overridable in
     `group_vars/` — e.g., hourly for servers, twice daily for workstations).
   - Use `Persistent=true` so laptops that sleep catch up on wake.
   - Safe on Arch because ansible-pull uses `state: present` (no partial
     upgrades — see [architecture.md](architecture.md#package-state-and-arch-linux-partial-upgrades)).

2. **Unattended security upgrades (Debian/Ubuntu only):**
   - Install and configure the `unattended-upgrades` package.
   - Distro conditional — no-op on Arch Linux (unattended upgrades are
     unsafe on rolling-release distributions).
   - Configurable via `base_unattended_upgrades` boolean (default: `true`
     on Debian/Ubuntu).

3. Molecule tests for both features.
4. Tag new base version and update controller `requirements.yml`.

### Server and Workstation Roles

**Tasks:**

1. Create `ansible-role-server` and `ansible-role-workstation` repositories.
2. Initialize from scaffold template.
3. Implement `server` role tasks:
   - Server security hardening (SSH config, fail2ban, firewall)
   - Server-specific packages
   - Monitoring/logging baseline
4. Implement `workstation` role tasks:
   - Display manager / desktop environment packages
   - Audio subsystem
   - Fonts
   - Base GUI tools
5. Create distro-specific vars files.
6. Set up Molecule with `prepare.yml` simulating `base` preconditions.
7. Test all three platforms.
8. Tag both repos `v0.1.0`.
9. Update controller `requirements.yml`.
10. Set `ansible-pull` timer interval overrides in `group_vars/servers.yml`
    and `group_vars/workstations.yml`.

**Deliverables:** Two tested standalone roles for server and workstation
layers.

---

## Milestone 5: Laptop Core Role

**Goal:** Create the `laptop` standalone core role.

**Tasks:**

1. Create `ansible-role-laptop` repository.
2. Initialize from scaffold template.
3. Implement tasks:
   - Lid close behavior
   - Screen/brightness management
   - Power management / TLP
   - Wi-Fi tooling
4. Create distro-specific vars files.
5. Set up Molecule with `prepare.yml`.
6. Test across distributions (hardware-specific tasks tagged for skip in
   Docker).
7. Tag `v0.1.0` and update controller.

**Deliverables:** Tested standalone `laptop` core role.

---

## Milestone 6: Initial Extension Roles

**Goal:** Create the first set of extension roles to validate the pattern.

**Tasks for each role:**

1. Create repository under the organization.
2. Initialize from scaffold template.
3. Implement role-specific tasks.
4. Create distro-specific vars files.
5. Set up Molecule with `prepare.yml` simulating core role preconditions.
6. Write verify tasks.
7. Test across distributions.
8. Tag `v0.1.0` and update controller.

**Initial extension roles:**

- **`syncthing_server`** — Syncthing service, config templating, systemd,
  firewall.
- **`taskchampion_sync_server`** — TaskChampion sync service, config, systemd.
- **`darp6`** — System76 firmware/drivers, hardware-specific kernel params.
- **`devbox`** — Compilers, build tools, language runtimes, editors/IDEs.
- **`hypervisor`** — Docker, docker-compose, QEMU, virt-manager, libvirt.
- **`intuos_pro`** — Wacom drivers, input device config.

**Deliverables:** Tested extension roles demonstrating the pattern.

---

## Milestone 7: Dotfiles Role

**Goal:** Create the `dotfiles` role with runtime package detection and XDG
`~/.config/` convention.

**Tasks:**

1. Create `ansible-role-dotfiles` repository.
2. Initialize from scaffold template.
3. Create distro-specific variable files mapping package names.
4. Implement `package_facts`-based detection tasks.
5. Deploy config files under `~/.config/<tool>/` with symlinks for legacy
   tools.
6. Deploy shell fragments to `~/.config/bash/conf.d/`.
7. Use `template` for dynamic configs, `copy` for static.
8. Set up Molecule with `prepare.yml` simulating `base` preconditions and
   installing sample packages.
9. Write `verify.yml` assertions for paths, ownership, permissions, symlinks.
10. Tag `v0.1.0` and update controller.

**Deliverables:** Tested dotfiles role with runtime detection.

---

## Milestone 8: End-to-End Integration Testing (virsh VMs)

**Goal:** Validate full stack from `bootstrap.sh` through `ansible-pull` and
role composition using disposable libvirt VMs.

**Why this exists alongside Molecule:** Molecule with Docker is unit testing.
Integration testing with VMs tests the full pipeline, role composition,
bootstrap flow, and covers kernel modules / hardware-specific gaps.

> **IMPORTANT:** Integration tests run against **disposable libvirt VMs**,
> never against production machines (`ceres`, `mars`, `jupiter`). The VMs are
> created from minimal base images, reverted to clean snapshots between runs,
> and can be destroyed at any time. Production hosts must not be targeted
> until all roles are fully unit-tested and integration-tested.

**Base VM images (disposable test VMs):**

- `test-archlinux`
- `test-ubuntu2404`
- `test-debian12`

**Scripts:**

- `create-base-vms.sh` — builds minimal test VMs, takes `clean` snapshots
- `run-integration-test.sh` — revert → bootstrap → verify → idempotency
- `verify-state.sh` — post-converge assertions via SSH

**Host profiles to test (on disposable VMs, not production machines):**

Each profile simulates the role stack that would eventually run on a
production host. The test VM receives the same group memberships and
`host_vars` as the production host it models, but it is a separate,
disposable libvirt VM.

| Profile              | Models role stack for | Role stack                                        |
|----------------------|-----------------------|---------------------------------------------------|
| Server               | jupiter               | base → server → extensions → dotfiles             |
| Workstation + laptop | ceres                 | base → workstation → laptop → extensions → dotfiles |
| Workstation          | mars                  | base → workstation → extensions → dotfiles        |

**Tasks:**

1. Write `create-base-vms.sh`.
2. Write `run-integration-test.sh`.
3. Write `verify-state.sh`.
4. Test server profile (models jupiter's role stack).
5. Test workstation + laptop profile (models ceres's role stack).
6. Test workstation profile (models mars's role stack).
7. Verify idempotency for each profile.
8. Document the workflow in controller `README.md`.

**Deliverables:** Repeatable, script-driven integration testing with verified
results for all host profiles.
