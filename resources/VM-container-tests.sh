#!/bin/bash

set -e

CMDPATH="${BASH_SOURCE[0]}"
echo "Sourcing $(dirname "${CMDPATH}")/settings.sh"
source "$(dirname "${CMDPATH}")/settings.sh"

echo "Sourcing $(dirname "${CMDPATH}")/VM-container-commands.sh"
source "$(dirname "${CMDPATH}")/VM-container-commands.sh"

echo "Sourcing $(dirname "${CMDPATH}")/VM-management.sh"
source "$(dirname "${CMDPATH}")/VM-management.sh"

echo "Sourcing $(dirname "${CMDPATH}")/testdata.sh"
source "$(dirname "${CMDPATH}")/testdata.sh"

OPT_FORCE_SIG_CFGS="n"

# Function definitions
# ----------------------------------------------

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
echo "OPT_FORCE_SIG_CFGS: $OPT_FORCE_SIG_CFGS"
if [ "dev" = "$MODE" ] && [ "n" = "$OPT_FORCE_SIG_CFGS" ];then
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

# List test containers
if [ "dev" = "$MODE" ] && [ "n" = "$OPT_FORCE_SIG_CFGS" ];then
	cmd_control_list_container "testcontainer"
fi

cmd_control_list_container "signedcontainer1"

if [[ -z "${SCHSM}" ]];then
	cmd_control_list_container "signedcontainer2"
fi

do_copy_configs

echo "STATUS: Updating signedcontainer1"

cmd_control_update_config "signedcontainer1 /tmp/signedcontainer1_update.conf /tmp/signedcontainer1_update.sig /tmp/signedcontainer1_update.cert" "netif: \"00:00:00:00:00:11\""
# Workaround to avoid issues qith QEMU's forwarding rules
#sleep 5

# Set device container pairing state if testing with physical tokens
if ! [[ -z "${SCHSM}" ]];then
	echo "STATUS: ########## Preparing SE ##########"
	sync_to_disk

	sync_to_disk

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

# List test containers
if [ "dev" = "$MODE" ] && [ "n" = "$OPT_FORCE_SIG_CFGS" ];then
	cmd_control_list_container "testcontainer"
fi

cmd_control_list_container "signedcontainer1"

if [[ -z "${SCHSM}" ]];then
	cmd_control_list_container "signedcontainer2"
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
