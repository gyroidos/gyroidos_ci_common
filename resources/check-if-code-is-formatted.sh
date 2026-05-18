#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

ROOT_DIR="$(realpath "$(dirname "$1")")"
CLANG_FORMAT="clang-format"
mapfile -t FILES < <(find "$ROOT_DIR" -type f -regextype sed -regex ".*\(\.c\|\.h\)")

einfo "clang-format: $("$CLANG_FORMAT" --version)"
einfo "Checking ${#FILES[@]} files in $ROOT_DIR"

ret=0
diff -u <(cat "${FILES[@]}") <("$CLANG_FORMAT" "${FILES[@]}") || ret=$?

if [[ $ret -ne 0 ]]; then
    eerror "Code is not formatted! See diff above."
    eerror "Run ./scripts/format-code.sh to fix."
else
    ok "Code is properly formatted"
fi

exit "$ret"
