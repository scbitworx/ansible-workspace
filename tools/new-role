#!/usr/bin/env bash
set -euo pipefail

readonly ORG="scbitworx"
readonly SCAFFOLD_REPO="https://github.com/${ORG}/ansible-role-scaffold.git"

usage() {
    echo "Usage: $(basename "$0") <role_name>"
    echo
    echo "Create a new Ansible role from the scaffold template."
    echo
    echo "  role_name   Lowercase alphanumeric + underscores (e.g., syncthing_server)"
    exit 1
}

die() {
    echo "Error: $1" >&2
    exit 1
}

# --- Validate input ---

[ $# -eq 1 ] || usage

role_name="$1"

if ! echo "$role_name" | grep -qE '^[a-z][a-z0-9_]*$'; then
    die "Role name '${role_name}' is invalid. Must match ^[a-z][a-z0-9_]*\$"
fi

if [ "$role_name" = "scaffold" ]; then
    die "Role name cannot be 'scaffold'"
fi

# Capitalize first letter for handler names (e.g., syncthing_server -> Syncthing_server)
capitalized="$(echo "${role_name:0:1}" | tr '[:lower:]' '[:upper:]')${role_name:1}"

repo_name="ansible-role-${role_name}"
work_dir="/tmp/${repo_name}"

if [ -d "$work_dir" ]; then
    die "${work_dir} already exists. Remove it first."
fi

echo "Creating role: ${role_name}"
echo "  Repo: ${ORG}/${repo_name}"
echo

# --- Clone scaffold ---

echo "Cloning scaffold..."
git clone --quiet "$SCAFFOLD_REPO" "$work_dir"

# --- Remove git history and reinitialize ---

rm -rf "${work_dir}/.git"
git -C "$work_dir" init --quiet
git -C "$work_dir" branch -m main

# --- Rename template file ---

if [ -f "${work_dir}/templates/scaffold_example.conf.j2" ]; then
    mv "${work_dir}/templates/scaffold_example.conf.j2" \
       "${work_dir}/templates/${role_name}_example.conf.j2"
fi

# --- Find-and-replace ---

# Replace capitalized form first (Scaffold -> Capitalized) to avoid
# the lowercase pass turning "Scaffold" into "Syncthing_server" via
# a partial match on "scaffold".
echo "Replacing Scaffold -> ${capitalized}..."
find "$work_dir" -type f \
    -not -path '*/.git/*' \
    -exec sed -i "s/Scaffold/${capitalized}/g" {} +

echo "Replacing scaffold -> ${role_name}..."
find "$work_dir" -type f \
    -not -path '*/.git/*' \
    -exec sed -i "s/scaffold/${role_name}/g" {} +

# --- Update meta/main.yml description ---

sed -i "s/^    description:.*/    description: \"TODO: Add description\"/" \
    "${work_dir}/meta/main.yml"

# --- Create GitHub repo ---

echo "Creating GitHub repository..."
gh repo create "${ORG}/${repo_name}" --public --description "Ansible role: ${role_name}"

# --- Initial commit and push ---

echo "Pushing initial commit..."
git -C "$work_dir" add -A
git -C "$work_dir" commit --quiet -m "Initialize ${role_name} role from scaffold"
git -C "$work_dir" remote add origin "https://github.com/${ORG}/${repo_name}.git"
git -C "$work_dir" push --quiet -u origin main

# --- Summary ---

echo
echo "Done! Role created successfully."
echo
echo "  Repository: https://github.com/${ORG}/${repo_name}"
echo "  Local copy: ${work_dir}"
echo
echo "Next steps:"
echo "  1. Clone the repo where you want to work on it"
echo "  2. Replace the example tasks/templates with real content"
echo "  3. Update meta/main.yml description"
echo "  4. Run molecule test to verify"
echo "  5. Tag v0.1.0 when ready"
