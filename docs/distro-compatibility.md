# Distro Compatibility — Detailed Reference

This document contains the full details of per-role distro handling patterns.

---

## The `first_found` + `include_vars` Pattern

Each role handles package manager and package name differences using
distro-keyed variable files loaded via the `first_found` lookup:

```text
ansible-role-base/
  tasks/
    main.yml
  vars/
    Archlinux.yml         # Arch is its own OS family
    Debian.yml            # shared by Ubuntu and Debian (same OS family)
    main.yml              # cross-distro fallback defaults
```

In `tasks/main.yml`:

```yaml
- name: Load distro-specific variables
  ansible.builtin.include_vars: >-
    {{ lookup('first_found', params) }}
  vars:
    params:
      files:
        - "{{ ansible_facts.distribution }}-\
          {{ ansible_facts.distribution_version }}.yml"
        - "{{ ansible_facts.distribution }}.yml"
        - "{{ ansible_facts.os_family }}.yml"
        - main.yml
      paths:
        - vars

- name: Install base packages
  ansible.builtin.package:
    name: "{{ base_packages }}"
    state: present
```

---

## How `first_found` Works

Ansible evaluates the file list in order and loads the **first file that
exists**. This provides cascading specificity:

1. **Distribution + version** (`Ubuntu-24.04.yml`) — for version-specific
   overrides. Rarely needed.
2. **Distribution** (`Ubuntu.yml`) — for cases where Ubuntu and Debian differ.
3. **OS family** (`Debian.yml`) — the common case. Ubuntu and Debian share
   the `Debian` OS family and usually have identical package names.
4. **Fallback** (`main.yml`) — cross-distro defaults.

Arch Linux is its own OS family (`Archlinux`), so `Archlinux.yml` matches
at both the distribution and OS family levels.

**Practical effect:** Most roles need only two vars files — `Archlinux.yml`
and `Debian.yml` — plus `main.yml` for cross-distro internal variables.

**Why `first_found` instead of direct `include_vars`:** A bare
`include_vars: "{{ ansible_distribution }}.yml"` **hard-fails** if the file
does not exist. `first_found` degrades gracefully through the cascade. This
is the pattern used by Jeff Geerling's Galaxy roles.

---

## Distro-Specific Task Includes

For cases where task logic itself differs across distros (not just package
names), use conditional task includes:

```yaml
- name: Include distro-specific tasks
  ansible.builtin.include_tasks: "{{ lookup('first_found', params) }}"
  vars:
    params:
      files:
        - "{{ ansible_facts.distribution }}.yml"
        - "{{ ansible_facts.os_family }}.yml"
      paths:
        - tasks
```

---

## Why Distro Handling Lives in Each Role

It may seem appealing to centralize package name mappings in the controller.
However:

- **Distro differences go beyond package names.** Each role may have
  distro-specific service names (`sshd` vs `ssh`), config file paths, repo
  URLs, and even entirely different task logic. These are role-specific
  concerns.
- **It would break role independence.** Roles are standalone and independently
  testable with Molecule. If they depended on controller-provided variables,
  every role's Molecule `converge.yml` would need to inject them.
- **The "update every role" cost is lower than it appears.** When adding a new
  distro, you must test each role on that distro regardless.
- **The controller already centralizes the right things.** Composition,
  ordering, version pins, and cross-cutting inventory variables. Role-internal
  implementation details belong in the role.
