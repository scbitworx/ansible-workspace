# ansible-workspace

Project-wide documentation, design decisions, and development tooling for the
[scbitworx](https://github.com/scbitworx) Ansible home infrastructure project.

## Contents

| Directory   | Purpose                                            |
| ----------- | -------------------------------------------------- |
| `docs/`     | Architecture, naming, testing strategy, milestones |
| `tools/`    | Dockerfile, entrypoint, and run script             |
| `CLAUDE.md` | Project instructions for Claude Code               |

## Related Repositories

- [ansible-controller][ctrl] —
  Playbook, inventory, and `requirements.yml`
- [ansible-role-scaffold][scaffold] —
  Reference template for all roles
- [ansible-role-base][base] —
  Base role applied to all hosts

[ctrl]: https://github.com/scbitworx/ansible-controller
[scaffold]: https://github.com/scbitworx/ansible-role-scaffold
[base]: https://github.com/scbitworx/ansible-role-base

## License

MIT
