#!/usr/bin/env bash
# Run one command with OpenSSL 3 visible to Microsoft's SQL Server driver.
# Usage: ./run.sh python test_connection.py
# Why: see "macOS OpenSSL note" in docs/setup-notes.md.

set -euo pipefail

OPENSSL3_LIB="/opt/homebrew/opt/openssl@3/lib"

if [ ! -d "$OPENSSL3_LIB" ]; then
    echo "run.sh: $OPENSSL3_LIB not found. Install it with: brew install openssl@3" >&2
    exit 1
fi

export DYLD_LIBRARY_PATH="$OPENSSL3_LIB"

exec "$@"
