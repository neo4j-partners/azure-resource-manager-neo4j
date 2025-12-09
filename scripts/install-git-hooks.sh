#!/bin/bash
#
# Install Git hooks for this repository
#
# This script installs the pre-commit hook for Bicep validation
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Installing Git hooks for Azure Neo4j Modernize repository..."
echo

# Check if .git directory exists
if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "ERROR: .git/hooks directory not found."
    echo "Please run this script from within the repository."
    exit 1
fi

# Install pre-commit hook
echo "Installing pre-commit hook for Bicep validation..."

if [ -f "$GIT_HOOKS_DIR/pre-commit" ]; then
    echo -e "${YELLOW}WARNING: pre-commit hook already exists.${NC}"
    echo "Backing up existing hook to pre-commit.backup"
    mv "$GIT_HOOKS_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-commit.backup"
fi

cp "$SCRIPT_DIR/pre-commit-bicep" "$GIT_HOOKS_DIR/pre-commit"
chmod +x "$GIT_HOOKS_DIR/pre-commit"

echo -e "${GREEN}✓ Pre-commit hook installed${NC}"
echo

echo -e "${GREEN}Git hooks installation complete!${NC}"
echo
echo "The pre-commit hook will now validate Bicep files before each commit."
echo "To bypass the hook in an emergency, use: git commit --no-verify"
