#!/bin/bash
#
# Environment Validation Script for Azure Neo4j Bicep Development
#
# This script validates that all required tools and configurations
# are properly set up for Bicep development.
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Symbols
CHECK_MARK="${GREEN}✓${NC}"
CROSS_MARK="${RED}✗${NC}"
WARNING_MARK="${YELLOW}⚠${NC}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Azure Neo4j Bicep Development Environment Validation    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

#
# Helper Functions
#

function check_command() {
    local cmd=$1
    local name=$2
    local min_version=$3

    echo -n "Checking $name... "

    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -n 1)
        echo -e "${CHECK_MARK} Installed"
        echo "  Version: $version"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${CROSS_MARK} Not found"
        echo "  $name is required but not installed."
        echo "  See docs/DEVELOPMENT_SETUP.md for installation instructions."
        FAILED=$((FAILED + 1))
        return 1
    fi
}

function check_azure_cli() {
    echo -n "Checking Azure CLI... "

    if command -v az &> /dev/null; then
        local version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
        echo -e "${CHECK_MARK} Installed"
        echo "  Version: $version"

        # Check minimum version (2.50.0) only if version is valid
        if [ "$version" != "unknown" ]; then
            local major=$(echo "$version" | cut -d. -f1)
            local minor=$(echo "$version" | cut -d. -f2)

            if [ -n "$major" ] && [ -n "$minor" ]; then
                if [ "$major" -ge 2 ] && [ "$minor" -ge 50 ]; then
                    echo "  ✓ Version meets minimum requirement (2.50.0+)"
                else
                    echo -e "  ${WARNING_MARK} Version $version is below recommended 2.50.0"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        fi

        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${CROSS_MARK} Not found"
        echo "  Azure CLI is required."
        echo "  See docs/DEVELOPMENT_SETUP.md for installation instructions."
        FAILED=$((FAILED + 1))
        return 1
    fi
}

function check_bicep_cli() {
    echo -n "Checking Bicep CLI... "

    if command -v az &> /dev/null; then
        if az bicep version &> /dev/null; then
            local version=$(az bicep version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            echo -e "${CHECK_MARK} Installed"
            echo "  Version: $version"

            # Check minimum version (0.20.0)
            local major=$(echo "$version" | cut -d. -f1)
            local minor=$(echo "$version" | cut -d. -f2)

            if [ "$major" -ge 1 ] || ([ "$major" -eq 0 ] && [ "$minor" -ge 20 ]); then
                echo "  ✓ Version meets minimum requirement (0.20.0+)"
            else
                echo -e "  ${WARNING_MARK} Version $version is below recommended 0.20.0"
                echo "  Run: az bicep upgrade"
                WARNINGS=$((WARNINGS + 1))
            fi

            PASSED=$((PASSED + 1))
            return 0
        else
            echo -e "${CROSS_MARK} Not installed"
            echo "  Bicep CLI is required."
            echo "  Run: az bicep install"
            FAILED=$((FAILED + 1))
            return 1
        fi
    else
        echo -e "${CROSS_MARK} Cannot check (Azure CLI not found)"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

function check_azure_login() {
    echo -n "Checking Azure CLI login status... "

    if command -v az &> /dev/null; then
        if az account show &> /dev/null; then
            local subscription=$(az account show --query name -o tsv 2>/dev/null)
            echo -e "${CHECK_MARK} Logged in"
            echo "  Active Subscription: $subscription"
            PASSED=$((PASSED + 1))
            return 0
        else
            echo -e "${WARNING_MARK} Not logged in"
            echo "  You are not logged into Azure CLI."
            echo "  Run: az login"
            WARNINGS=$((WARNINGS + 1))
            return 1
        fi
    else
        echo -e "${CROSS_MARK} Cannot check (Azure CLI not found)"
        return 1
    fi
}

function check_bicep_config() {
    echo -n "Checking Bicep linter configuration... "

    if [ -f "$REPO_ROOT/bicepconfig.json" ]; then
        echo -e "${CHECK_MARK} Found"
        echo "  Location: $REPO_ROOT/bicepconfig.json"

        # Validate JSON syntax
        if command -v python3 &> /dev/null; then
            if python3 -m json.tool "$REPO_ROOT/bicepconfig.json" &> /dev/null; then
                echo "  ✓ Valid JSON syntax"
            else
                echo -e "  ${WARNING_MARK} Invalid JSON syntax"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi

        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${CROSS_MARK} Not found"
        echo "  Expected location: $REPO_ROOT/bicepconfig.json"
        echo "  This file should have been created during Phase 1 setup."
        FAILED=$((FAILED + 1))
        return 1
    fi
}

function check_git_hooks() {
    echo -n "Checking Git pre-commit hook... "

    # Determine git hooks directory (handles worktrees)
    local git_dir=$(git rev-parse --git-dir 2>/dev/null || echo "")

    if [ -z "$git_dir" ]; then
        echo -e "${WARNING_MARK} Not in a Git repository"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi

    local hooks_dir="$git_dir/hooks"

    if [ -f "$hooks_dir/pre-commit" ]; then
        echo -e "${CHECK_MARK} Installed"
        echo "  Location: $hooks_dir/pre-commit"

        if [ -x "$hooks_dir/pre-commit" ]; then
            echo "  ✓ Executable"
        else
            echo -e "  ${WARNING_MARK} Not executable"
            echo "  Run: chmod +x $hooks_dir/pre-commit"
            WARNINGS=$((WARNINGS + 1))
        fi

        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${WARNING_MARK} Not installed"
        echo "  Pre-commit hook is recommended for validating Bicep files."
        echo "  Run: ./scripts/install-git-hooks.sh"
        echo "  Note: May not work in git worktrees - install in main repository."
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

function check_docs() {
    echo -n "Checking documentation files... "

    local all_docs_exist=true

    if [ ! -f "$REPO_ROOT/docs/BICEP_STANDARDS.md" ]; then
        all_docs_exist=false
    fi

    if [ ! -f "$REPO_ROOT/docs/DEVELOPMENT_SETUP.md" ]; then
        all_docs_exist=false
    fi

    if [ "$all_docs_exist" = true ]; then
        echo -e "${CHECK_MARK} All documentation present"
        echo "  - docs/BICEP_STANDARDS.md"
        echo "  - docs/DEVELOPMENT_SETUP.md"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${CROSS_MARK} Some documentation missing"
        [ ! -f "$REPO_ROOT/docs/BICEP_STANDARDS.md" ] && echo "  Missing: docs/BICEP_STANDARDS.md"
        [ ! -f "$REPO_ROOT/docs/DEVELOPMENT_SETUP.md" ] && echo "  Missing: docs/DEVELOPMENT_SETUP.md"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

#
# Run Checks
#

echo "═══════════════════════════════════════════════════════════"
echo " Required Tools"
echo "═══════════════════════════════════════════════════════════"
echo

check_azure_cli
echo

check_bicep_cli
echo

check_command git "Git" "2.30.0"
echo

echo "═══════════════════════════════════════════════════════════"
echo " Azure Configuration"
echo "═══════════════════════════════════════════════════════════"
echo

check_azure_login
echo

echo "═══════════════════════════════════════════════════════════"
echo " Repository Configuration"
echo "═══════════════════════════════════════════════════════════"
echo

check_bicep_config
echo

check_git_hooks
echo

check_docs
echo

#
# Summary
#

echo "═══════════════════════════════════════════════════════════"
echo " Validation Summary"
echo "═══════════════════════════════════════════════════════════"
echo

TOTAL=$((PASSED + FAILED))

echo -e "${GREEN}Passed:${NC}   $PASSED / $TOTAL"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}   $FAILED / $TOTAL"
echo

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Environment is fully configured and ready for Bicep development!${NC}"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠ Environment is configured but has warnings.${NC}"
    echo "  Review warnings above and address them if needed."
    exit 0
else
    echo -e "${RED}✗ Environment validation failed.${NC}"
    echo "  Please address the failed checks above."
    echo "  See docs/DEVELOPMENT_SETUP.md for setup instructions."
    exit 1
fi
