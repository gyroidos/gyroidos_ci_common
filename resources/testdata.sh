#!/bin/bash
set -e

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