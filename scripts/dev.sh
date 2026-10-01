#!/usr/bin/env bash
# Thin launcher for the LT dev auto hot-reload tool.
# All logic lives in tool/dev_hot_reload.py; this only forwards arguments.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tool/dev_hot_reload.py --device linux "$@"
