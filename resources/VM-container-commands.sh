#!/usr/bin/env bash
set -euo pipefail

RUNDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=common.sh
source "${RUNDIR}/common.sh"

do_wait_running () {
	while true; do
		STATE="$(ssh "${SSH_OPTS[@]}" "/usr/sbin/control state $1" 2>&1)"
		edebug "control state $1: $STATE"
		if [[ "$STATE" == *RUNNING* ]]; then
			break
		elif [[ "$STATE" == *STARTING* ]] || [[ "$STATE" == *BOOTING* ]]; then
			sleep 0.1
		else
			die "Expected STARTING/RUNNING for \"$1\", got: ${STATE}"
		fi
	done
}

do_wait_stopped () {
	while true; do
		STATE="$(ssh "${SSH_OPTS[@]}" "/usr/sbin/control state $1" 2>&1)"
		if [[ "$STATE" == *STOPPED* ]]; then
			break
		fi
		sleep 0.5
	done
}

do_test_cmd_output() {
	if [[ -z "$1" || -z "$2" ]]; then
		die "do_test_cmd_output: required parameters missing"
	fi

	OUTPUT="$(ssh "${SSH_OPTS[@]}" "$1" 2>&1)" || true
	edebug "cmd='$1' output='$OUTPUT'"

	if ! echo "$OUTPUT" | grep -q "$2"; then
		eerror "Expected \"$2\" in output of: $1"
		die "Got: $OUTPUT"
	fi
}

do_test_cmd_noutput() {
	if [[ -z "$1" || -z "$2" ]]; then
		die "do_test_cmd_noutput: required parameters missing"
	fi

	OUTPUT="$(ssh "${SSH_OPTS[@]}" "$1" 2>&1)" || true
	edebug "cmd='$1' output='$OUTPUT'"

	if echo "$OUTPUT" | grep -q "$2"; then
		eerror "Did not expect \"$2\" in output of: $1"
		die "Got: $OUTPUT"
	fi
}


cmd_control_start() {
	do_test_cmd_output "/usr/sbin/control start $1 --key=$2" "CONTAINER_START_OK"
	do_wait_running "$1"
}

cmd_control_start_error_unpaired() {
	do_test_cmd_output "/usr/sbin/control start $1 --key=$2" "CONTAINER_START_TOKEN_UNPAIRED"
}

cmd_control_start_error_eexist() {
	do_test_cmd_output "/usr/sbin/control start $1 --key=$2" "CONTAINER_START_EEXIST"
}

cmd_control_stop() {
	do_test_cmd_output "/usr/sbin/control stop $1 --key=$2" "CONTAINER_STOP_OK"
	do_wait_stopped "$1"
}

cmd_control_stop_error_notrunning() {
	do_test_cmd_output "/usr/sbin/control stop $1 --key=$2" "CONTAINER_STOP_FAILED_NOT_RUNNING"
	do_wait_stopped "$1"
}

cmd_control_list() {
	do_test_cmd_output "/usr/sbin/control list" "code: CONTAINER_STATUS"
}

cmd_control_list_container() {
	do_test_cmd_output "/usr/sbin/control list" "$1"
}

cmd_control_list_ncontainer() {
	do_test_cmd_noutput "/usr/sbin/control list" "$1"
}

cmd_control_list_guestos() {
	do_test_cmd_output "/usr/sbin/control list_guestos" "$1"
}

cmd_control_create() {
	if [[ -z "${2:-}" ]]; then
		do_test_cmd_output "/usr/sbin/control create \"$1\"" "guest_os"
	else
		do_test_cmd_output "/usr/sbin/control create \"$1\" \"$2\" \"$3\"" "guest_os"
	fi
}

cmd_control_create_error() {
	if [[ -z "${2:-}" ]]; then
		do_test_cmd_noutput "/usr/sbin/control create \"$1\"" "uuids"
	else
		do_test_cmd_noutput "/usr/sbin/control create \"$1\" \"$2\" \"$3\"" "uuids"
	fi
}

cmd_control_change_pin() {
	do_test_cmd_output "echo -ne \"$2\n$3\n$3\n\" | /usr/sbin/control change_pin $1" "CONTAINER_CHANGE_PIN_SUCCESSFUL"
}

cmd_control_change_pin_error() {
	do_test_cmd_output "echo -ne \"$2\n$3\n$3\n\" | /usr/sbin/control change_pin $1" "CONTAINER_CHANGE_PIN_FAILED"
}

cmd_control_config() {
	do_test_cmd_output "/usr/sbin/control config $1" "$1"
}

cmd_control_remove() {
	do_test_cmd_noutput "/usr/sbin/control remove $1 --key=$2" "Abort"
}

cmd_control_remove_error_eexist() {
	do_test_cmd_output "/usr/sbin/control remove $1 --key=${2:-}" "Container with provided uuid/name does not exist!"
}

cmd_control_ca_register() {
	do_test_cmd_noutput "/usr/sbin/control ca_register $1" "Abort"
}

cmd_control_reboot() {
	do_test_cmd_noutput "/usr/sbin/control reboot" "Abort"
}

cmd_control_get_guestos_version(){
	CMD="/usr/sbin/control list_guestos | grep $1 -A 2 | grep version\: | awk '{print \$2}' | sort | tail -n 1"
	OUTPUT="$(ssh "${SSH_OPTS[@]}" "$CMD")"
	echo "$OUTPUT"
}

cmd_control_retrieve_logs() {
	do_test_cmd_output "/usr/sbin/control retrieve_logs $1" "$2"
}

cmd_control_get_provisioned() {
	do_test_cmd_output "/usr/sbin/control get_provisioned" "device_is_provisioned: $1"
}

cmd_control_set_provisioned() {
	do_test_cmd_output "/usr/sbin/control set_provisioned" "response: $1"
}

cmd_control_list_guestos_silent() {
    OUTPUT="$(ssh "${SSH_OPTS[@]}" "/usr/sbin/control list_guestos" 2>&1)" || true
    if ! echo "$OUTPUT" | grep -q "$1"; then
        die "Expected \"$1\" in list_guestos output"
    fi
}

cmd_control_update_config() {
	do_test_cmd_output "/usr/sbin/control update_config $1" "$2"
}

cmd_control_push_guestos_config() {
	do_test_cmd_output "/usr/sbin/control push_guestos_config $1" "response: $2"
}

cmd_control_get_uuid() {
	CMD="/usr/sbin/control state $1 | grep uuid\: | awk -F '\"' '{print \$2}'"
	OUTPUT="$(ssh "${SSH_OPTS[@]}" "$CMD")"
	echo "$OUTPUT"
}

cmd_control_state_is_running() {
	do_wait_running "$1"
}
