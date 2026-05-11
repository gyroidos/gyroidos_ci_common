#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

sync_to_disk() {
    for I in $(seq 1 10) ;do
        if ssh "${SSH_OPTS[@]}" 'sh -c sync && sleep 1' 2>&1; then
            return
        elif [[ "$I" == "10" ]]; then
            eerror "Could not sync VM state to disk"
        fi
        sleep 0.5
    done
}

force_stop_vm() {
    elog "Stopping VM"
    sync_to_disk
    sleep 2
    printf 'quit\n' | socat -T2 STDIN "UNIX-CONNECT:./${PROCESS_NAME}.qemumon" || true
    rm -f "${PROCESS_NAME}.vm_key"
}

fetch_logs() {
    if [[ -z "${LOG_DIR}" ]]; then
        return
    fi
    elog "Retrieving CML logs to ${LOG_DIR}"
    {
        mkdir -p "${LOG_DIR}"
        local skip sectors sector_size fdisk_out
        fdisk_out="$(/sbin/fdisk -lu "${PROCESS_NAME}.img")"
        sector_size="$(awk '/Sector size/ {print $4; exit}' <<< "${fdisk_out}")"
        # Fallback if parsing fails
        : "${sector_size:=512}"

        local last_line
        last_line="$(tail -n1 <<< "${fdisk_out}")"
        skip="$(awk '{print $2}' <<< "${last_line}")"
        sectors="$(awk '{print $4}' <<< "${last_line}")"

		set -x
        dd if="${PROCESS_NAME}.img" of="${PROCESS_NAME}.data" bs=4M \
            iflag=skip_bytes,count_bytes \
            skip=$((skip*sector_size)) count=$((sectors*sector_size)) status=none
		set +x

        for i in `e2ls ${PROCESS_NAME}.data:/userdata/logs`; do
            if [ -z "${i##*.current}" ]; then
                continue;
            fi
            e2cp "${PROCESS_NAME}.data:/userdata/logs/${i}" "${LOG_DIR}/"
        done
    }
}

err_fetch_logs() {
    eerror "An error occurred, attempting to fetch logs from VM"
    trap - EXIT INT TERM
    force_stop_vm
    fetch_logs
    exit 1
}


trap 'err_fetch_logs' EXIT INT TERM

wait_vm () {
    elog "Waiting for VM to become available"
    sleep 3
    for I in $(seq 1 100) ;do
        sleep 1
        if [[ -z "$(pgrep "$PROCESS_NAME")" ]]; then
            die "QEMU process exited unexpectedly"
        fi
        if ssh -q "${SSH_OPTS[@]}" "ls /data" ; then
            return
        fi
    done
    die "VM not reachable after 100s"
}

start_swtpm() {
    if [[ ! -d "/tmp/swtpmqemu" ]]; then
	    mkdir /tmp/swtpmqemu
    fi

    swtpm socket --tpmstate dir=/tmp/swtpmqemu --tpm2 --ctrl type=unixio,path=/tmp/swtpmqemu/swtpm-sock &
}

# $1: Disk Image Path
align_image () {
    local img_path
    img_path="$(realpath -e "$1")"
    local hosting_mount
    hosting_mount="$(df --output=target "$img_path" | tail -1)"
    local fs_bsize
    fs_bsize="$(stat -fc%s "$hosting_mount" 2>/dev/null || echo 4096)"
    qemu-img resize -f raw "$img_path" $(( (($(stat -c%s "$img_path") + fs_bsize - 1) / fs_bsize) * fs_bsize )) >/dev/null
}

start_vm() {
	local ovmf_code=""
	if [[ -f "/usr/share/OVMF/OVMF_CODE.fd" ]]; then
		ovmf_code="/usr/share/OVMF/OVMF_CODE.fd"
	elif [[ -f "/usr/share/OVMF/OVMF_CODE_4M.fd" ]]; then
		ovmf_code="/usr/share/OVMF/OVMF_CODE_4M.fd"
	else
		die "Failed to locate OVMF_CODE"
	fi

    elog "Starting QEMU VM (${PROCESS_NAME})"
    align_image "${PROCESS_NAME}.img"
    align_image "${PROCESS_NAME}.ext4fs"
    # shellcheck disable=SC2086 # SWTPM, VNC, TELNET, PASS_HSM are intentionally word-split
    qemu-system-x86_64 -machine accel=kvm,vmport=off -m 64G -smp 4 -cpu host -bios OVMF.fd \
        -monitor unix:./"${PROCESS_NAME}".qemumon,server,nowait \
        -name gyroidos-tester,process="${PROCESS_NAME}" -nodefaults -nographic \
        -device virtio-rng-pci,rng=id -object rng-random,id=id,filename=/dev/urandom \
        -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
        -drive if=none,id=hd0,file="${PROCESS_NAME}".img,cache=directsync,format=raw \
        -device scsi-hd,drive=hd1 \
        -drive if=none,id=hd1,file="${PROCESS_NAME}".ext4fs,cache=directsync,format=raw \
        -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::"$SSH_PORT"-:22 \
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
        -drive "if=pflash,format=raw,file=./OVMF_VARS.fd" \
        $SWTPM \
        $VNC \
        $TELNET \
        $PASS_HSM >/dev/null &

    wait_vm
}
