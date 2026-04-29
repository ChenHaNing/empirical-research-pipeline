#!/bin/bash
# install.sh — symlink all pipeline modules into Claude Code's skills directory
#
# Usage:
#   bash install.sh             # install all modules
#   bash install.sh 01-data-intake   # install only the named module
#
# Behavior:
#   - Creates ~/.claude/skills/ if missing
#   - For each module under modules/, creates a symlink at ~/.claude/skills/<module-name>
#   - Skips modules already linked (won't overwrite existing skills)
#
# Uninstall:
#   rm ~/.claude/skills/<module-name>

set -e

SKILLS_DIR="${HOME}/.claude/skills"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${REPO_DIR}/modules"

mkdir -p "$SKILLS_DIR"

if [ ! -d "$MODULES_DIR" ]; then
    echo "Error: ${MODULES_DIR} not found." >&2
    exit 1
fi

# If a specific module was requested, install only that one
TARGETS=()
if [ $# -gt 0 ]; then
    for arg in "$@"; do
        if [ -d "${MODULES_DIR}/${arg}" ]; then
            TARGETS+=("${MODULES_DIR}/${arg}")
        else
            echo "Error: module '${arg}' not found under modules/" >&2
            exit 1
        fi
    done
else
    for module_path in "${MODULES_DIR}"/*/; do
        TARGETS+=("${module_path%/}")
    done
fi

echo "Installing ${#TARGETS[@]} module(s) into ${SKILLS_DIR}/"
echo ""

n_linked=0
n_skipped=0
for module_path in "${TARGETS[@]}"; do
    module_name=$(basename "$module_path")
    target="${SKILLS_DIR}/${module_name}"

    if [ -L "$target" ]; then
        existing=$(readlink "$target")
        if [ "$existing" = "$module_path" ]; then
            echo "  [skip]  ${module_name} (already linked correctly)"
            n_skipped=$((n_skipped + 1))
        else
            echo "  [warn]  ${module_name} already linked to a different path:"
            echo "          ${existing}"
            echo "          Remove it manually if you want to relink."
            n_skipped=$((n_skipped + 1))
        fi
    elif [ -e "$target" ]; then
        echo "  [warn]  ${module_name} already exists as a real file/dir at ${target}"
        echo "          Remove it manually if you want to install."
        n_skipped=$((n_skipped + 1))
    else
        ln -s "$module_path" "$target"
        echo "  [link]  ${module_name}"
        n_linked=$((n_linked + 1))
    fi
done

echo ""
echo "Done: ${n_linked} linked, ${n_skipped} skipped."
echo "Restart Claude Code to discover newly installed skills."
