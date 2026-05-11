#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

export PATH="/sbin/:usr/sbin/:${PATH}"

PROCESS_NAME="qemu-gyroid-ci"
SSH_PORT=2222
BUILD_DIR=""
KILL_VM=false
IMGPATH=""
MODE=""
LOG_DIR=""
PKI_DIR=""
HSM_SERIAL=""
HSM_VID=""
HSM_PID=""
COPY_ROOTCA="y"
SCRIPTS_DIR=""
TESTPW="pw"

COMPILE=false
BRANCH=""
FORCE=false
VNC=""
TELNET=""
PASS_HSM=""
SWTPM=""
OPT_FORCE_SIG_CFGS="${OPT_FORCE_SIG_CFGS:-n}"
OPT_CC_MODE_EXPERIMENTAL="${OPT_CC_MODE_EXPERIMENTAL:-n}"

BASE_OPTS=(-o StrictHostKeyChecking=no -o "UserKnownHostsFile=${PROCESS_NAME}.vm_key" -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=5)
SCP_OPTS=(-P "$SSH_PORT" "${BASE_OPTS[@]}")
SSH_OPTS=(-p "$SSH_PORT" "${BASE_OPTS[@]}" root@localhost)

###################################################################################################
# COMMAND LINE INTERFACE
###################################################################################################
parse_cli() {
    while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
        echo -e "Performs set of tests to start, stop and modify containers in VM among other operations."
        echo " "
        echo "Run with ./run-tests.sh { --builddir <out-yocto dir> | --img <image file> } [-c] [-k] [-v <display number>] [-f] [-b <branch name>] [-d <directory>]"
        echo " "
        echo "options:"
        echo "-h, --help                  Show brief help"
        echo "-c, --compile               (Re-)compile images (e.g. if new changes were commited to the repository)"
        echo "-b, --branch <branch>       Use this cml git branch (if not default) during compilation"
        echo "                            (see cmld recipe and init_ws.sh for details on branch name and repository location)"
        echo "-d, --dir <directory>       Use this path to workspace root directory if not current directory"
        echo "-d, --builddir <directory>       Use this path as build directory name"
        echo "-f, --force                 Clean up all components and rebuild them"
        echo "-s, --ssh <ssh port>        Use this port on the host for port forwarding (if not default 2223)"
        echo "-v, --vnc <display number>  Start the VM with VNC (port 5900 + display number)"
        echo "-t, --telnet <telnet port>  Start VM with telnet on specified port (connect with 'telnet localhost <telnet port>')"
        echo "-k, --kill                  Kill the VM after the tests are completed"
        echo "-n, --name        	Use the given name for the QEMU VM"
        echo "-p, --pki         	Use the given test PKI directory"
        echo "-i, --image       	Test the given GyroidOS image instead of looking inside --dir"
        echo "-m, --mode        	Test \"dev\", \"production\", or \"ccmode\" image? Default is \"dev\""
        echo "-e, --enable-hsm <serial> <vid> <pid> <pin>	Test with given hsm"
        echo "-k, --skip-rootca	Skip attempt to copy custom root CA to image"
        echo "-r, --scripts-dir	Specify directory containing signing scripts (gyroidos_build repo)"
        exit 1
        ;;
        -c|--compile)       COMPILE=true; shift ;;
        -b|--branch)        shift; BRANCH=$1; [[ -n "$BRANCH" ]] || die "No branch specified"; shift ;;
        -d|--dir)
        shift
        [[ -n "$1" && -d "$1" ]] || die "No (existing) directory specified"
        cd "$1"; shift  # cd is intentional: --dir sets cwd for all subsequent operations
        ;;
        -o|--builddir)      shift; BUILD_DIR="$(readlink -v -f "$1")"; shift ;;
        -f|--force)         shift; FORCE=true ;;
        -v|--vnc)
        shift; [[ $1 =~ ^[0-9]+$ ]] || die "VNC port must be a number (got $1)"
        VNC="-vnc 0.0.0.0:$1 -vga std"; shift
        ;;
        -s|--ssh)
        shift; SSH_PORT=$1; [[ $SSH_PORT =~ ^[0-9]+$ ]] || die "SSH port must be a number (got $SSH_PORT)"
        shift
        ;;
        -t|--telnet)
        shift; [[ $1 =~ ^[0-9]+$ ]] || die "Telnet port must be a number (got $1)"
        TELNET="-serial mon:telnet:127.0.0.1:$1,server,nowait"; shift
        ;;
        -k|--kill)          shift; KILL_VM=true ;;
        -n|--name)          shift; PROCESS_NAME=$1; shift ;;
        -p|--pki)           shift; PKI_DIR="$(readlink -v -f "$1")"; shift ;;
        -i|--image)         shift; IMGPATH=$1; shift ;;
        -m|--mode)
        shift
        [[ "$1" = "dev" || "$1" = "production" || "$1" = "ccmode" ]] || die "Unknown mode \"$1\""
        MODE=$1; shift
        ;;
        -e|--enable-hsm)
        shift; HSM_SERIAL="$1"; shift; HSM_VID="$1"; shift; HSM_PID="$1"; shift; TESTPW="$1"
        PASS_HSM="-usb -device qemu-xhci -device usb-host,vendorid=0x${HSM_VID},productid=0x${HSM_PID}"
        shift
        ;;
        -k|--skip-rootca)   COPY_ROOTCA="n"; shift ;;
        -r|--scripts-dir)   shift; SCRIPTS_DIR="$(readlink -v -f "$1")"; shift ;;
        -l|--log-dir)       shift; LOG_DIR="$(readlink -v -m "$1")"; shift ;;
        --force-sig-cfgs)   OPT_FORCE_SIG_CFGS="y"; shift ;;
        --cc-mode-experimental) OPT_CC_MODE_EXPERIMENTAL="y"; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
    done

    # Rebuild opts arrays after SSH_PORT may have changed
    SCP_OPTS=(-P "$SSH_PORT" "${BASE_OPTS[@]}")
    SSH_OPTS=(-p "$SSH_PORT" "${BASE_OPTS[@]}" root@localhost)

    if [[ -z "${PKI_DIR}" ]]; then
        PKI_DIR="test_certificates"
    fi
    [[ -d "${PKI_DIR}" ]] || die "PKI directory not found: ${PKI_DIR}"
}
