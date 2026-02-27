# Milestone 4c: Base Role Audit Fixes (Round 2)

Second audit pass — test coverage gaps, CI improvements, and minor polish.

## Status: COMPLETE

## Batch 1: Test Coverage — SSH and Security

- [x] Test `.ssh` directory exists (mode 0700, user-owned)
- [x] Test config file ownership (bashrc, profile, inputrc owned by user)
- [x] Test missing sshd directives: X11Forwarding, PrintMotd, UsePAM, HostKey, Subsystem sftp (distro-specific)
- [x] Add negative SSH assertions (weak ciphers/MACs/KEX must NOT be present)
- [x] Fix timezone test to verify symlink target matches `base_timezone`

## Batch 2: Test Coverage — Users and DRY Refactors

- [x] Test user shell assignment (`u.shell == "/bin/bash"`)
- [x] DRY: parametrize directory existence checks (4 tests → 1 parametrized)
- [x] DRY: parametrize symlink checks (4 tests → 1 parametrized)
- [x] Test AllowGroups in alternate scenario (non-empty value)
- [x] Test authorized_keys exclusive mode (unauthorized key NOT present)

## Batch 3: CI, Config, and Polish

- [x] Add pip caching to CI workflow
- [x] Add `.pytest_cache/` to `.gitignore`
- [x] ~~Fix sshd_config.j2 leading-space inconsistency~~ (false finding — no issue exists)
- [x] Add section headers to `defaults/main.yml`

## Batch 4: Optional Enhancements

- [x] Add optional `base_sshd_banner` variable
- [x] Test distro-specific package verification (base-devel vs build-essential)

## Validation

- Molecule Docker (default): 404 passed, 10 skipped
- Molecule Docker (alternate): 9 passed
- ansible-lint: 0 failures, 0 warnings
