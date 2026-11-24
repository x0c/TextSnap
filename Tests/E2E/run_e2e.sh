#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTEST_BIN="${HOME}/.macos-e2e-toolkit/.venv/bin/pytest"

if [[ ! -x "${PYTEST_BIN}" ]]; then
    echo "Missing macos-e2e pytest runtime at ${PYTEST_BIN}" >&2
    exit 1
fi

export E2E_PROJECT_ROOT="${PROJECT_ROOT}"
exec "${PYTEST_BIN}" -v "${PROJECT_ROOT}/Tests/E2E" "$@"
