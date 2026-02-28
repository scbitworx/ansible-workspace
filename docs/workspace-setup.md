# Claude Code Workspace Setup Checklist

<!--toc:start-->
- [Claude Code Workspace Setup Checklist](#claude-code-workspace-setup-checklist)
  - [Container Image Requirements](#container-image-requirements)
  - [Python Packages](#python-packages)
  - [GitHub Authentication (Fine-Grained PAT)](#github-authentication-fine-grained-pat)
  - [Git Identity](#git-identity)
  - [Molecule Testing (Test-Runner Sidecar)](#molecule-testing-test-runner-sidecar)
  - [Verification](#verification)
<!--toc:end-->

This checklist configures the Docker container running Claude Code so that
linting, `git` operations, and GitHub CLI access all work directly inside the
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
both `git` push/pull and `gh` CLI operations. No SSH keys, no scripts, no
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

- [x] Configure `git` to use the token for HTTPS operations. Handled in
      `entrypoint.sh` at runtime (rewrites both SSH and HTTPS URLs).

### Git Remote URLs

Git remote URLs for cloned repos should use plain HTTPS without embedded
tokens:

```text
https://github.com/scbitworx/ansible-role-base.git    # correct
https://oauth2:ghp_xxx@github.com/scbitworx/...       # wrong — stale PAT
```

The `gh` CLI (authenticated via `GH_TOKEN`) acts as the `git` credential
helper, so embedded tokens are unnecessary and will cause push failures
when the token expires. Fix with:

```bash
git remote set-url origin https://github.com/scbitworx/<repo>.git
```

## Git Identity

- [x] Configure `git` user inside the container. Handled in `entrypoint.sh`
      at runtime via `GIT_USER_NAME` and `GIT_USER_EMAIL` env vars (passed by
      `run-agent`).

## Molecule Testing (Test-Runner Sidecar)

Molecule requires Docker to create test containers. Rather than mounting the
host Docker socket into the hardened Claude Code container (which would
undermine its security model), a **test-runner sidecar container** handles
Molecule execution.

### Architecture

```text
Host
├── Docker network: claude-net
│
├── provisioner-agent (hardened — cap-drop=ALL, read-only, no-new-privileges)
│   ├── Credentials: API key, GH token
│   ├── Can: edit files, lint, git, SSH to test-runner
│   └── Cannot: access Docker socket
│
└── test-runner (Molecule execution)
    ├── Credentials: NONE
    ├── Can: run molecule (spawns sibling containers via host Docker)
    └── Cannot: access API keys, GH tokens, ~/.claude
```

Claude Code SSHs into the test-runner to execute Molecule commands. Files are
shared via bind mount (same `/workspace` path in both containers).

### Build Images

```bash
# Claude Code container (unchanged)
docker build -t provisioner-agent -f tools/Dockerfile tools/

# Test-runner sidecar
docker build -t test-runner -f tools/Dockerfile.test-runner tools/
```

### Run

`run-agent` orchestrates both containers automatically:

```bash
./tools/run-agent
```

This creates the Docker network, generates ephemeral SSH keys, starts the
test-runner sidecar, then starts Claude Code. Everything is cleaned up on exit.

### Usage From Inside Claude Code

```bash
# Full test suite
ssh test-runner "cd /workspace/ansible-role-base && molecule test"

# Fast iteration (reuse containers between runs)
ssh test-runner "cd /workspace/ansible-role-base && molecule converge"
ssh test-runner "cd /workspace/ansible-role-base && molecule verify"
ssh test-runner "cd /workspace/ansible-role-base && molecule destroy"
```

### Security Model

| Property              | Claude Code      | Test Runner      |
|-----------------------|------------------|------------------|
| cap-drop=ALL          | Yes              | No (needs caps)  |
| read-only root        | Yes              | No               |
| no-new-privileges     | Yes              | No               |
| Docker socket         | No               | Yes              |
| API key / GH token    | Yes              | No               |
| ~/.claude access      | Yes              | No               |

The test-runner is intentionally less hardened (it needs Docker access), but
has zero credentials. The worst case is equivalent to any Docker user on the
host.

## Verification

Run these inside the container to confirm everything works:

- [x] `python3 --version` — Python available
- [x] `yamllint --version` — yamllint installed
- [x] `ansible-lint --version` — ansible-lint installed
- [x] `gh auth status` — GitHub CLI authenticated
- [x] `gh repo list scbitworx` — can list org repos
- [x] `git clone https://github.com/scbitworx/ansible-controller.git /tmp/test && rm -rf /tmp/test` — clone works

Test the sidecar integration:

- [ ] `ssh test-runner hostname` — prints "test-runner"
- [ ] `ssh test-runner "cd /workspace/ansible-role-scaffold && molecule test"` — full pipeline passes
- [ ] Verify no credentials leak: `ssh test-runner 'echo $ANTHROPIC_API_KEY'` — empty
- [ ] Exit Claude Code — test-runner auto-stops, network cleaned up, keys deleted
