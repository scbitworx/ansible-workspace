#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# run-agent — Start Claude Code with a test-runner sidecar
#
# Generates an ephemeral SSH keypair, exports required environment variables,
# and delegates all container orchestration to Docker Compose.
#
# The test-runner starts in the background. The agent container runs in the
# foreground with an interactive TTY so Claude Code receives stdin.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(pwd)"

# --- Resolve workspace mount path ---
# If running inside a container, the bind-mount source path (on the host)
# may differ from the path seen inside this container. Allow override.
export HOST_WORKSPACE="${HOST_WORKSPACE:-$WORKSPACE}"

# --- Ephemeral SSH key pair ---
SSH_TMPDIR=$(mktemp -d)
export SSH_TMPDIR

cleanup() {
    echo "Stopping containers..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" down 2>/dev/null || true
    rm -rf "$SSH_TMPDIR"
    echo "Done."
}
trap cleanup EXIT

ssh-keygen -t ed25519 -f "$SSH_TMPDIR/id_ed25519" -N "" -q

# --- GitHub token ---
export GH_TOKEN="${GH_TOKEN:-$(pass cloud/github/scbitworx/claude-box-access-token)}"

# --- Build images ---
docker compose -f "$SCRIPT_DIR/docker-compose.yml" build

# --- Start test-runner in the background ---
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d test-runner

# --- Run agent interactively (stdin + tty forwarded) ---
# "docker compose run" is the Compose equivalent of "docker run -it" — it
# properly attaches stdin to a single service. The --rm flag removes the
# one-off container on exit.
docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm agent
