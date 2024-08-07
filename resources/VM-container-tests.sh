#!/bin/bash

set -e

sync_to_disk() {
    echo "STATUS: Syncing VM state to disk"
    for I in $(seq 1 10) ;do 
        if ssh ${SSH_OPTS} 'sh -c sync && sleep 1' 2>&1;then
            echo "STATUS: Synced VM state to disk"
            break
        elif ! [[ "$I" == "10" ]];then
            echo "STATUS: Failed to sync VM state to disk, retrying"
			sleep 0.5
        else
            echo "ERROR: Could not sync VM state to disk, exiting..."
        fi
    done
}

force_stop_vm() {
    sync_to_disk

    sleep 2
    echo "Sending quit to QEMU monitor socket"
    if echo "quit" | socat - ./${PROCESS_NAME}.qemumon;then
		echo "Sucessfully requested VM to exit cleanly"
	else
		echo "Failed to request clean VM exit"
	fi

    rm -f ${PROCESS_NAME}.vm_key
}

fetch_logs() {
	if [ -z "${LOG_DIR}" ];then
		echo "-l / --log-dir not specified, skipping log file retrieval"
	else
		mkdir -p "${LOG_DIR}"
		skip=$(/sbin/fdisk -lu ${PROCESS_NAME}.img | tail -n1 | awk '{print $2}')
		sectors=$(/sbin/fdisk -lu ${PROCESS_NAME}.img | tail -n1 | awk '{print $3}')
		dd if=${PROCESS_NAME}.img of=${PROCESS_NAME}.data bs=512 skip=${skip} count=${sectors}
		for i in `e2ls ${PROCESS_NAME}.data:/userdata/logs`; do
			e2cp ${PROCESS_NAME}.data:/userdata/logs/${i} ${LOG_DIR}/
		done
		echo "Retrieved CML logs: $(ls -al ${LOG_DIR})"
	fi
}

err_fetch_logs() {
    echo "An error occurred, attempting to fetch logs from VM"

	trap - EXIT INT TERM

    force_stop_vm

    fetch_logs
    exit 1
}


trap 'err_fetch_logs' EXIT INT TERM


CMDPATH="${BASH_SOURCE[0]}"
echo "Sourcing $(dirname "${CMDPATH}")/VM-container-commands.sh"
source "$(dirname "${CMDPATH}")/VM-container-commands.sh"

export PATH="/sbin/:usr/sbin/:${PATH}"

PROCESS_NAME="qemu-gyroid-ci"
SSH_PORT=2223
BUILD_DIR=""
KILL_VM=false
IMGPATH=""
MODE=""
LOG_DIR=""

# Directory containing test PKI for image
PKI_DIR=""

# Serial of USB Token
SCHSM=""

# Copy root CA from test PKI to image
COPY_ROOTCA="y"

SCRIPTS_DIR=""

TESTPW="pw"

# Function definitions
# ----------------------------------------------

wait_vm () {
	echo "Waiting for VM to become available"
	sleep 3
	# Copy test container config to VM
	success="n"
	for I in $(seq 1 100) ;do
		sleep 1

		if [[ -z "$(pgrep $PROCESS_NAME)" ]];then
			echo "Error: QEMU process exited"
			exit 1
		fi
		if ssh -q ${SSH_OPTS} "ls /data" ;then
			echo "VM access was successful"
			success="y"
			break
		else
			printf "."
		fi
	done

	if [[ "$success" != "y" ]];then
		echo "VM access failed, exiting..."
		exit 1
	fi
}

start_vm() {
	qemu-system-x86_64 -machine accel=kvm,vmport=off -m 64G -smp 4 -cpu host -bios OVMF.fd \
		-monitor unix:./${PROCESS_NAME}.qemumon,server,nowait \
		-name trustme-tester,process=${PROCESS_NAME} -nodefaults -nographic \
		-device virtio-rng-pci,rng=id -object rng-random,id=id,filename=/dev/urandom \
		-device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
		-drive if=none,id=hd0,file=${PROCESS_NAME}.img,cache=directsync,format=raw \
		-device scsi-hd,drive=hd1 \
		-drive if=none,id=hd1,file=${PROCESS_NAME}.ext4fs,cache=directsync,format=raw \
		-device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 \
		-drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd" \
		-drive "if=pflash,format=raw,file=./OVMF_VARS.fd" \
		$VNC \
		$TELNET \
		$PASS_SCHSM >/dev/null &

	wait_vm
}

sync_to_disk() {
	echo "STATUS: Syncing VM state to disk"
	for I in $(seq 1 10) ;do
		if ssh ${SSH_OPTS} 'sh -c sync && sleep 1' 2>&1;then
			echo "STATUS: Synced VM state to disk"
			break
		elif ! [[ "$I" == "10" ]];then
			echo "STATUS: Failed to sync VM state to disk, retrying, status: $?"
		else
			echo "ERROR: Could not sync VM state to disk, exiting..."
		fi
	done
}

do_create_testconfigs() {
# Create container configuration files for tests
# -----------------------------------------------

if [[ -z "$SCHSM" ]];then

cat > ./testcontainer.conf << EOF
name: "testcontainer"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:2 rwm"
image_sizes {
  image_name: "etc"
  image_size: 10
}
EOF


cat > ./signedcontainer1.conf << EOF
name: "signedcontainer1"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:2 rwm"
image_sizes {
  image_name: "etc"
  image_size: 10
}
EOF


cat > ./signedcontainer1_update.conf << EOF
name: "signedcontainer1"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:2 rwm"
image_sizes {
  image_name: "etc"
  image_size: 10
}
fifos: "signedfifo11"
fifos: "signedfifo12"

vnet_configs {
if_name: "vnet0"
configure: false
if_rootns_name: "r_1"
}
vnet_configs {
if_name: "vnet1"
configure: false
if_rootns_name: "r_2"
}


net_ifaces {
netif: "00:00:00:00:00:11"
mac_filter: "AA:AA::AA:AA:AA"
mac_filter: "00:00:00:00:00:14"
}
EOF

cat > ./signedcontainer2.conf << EOF
name: "signedcontainer2"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:3 rwm"
allow_dev: "b 8:* rwm"
fifos: "signedfifo21"
fifos: "signedfifo22"

vnet_configs {
if_name: "vnet0"
configure: false
if_rootns_name: "r_3"
}
vnet_configs {
if_name: "vnet1"
configure: false
if_rootns_name: "r_4"
}

net_ifaces {
netif: "00:00:00:00:00:14"
mac_filter: "AA:AA::AA:AA:AA"
mac_filter: "00:00:00:00:00:11"
}
net_ifaces {
netif: "00:00:00:00:00:15"
}
net_ifaces {
netif: "00:00:00:00:00:16"
}
EOF


else

cat > ./testcontainer.conf << EOF
name: "testcontainer"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:5 rwm"
image_sizes {
  image_name: "etc"
  image_size: 10
}
EOF


cat > ./signedcontainer1.conf << EOF
name: "signedcontainer1"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:2 rwm"
token_type: USB
usb_configs {
  id: "04e6:5816"
  serial: "${SCHSM}"
  assign: true
  type: TOKEN
}
image_sizes {
  image_name: "etc"
  image_size: 10
}
EOF


cat > ./signedcontainer1_update.conf << EOF
name: "signedcontainer1"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:2 rwm"
token_type: USB
usb_configs {
  id: "04e6:5816"
  serial: "${SCHSM}"
  assign: true
  type: TOKEN
}
image_sizes {
  image_name: "etc"
  image_size: 10
}
fifos: "signedfifo11"
fifos: "signedfifo12"

vnet_configs {
if_name: "vnet0"
configure: false
if_rootns_name: "r_1"
}
vnet_configs {
if_name: "vnet1"
configure: false
if_rootns_name: "r_2"
}


net_ifaces {
netif: "00:00:00:00:00:11"
mac_filter: "AA:AA::AA:AA:AA"
mac_filter: "00:00:00:00:00:14"
}
EOF

cat > ./signedcontainer2.conf << EOF
name: "signedcontainer2"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:3 rwm"
fifos: "signedfifo21"
fifos: "signedfifo22"

vnet_configs {
if_name: "vnet0"
configure: false
if_rootns_name: "r_3"
}
vnet_configs {
if_name: "vnet1"
configure: false
if_rootns_name: "r_4"
}

net_ifaces {
netif: "00:00:00:00:00:14"
mac_filter: "AA:AA::AA:AA:AA"
mac_filter: "00:00:00:00:00:11"
}
net_ifaces {
netif: "00:00:00:00:00:15"
}
net_ifaces {
netif: "00:00:00:00:00:16"
}
EOF

fi

echo "STATUS: Prepared testcontainer.conf:"
echo "$(cat ./testcontainer.conf)"

echo "STATUS: Prepared signedcontainer1.conf:"
echo "$(cat ./signedcontainer1.conf)"

echo "STATUS: Prepared signedcontainer1_update.conf:"
echo "$(cat ./signedcontainer1_update.conf)"



echo "STATUS: Prepared signedcontainer2.conf:"
echo "$(cat ./signedcontainer2.conf)"



cat > ./c0.conf << EOF
name: "core0"
guest_os: "trustx-coreos"
guestos_version: $installed_guestos_version
assign_dev: "c 4:1 rwm"
allow_dev: "b 8:* rwm"
EOF


echo "STATUS: Prepared c0.conf:"
echo "$(cat ./c0.conf)"


cat > ./nullos-1.conf << EOF
name: "nullos"
hardware: "x86"
version: 1
init_path: "/sbin/init"
init_param: "splash"
mounts {
	image_file: "root"
	mount_point: "/"
	fs_type: "squashfs"
	mount_type: SHARED_RW
	image_size: 1073741824
	image_sha1: "2a492f15396a6768bcbca016993f4b4c8b0b5307"
	image_sha2_256: "49bc20df15e412a64472421e13fe86ff1c5165e18b2afccf160d4dc19fe68a14"
	image_verity_sha256: "0000000000000000000000000000000000000000000000000000000000000000"
}
description {
	en: "null os just for update testing 1GB root.img (x86)"
}
update_base_url: "file://$update_base_url"
build_date: "$(date +%F%T%Z -u)"
EOF

cat > ./nullos-2.conf << EOF
name: "nullos"
hardware: "x86"
version: 2
init_path: "/sbin/init"
init_param: "splash"
mounts {
	image_file: "root"
	mount_point: "/"
	fs_type: "squashfs"
	mount_type: SHARED_RW
	image_size: 2147483648
	image_sha1: "91d50642dd930e9542c39d36f0516d45f4e1af0d"
	image_sha2_256: "a7c744c13cc101ed66c29f672f92455547889cc586ce6d44fe76ae824958ea51"
	image_verity_sha256: "0000000000000000000000000000000000000000000000000000000000000000"
}
description {
	en: "null os just for update testing 2GB root.img (x86)"
}
update_base_url: "file://$update_base_url"
build_date: "$(date +%F%T%Z -u)"
EOF

cat > ./nullos-3.conf << EOF
name: "nullos"
hardware: "x86"
version: 3
init_path: "/sbin/init"
init_param: "splash"
mounts {
	image_file: "root"
	mount_point: "/"
	fs_type: "squashfs"
	mount_type: SHARED_RW
	image_size: 3221225472
	image_sha1: "6e7f6dca8def40df0b21f58e11c1a41c3e000285"
	image_sha2_256: "305b66a59d15b252092fbda9d09711230c429f351897cbd430e7b55a35fd3b97"
	image_verity_sha256: "0000000000000000000000000000000000000000000000000000000000000000"
}
description {
	en: "null os just for update testing 3GB root.img (x86)"
}
update_base_url: "file://$update_base_url"
build_date: "$(date +%F%T%Z -u)"
EOF


echo "STATUS: Prepared nullos-1.conf:"
echo "$(cat ./nullos-1.conf)"

echo "STATUS: Prepared nullos-2.conf:"
echo "$(cat ./nullos-2.conf)"

echo "STATUS: Prepared nullos-3.conf:"
echo "$(cat ./nullos-3.conf)"


echo "PKI_DIR there?: $PKI_DIR"
# Sign signedcontainer{1,2}.conf, c0.conf (enforced in production and ccmode images)
if [[ -d "$PKI_DIR" ]];then
	echo "A"
	scripts_path=""
	if ! [[ -z "${SCRIPTS_DIR}" ]];then
		scripts_path="${SCRIPTS_DIR}/"
	elif ! [[ -z "${BUILD_DIR}" ]];then
		echo "STATUS: --scripts-dir not given, assuming \"../trustme/build\""
		scripts_path="$(pwd)/../trustme/build"
		echo "scripts_path: $scripts_path"
	else
		echo "STATUS: --scripts-dir not given, assuming \"./trustme/build\""
		scripts_path="$(pwd)/trustme/build"
	fi

	echo "B"
	if ! [[ -d "$scripts_path" ]];then
		echo "STATUS: Could not find trustme_build directory at $scripts_path."
		read -r -p "Download from GitHub?" -n 1

		if [[ "$REPLY" == "y" ]];then
			mkdir -p "$scripts_path"
			echo "STATUS: Got y, downloading trustme_build repository to $scripts_path"
			git clone https://github.com/gyroidos/gyroidos_build.git "$scripts_path"
		fi
	fi

	echo "c"

	if ! [ -f "$scripts_path/device_provisioning/oss_enrollment/config_creator/sign_config.sh" ];then
		echo "ERROR: Could not find sign_config.sh at $scripts_path/device_provisioning/oss_enrollment/config_creator/sign_config.sh. Exiting..."
		exit 1
	fi

	signing_script="$scripts_path/device_provisioning/oss_enrollment/config_creator/sign_config.sh"

	if ! [[ -f "$signing_script" ]];then
		echo "ERROR: $signing_script does not exist or is not a regular file. Exiting..."
		exit 1
	fi

	echo "STATUS: Signing container configuration filessing using PKI at ${PKI_DIR} and $signing_script"


	echo "bash \"$signing_script\" \"./signedcontainer1.conf\" \"${PKI_DIR}/ssig_cml.key\" \"${PKI_DIR}/ssig_cml.cert\""
	bash "$signing_script" "./signedcontainer1.conf" "${PKI_DIR}/ssig_cml.key" "${PKI_DIR}/ssig_cml.cert"

	echo "bash \"$signing_script\" \"./signedcontainer1_update.conf\" \"${PKI_DIR}/ssig_cml.key\" \"${PKI_DIR}/ssig_cml.cert\""
	bash "$signing_script" "./signedcontainer1_update.conf" "${PKI_DIR}/ssig_cml.key" "${PKI_DIR}/ssig_cml.cert"

	echo "bash \"$signing_script\" \"./signedcontainer2.conf\" \"${PKI_DIR}/ssig_cml.key\" \"${PKI_DIR}/ssig_cml.cert\""
	bash "$signing_script" "./signedcontainer2.conf" "${PKI_DIR}/ssig_cml.key" "${PKI_DIR}/ssig_cml.cert"

	echo "bash \"$signing_script\" \"./c0.conf\" \"${PKI_DIR}/ssig_cml.key\" \"${PKI_DIR}/ssig_cml.cert\""
	bash "$signing_script" "./c0.conf" "${PKI_DIR}/ssig_cml.key" "${PKI_DIR}/ssig_cml.cert"


	echo "STATUS: Signing guestos configuration files using using PKI at ${PKI_DIR} and $signing_script"

	for I in $(seq 1 3); do
		echo "bash \"$signing_script\" \"./nullos-${I}.conf\" \"${PKI_DIR}/ssig_cml.key\" \"${PKI_DIR}/ssig_cml.cert\""
		bash "$signing_script" "./nullos-${I}.conf" "${PKI_DIR}/ssig_cml.key" "${PKI_DIR}/ssig_cml.cert"
	done
else
	echo "ERROR: No test PKI found at $PKI_DIR, exiting..."
	exit 1
fi

echo "STATUS: Signed signedcontainer{1,2}.conf, signedcontainer1_update.conf, c0.conf:"
}

do_copy_configs(){
# Copy test container configs to VM
for I in $(seq 1 10) ;do
	echo "STATUS: Trying to copy container configs to image"

	# copy only .conf if signing was skipped
	if [ -f signedcontainer1.sig ];then
		FILES="testcontainer.conf signedcontainer1.conf signedcontainer1.sig signedcontainer1.cert \
			   signedcontainer1_update.conf signedcontainer1_update.sig signedcontainer1_update.cert \
			   signedcontainer2.conf signedcontainer2.sig signedcontainer2.cert \
			   c0.conf c0.sig c0.cert"
	else
		FILES="signedcontainer1.conf signedcontainer1_update.conf signedcontainer2.conf c0.conf"
	fi

	if scp $SCP_OPTS $FILES root@127.0.0.1:/tmp/;then
		echo "STATUS: scp was successful"
		break
	elif ! [ $I -eq 10 ];then
		echo "STATUS: scp failed, retrying..."
	else
		echo "STATUS: Failed to copy container configs to VM, exiting..."
		err_fetch_logs
	fi
done
}

do_copy_update_configs(){
# Copy test guestos configs for update to VM
for I in $(seq 1 10) ;do
	echo "STATUS: Trying to copy GuestOS configs to image"

	FILES=" nullos-1.conf nullos-1.sig nullos-1.cert \
		nullos-2.conf nullos-2.sig nullos-2.cert \
		nullos-3.conf nullos-3.sig nullos-3.cert"

	if scp $SCP_OPTS $FILES root@127.0.0.1:/tmp/;then
		echo "STATUS: scp was successful"
		break
	elif ! [ $I -eq 10 ];then
		echo "STATUS: scp failed, retrying..."
	else
		echo "STATUS: Failed to copy nullos GuestOS configs to VM, exiting..."
		err_fetch_logs
	fi
done
}

do_test_complete() {
	CONTAINER="$1"
	SECOND_RUN="$2"
	USBTOKEN="$3"
	echo "STATUS: ########## Starting container test suite, CONTAINER=${CONTAINER}, SECOND_RUN=${SECOND_RUN}, USBTOKEN=${USBTOKEN} ##########"

	# Test if cmld is up and running
	echo "STATUS: Test if cmld is up and running"
	cmd_control_list

	if [ "n" = "$USBTOKEN" ];then
		# Skip these tests for physical schsm
		cmd_control_change_pin_error "${CONTAINER}" "wrongpin" "$TESTPW"

		if ! [ "${SECOND_RUN}" = "y" ];then
			echo "STATUS: Trigger ERROR_UNPAIRED"
			cmd_control_start_error_unpaired "${CONTAINER}" "$TESTPW"

			echo "STATUS: Change pin: trustme -> $TESTPW token PIN"
			cmd_control_change_pin "${CONTAINER}" "trustme" "$TESTPW"

		else
			echo "STATUS: Re-changing token PIN"
			cmd_control_change_pin "${CONTAINER}" "$TESTPW" "$TESTPW"
		fi
	else
		# TODO add --schsm-all flag
		echo "STATUS: Skipping change_pin test for sc-hsm"
	fi

	echo "STATUS: Starting container \"${CONTAINER}\""
	cmd_control_start "${CONTAINER}" "$TESTPW"

	cmd_control_config "${CONTAINER}"

	ssh ${SSH_OPTS} "echo testmessage1 > /dev/fifos/signedfifo1"

	ssh ${SSH_OPTS} "echo testmessage2 > /dev/fifos/signedfifo2"

	cmd_control_list_guestos "trustx-coreos"

	cmd_control_remove_error_eexist "nonexistent-container"

	cmd_control_start_error_eexist "${CONTAINER}" "$TESTPW"


	# Stop test container
	cmd_control_stop "${CONTAINER}" "$TESTPW"

	cmd_control_stop_error_notrunning "${CONTAINER}" "$TESTPW"


	# Perform additional tests in second run
	if [[ "${SECOND_RUN}" == "y" ]];then

		# test start / stop cycles
		for I in {1..100};do
			echo "Start/stop cycle $I"

			cmd_control_start "${CONTAINER}" "$TESTPW"

			cmd_control_stop "${CONTAINER}" "$TESTPW"
		done


		# test retrieve_logs command
		TMPDIR="$(ssh ${SSH_OPTS} "mktemp -d -p /tmp")"

		if [[ "ccmode" == "${MODE}" ]];then
			cmd_control_retrieve_logs "${TMPDIR}" "CMD_UNSUPPORTED"
		else
			cmd_control_retrieve_logs "${TMPDIR}" "CMD_OK"
		fi

		# Test container removal
		echo "Second test run, removing container"
		cmd_control_remove "${CONTAINER}" "$TESTPW"

		echo "STATUS: Check container has been removed"
		cmd_control_list_ncontainer "${CONTAINER}"

		echo "STATUS: Removing non-existent container"
		cmd_control_remove_error_eexist "${CONTAINER}" "$TESTPW"
	fi

}

do_test_provisioning() {
	echo "STATUS: ########## Starting device provisioning test suite ##########"
	# test provisioning always last since set_provisioned reduces the command set

	echo "STATUS: Check that device is not provisioned yet"
	cmd_control_get_provisioned false

	echo "STATUS: Setting device to provisioned state"
	cmd_control_set_provisioned "CMD_OK"

	echo "STATUS: Check that device is provisioned"
	cmd_control_get_provisioned true

	echo "STATUS: Check device reduced command set"
	cmd_control_set_provisioned "CMD_UNSUPPORTED"
}

do_test_update() {
	GUESTOS_NAME="$1"
	GUESTOS_VERSION="$2"

	echo "STATUS: ########## Starting guestos update test suite, GUESTOS=${GUESTOS_NAME}, VERSION=${GUESTOS_VERSION} ##########"

	let "image_size_by_os_version = $GUESTOS_VERSION * 1024"

	ssh ${SSH_OPTS} "mkdir -p /${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}"
	cmd_control_push_guestos_config "/tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.conf /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.sig /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.cert" "GUESTOS_MGR_INSTALL_FAILED"

	ssh ${SSH_OPTS} "dd if=/dev/zero of=/${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}/root.img bs=1M count=${image_size_by_os_version}"
	echo "ssh ${SSH_OPTS} \"dd if=/dev/zero of=/${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}/root.img bs=1M count=${image_size_by_os_version}\""
	ssh ${SSH_OPTS} "dd if=/dev/zero of=/${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}/root.hash.img bs=1M count=${GUESTOS_VERSION}"

	echo "ssh ${SSH_OPTS} \"ls -lh /${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}\""
	ssh ${SSH_OPTS} "ls -lh /${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}"

	cmd_control_push_guestos_config "/tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.conf /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.sig /tmp/${GUESTOS_NAME}-${GUESTOS_VERSION}.cert" "GUESTOS_MGR_INSTALL_COMPLETED"

	ssh ${SSH_OPTS} "rm -r /${update_base_url}/operatingsystems/x86/${GUESTOS_NAME}-${GUESTOS_VERSION}"
}


# Argument retrieval
# -----------------------------------------------
while [[ $# > 0 ]]; do
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
      echo "-e, --enable-schsm	Test with given schsm"
      echo "-k, --skip-rootca	Skip attempt to copy custom root CA to image"
      echo "-r, --scripts-dir	Specify directory containing signing scripts (trustme_build repo)"
      exit 1
      ;;
    -c|--compile)
      COMPILE=true
      shift
      ;;
    -b|--branch)
      shift
      BRANCH=$1
      if [[ $BRANCH  == "" ]]
      then
        echo "ERROR: No branch specified. Run with --help for more information."
        exit 1
      fi
      shift
      ;;
    -d|--dir)
      shift
      if [[ $1  == "" || ! -d $1 ]]
      then
        echo "ERROR: No (existing) directory specified. Run with --help for more information."
        exit 1
      fi
      echo "STATUS: changing to directory $(pwd)"
      cd $1
      echo "STATUS: changed to directory $(pwd)"
      shift
      ;;
    -o|--builddir)
      shift
      BUILD_DIR="$(readlink -v -f $1)"
      shift
      ;;
    -f|--force)
      shift
      FORCE=true
      ;;
    -v|--vnc)
      shift
      if ! [[ $1 =~ ^[0-9]+$ ]]
      then
        echo "ERROR: VNC port must be a number. (got $1)"
        exit 1
      fi
      VNC="-vnc 0.0.0.0:$1 -vga std"
      shift
      ;;
    -s|--ssh)
      shift
      SSH_PORT=$1
      if ! [[ $SSH_PORT =~ ^[0-9]+$ ]]
      then
        echo "ERROR: ssh host port must be a number. (got $SSH_PORT)"
        exit 1
      fi
      shift
      ;;
    -t|--telnet)
      shift
      if ! [[ $1 =~ ^[0-9]+$ ]]
      then
        echo "ERROR: telnet host port must be a number. (got $1)"
        exit 1
      fi
      TELNET="-serial mon:telnet:127.0.0.1:$1,server,nowait"
      shift
      ;;
    -k|--kill)
      shift
      KILL_VM=true
      ;;
    -n|--name)
      shift
      PROCESS_NAME=$1
      shift
      ;;
    -p|--pki)
      shift
      PKI_DIR="$(readlink -v -f $1)"
      shift
      ;;
    -i|--image)
      shift
      IMGPATH=$1
      shift
      ;;
    -m|--mode)
      shift
      if ! [[ "$1" = "dev" ]] && ! [[ $1 = "production" ]] && ! [[ "$1" = "ccmode" ]];then
      echo "ERROR: Unkown mode \"$1\" specified. Exiting..."
      exit 1
      fi
      echo "STATUS: Testing \"$1\" image"
      MODE=$1
      shift
      ;;
     -e|--enable-schsm)
      shift
      SCHSM="$1"
      shift
      TESTPW="$1"
      PASS_SCHSM="-usb -device qemu-xhci -device usb-host,vendorid=0x04e6,productid=0x5816"
      echo "STATUS: Enable sc-hsm tests for token $SCHSM"
      shift
      ;;
    -k|--skip-rootca)
      COPY_ROOTCA="n"
      shift
      ;;
    -r| --scripts-dir)
      shift
      SCRIPTS_DIR="$(readlink -v -f $1)"
      shift
      ;;
    -l| --log-dir)
      shift
      LOG_DIR="$(readlink -v -m $1)"
      shift
      ;;

     *)
      echo "ERROR: Unknown arguments specified? ($1)"
      exit 1
      ;;
  esac
done

BASE_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=${PROCESS_NAME}.vm_key -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=5"
SCP_OPTS="-P $SSH_PORT $BASE_OPTS"
SSH_OPTS="-p $SSH_PORT $BASE_OPTS root@localhost"

# check PKI dir
if [[ -z "${PKI_DIR}" ]];then
	echo "STATUS: --pki not specified, assuming \"test_certificates\""
	PKI_DIR="test_certificates"
fi



if ! [ -d "${PKI_DIR}" ];then
	echo "ERROR: No PKI given, exiting..."
	exit 1
fi


# Compile project
# -----------------------------------------------
if [[ $COMPILE == true ]]
then
	# changes dir to BUILD_DIR
	source init_ws.sh ${BUILD_DIR} x86 genericx86-64

	if [[ $FORCE == true ]]
	then
		bitbake -c clean multiconfig:container:trustx-core
		bitbake -c clean cmld
		bitbake -c clean trustx-cml-initramfs
		bitbake -c clean trustx-cml
	fi

	if [[ $BRANCH != "" ]]
	then
		# TODO \${BRANCH} is defined in init_ws.sh -> if changes there, this won't work
		sed -i "s/branch=\${BRANCH}/branch=$BRANCH/g" cmld_git.bbappend
	fi

	bitbake multiconfig:container:trustx-core
	bitbake trustx-cml
elif [[ -z "${IMGPATH}" ]]
then
	if [ ! -d "${BUILD_DIR}" ]
	then
		echo "ERROR: Could not find build directory at \"${BUILD_DIR}\". Specify --build-dir or --img."
		exit 1
	fi

	cd ${BUILD_DIR}
	echo "STATUS: Changed dir to ${BUILD_DIR}"
fi

# Check if the branch matches the built one
if [[ $BRANCH != "" ]]
then
	# Check if cmld was build
	if [ -z $(ls -d tmp/work/core*/cmld/git*/git) ]
	then
		echo "ERROR: No cmld build found: did you compile?"
		exit 1
	fi


	BUILD_BRANCH=$(git -C tmp/work/core*/cmld/git*/git branch | tee /proc/self/fd/1 | grep '*' | awk '{ print $NF }')  # check if git repo found and correct branch used
	if [[ $BRANCH != $BUILD_BRANCH ]]
	then
		echo "ERROR: The specified branch \"$BRANCH\" does not match the build ($BUILD_BRANCH). Please recompile with flag -c."
		exit 1
	fi
fi

# Ensure VM is not running
# -----------------------------------------------
echo "STATUS: Ensure VM is not running"
if [[ $(pgrep $PROCESS_NAME) != "" ]]
then
	if [ ${KILL_VM} ];then
		echo "STATUS: Kill current VM (--kill was given)"
		pgrep ${PROCESS_NAME} | xargs kill -SIGKILL
else
		echo "ERROR: VM instance called \"$PROCESS_NAME\" already running. Please stop/kill it first."
		exit 1
fi
else
	echo "STATUS: VM not running"
fi

# Create image
# -----------------------------------------------
echo "STATUS: Creating images"
if ! [ -e "${PROCESS_NAME}.ext4fs" ]
then
	dd if=/dev/zero of=${PROCESS_NAME}.ext4fs bs=1M count=10000 &> /dev/null
fi

mkfs.ext4 -L containers ${PROCESS_NAME}.ext4fs

# Backup system image
# TODO it could have been modified if VM run outside of this script with different args already
rm -f ${PROCESS_NAME}.img

if ! [[ -z "${IMGPATH}" ]];then
	echo "STATUS: Testing image at ${IMGPATH}"
	rsync ${IMGPATH} ${PROCESS_NAME}.img
else
	echo "STATUS: Testing image at $(pwd)/tmp/deploy/images/genericx86-64/trustme_image/trustmeimage.img"
	rsync tmp/deploy/images/genericx86-64/trustme_image/trustmeimage.img ${PROCESS_NAME}.img
fi

# Prepare image for test with physical tokens
if ! [[ -z "${SCHSM}" ]]
then
	echo "STATUS: Preparing image for test with sc-hsm container"
	/usr/local/bin/preparetmeimg.sh "$(pwd)/${PROCESS_NAME}.img"
fi

# Start VM
# -----------------------------------------------

# copy for faster startup
cp /usr/share/OVMF/OVMF_VARS.fd .

# Start test VM
start_vm


# Retrieve VM host key
echo "STATUS: Retrieving VM host key"
for I in $(seq 1 10) ;do
	echo "STATUS: Scanning for VM host key on port $SSH_PORT"
	if ssh-keyscan -T 10 -p $SSH_PORT -H 127.0.0.1 > ${PROCESS_NAME}.vm_key ;then
		echo "STATUS: Got VM host key: $!"
		break
	elif [ "10" = "$I" ];then
		echo "ERROR: exitcode $1"
		exit 1
	fi

	echo "STATUS: Failed to retrieve VM host key"
done

echo "STATUS: extracting current installed OS version"
installed_guestos_version="$(cmd_control_get_guestos_version trustx-coreos)"
echo "Found OS version: $installed_guestos_version"

update_base_url="var/volatile/tmp"

# Prepare tests
# -----------------------------------------------
echo "STATUS: ########## Preparing tests ##########"

do_create_testconfigs

do_copy_configs

# Prepare test container
# -----------------------------------------------


echo "STATUS: ########## Setting up test containers ##########"
# Test if cmld is up and running
echo "STATUS: Test if cmld is up and running"
cmd_control_list

# Skip root CA registering test if test PKI no available or disabled
if [[ "$COPY_ROOTCA" == "y" ]]
then
	echo "STATUS: Copying root CA at ${PKI_DIR}/ssig_rootca.cert to image as requested"
	for I in $(seq 1 10) ;do
		echo "STATUS: Trying to copy rootca cert"
		if scp -q $SCP_OPTS ${PKI_DIR}/ssig_rootca.cert root@127.0.0.1:/tmp/;then
			echo "STATUS: scp was sucessful"
			break
		elif ! [ $I -eq 10 ];then
			echo "STATUS: Failed to copy root CA, retrying..."
			sleep 0.5
		else
			echo "ERROR: Could not copy root CA to VM, exiting..."
			exit 1
		fi
	done


	cmd_control_ca_register " /tmp/ssig_rootca.cert"
fi

echo "STATUS: Updating c0.conf"
cmd_control_update_config "core0 /tmp/c0.conf /tmp/c0.sig /tmp/c0.cert" "allow_dev: \"b 8:"
cmd_control_config "core0"

# Create test containers
if [ "dev" = "$MODE" ];then
	echo "Creating unsigned test container, expecting success:\n$(cat testcontainer.conf)"
	cmd_control_create "/tmp/testcontainer.conf"
	cmd_control_list_container "testcontainer"
else
	echo "Creating unsigned test container, expecting error:\n$(cat testcontainer.conf)"
	cmd_control_create_error "/tmp/testcontainer.conf"
fi

echo "Creating signed container:\n$(cat signedcontainer1.conf)"
cmd_control_create "/tmp/signedcontainer1.conf" "/tmp/signedcontainer1.sig" "/tmp/signedcontainer1.cert"
cmd_control_list_container "signedcontainer1"


if [[ -z "${SCHSM}" ]];then
	echo "Creating signed container:\n$(cat signedcontainer2.conf)"
	cmd_control_create "/tmp/signedcontainer2.conf" "/tmp/signedcontainer2.sig" "/tmp/signedcontainer2.cert"
	cmd_control_list_container "signedcontainer2"
fi

sync_to_disk

sync_to_disk

cmd_control_reboot

wait_vm

do_copy_configs

echo "STATUS: Updating signedcontainer1"

cmd_control_update_config "signedcontainer1 /tmp/signedcontainer1_update.conf /tmp/signedcontainer1_update.sig /tmp/signedcontainer1_update.cert" "netif: \"00:00:00:00:00:11\""
# Workaround to avoid issues qith QEMU's forwarding rules
#sleep 5

# Set device container pairing state if testing with physical tokens
if ! [[ -z "${SCHSM}" ]];then
	echo "STATUS: ########## Preparing SE ##########"
	force_stop_vm

	echo "STATUS: Setting container pairing state"
	/usr/local/bin/preparetmecontainer.sh "$(pwd)/${PROCESS_NAME}.ext4fs"

	echo "STATUS: Waiting for QEMU to cleanup USB devices"
	sleep 2

	start_vm
	echo "STATUS: Waiting for USB devices to become ready in QEMU"
	sleep 2
	ssh ${SSH_OPTS} 'echo "VM USB Devices: " && lsusb' 2>&1
fi

do_copy_update_configs

# Start tests
# -----------------------------------------------

echo "STATUS: Starting tests"

if [ -z "${SCHSM}" ];then
	do_test_complete "signedcontainer1" "n" "n"
	do_test_complete "signedcontainer2" "n" "n"
else
	do_test_complete "signedcontainer1" "n" "y"
fi

do_test_update "nullos" "1"
do_test_update "nullos" "2"


cmd_control_reboot

# Workaround to avoid issues qith QEMU's forwarding rules
#sleep 5

wait_vm

do_copy_configs
do_copy_update_configs

#echo "Waiting for USB devices to become ready in QEMU"
#sleep 5
#ssh ${SSH_OPTS} 'echo "STATUS: VM USB Device: " && lsusb' 2>&1

if [ -z "${SCHSM}" ];then
	do_test_complete "signedcontainer1" "y" "n"
	do_test_complete "signedcontainer2" "y" "n"
else
	do_test_complete "signedcontainer1" "y" "y"
fi

do_test_update "nullos" "3"

do_test_provisioning

# Success
# -----------------------------------------------
echo -e "\n\nSUCCESS: All tests passed"

trap - EXIT

force_stop_vm

fetch_logs

exit 0
