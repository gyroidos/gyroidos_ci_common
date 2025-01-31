#!/bin/bash

set -e

UPSTREAM="gyroidos"

MANIFEST_PATH=""
WS_PATH="$(realpath .)"
BH_PATH=""
CML="n"
ROLLING_STABLE="n"
OUT="$(realpath .)"

parse_manifest() {
	manifest="$1"
	outfile="$OUT/$(basename "$manifest").revisions"

	while IFS= read l || [ -n "$l" ];do
		if [[ $l == *"<project"* ]];then
			echo "Processing $l"

			oldrev="$(echo $l | sed -nE 's|.*revision="([a-z0-9._]*)".*|\1|p')"
			repo="$(echo $l | sed -nE 's|.*name="([/a-z0-9_\-]*)".*|\1|p')"
			path="$(echo $l | sed -nE 's|.*path="([/a-z0-9_\-]*)".*|\1|p')"

			if [ -z "$path" ] ;then
				echo "Error: failed to parse repo path for line $l"
				exit 1
			fi

			newrev="$(git -C $path rev-parse HEAD)"

			if [ -z "$repo" ] || [ -z "$path" ] || [ -z $newrev ];then
				echo "Error: failed to parse line $l, oldrev=$oldrev, repo=$repo, path=$path, newrev=$newrev"
				exit 1
			fi

			if ! [ -z "$oldrev" ];then
				echo "Replacing rev for repo $repo at $path: $oldrev => $newrev"
				l_new=$(echo "$l" | sed -nE "s/revision=\"([a-z0-9._]*)\"/revision=\"$newrev\"/p")
				echo "l_new=$l_new"
				printf "$l_new\n" >> "$outfile"
			else
				echo "Adding new rev entry for repo $repo at $path on remote $remote: <default rev: $default_remote> => $newrev"

				if [ -z "$(echo "$l" | grep "/>")" ];then
					l_new=$(echo "$l" | sed -nE "s|>|revision=\"$newrev\">|p")
				else
					l_new=$(echo "$l" | sed -nE "s|/>|revision=\"$newrev\"/>|p")
				fi

				echo "l_new=$l_new"

				printf "$l_new\n" >> "$outfile"

			fi
		else
			printf "$l\n" >> "$outfile"
		fi
	done < "$manifest"
}


# Argument retrieval
# -----------------------------------------------
while [[ $# > 0 ]]; do
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
      echo "-r, --rolling-stable        Store revision of linux-rolling-stable in auto.conf"
      exit 1
      ;;
    -m|--manifest)
      shift
      MANIFEST_PATH="$(realpath $1)"
      shift
      ;;
    -w|--workspace)
      shift
      WS_PATH="$(realpath $1)"
      shift
      ;;
    -b|--buildhistory)
      shift
      BH_PATH="$(realpath $1)"
      shift
      ;;
    -c|--cml)
      shift
	  CML="y"
      ;;
    -r|--rolling-stable)
      shift
	  ROLLING_STABLE="y"
      ;;
    -o|--out)
      shift
      OUT="$(realpath $1)" 
      shift
      ;;

     *)
      echo "ERROR: Unknown arguments specified? ($1)"
      exit 1
      ;;
  esac
done

BASE_MANIFEST_PATH="$(dirname "${MANIFEST_PATH}")/gyroidos-base.xml"

echo "MANIFEST_PATH=${MANIFEST_PATH}"
echo "BASE_MANIFEST_PATH=${BASE_MANIFEST_PATH}"
echo "WS_PATH=${WS_PATH}"
echo "BH_PATH=${BH_PATH}"
echo "OUT=${OUT}"
echo "CML=${CML}"
echo "ROLLING_STABLE=${ROLLING_STABLE}"

# sanity checks for parameters
if [ -z "$WS_PATH" ] || ! [ -d "$WS_PATH" ];then
	echo "Error: No or non-existing workspace path specified, exiting..."
	exit 1
fi

if [ -z "$MANIFEST_PATH" ] || ! [ -f "$MANIFEST_PATH" ];then
	echo "Error: No or non-existing manifest path specified, exiting..."
	exit 1
fi

if [ "y" = "$CML" ] && [ -z "$BH_PATH" ];then
	echo "Error: --cml specified but no path to buildhistory given, exiting..."
	exit 1
fi

if [ "y" = "$ROLLING_STABLE" ] && [ -z "$BH_PATH" ];then
	echo "Error: --rolling-stable specified but no path to buildhistory given, exiting..."
	exit 1
fi


echo "Storing revisions to new manifest at $OUT/manifest_revisions.xml"
cd "${WS_PATH}"

# Parse default remote
if [ -z "$repo" ];then
	default_remote="$(sed -nE '0,/remote=/{s|.*remote="([[:alpha:]]*)".*|\1|p}' ${MANIFEST_PATH})"
fi

if [ -z "$default_remote" ];then
	echo "Failed to get default remote, exiting..."
	exit 1
fi

echo "Default remote: $default_remote"

# Parse manifest and store revisions of Yocto layers

echo "Parsing $MANIFEST_PATH"
set +e
parse_manifest "$MANIFEST_PATH"
set -e

if [ -f "${BASE_MANIFEST_PATH}" ];then
	echo "Attempting to parse base manifest at ${BASE_MANIFEST_PATH}"
	set +e
	parse_manifest "$BASE_MANIFEST_PATH" || true
	set -e
else
	echo "No base manifest at ${BASE_MANIFEST_PATH} detected, skipping..."
fi

echo 'Successfully stored revisions in manifest(s)'

# Store revision of linux-rolling-stable
if [ "y" == "$ROLLING_STABLE" ] || [ "y" == "$CML" ];then
	echo -n > "$OUT/auto.conf"
fi

if [ "y" == "$ROLLING_STABLE" ];then
	echo "Writing linux-rolling-stable revision to auto.conf"

	find "$BH_PATH/packages" -wholename '*/linux-rolling-stable/latest_srcrev'

	srcrevpath="$(find "$BH_PATH/packages" -wholename '*/linux-rolling-stable/latest_srcrev')"
	if [ -z "$srcrevpath" ];then
		echo "Failed to find file */linux-rolling-stable/latest_srcrev in buildhistory. Abort."
		exit 1
	fi

	srcrev="$(sed -nE 's|^SRCREV.* = "([a-z0-9._]*)".*|\1|p' $srcrevpath)"
	echo "SRCREV_machine = \"${srcrev}\"" >> "$OUT/auto.conf"


	echo 'Successfully stored revision of linux-rolling-stable'
fi


# Store CML revisions
if [ "y" == "$CML" ]; then
	echo "Writing CML revisions to auto.conf"

	srcrevpath="$(find "$BH_PATH/packages" -wholename '*/cmld/latest_srcrev')"
	if [ -z "$srcrevpath" ];then
		echo "Failed to find file */cmld/latest_srcrev in buildhistory, \
			  attempting to fetch revision from $WS_PATH/gyroidos/cml."

		if [ -d "$WS_PATH/gyroidos/cml" ];then
			srcrev="$(git -C "$WS_PATH/gyroidos/cml" rev-parse HEAD)"
			echo "CML revision in EXTERNALSRC build is $srcrev"
		else
			echo "Could not find directory holding cml git."
			exit 1
		fi
	else
		tmprev=""
		for path in $srcrevpath;do
			srcrev="$(sed -nE 's|^SRCREV.* = "([a-z0-9._]*)".*|\1|p' "$path")"

			if ! [ "" = "$tmprev" ] && [ "$tmprev" != "$srcrev" ];then
				echo "ERROR: Multiple cmld evisions detected, changed during build? (srcrev '$srcrev' != tmprev '$tmprev')"
				exit 1
			fi
			tmprev="$srcrev"
		done

		echo "CML revision from buildhistory is $srcrev"
	fi

	echo "SRCREV:pn-cmld = \"${srcrev}\"" >> "$OUT/auto.conf"
	echo "SRCREV:pn-service = \"${srcrev}\"" >> "$OUT/auto.conf"
	echo "SRCREV:pn-service-static = \"${srcrev}\"" >> "$OUT/auto.conf"

	echo 'Successfully stored CML revisions'
fi

exit 0
