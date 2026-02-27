# Milestone 4c: Base Role Audit Fixes

Best-practice audit of ansible-role-base against community standards
(geerlingguy, dev-sec). Fixing correctness issues, adopting idiomatic
patterns, and hardening CI.

## Status: COMPLETE — all items done, ready for tag

## Tasks

### High Priority (Correctness)

- [x] Fix README collections install command (references `meta/requirements.yml`, should be `collections.yml`)
- [x] Remove `molecule/tests/__pycache__/` from git tracking (already clean — not tracked)
- [x] Add missing variables to README table (`base_pull_timer_enabled`, `base_pull_interval`, `base_unattended_upgrades`)

### Medium Priority (Best Practice)

- [x] Switch unconditional includes to `import_tasks` (packages, timezone_locale, ssh, ansible_pull)
- [x] Add `.vagrant/` to `.gitignore`
- [x] Add locale-setting task (set system default via `/etc/locale.conf`)
- [x] Add `$include /etc/inputrc` to `inputrc.j2`
- [x] Change sshd handler from `restarted` to `reloaded`
- [x] Add `timeout-minutes: 30` to CI workflow jobs
- [x] Add test for `/etc/locale.conf` (test_timezone.py)

### Low Priority (Enhancements)

- [x] Add `AllowGroups` to sshd_config for defense-in-depth
- [x] Add cipher/MAC/KexAlgorithm/HostKeyAlgorithms hardening to sshd_config
- [x] Expand test coverage: testuser3 (sudo_passwordless=false), alternate scenario (timer disabled, custom editor/histsize/extra_packages)
- [x] Pin CI pip package versions
- [x] Add example playbook to README
- [x] DRY converge test data between default and integration scenarios (shared_vars.yml)

## Validation

- Molecule Docker (default): 326 passed, 10 skipped (3 platforms)
- Molecule Docker (alternate): 8 passed (Arch only)
- Molecule Vagrant (integration): 108 passed, 4 skipped (Arch VM)
- Idempotence: passed (all scenarios)
- ansible-lint: 0 failures, 0 warnings
- yamllint: clean
