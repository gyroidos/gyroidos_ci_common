#!/bin/bash
set -e

sync_to_disk() {
    echo_status "Syncing VM state to disk"
    for I in $(seq 1 10) ;do 
        if ssh ${SSH_OPTS} 'sh -c sync && sleep 1' 2>&1;then
            echo_status "Synced VM state to disk"
            break
        elif ! [[ "$I" == "10" ]];then
            echo_status "Failed to sync VM state to disk, retrying"
            sleep 0.5
        else
            echo_error "Could not sync VM state to disk, exiting..."
        fi
    done
}

force_stop_vm() {
    sync_to_disk

    sleep 2
    echo_status "Sending quit to QEMU monitor socket"
    if echo "quit" | socat - ./${PROCESS_NAME}.qemumon;then
        echo_status "Sucessfully requested VM to exit cleanly"
    else
        echo_status "Failed to request clean VM exit"
    fi

    rm -f ${PROCESS_NAME}.vm_key
}

fetch_logs() {
    if [ -z "${LOG_DIR}" ];then
        echo_status "-l / --log-dir not specified, skipping log file retrieval"
    else
        mkdir -p "${LOG_DIR}"
        local skip sectors fdisk_out
        fdisk_out="$(/sbin/fdisk -lu "${PROCESS_NAME}.img" | tail -n1)"
        skip="$(awk '{print $2}' <<< "${fdisk_out}")"
        sectors="$(awk '{print $3}' <<< "${fdisk_out}")"
        dd if="${PROCESS_NAME}.img" of="${PROCESS_NAME}.data" bs=4M \
            iflag=skip_bytes,count_bytes \
            skip=$((skip*512)) count=$((sectors*512)) status=none
        for i in `e2ls ${PROCESS_NAME}.data:/userdata/logs`; do
            if [ -z "${i##*.current}" ]; then
                continue;
            fi
            e2cp ${PROCESS_NAME}.data:/userdata/logs/${i} ${LOG_DIR}/
        done
        echo_status "Retrieved CML logs: $(ls -al ${LOG_DIR})"
    fi
}

err_fetch_logs() {
    echo_status "An error occurred, attempting to fetch logs from VM"

    trap - EXIT INT TERM

    force_stop_vm

    fetch_logs
    exit 1
}


trap 'err_fetch_logs' EXIT INT TERM

wait_vm () {
    echo_status "Waiting for VM to become available"
    sleep 3
    # Copy test container config to VM
    success="n"
    for I in $(seq 1 100) ;do
        sleep 1

        if [[ -z "$(pgrep $PROCESS_NAME)" ]];then
            echo_status "Error: QEMU process exited"
            exit 1
        fi
        if ssh -q ${SSH_OPTS} "ls /data" ;then
            echo_status "VM access was successful"
            success="y"
            break
        else
            printf "."
        fi
    done

    if [[ "$success" != "y" ]];then
        echo_status "VM access failed, exiting..."
        exit 1
    fi
}

start_swtpm() {
    if [[ ! -d "/tmp/swtpmqemu" ]];then
	    mkdir /tmp/swtpmqemu
    fi

    swtpm socket --tpmstate dir=/tmp/swtpmqemu --tpm2 --ctrl type=unixio,path=/tmp/swtpmqemu/swtpm-sock &
}

# $1: Disk Image Path
align_image () {
    local img_path="$(realpath -e "$1")"
    # Get mountpoint of hosting filesystem
    local hosting_mount="$(df --output=target "$img_path" | tail -1)"
    # Get filesystem block size
    local fs_bsize="$(stat -fc%s "$hosting_mount" 2>/dev/null || echo 4096)"
    # Resize to be a multiple of the fs block size
    echo_status "Resizing ${1} to match fs block size of ${fs_bsize}B"
    qemu-img resize -f raw "$img_path" $(( (($(stat -c%s "$img_path") + $fs_bsize - 1) / $fs_bsize) * $fs_bsize ))
}

start_vm() {
	ovmf_code=""
	if [ -f "/usr/share/OVMF/OVMF_CODE.fd" ];then
		ovmf_code="/usr/share/OVMF/OVMF_CODE.fd"
	elif [ -f "/usr/share/OVMF/OVMF_CODE_4M.fd" ];then
		ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.fd"
	else
		echo_error "Failed to locate OVMF_CODE"
		exit 1
	fi

    align_image "${PROCESS_NAME}.img"
    align_image "${PROCESS_NAME}.ext4fs"
    qemu-system-x86_64 -machine accel=kvm,vmport=off -m 64G -smp 4 -cpu host -bios OVMF.fd \
        -monitor unix:./${PROCESS_NAME}.qemumon,server,nowait \
        -name gyroidos-tester,process=${PROCESS_NAME} -nodefaults -nographic \
        -device virtio-rng-pci,rng=id -object rng-random,id=id,filename=/dev/urandom \
        -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
        -drive if=none,id=hd0,file=${PROCESS_NAME}.img,cache=directsync,format=raw \
        -device scsi-hd,drive=hd1 \
        -drive if=none,id=hd1,file=${PROCESS_NAME}.ext4fs,cache=directsync,format=raw \
        -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 \
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
        -drive "if=pflash,format=raw,file=./OVMF_VARS.fd" \
        $SWTPM \
        $VNC \
        $TELNET \
        $PASS_HSM >/dev/null &

    wait_vm
}
