#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"
source "${RUNDIR}/settings.sh"
source "${RUNDIR}/VM-container-commands.sh"
source "${RUNDIR}/VM-management.sh"
source "${RUNDIR}/testdata.sh"

OPT_FORCE_SIG_CFGS="n"

# Function definitions
# ----------------------------------------------

do_copy_update_configs(){
local -a FILES=(
	nullos-1.conf nullos-1.sig nullos-1.cert
	nullos-2.conf nullos-2.sig nullos-2.cert
	nullos-3.conf nullos-3.sig nullos-3.cert
)
for I in $(seq 1 10) ;do
	if scp "${SCP_OPTS[@]}" "${FILES[@]}" root@127.0.0.1:/tmp/; then
		break
	elif [[ "$I" -eq 10 ]]; then
		eerror "Failed to copy GuestOS configs to VM after 10 attempts"
		err_fetch_logs
	fi
	sleep 0.5
done
}

do_copy_kernel_update(){
local KERNEL_VERSION="$1"
local -a FILES=(
	"kernel-${KERNEL_VERSION}.conf"
	"kernel-${KERNEL_VERSION}.sig"
	"kernel-${KERNEL_VERSION}.cert"
	"kernel-${KERNEL_VERSION}"
)
for I in $(seq 1 10) ;do
	if scp -r "${SCP_OPTS[@]}" "${FILES[@]}" root@127.0.0.1:/tmp/; then
		break
	elif [[ "$I" -eq 10 ]]; then
		eerror "Failed to copy kernel configs to VM after 10 attempts"
		err_fetch_logs
	fi
	sleep 0.5
done
}

do_test_rm() {
	local CONTAINER="$1"
	einfo "Test: remove running container ${CONTAINER}"
	cmd_control_change_pin "${CONTAINER}" "" "$TESTPW"
	cmd_control_start "${CONTAINER}" "$TESTPW"
	cmd_control_remove "${CONTAINER}" "$TESTPW"
}

do_test_complete() {
	local CONTAINER="$1"
	local SECOND_RUN="$2"
	local USBTOKEN="$3"
	begin "Test suite: ${CONTAINER} (run=${SECOND_RUN}, usb=${USBTOKEN})"

	cmd_control_list

	if [[ "n" == "$USBTOKEN" ]]; then
		if [[ "${SECOND_RUN}" != "y" ]]; then
			elog "Verify unpaired start fails"
			cmd_control_start_error_unpaired "${CONTAINER}" "$TESTPW"
			cmd_control_change_pin "${CONTAINER}" "" "$TESTPW"
		else
			cmd_control_change_pin "${CONTAINER}" "$TESTPW" "$TESTPW"
		fi
		elog "Verify wrong PIN fails"
		cmd_control_change_pin_error "${CONTAINER}" "wrongpin" "$TESTPW"
	fi

	elog "Start/stop/config lifecycle"
	cmd_control_start "${CONTAINER}" "$TESTPW"
	cmd_control_config "${CONTAINER}"

	ssh "${SSH_OPTS[@]}" "echo testmessage1 > /dev/fifos/signedfifo1"
	ssh "${SSH_OPTS[@]}" "echo testmessage2 > /dev/fifos/signedfifo2"

	cmd_control_list_guestos "gyroidos-coreos"
	cmd_control_remove_error_eexist "nonexistent-container"
	cmd_control_start_error_eexist "${CONTAINER}" "$TESTPW"

	cmd_control_stop "${CONTAINER}" "$TESTPW"
	cmd_control_stop_error_notrunning "${CONTAINER}" "$TESTPW"

	# Perform extended update test (triggers reload)
	if [[ -f "${CONTAINER}_rename.conf" ]]; then
		elog "Config update/reload test"
		local uuid
		uuid=$(cmd_control_get_uuid "${CONTAINER}")

		cmd_control_update_config "${uuid} /tmp/${CONTAINER}_rename.conf /tmp/${CONTAINER}_rename.sig /tmp/${CONTAINER}_rename.cert" "name: \"${CONTAINER}-rename\""
		cmd_control_start "${CONTAINER}-rename" "$TESTPW"
		cmd_control_update_config "${uuid} /tmp/${CONTAINER}_update.conf /tmp/${CONTAINER}_update.sig /tmp/${CONTAINER}_update.cert" "name: \"${CONTAINER}\""
		cmd_control_stop "${uuid}" "$TESTPW"
		cmd_control_start "${CONTAINER}" "$TESTPW"
		cmd_control_stop "${CONTAINER}" "$TESTPW"
	fi

	if [[ "${SECOND_RUN}" == "y" ]]; then
		einfo "Start/stop stress test (100 cycles)"
		for I in {1..100}; do
			cmd_control_start "${CONTAINER}" "$TESTPW"
			cmd_control_stop "${CONTAINER}" "$TESTPW"
		done

		elog "Retrieve logs"
		local TMPDIR
		TMPDIR="$(ssh "${SSH_OPTS[@]}" "mktemp -d -p /tmp")"
		if [[ "ccmode" == "${MODE}" ]] && [[ "y" != "${OPT_CC_MODE_EXPERIMENTAL}" ]]; then
			cmd_control_retrieve_logs "${TMPDIR}" "CMD_UNSUPPORTED"
		else
			cmd_control_retrieve_logs "${TMPDIR}" "CMD_OK"
		fi

		elog "Remove container and verify"
		cmd_control_remove "${CONTAINER}" "$TESTPW"
		cmd_control_list_ncontainer "${CONTAINER}"
		cmd_control_remove_error_eexist "${CONTAINER}" "$TESTPW"
	fi

	ok "Test suite: ${CONTAINER}"
}

do_test_provisioning() {
	begin "Test: device provisioning"
	cmd_control_get_provisioned false
	cmd_control_set_provisioned "CMD_OK"
	cmd_control_get_provisioned true
	cmd_control_set_provisioned "CMD_UNSUPPORTED"
	ok "Test: device provisioning"
}

do_test_update() {
	local GUESTOS_NAME="$1"
	local GUESTOS_VERSION="$2"
	local image_size_by_os_version=$(( GUESTOS_VERSION * 1024 ))
	local os_path="/${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}"
	local conf_args="/tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.conf /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.sig /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.cert"

	local update_path="/${update_base_url#/}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}"
	einfo "########## Starting guestos update test suite, GUESTOS=${GUESTOS_NAME}, VERSION=${GUESTOS_VERSION} ##########"

	ssh ${SSH_OPTS} "mkdir -p '${update_path}'"
	cmd_control_push_guestos_config "/tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.conf /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.sig /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.cert" "GUESTOS_MGR_INSTALL_FAILED"

	ssh ${SSH_OPTS} "truncate -s '${GUESTOS_VERSION}G' '${update_path}/root.img'"
	einfo "ssh ${SSH_OPTS} \"truncate -s '${GUESTOS_VERSION}G' '${update_path}/root.img'\""
	ssh ${SSH_OPTS} "truncate -s '${GUESTOS_VERSION}M' '${update_path}/root.hash.img'"

	einfo "ssh ${SSH_OPTS} \"ls -lh '${update_path}'\""
	ssh ${SSH_OPTS} "ls -lh '${update_path}'"

	cmd_control_push_guestos_config "/tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.conf /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.sig /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.cert" "GUESTOS_MGR_INSTALL_COMPLETED"

	ssh ${SSH_OPTS} "rm -r '${update_path}'"
}

do_test_push_kernel_update() {
	local KERNEL_VERSION
	KERNEL_VERSION=$(gawk 'match($0, /^version: (.*)/, ary) {print ary[1]}' kernel/kernel-*.conf)
	local KERNEL_VERSION_NEW=$(( KERNEL_VERSION + 1 ))

	begin "Test: kernel update ${KERNEL_VERSION} -> ${KERNEL_VERSION_NEW}"
	do_copy_kernel_update "$KERNEL_VERSION_NEW"
	ssh "${SSH_OPTS[@]}" "mkdir -p /${update_base_url}/operatingsystems/x86"
	ssh "${SSH_OPTS[@]}" "mv /tmp/kernel-${KERNEL_VERSION_NEW} /${update_base_url}/operatingsystems/x86"
	cmd_control_push_guestos_config "/tmp/kernel-${KERNEL_VERSION_NEW}.conf /tmp/kernel-${KERNEL_VERSION_NEW}.sig /tmp/kernel-${KERNEL_VERSION_NEW}.cert" "GUESTOS_MGR_INSTALL_COMPLETED"

	cmd_control_list_guestos "${KERNEL_VERSION}"
	cmd_control_list_guestos "${KERNEL_VERSION_NEW}"
	ok "Test: kernel update"
}

do_test_check_kernel_version() {
	local KERNEL_VERSION
	KERNEL_VERSION=$(gawk 'match($0, /^version: (.*)/, ary) {print ary[1]}' kernel/kernel-*.conf)
	local KERNEL_VERSION_NEW=$(( KERNEL_VERSION + 1 ))

	einfo "Verify kernel versions ${KERNEL_VERSION} and ${KERNEL_VERSION_NEW} present after reboot"
	cmd_control_list_guestos "${KERNEL_VERSION}"
	cmd_control_list_guestos "${KERNEL_VERSION_NEW}"

	if [[ "ccmode" != "${MODE}" ]] || [[ "y" == "${OPT_CC_MODE_EXPERIMENTAL}" ]]; then
		elog "Checking device.conf.B in cml-daemon log"
		local TMPDIR
		TMPDIR=$(ssh "${SSH_OPTS[@]}" "mktemp -d -p /tmp")
		cmd_control_retrieve_logs "${TMPDIR}" "CMD_OK"
		local LATEST_LOG
		LATEST_LOG=$(ssh "${SSH_OPTS[@]}" "ls ${TMPDIR}/cml-daemon* | tail -n1")
		local GREP_OUT
		GREP_OUT=$(ssh "${SSH_OPTS[@]}" "grep 'device.conf path is /data/cml/device.conf.B' ${LATEST_LOG}") || true
		if [[ -z "${GREP_OUT}" ]]; then
			die "cmld did not load device.conf.B — kernel update failed"
		fi
	fi
}

# =====================================================================
# Main
# =====================================================================
parse_cli "$@"

# Compile project
if [[ "$COMPILE" == true ]]; then
	begin "Compile"
	# oe-init-build-env (sourced transitively) doesn't tolerate nounset
	set +u
	# shellcheck disable=SC1091
	source init_ws.sh "${BUILD_DIR}" x86 genericx86-64
	set -u

	if [[ "$FORCE" == true ]]; then
		bitbake -c clean multiconfig:container:gyroidos-core
		bitbake -c clean cmld
		bitbake -c clean gyroidos-cml-initramfs
		bitbake -c clean gyroidos-cml
	fi

	if [[ -n "$BRANCH" ]]; then
		sed -i "s/branch=\${BRANCH}/branch=$BRANCH/g" cmld_git.bbappend
	fi

	bitbake multiconfig:container:gyroidos-core
	bitbake gyroidos-cml
	ok "Compile"
elif [[ -z "${IMGPATH}" ]]; then
	[[ -d "${BUILD_DIR}" ]] || die "Build directory not found: ${BUILD_DIR}"
	cd "${BUILD_DIR}"  # intentional: subsequent operations run relative to BUILD_DIR
fi

if [[ -n "$BRANCH" ]]; then
	# shellcheck disable=SC2012
	[[ -n "$(ls -d tmp/work/core*/cmld/git*/git 2>/dev/null || true)" ]] || die "No cmld build found"
	BUILD_BRANCH=$(git -C tmp/work/core*/cmld/git*/git branch | tee /proc/self/fd/1 | grep '\*' | awk '{ print $NF }')
	[[ "$BRANCH" == "$BUILD_BRANCH" ]] || die "Branch mismatch: expected \"$BRANCH\", built \"$BUILD_BRANCH\""
fi

if [[ -n "$(pgrep "$PROCESS_NAME" || true)" ]]; then
	[[ "$KILL_VM" == true ]] || die "VM \"$PROCESS_NAME\" already running"
	pgrep "${PROCESS_NAME}" | xargs kill -SIGKILL
fi

# Prepare images
begin "Prepare test images"
if ! [[ -e "${PROCESS_NAME}.ext4fs" ]]; then
	dd if=/dev/zero of="${PROCESS_NAME}.ext4fs" bs=1M count=10000 &> /dev/null
fi
mkfs.ext4 -L containers "${PROCESS_NAME}.ext4fs"
rm -f "${PROCESS_NAME}.img"

if [[ -n "${IMGPATH}" ]]; then
	einfo "Image: ${IMGPATH}"
	rsync "${IMGPATH}" "${PROCESS_NAME}.img"
else
	einfo "Image: $(pwd)/tmp/deploy/images/genericx86-64/gyroidos_image/gyroidosimage.img"
	rsync tmp/deploy/images/genericx86-64/gyroidos_image/gyroidosimage.img "${PROCESS_NAME}.img"
fi

# Create image
# -----------------------------------------------
echo_status "Creating images"
if ! [ -e "${PROCESS_NAME}.ext4fs" ]
then
	truncate -s 10G "${PROCESS_NAME}.ext4fs"
fi

mkfs.ext4 -E nodiscard -L containers "${PROCESS_NAME}.ext4fs"

# Backup system image
# TODO it could have been modified if VM run outside of this script with different args already
rm -f ${PROCESS_NAME}.img

if ! [[ -z "${IMGPATH}" ]];then
	echo_status "Testing image at ${IMGPATH}"
	# Attempt COW copy, fallback to regular cp
	cp --reflink=auto --dereference "${IMGPATH}" "${PROCESS_NAME}.img"
else
	echo_status "Testing image at $(pwd)/tmp/deploy/images/genericx86-64/gyroidos_image/gyroidosimage.img"
	# Attempt COW copy, fallback to regular cp
	cp --reflink=auto --dereference tmp/deploy/images/genericx86-64/gyroidos_image/gyroidosimage.img "${PROCESS_NAME}.img"
fi

# Prepare image for test with physical tokens
if [[ -n "${HSM_SERIAL}" ]]; then
	einfo "Preparing HSM image (serial=${HSM_SERIAL})"
	/usr/local/bin/preparetmeimg.sh "$(pwd)/${PROCESS_NAME}.img"
fi

if [[ -f "/usr/share/OVMF/OVMF_VARS.fd" ]]; then
	cp /usr/share/OVMF/OVMF_VARS.fd OVMF_VARS.fd
elif [[ -f "/usr/share/OVMF/OVMF_VARS_4M.fd" ]]; then
	cp /usr/share/OVMF/OVMF_VARS_4M.fd OVMF_VARS.fd
else
	die "Failed to locate OVMF_VARS"
fi
ok "Prepare test images"

# Boot 1 — initial boot & host key
begin "Boot 1"
start_vm

for I in $(seq 1 10) ;do
	if ssh-keyscan -T 10 -p "$SSH_PORT" -H 127.0.0.1 > "${PROCESS_NAME}.vm_key" 2>/dev/null; then
		break
	elif [[ "10" == "$I" ]]; then
		die "Failed to retrieve VM host key"
	fi
done

installed_guestos_version="$(cmd_control_get_guestos_version gyroidos-coreos)"
einfo "GuestOS version: $installed_guestos_version"

update_base_url="var/volatile/tmp"
ok "Boot 1"

# Prepare test configs & containers
begin "Create test configs and containers"
do_create_testconfigs
do_copy_configs

cmd_control_list

if [[ "$COPY_ROOTCA" == "y" ]]; then
	elog "Copying root CA to VM"
	for I in $(seq 1 10) ;do
		if scp -q "${SCP_OPTS[@]}" "${PKI_DIR}/ssig_rootca.cert" root@127.0.0.1:/tmp/; then
			break
		elif [[ "$I" -eq 10 ]]; then
			die "Could not copy root CA to VM"
		fi
		sleep 0.5
	done
	cmd_control_ca_register " /tmp/ssig_rootca.cert"
fi

cmd_control_update_config "core0 /tmp/c0.conf /tmp/c0.sig /tmp/c0.cert" "allow_dev: \"b 8:"
cmd_control_config "core0"

elog "Creating containers (mode=${MODE}, force_sig=${OPT_FORCE_SIG_CFGS})"
if [[ "dev" == "$MODE" ]] && [[ "n" == "$OPT_FORCE_SIG_CFGS" ]]; then
	cmd_control_create "/tmp/testcontainer.conf"
	cmd_control_list_container "testcontainer"
else
	cmd_control_create_error "/tmp/testcontainer.conf"
fi

cmd_control_create "/tmp/signedcontainer1.conf" "/tmp/signedcontainer1.sig" "/tmp/signedcontainer1.cert"
cmd_control_list_container "signedcontainer1"

if [[ -z "${HSM_SERIAL}" ]]; then
	cmd_control_create "/tmp/signedcontainer2.conf" "/tmp/signedcontainer2.sig" "/tmp/signedcontainer2.cert"
	cmd_control_list_container "signedcontainer2"
fi

cmd_control_create "/tmp/rmcontainer3.conf" "/tmp/rmcontainer3.sig" "/tmp/rmcontainer3.cert"
cmd_control_list_container "rmcontainer3"
ok "Create test configs and containers"

sync_to_disk
sync_to_disk

# Boot 2 — reboot and verify persistence
begin "Boot 2"
cmd_control_reboot
wait_vm

cmd_control_list_container "signedcontainer1"
do_copy_configs

cmd_control_update_config "signedcontainer1 /tmp/signedcontainer1_update.conf /tmp/signedcontainer1_update.sig /tmp/signedcontainer1_update.cert" "netif: \"00:00:00:00:00:11\""

if [[ -n "${HSM_SERIAL}" ]]; then
	einfo "Preparing SE pairing"
	sync_to_disk
	sync_to_disk
	force_stop_vm

	/usr/local/bin/preparetmecontainer.sh "$(pwd)/${PROCESS_NAME}.ext4fs"
	sleep 2

	start_vm
	sleep 2
	do_copy_configs
fi

cmd_control_list_container "signedcontainer1"
if [[ -z "${HSM_SERIAL}" ]]; then
	cmd_control_list_container "signedcontainer2"
fi
do_copy_update_configs
ok "Boot 2"

# Run integration tests — first pass
begin "Integration tests (pass 1)"
if [[ -z "${HSM_SERIAL}" ]]; then
	do_test_complete "signedcontainer1" "n" "n"
	do_test_complete "signedcontainer2" "n" "n"
else
	do_test_complete "signedcontainer1" "n" "y"
fi

do_test_rm "rmcontainer3"
do_test_update "nullos" "1"
do_test_update "nullos" "2"
ok "Integration tests (pass 1)"

# Boot 3 — reboot and second pass
begin "Boot 3"
cmd_control_reboot
wait_vm
ok "Boot 3"

do_copy_configs
do_copy_update_configs

begin "Integration tests (pass 2)"
if [[ -z "${HSM_SERIAL}" ]]; then
	do_test_complete "signedcontainer1" "y" "n"
	do_test_complete "signedcontainer2" "y" "n"
else
	do_test_complete "signedcontainer1" "y" "y"
fi

do_test_update "nullos" "3"
do_test_provisioning
do_test_push_kernel_update
ok "Integration tests (pass 2)"

# Boot 4 — verify kernel update
begin "Boot 4"
cmd_control_reboot
wait_vm
ok "Boot 4"

do_test_check_kernel_version

if [[ "production" == "${MODE}" ]]; then
	begin "TPM2 test"
	force_stop_vm
	sleep 2
	fetch_logs  # must happen before encryption
	start_swtpm

	SWTPM="-chardev socket,id=chrtpm,path=/tmp/swtpmqemu/swtpm-sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
	start_vm

	cmd_control_state_is_running "TPM2D"
	ok "TPM2 test"
fi

# Success
trap - EXIT
force_stop_vm

if [[ "production" != "${MODE}" ]]; then
	fetch_logs
fi

ok "All tests passed"
exit 0
