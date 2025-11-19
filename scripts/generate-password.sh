#!/usr/bin/env bash
#
# generate-password.sh - Generate a strong password for Neo4j deployments
#
# USAGE:
#   ./generate-password.sh [length]
#
# ARGUMENTS:
#   length    Password length (default: 32)
#
# DESCRIPTION:
#   Generates a cryptographically strong password with mixed case letters,
#   numbers, and special characters. Outputs the password to stdout.
#
# EXAMPLES:
#   PASSWORD=$(./generate-password.sh)
#   PASSWORD=$(./generate-password.sh 64)
#

set -euo pipefail

# Default password length
DEFAULT_LENGTH=32
LENGTH="${1:-$DEFAULT_LENGTH}"

# Validate length
if ! [[ "$LENGTH" =~ ^[0-9]+$ ]] || [[ "$LENGTH" -lt 16 ]]; then
    echo "Error: Length must be a number >= 16" >&2
    exit 1
fi

# Generate password using OpenSSL
# Mix of base64 for alphanumerics and special character insertion
password=$(openssl rand -base64 $((LENGTH * 2)) | tr -d '\n=' | head -c "$LENGTH")

# Ensure we have special characters by replacing some positions
special_chars='!@#$%^&*()-_=+[]{}~'
positions="5 11 17 23 29"
for pos in $positions; do
    if [[ $pos -lt $LENGTH ]]; then
        rand_special=$(echo -n "$special_chars" | fold -w1 | tail -n +$((RANDOM % ${#special_chars} + 1)) | head -n 1)
        password="${password:0:pos}${rand_special}${password:pos+1}"
    fi
done

# Output the password
echo -n "$password"
