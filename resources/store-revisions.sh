#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

UPSTREAM="gyroidos"

MANIFEST_PATH=""
WS_PATH="$(realpath .)"
BH_PATH=""
CML="n"
ROLLING_STABLE="n"
OUT="$(realpath .)"
AUTO_CONF_SUFFIX=""

parse_manifest() {
	local manifest="$1"
	local outfile="$OUT/$(basename "$manifest").revisions"

	while IFS= read -r l || [[ -n "$l" ]]; do
		if [[ "$l" == *"<project"* ]]; then
			oldrev="$(echo "$l" | sed -nE 's|.*revision="([a-z0-9._]*)".*|\1|p')"
			repo="$(echo "$l" | sed -nE 's|.*name="([/a-z0-9_\-]*)".*|\1|p')"
			path="$(echo "$l" | sed -nE 's|.*path="([/a-z0-9_\-]*)".*|\1|p')"

			[[ -n "$path" ]] || die "Failed to parse repo path for line: $l"

			newrev="$(git -C "$path" rev-parse HEAD)" || true

			if [[ -z "$repo" ]] || [[ -z "$path" ]] || [[ -z "${newrev:-}" ]]; then
				die "Failed to parse line: $l (oldrev=$oldrev, repo=$repo, path=$path, newrev=${newrev:-})"
			fi

			if [[ -n "$oldrev" ]]; then
				l_new=$(echo "$l" | sed -nE "s/revision=\"([a-z0-9._]*)\"/revision=\"$newrev\"/p")
				printf "%s\n" "$l_new" >> "$outfile"
			else
				if [[ "$l" == *"/>"* ]]; then
					l_new=$(echo "$l" | sed -nE "s|/>|revision=\"$newrev\"/>|p")
				else
					l_new=$(echo "$l" | sed -nE "s|>|revision=\"$newrev\">|p")
				fi
				printf "%s\n" "$l_new" >> "$outfile"
			fi
		else
			printf "%s\n" "$l" >> "$outfile"
		fi
	done < "$manifest"
}


# Argument retrieval
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo -e "Creates a copy of the given manifest containing the checked-out revisions of Yocto layers, CML and kernel"
      echo " "
      echo "Run with ./store_revisions.sh  --manifest <manifest path> [ -w <workspace dir> ] [ -b <buildhistory path> ]"
      echo " "
      echo "Options:"
      echo "-h, --help                  Show brief help"
      echo "-m, --manifest              Path to repotool manifest to operate on"
      echo "-w, --workspace             Path to Yocto workspace to operate on, defaults to ."
      echo "-o, --out                   Output directory, defaults to ."
      echo "-b, --buildhistory          Path to the buildhistory directory in the Yocto tree"
      echo "-c, --cml                   Store revisions of 'cmld', 'service' and  'service-static' recipes in auto.conf"
      echo "--gyroid_machine            GyroidOS machine being build"
      exit 1
      ;;
    -m|--manifest)      shift; MANIFEST_PATH="$(realpath "$1")"; shift ;;
    -w|--workspace)     shift; WS_PATH="$(realpath "$1")"; shift ;;
    -b|--buildhistory)  shift; BH_PATH="$(realpath "$1")"; shift ;;
    -c|--cml)           shift; CML="y" ;;
    -o|--out)           shift; OUT="$(realpath "$1")"; shift ;;
    --gyroid_machine)   shift; AUTO_CONF_SUFFIX="_$1"; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

BASE_MANIFEST_PATH="$(dirname "${MANIFEST_PATH}")/gyroidos-base.xml"
ROLLING_SRCREV=""
if [[ -n "$BH_PATH" ]]; then
	ROLLING_SRCREV="$(find "$BH_PATH/packages" -wholename '*/linux-*/latest_srcrev')" || true
fi

# sanity checks
[[ -n "$WS_PATH" && -d "$WS_PATH" ]] || die "No or non-existing workspace path: ${WS_PATH:-<empty>}"
[[ -n "$MANIFEST_PATH" && -f "$MANIFEST_PATH" ]] || die "No or non-existing manifest path: ${MANIFEST_PATH:-<empty>}"
if [[ "y" == "$CML" ]] && [[ -z "$BH_PATH" ]]; then
	die "--cml specified but no path to buildhistory given"
fi

# Parse default remote
default_remote="$(sed -nE '0,/remote=/{s|.*remote="([[:alpha:]]*)".*|\1|p}' "${MANIFEST_PATH}")"
[[ -n "${default_remote:-}" ]] || die "Failed to parse default remote from manifest"

begin "Storing revisions"
einfo "Manifest: $(basename "$MANIFEST_PATH"), workspace: $WS_PATH"

(cd "${WS_PATH}" && parse_manifest "$MANIFEST_PATH")

if [[ -f "${BASE_MANIFEST_PATH}" ]]; then
	elog "Parsing base manifest: $(basename "$BASE_MANIFEST_PATH")"
	(cd "${WS_PATH}" && parse_manifest "$BASE_MANIFEST_PATH") || true
fi

# Store revision of linux-rolling-{stable|lts}
if [[ -n "${ROLLING_SRCREV}" ]] || [[ "y" == "${CML}" ]]; then
	echo -n > "$OUT/auto${AUTO_CONF_SUFFIX}.conf"
fi

if [[ -n "${ROLLING_SRCREV}" ]]; then
	elog "Writing linux-rolling revision to auto.conf"
	cat "${ROLLING_SRCREV}" >> "$OUT/auto${AUTO_CONF_SUFFIX}.conf"
fi

# Store CML revisions
if [[ "y" == "$CML" ]]; then
	srcrevpath="$(find "$BH_PATH/packages" -wholename '*/cmld/latest_srcrev')" || true
	if [[ -z "${srcrevpath:-}" ]]; then
		[[ -d "$WS_PATH/gyroidos/cml" ]] || die "Could not find cml git directory"
		srcrev="$(git -C "$WS_PATH/gyroidos/cml" rev-parse HEAD)"
		elog "CML revision (EXTERNALSRC): $srcrev"
	else
		tmprev=""
		for path in $srcrevpath; do
			srcrev="$(sed -nE 's|^SRCREV.* = "([a-z0-9._]*)".*|\1|p' "$path")"
			if [[ -n "$tmprev" ]] && [[ "$tmprev" != "$srcrev" ]]; then
				die "Multiple cmld revisions detected: '$srcrev' != '$tmprev'"
			fi
			tmprev="$srcrev"
		done
		elog "CML revision (buildhistory): $srcrev"
	fi

	echo "SRCREV:pn-cmld = \"${srcrev}\"" >> "$OUT/auto${AUTO_CONF_SUFFIX}.conf"
	echo "SRCREV:pn-service = \"${srcrev}\"" >> "$OUT/auto${AUTO_CONF_SUFFIX}.conf"
	echo "SRCREV:pn-service-static = \"${srcrev}\"" >> "$OUT/auto${AUTO_CONF_SUFFIX}.conf"
fi

ok "Stored revisions"
exit 0
