# Claude Code Workspace Setup Checklist

<!--toc:start-->
- [Claude Code Workspace Setup Checklist](#claude-code-workspace-setup-checklist)
  - [Container Image Requirements](#container-image-requirements)
  - [Python Packages](#python-packages)
  - [GitHub Authentication (Fine-Grained PAT)](#github-authentication-fine-grained-pat)
  - [Git Identity](#git-identity)
  - [Molecule Testing (Run on Host)](#molecule-testing-run-on-host)
  - [Verification](#verification)
<!--toc:end-->

This checklist configures the Docker container running Claude Code so that
linting, git operations, and GitHub CLI access all work directly inside the
workspace.

Access is scoped to the `scbitworx` org only via a fine-grained personal
access token. Personal repos are not exposed to the container.

## Container Image Requirements

- [x] **Python 3 + pip** — needed for all Ansible tooling
- [x] **Git** — needed for commits, tags, and push operations
- [x] **GitHub CLI (`gh`)** — needed for repo creation, CI status, PRs

## Python Packages

- [x] Install the Ansible toolchain inside the container:

  ```bash
  pip install ansible-core ansible-lint yamllint
  ```

- [x] Install required Ansible collections:

  ```bash
  ansible-galaxy collection install community.general
  ```

## GitHub Authentication (Fine-Grained PAT)

A fine-grained personal access token scoped to the `scbitworx` org. Handles
both git push/pull and `gh` CLI operations. No SSH keys, no scripts, no
refresh logic.

### Create the Token

- [x] Go to <https://github.com/settings/personal-access-tokens/new>
- [x] Under **Resource owner**, select `scbitworx`
- [x] Under **Repository access**, select **All repositories**
- [x] Set **expiration** (90 days recommended; regenerate when it expires)
- [x] Grant these **repository permissions**:

  | Permission | Access | Why |
  |---|---|---|
  | Contents | Read & Write | Push/pull code, create branches, tags |
  | Metadata | Read-only | Required (always on) |
  | Administration | Read & Write | Create repos via API |
  | Actions | Read-only | Check CI/workflow status |
  | Pull requests | Read & Write | Create and manage PRs |

- [x] Click **Generate token** and copy the value

### Pass to Container

- [x] Pass the token as an environment variable when starting the container:

  ```bash
  docker run \
    -e GH_TOKEN=github_pat_... \
    your-image
  ```

  The `gh` CLI picks up `GH_TOKEN` automatically — no additional config
  needed.

- [x] Configure git to use the token for HTTPS operations. Handled in
      `entrypoint.sh` at runtime (rewrites both SSH and HTTPS URLs).

## Git Identity

- [x] Configure git user inside the container. Handled in `entrypoint.sh`
      at runtime via `GIT_USER_NAME` and `GIT_USER_EMAIL` env vars (passed by
      `run-agent`).

## Molecule Testing (Run on Host)

Molecule requires Docker to create test containers. Rather than mounting the
host Docker socket into the Claude Code container (which grants root-equivalent
access to the host), run Molecule on your host machine where Docker is already
available.

**Inside the container** (Claude Code handles):

- Editing role files
- `yamllint .` and `ansible-lint` — catches most errors without Docker
- Git commits, pushes, tags
- `gh` commands (CI status, PRs, repo creation)

**On the host** (you run manually):

- `molecule test` — full integration test with Docker containers

### Host Prerequisites

- [x] Python 3 + pip
- [x] Docker (running)
- [x] Install the Molecule toolchain:

  ```bash
  pip install ansible-core molecule molecule-plugins[docker]
  ansible-galaxy collection install community.general
  ```

### Typical Workflow

1. Claude Code edits files and runs `yamllint . && ansible-lint`
2. Claude Code commits and pushes
3. You run `molecule test` on the host if needed (or let GitHub Actions CI
   handle it)

In practice, lint catches most issues. Molecule is the slower step that
validates convergence and idempotence — GitHub Actions CI runs it on every
push, so running it locally is optional.

## Verification

Run these inside the container to confirm everything works:

- [x] `python3 --version` — Python available
- [x] `yamllint --version` — yamllint installed
- [x] `ansible-lint --version` — ansible-lint installed
- [x] `gh auth status` — GitHub CLI authenticated
- [x] `gh repo list scbitworx` — can list org repos
- [x] `git clone https://github.com/scbitworx/ansible-controller.git /tmp/test && rm -rf /tmp/test` — clone works

Run this on the host to confirm Molecule works:

- [ ] Clone a role repo, run `molecule test` — full pipeline passes
