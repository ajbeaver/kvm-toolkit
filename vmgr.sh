#!/bin/bash
# vmgr - KVM/QEMU Virtual Machine Management Utility
# Version: 1.0.0
# Usage: vmgr <command> [options]

VERSION="1.0.0"
LIBVIRT_URI="qemu:///system"
DISK_DIR="/var/lib/libvirt/images"
DEFAULT_SHUTDOWN_WAIT=60

SCRIPT_NAME=$(basename "$0")
SCRIPT_DISPLAY_NAME="${SCRIPT_NAME%.sh}"

info() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
error() { printf 'Error: %s\n' "$*" >&2; }

show_help() {
    cat << EOF
$SCRIPT_DISPLAY_NAME version $VERSION - KVM/QEMU VM manager

USAGE:
    $SCRIPT_DISPLAY_NAME <command> [arguments]

INSPECTION:
    list                              List all VMs
    status <vm-name>                  Show concise VM state
    info <vm-name>                    Show domain and storage information
    disks <vm-name>                   Show attached block devices
    network <vm-name>                 Show attached network interfaces

LIFECYCLE:
    start <vm-name>                   Start a stopped VM
    launch <vm-name>                  Start if needed, then open virt-viewer
    shutdown <vm-name> [--wait SEC]   Request graceful shutdown and optionally wait
    reboot <vm-name>                  Request graceful reboot
    force-stop <vm-name>              Immediately power off after confirmation

ACCESS:
    view <vm-name>                    Open a running VM in virt-viewer
    console <vm-name>                 Attach to the serial console

MAINTENANCE:
    autostart <vm-name> enable|disable
    undefine <vm-name>                Remove the domain definition, keeping storage
    remove <vm-name>                  Remove a shut-down VM and eligible storage

OPTIONS:
    --help, -h                        Show this help message
    --version, -v                     Show version information

EXAMPLES:
    $SCRIPT_DISPLAY_NAME list
    $SCRIPT_DISPLAY_NAME launch <vm-name>
    $SCRIPT_DISPLAY_NAME shutdown <vm-name> --wait $DEFAULT_SHUTDOWN_WAIT
    $SCRIPT_DISPLAY_NAME autostart <vm-name> enable
    $SCRIPT_DISPLAY_NAME remove <vm-name>

SAFETY:
    - All domain operations use $LIBVIRT_URI.
    - force-stop, undefine, and remove require confirmation.
    - remove refuses snapshots, shared disks, external paths, and ambiguous storage.
    - setup-vm's expected primary disk directory is $DISK_DIR.
EOF
}

show_version() {
    printf '%s version %s\n' "$SCRIPT_DISPLAY_NAME" "$VERSION"
}

prompt_value() {
    local prompt="$1"
    local output_name="$2"
    local value

    if ! IFS= read -r -p "$prompt" value; then
        printf '\n' >&2
        error "Input cancelled or unavailable."
        return 1
    fi
    printf -v "$output_name" '%s' "$value"
}

confirm_action() {
    local prompt="$1"
    local response

    prompt_value "$prompt" response || return 1
    [[ "$response" =~ ^[Yy]$ ]]
}

validate_vm_name() {
    local name="$1"

    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]]; then
        error "VM name must be 1-63 characters using letters, numbers, dots, underscores, or hyphens."
        return 1
    fi
}

validate_wait_seconds() {
    local value="$1"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        error "Wait time must be a whole number of seconds."
        return 1
    fi
    value=$((10#$value))
    if [ "$value" -lt 1 ] || [ "$value" -gt 3600 ]; then
        error "Wait time must be between 1 and 3600 seconds."
        return 1
    fi
}

require_commands() {
    local command_name
    local missing=()

    for command_name in sudo virsh; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing+=("$command_name")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing required command(s): ${missing[*]}"
        return 1
    fi
}

virsh_system() {
    sudo virsh --connect "$LIBVIRT_URI" "$@"
}

check_libvirt() {
    require_commands || return 1

    if ! sudo -v; then
        error "Sudo authentication failed or was cancelled."
        return 1
    fi
    if ! virsh_system list --all >/dev/null; then
        error "Could not connect to libvirt at $LIBVIRT_URI."
        return 1
    fi
}

vm_exists() {
    virsh_system dominfo "$1" >/dev/null 2>&1
}

require_vm() {
    local name="$1"

    if ! vm_exists "$name"; then
        error "VM '$name' does not exist in $LIBVIRT_URI."
        return 1
    fi
}

get_vm_state() {
    local name="$1"
    local output_name="$2"
    local domain_state

    if ! domain_state=$(LC_ALL=C virsh_system domstate "$name" 2>/dev/null); then
        error "Could not determine state for VM '$name'."
        return 1
    fi
    printf -v "$output_name" '%s' "$domain_state"
}

is_active_state() {
    case $1 in
        running|paused|pmsuspended|"in shutdown") return 0 ;;
        *) return 1 ;;
    esac
}

require_shut_off() {
    local name="$1"
    local state

    get_vm_state "$name" state || return 1
    if [ "$state" != "shut off" ]; then
        error "VM '$name' must be fully shut off; current state is '$state'."
        return 1
    fi
}

prepare_named_vm_command() {
    local name="$1"

    validate_vm_name "$name" || return 1
    check_libvirt || return 1
    require_vm "$name" || return 1
}

get_disk_sources() {
    local name="$1"
    local output_name="$2"
    local block_output sources parse_status

    if ! block_output=$(virsh_system domblklist "$name" --details 2>/dev/null); then
        error "Could not inspect disks attached to VM '$name'."
        return 1
    fi
    sources=$(printf '%s\n' "$block_output" | awk '
        $2 == "disk" {
            if (NF != 4) exit 2
            if ($4 != "-") print $4
        }
    ')
    parse_status=$?
    if [ "$parse_status" -ne 0 ]; then
        error "Disk metadata for VM '$name' is ambiguous (for example, a path containing whitespace)."
        error "No destructive storage operation will be attempted."
        return 1
    fi
    printf -v "$output_name" '%s' "$sources"
}

get_snapshot_names() {
    local name="$1"
    local output_name="$2"
    local snapshot_output

    if ! snapshot_output=$(virsh_system snapshot-list --name "$name" 2>/dev/null); then
        error "Could not inspect snapshots for VM '$name'."
        return 1
    fi
    printf -v "$output_name" '%s' "$snapshot_output"
}

cmd_list() {
    if [ "$#" -ne 0 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME list"
        return 2
    fi
    check_libvirt || return 1
    virsh_system list --all
}

cmd_status() {
    local name="${1:-}"
    local state

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME status <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    get_vm_state "$name" state || return 1
    info "$name: $state"
}

cmd_info() {
    local name="${1:-}"
    local disks expected_disk

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME info <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    if ! virsh_system dominfo "$name"; then
        error "Could not read domain information for '$name'."
        return 1
    fi

    get_disk_sources "$name" disks || return 1
    expected_disk="$DISK_DIR/${name}.qcow2"
    info ""
    info "Expected setup-vm disk: $expected_disk"
    info "Attached disks:"
    if [ -z "$disks" ]; then
        info "  (none)"
    else
        while IFS= read -r disk; do
            [ -n "$disk" ] && info "  $disk"
        done <<< "$disks"
    fi
}

cmd_disks() {
    local name="${1:-}"

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME disks <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    if ! virsh_system domblklist "$name" --details; then
        error "Could not list disks for VM '$name'."
        return 1
    fi
}

cmd_network() {
    local name="${1:-}"

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME network <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    if ! virsh_system domiflist "$name"; then
        error "Could not list network interfaces for VM '$name'."
        return 1
    fi
}

start_vm() {
    local name="$1"
    local state

    get_vm_state "$name" state || return 1
    case $state in
        running|paused|pmsuspended)
            info "VM '$name' is already $state."
            return 0
            ;;
        "shut off")
            info "Starting VM '$name'..."
            if ! virsh_system start "$name"; then
                error "Could not start VM '$name'."
                return 1
            fi
            info "VM '$name' started."
            ;;
        *)
            error "VM '$name' cannot be started from state '$state'."
            return 1
            ;;
    esac
}

cmd_start() {
    local name="${1:-}"

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME start <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    start_vm "$name"
}

open_viewer() {
    local name="$1"

    if ! command -v virt-viewer >/dev/null 2>&1; then
        error "virt-viewer is required for graphical VM access."
        return 1
    fi
    info "Opening graphical console for '$name'..."
    if ! virt-viewer --connect "$LIBVIRT_URI" "$name"; then
        error "virt-viewer could not open VM '$name'."
        return 1
    fi
}

cmd_launch() {
    local name="${1:-}"

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME launch <vm-name>"
        return 2
    fi
    validate_vm_name "$name" || return 1
    if ! command -v virt-viewer >/dev/null 2>&1; then
        error "virt-viewer is required for launch."
        return 1
    fi
    check_libvirt || return 1
    require_vm "$name" || return 1
    start_vm "$name" || return 1
    open_viewer "$name"
}

cmd_view() {
    local name="${1:-}"
    local state

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME view <vm-name>"
        return 2
    fi
    validate_vm_name "$name" || return 1
    if ! command -v virt-viewer >/dev/null 2>&1; then
        error "virt-viewer is required for graphical VM access."
        return 1
    fi
    check_libvirt || return 1
    require_vm "$name" || return 1
    get_vm_state "$name" state || return 1
    if ! is_active_state "$state" || [ "$state" = "in shutdown" ]; then
        error "VM '$name' is '$state'. Use '$SCRIPT_DISPLAY_NAME launch $name' to start and view it."
        return 1
    fi
    open_viewer "$name"
}

cmd_console() {
    local name="${1:-}"
    local state

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME console <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    get_vm_state "$name" state || return 1
    if [ "$state" != "running" ]; then
        error "VM '$name' must be running for console access; current state is '$state'."
        return 1
    fi
    info "Connecting to '$name'. Press Ctrl+] to leave the virsh console."
    virsh_system console "$name"
}

wait_for_shutdown() {
    local name="$1"
    local wait_seconds="$2"
    local elapsed=0 state

    while [ "$elapsed" -lt "$wait_seconds" ]; do
        get_vm_state "$name" state || return 1
        if [ "$state" = "shut off" ]; then
            info "VM '$name' shut down successfully."
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    get_vm_state "$name" state || return 1
    warn "VM '$name' is still '$state' after ${wait_seconds}s. It was not force-stopped."
    return 1
}

cmd_shutdown() {
    local name="${1:-}"
    local wait_seconds=""
    local state

    if [ "$#" -lt 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME shutdown <vm-name> [--wait SEC]"
        return 2
    fi
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wait)
                if [ "$#" -lt 2 ]; then
                    error "--wait requires a number of seconds."
                    return 2
                fi
                wait_seconds="$2"
                shift 2
                ;;
            *)
                error "Unknown shutdown option: $1"
                return 2
                ;;
        esac
    done

    validate_vm_name "$name" || return 1
    if [ -n "$wait_seconds" ]; then
        validate_wait_seconds "$wait_seconds" || return 1
        wait_seconds=$((10#$wait_seconds))
    fi
    check_libvirt || return 1
    require_vm "$name" || return 1
    get_vm_state "$name" state || return 1
    if [ "$state" = "shut off" ]; then
        info "VM '$name' is already shut off."
        return 0
    fi
    if [ "$state" != "running" ] && [ "$state" != "paused" ]; then
        error "Graceful shutdown is unavailable from state '$state'."
        return 1
    fi

    info "Requesting graceful shutdown for '$name'..."
    if ! virsh_system shutdown "$name"; then
        error "Shutdown request failed for VM '$name'."
        return 1
    fi
    if [ -n "$wait_seconds" ]; then
        wait_for_shutdown "$name" "$wait_seconds"
    else
        info "Shutdown requested. Use '$SCRIPT_DISPLAY_NAME status $name' to check progress."
    fi
}

cmd_reboot() {
    local name="${1:-}"
    local state

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME reboot <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    get_vm_state "$name" state || return 1
    if [ "$state" != "running" ]; then
        error "VM '$name' must be running to reboot; current state is '$state'."
        return 1
    fi
    if ! virsh_system reboot "$name"; then
        error "Reboot request failed for VM '$name'."
        return 1
    fi
    info "Reboot requested for VM '$name'."
}

cmd_force_stop() {
    local name="${1:-}"
    local state

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME force-stop <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    get_vm_state "$name" state || return 1
    if [ "$state" = "shut off" ]; then
        info "VM '$name' is already shut off."
        return 0
    fi

    warn "Force-stop is equivalent to disconnecting power and may corrupt guest data."
    if ! confirm_action "Immediately power off '$name'? (y/N): "; then
        info "Cancelled; the VM was not changed."
        return 0
    fi
    if ! virsh_system destroy "$name"; then
        error "Could not force-stop VM '$name'."
        return 1
    fi
    info "VM '$name' was force-stopped."
}

cmd_autostart() {
    local name="${1:-}"
    local action="${2:-}"

    if [ "$#" -ne 2 ] || [[ ! "$action" =~ ^(enable|disable)$ ]]; then
        error "Usage: $SCRIPT_DISPLAY_NAME autostart <vm-name> enable|disable"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    if [ "$action" = "enable" ]; then
        if ! virsh_system autostart "$name"; then
            error "Could not enable autostart for VM '$name'."
            return 1
        fi
        info "Autostart enabled for VM '$name'."
    else
        if ! virsh_system autostart "$name" --disable; then
            error "Could not disable autostart for VM '$name'."
            return 1
        fi
        info "Autostart disabled for VM '$name'."
    fi
}

require_no_snapshots() {
    local name="$1"
    local snapshots

    get_snapshot_names "$name" snapshots || return 1
    if [ -n "$snapshots" ]; then
        error "VM '$name' still has snapshots. Remove them with the snapshot tool first:"
        while IFS= read -r snapshot_name; do
            [ -n "$snapshot_name" ] && error "  $snapshot_name"
        done <<< "$snapshots"
        return 1
    fi
}

cmd_undefine() {
    local name="${1:-}"

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME undefine <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    require_shut_off "$name" || return 1
    require_no_snapshots "$name" || return 1

    warn "The domain definition for '$name' will be removed; attached storage will be kept."
    if ! confirm_action "Undefine VM '$name'? (y/N): "; then
        info "Cancelled; the VM was not changed."
        return 0
    fi
    if ! virsh_system undefine "$name"; then
        error "Could not undefine VM '$name'. It may have managed-save data or NVRAM."
        return 1
    fi
    info "VM '$name' was undefined; its storage was kept."
}

disk_is_shared() {
    local target_vm="$1"
    local target_disk="$2"
    local domains other_vm block_output

    if ! domains=$(virsh_system list --all --name); then
        error "Could not inspect other domains for shared storage."
        return 2
    fi
    while IFS= read -r other_vm; do
        [ -n "$other_vm" ] || continue
        [ "$other_vm" != "$target_vm" ] || continue
        if ! block_output=$(virsh_system domblklist "$other_vm" --details 2>/dev/null); then
            error "Could not inspect storage for VM '$other_vm'."
            return 2
        fi
        if printf '%s\n' "$block_output" | awk -v path="$target_disk" '$2 == "disk" && $4 == path { found=1 } END { exit !found }'; then
            error "Disk is also attached to VM '$other_vm': $target_disk"
            return 0
        fi
    done <<< "$domains"
    return 1
}

validate_removable_disks() {
    local name="$1"
    local disks="$2"
    local disk shared_status

    if [ -z "$disks" ]; then
        error "VM '$name' has no removable file-backed disks. Use undefine instead."
        return 1
    fi

    while IFS= read -r disk; do
        [ -n "$disk" ] || continue
        if [[ "$disk" != "$DISK_DIR/"* ]] || [[ "$disk" == *"/../"* ]]; then
            error "External or ambiguous disk will not be deleted: $disk"
            error "Detach or handle it manually, then use undefine if appropriate."
            return 1
        fi
        disk_is_shared "$name" "$disk"
        shared_status=$?
        case $shared_status in
            0) return 1 ;;
            1) ;;
            *) return 1 ;;
        esac
    done <<< "$disks"
}

cmd_remove() {
    local name="${1:-}"
    local disks disk
    local failures=0

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME remove <vm-name>"
        return 2
    fi
    prepare_named_vm_command "$name" || return 1
    require_shut_off "$name" || return 1
    require_no_snapshots "$name" || return 1
    get_disk_sources "$name" disks || return 1
    validate_removable_disks "$name" "$disks" || return 1

    warn "VM '$name' will be undefined and these disks will be permanently deleted:"
    while IFS= read -r disk; do
        [ -n "$disk" ] && warn "  $disk"
    done <<< "$disks"
    if ! confirm_action "Permanently remove VM '$name' and the listed disks? (y/N): "; then
        info "Cancelled; the VM and disks were not changed."
        return 0
    fi

    if ! virsh_system undefine "$name"; then
        error "Could not undefine VM '$name'. No disks were deleted."
        return 1
    fi

    while IFS= read -r disk; do
        [ -n "$disk" ] || continue
        if sudo rm -f -- "$disk"; then
            info "Deleted disk: $disk"
        else
            error "Could not delete disk after undefining VM: $disk"
            failures=$((failures + 1))
        fi
    done <<< "$disks"

    if [ "$failures" -ne 0 ]; then
        error "VM was undefined, but $failures disk deletion(s) failed."
        return 1
    fi
    info "VM '$name' and its eligible storage were removed."
}

main() {
    local command="${1:-help}"

    case $command in
        version|--version|-v) show_version ;;
        help|--help|-h) show_help ;;
        list) shift; cmd_list "$@" ;;
        status) shift; cmd_status "$@" ;;
        info) shift; cmd_info "$@" ;;
        disks) shift; cmd_disks "$@" ;;
        network) shift; cmd_network "$@" ;;
        start) shift; cmd_start "$@" ;;
        launch) shift; cmd_launch "$@" ;;
        shutdown) shift; cmd_shutdown "$@" ;;
        reboot) shift; cmd_reboot "$@" ;;
        force-stop) shift; cmd_force_stop "$@" ;;
        view) shift; cmd_view "$@" ;;
        console) shift; cmd_console "$@" ;;
        autostart) shift; cmd_autostart "$@" ;;
        undefine) shift; cmd_undefine "$@" ;;
        remove) shift; cmd_remove "$@" ;;
        *)
            error "Unknown command: $command"
            show_help >&2
            return 2
            ;;
    esac
}

main "$@"
