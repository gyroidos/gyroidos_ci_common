#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

# Jenkins executes this script before it builds the gyroidos image (i.e. pre-yocto).
# If this script exits with a non-zero code, the whole pipeline fails.

REPO_DIR="$(realpath "$1")"

dirs=(common control converter daemon scd)
for d in "${dirs[@]}"; do
    begin "Static analysis: ${d}"
    make -C "${REPO_DIR}/common" clean
    make -C "${REPO_DIR}/${d}" clean
    AGGRESSIVE_WARNINGS=y make -C "${REPO_DIR}/${d}"
    make -C "${REPO_DIR}/${d}" clean
    ok "Static analysis: ${d}"
done

begin "Unit tests: libcommon"
make -C "${REPO_DIR}/common" clean
SANITIZERS=n make -C "${REPO_DIR}/common" test
make -C "${REPO_DIR}/common" clean
ok "Unit tests: libcommon"
