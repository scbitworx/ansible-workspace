#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Test-runner sidecar entrypoint
#
# 1. Installs the mounted SSH public key for the agent user
# 2. Fixes Docker socket group ownership so agent can talk to the host daemon
# 3. Starts sshd in the foreground
# ---------------------------------------------------------------------------

# --- SSH authorized_keys setup ---
AGENT_SSH_DIR="/home/agent/.ssh"
mkdir -p "$AGENT_SSH_DIR"

if [ -f /run/ssh-pubkey/authorized_keys ]; then
    cp /run/ssh-pubkey/authorized_keys "$AGENT_SSH_DIR/authorized_keys"
else
    echo "Error: /run/ssh-pubkey/authorized_keys not found" >&2
    exit 1
fi

cat > "$AGENT_SSH_DIR/environment" <<'EOF'
PATH=/opt/molecule-venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ANSIBLE_COLLECTIONS_PATH=/opt/ansible-collections
EOF

chmod 700 "$AGENT_SSH_DIR"
chmod 600 "$AGENT_SSH_DIR/authorized_keys" "$AGENT_SSH_DIR/environment"
chown -R agent:agent "$AGENT_SSH_DIR"

# --- Docker socket group fix ---
# The host Docker socket GID varies across systems. Detect it dynamically
# and ensure the agent user belongs to a group with that GID.
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    if ! getent group "$DOCKER_GID" >/dev/null 2>&1; then
        addgroup -g "$DOCKER_GID" -S docker-host
    fi
    addgroup agent "$(getent group "$DOCKER_GID" | cut -d: -f1)"
fi

# --- Generate host keys if missing (first run) ---
ssh-keygen -A

# --- Ensure /run/sshd exists (required by sshd) ---
mkdir -p /run/sshd

# --- Start sshd in the foreground ---
exec /usr/sbin/sshd -D -e
