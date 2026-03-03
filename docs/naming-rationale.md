# Naming Conventions — Detailed Rationale

This document contains the detailed rationale for the naming conventions
summarized in [CLAUDE.md](../CLAUDE.md).

---

## Why Underscores in Repository Names

The community is split on this. Jeff Geerling's older roles use hyphens
(e.g., `ansible-role-php-versions`), but his newer roles have shifted to
underscores (e.g., `ansible-role-node_exporter`, `ansible-role-k8s_manifests`).
Robert de Bock uses underscores exclusively across his entire catalog of 200+
roles (e.g., `ansible-role-docker_ce`, `ansible-role-gitlab_runner`). We
follow the underscore convention for these reasons:

- **`ansible-lint` requires it.** The `role-name` rule enforces the pattern
  `^[a-z][a-z0-9_]*$` — hyphens are not permitted in role names. Using
  underscores in the repo name keeps the repo name and the `ansible-lint`-
  compliant role name identical.
- **Galaxy does not auto-convert hyphens to underscores in role names.**
  Galaxy preserves role names verbatim as set in `meta/main.yml`. (Galaxy
  only auto-converts hyphens to underscores in *namespace* names, not role
  names.) If the repo uses hyphens but the role name must use underscores
  to satisfy `ansible-lint`, the two names diverge — creating a mismatch
  that invites confusion.
- **Consistency with `meta/main.yml`.** Every role explicitly sets
  `galaxy_info.role_name` in `meta/main.yml`. When the repo name portion
  matches the `role_name` value character-for-character, there is never any
  ambiguity about which role a repo contains.

---

## Why the GitHub Organization Uses Underscores

Galaxy auto-converts hyphens to underscores in **namespace names** (the
org/user portion that identifies who owns a role). Using underscores in the
org name means zero conversion friction — the org name, the Galaxy namespace,
and the Ansible namespace are all identical.

---

## Why `role_name` Is Set Explicitly in `meta/main.yml`

Both Jeff Geerling and Robert de Bock always set `galaxy_info.role_name`
explicitly rather than relying on auto-derivation from the repository name.
We do the same. This ensures the role name is deterministic regardless of how
the repo is cloned, forked, or renamed — and prevents Molecule and Galaxy
from deriving an incorrect name.

---

## Why `namespace` Is Set Explicitly in `meta/main.yml`

Galaxy derives the namespace from the account that owns the role, not from
the metadata file. Neither Jeff Geerling nor Robert de Bock set `namespace`
in their roles' `meta/main.yml`, because for Galaxy publishing it is
redundant.

However, **Molecule uses `namespace` from `meta/main.yml`** to resolve the
role's fully qualified name during testing. Without it, Molecule may fail to
locate the role in `converge.yml` when referenced as `scbitworx.<role_name>`.
We set `namespace: scbitworx` explicitly in every role to ensure consistent
behavior across Galaxy, Molecule, and `ansible-galaxy install`.

---

## Variable Naming Convention

**Public and private variables are not the same variables.** They do not merge
or override each other. They are entirely separate variables that serve
different purposes and coexist in Ansible's flat global namespace:

- `defaults/main.yml` variables are the **public API** of the role — knobs the
  user is expected to tune. They have the **lowest precedence** in Ansible's
  variable precedence order, so inventory, `group_vars`, `host_vars`, and
  playbook vars can all override them.
- `vars/` variables are **internal constants** the role needs to do its job
  (e.g., distro-specific package names, config file paths, service names).
  They have **higher precedence** than defaults and are not intended to be
  overridden by the user.

Example showing both kinds used together in tasks:

```yaml
- name: Install base packages
  ansible.builtin.package:
    name: "{{ base_packages }}"        # public — user can override the list
    state: present

- name: Enable SSH service
  ansible.builtin.service:
    name: "{{ __base_service_name }}"  # private — 'sshd' on Arch, 'ssh' on Ubuntu
    enabled: true
```

The double-underscore prefix is a **human naming convention**, not an Ansible
mechanism — Ansible has no concept of private variables. The prefix serves as a
visual signal that a variable is an internal implementation detail and should
not be overridden. This convention was popularized by Jeff Geerling's widely
used Galaxy roles and is a recognized community pattern.

---

## Handler Naming Convention

Ansible handler names are global — they share a flat namespace just like
variables. If two roles both defined a handler named `restart sshd`, they
would collide. Prefixing with the role name ensures uniqueness. The pipe `|`
character is a visual separator with no special meaning to Ansible.

**What handlers are:** Handlers are special Ansible tasks that only run when
**notified** by another task. They are typically used to restart or reload a
service after a configuration change.

**How they work:** A regular task notifies a handler by name. Ansible collects
all notifications during a play and runs each notified handler **once** at the
end of the play, regardless of how many tasks notified it.

Example — a task notifies a handler:

```yaml
- name: Update syncthing configuration
  ansible.builtin.template:
    src: config.xml.j2
    dest: /etc/syncthing/config.xml
  notify: "syncthing_server | restart"
```

The corresponding handler:

```yaml
- name: syncthing_server | restart
  ansible.builtin.service:
    name: syncthing
    state: restarted
```
