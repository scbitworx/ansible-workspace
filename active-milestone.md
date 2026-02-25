# Active Milestone: 4 — Single-VM Integration Testing (Arch Linux)

## Goal

Validate the controller pipeline end-to-end on a single disposable Arch
Linux libvirt VM, using only the base role.

## Exit Criteria

- [ ] `bootstrap.sh` successfully installs Ansible and runs the initial pull
- [ ] `ansible-pull-wrapper` completes a full converge
- [ ] Vault-encrypted variables are decrypted correctly
- [ ] The systemd timer is active and enabled
- [ ] A second run is idempotent
- [ ] The VM can be destroyed and recreated from the clean snapshot

---

## Tasks

### 1. Design integration test approach
- [ ] Determine VM creation strategy (virt-install CLI vs. kickstart vs. cloud image)
- [ ] Decide on network config (NAT, bridge, SSH access method)
- [ ] Decide on snapshot strategy (virsh snapshot-create-as)
- [ ] Determine how vault/pass/GPG will be set up on the test VM
- [ ] Document decisions below in "Design Decisions" section

### 2. Write `scripts/integration/create-base-vms.sh`
- [ ] Create a single Arch Linux VM (`test-archlinux`)
- [ ] Minimal install — just enough to run `bootstrap.sh`
- [ ] Take a `clean` snapshot after initial setup
- [ ] Script should be idempotent (safe to re-run)

### 3. Write `scripts/integration/run-integration-test.sh`
- [ ] Revert VM to `clean` snapshot
- [ ] Start VM and wait for SSH
- [ ] Copy/run `bootstrap.sh`
- [ ] Verify converge succeeded (exit code)
- [ ] Run `ansible-pull-wrapper` a second time for idempotency check
- [ ] Call `verify-state.sh`
- [ ] Report pass/fail

### 4. Write `scripts/integration/verify-state.sh`
- [ ] SSH into VM and assert base role state:
  - Admin user exists with correct groups/shell
  - SSH hardening applied (sshd_config settings)
  - Timezone and locale set
  - Base packages installed
  - ansible-pull.timer active and enabled
  - ansible-pull.service unit exists
  - Vault-encrypted variables decrypted correctly (e.g., password_hash)
  - Unattended-upgrades NOT installed (Arch — no-op expected)

### 5. Run the full cycle
- [ ] Execute the scripts on the host workstation
- [ ] Fix any issues discovered
- [ ] Confirm all exit criteria pass

### 6. Document in controller README
- [ ] Add integration testing section to `ansible-controller/README.md`
- [ ] Document prerequisites (libvirt, virsh, Arch ISO or cloud image)
- [ ] Document usage (`create-base-vms.sh`, `run-integration-test.sh`)

---

## Design Decisions

*(Record decisions made during implementation here)*

---

## Blockers / Open Questions

*(Track anything that blocks progress or needs user input)*

- Where will these scripts run? They require libvirt on the host — not
  available in the Claude Code container. Scripts will be written here but
  executed by the user on a workstation.

---

## Progress Log

*(Brief notes on what was done each session)*
