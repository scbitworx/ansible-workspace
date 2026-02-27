# Active Milestone: 4a — Integration Test Refactoring

## Goal

Migrate integration testing from shell scripts (virsh + grep assertions) to
the community-proven pattern: **Molecule + Vagrant + libvirt** for VM
lifecycle, **Testinfra** (pytest) for assertions. Each role owns its own
VM-based integration tests. The controller keeps a thin pipeline-level test.

## Motivation

Before building more roles (Milestones 5–8), refactor the test foundation
so that new roles get proper integration tests from the start — avoiding
throwaway shell-script tests that would need to be reimplemented later.

## Exit Criteria

- [ ] Base role has Testinfra-based verification for both Docker and VM scenarios
- [ ] Base role has a `molecule/integration/` scenario using Vagrant + libvirt
- [ ] Docker CI pipeline continues to pass on GitHub Actions (no regression)
- [ ] Controller's `verify-state.sh` is slimmed to controller-only assertions
- [ ] All existing test coverage is preserved or improved

---

## Repos and Branches

| Repo | Branch | Scope |
|------|--------|-------|
| `ansible-role-base` | `feature/molecule-vagrant-testinfra` | Testinfra migration + new integration scenario |
| `ansible-controller` | `feature/thin-integration-test` | Slim verify-state.sh to controller-only assertions |
| `ansible-workspace` | `main` (no branch) | Milestone tracking only |

Work the base role first. Controller changes depend on a new base role tag.

---

## Tasks

### Phase 1: Testinfra Migration (Docker Scenario) — ansible-role-base

Migrate the existing Docker scenario's verifier from Ansible assert to
Testinfra before adding the Vagrant scenario.

- [ ] Create feature branch `feature/molecule-vagrant-testinfra`
- [ ] Create `molecule/tests/` shared test directory
- [ ] Write `conftest.py` — fixtures for test_users, os_family, admin_group,
      vm_only marker skip logic
- [ ] Write `test_packages.py` — base package binary checks
- [ ] Write `test_timezone.py` — /etc/localtime exists
- [ ] Write `test_sshd.py` — sshd_config hardening (parameterized)
- [ ] Write `test_ansible_pull.py` — timer/service unit files, enablement
- [ ] Write `test_unattended_upgrades.py` — Debian/Ubuntu only, skip on Arch
- [ ] Write `test_users.py` — per-user checks (parameterized over users):
      user existence, groups, shell, sudoers, authorized_keys, shell config
      dirs, profile, bashrc, symlinks, password hash
- [ ] Update `molecule/default/molecule.yml` — change verifier to testinfra
- [ ] Move test variables from `converge.yml` to `molecule.yml` provisioner
      inventory (allows sharing converge.yml between scenarios)
- [ ] Simplify `converge.yml` (remove inline vars)
- [ ] Add `pytest-testinfra` to CI workflow pip install
- [ ] Validate on all 3 Docker platforms via test-runner sidecar
- [ ] Remove old `verify.yml` and `verify_user.yml`

### Phase 2: Vagrant Integration Scenario — ansible-role-base

- [ ] Create `molecule/integration/molecule.yml` — Vagrant driver, libvirt
      provider, `generic/arch` box, 2048 MB RAM, 2 CPUs
- [ ] Create `molecule/integration/prepare.yml` — minimal (dummy
      ansible-pull-wrapper, pacman cache update)
- [ ] Create `molecule/integration/converge.yml` (shared or symlink)
- [ ] Add `@pytest.mark.vm_only` tests:
      - Actually attempt root SSH and confirm rejection
      - Verify ansible-pull.timer is running (not just enabled)
      - Verify sshd service is running and enabled
- [ ] Validate `molecule test -s integration` on developer workstation
- [ ] Confirm Docker scenario still works (`molecule test`)
- [ ] Update base role README with integration scenario docs

### Phase 3: Merge and Tag — ansible-role-base

- [ ] Push branch, create PR
- [ ] Confirm CI passes (Docker scenario on GitHub Actions)
- [ ] Merge to main
- [ ] Tag new version (e.g., v0.16.0)

### Phase 4: Controller Changes — ansible-controller

- [ ] Create feature branch `feature/thin-integration-test`
- [ ] Slim `verify-state.sh` to controller-only assertions (~4-5 checks):
      1. ansible-pull-wrapper exists and is executable
      2. ansible-vault-client exists and is executable
      3. Vault-encrypted password hash decrypted and applied
      4. Root SSH is blocked (proves full converge completed)
- [ ] Update `requirements.yml` to pin new base role tag
- [ ] Validate `run-all.sh` on workstation
- [ ] Merge and push

### Phase 5: Update Tracking

- [ ] Update active-milestone.md (mark complete or transition to next milestone)
- [ ] Update MEMORY.md with Testinfra/Vagrant patterns for future roles

---

## Key Design Decisions

### Testinfra for Both Scenarios
Ansible assert-based verify.yml is verbose (337 lines, 2 tasks per assertion)
with poor failure messages. Testinfra provides purpose-built infrastructure
abstractions, parameterized tests, and pytest output with diffs. Both Docker
and VM scenarios use the same Testinfra tests from `molecule/tests/`.

### Shared Tests with VM-Only Markers
Tests live in `molecule/tests/` (shared). VM-only tests use
`@pytest.mark.vm_only` and are skipped when `MOLECULE_DRIVER_NAME == "docker"`
(detected in conftest.py). No test duplication.

### Per-Role VM Ownership
Each role manages its own VM lifecycle via Molecule + Vagrant. No shared VM
infrastructure between roles. This follows the dev-sec and githubixx patterns
and avoids coupling roles to the controller for testing.

### Controller Stays as Shell Scripts
The controller's integration test validates bootstrap.sh, ansible-pull
mechanics, and vault decryption — workflow-level concerns that don't fit
Molecule's role-testing model. The existing virsh + snapshot approach is
appropriate. Only `verify-state.sh` is slimmed to remove role-specific
assertions.

### Vagrant Box: generic/arch
Maintained by the Roboxes project, rebuilt regularly, well-tested with
libvirt. Community standard for Arch Vagrant boxes. Ubuntu/Debian boxes
added later (Milestone 9).

---

## Dependencies and Prerequisites

**Developer workstation needs (Phase 2):**
- `vagrant` package
- `vagrant-libvirt` plugin (`vagrant plugin install vagrant-libvirt`)
- Existing libvirt/qemu setup (already present from Milestone 4)

**Test-runner sidecar needs (Phase 1):**
- `pytest-testinfra` — must be installed in sidecar for Docker testing

**No changes to GitHub Actions runners** — VM tests run locally only.

---

## Verification Strategy

| Phase | How to verify |
|-------|--------------|
| Phase 1 | `ssh test-runner "env -C /workspace/ansible-role-base molecule test"` — all 3 platforms pass |
| Phase 2 | `molecule test -s integration` on workstation — Arch VM passes |
| Phase 2 | `molecule test` still works (Docker regression check) |
| Phase 3 | GitHub Actions CI green on PR |
| Phase 4 | `scripts/integration/run-all.sh` on workstation — slim verify passes |

---

## Progress Log

- **Milestone 4 (complete):** Shell-script integration tests fully operational.
  All 3 checks passing (bootstrap, 22/22 verification, idempotency).
  README documentation added. Tagged base v0.15.2, scaffold v0.2.0.
- **Milestone 4a (this document):** Refactoring integration tests to
  Molecule + Vagrant + Testinfra before proceeding to new roles.
