#!/bin/bash
# snapshot - KVM/QEMU Snapshot Management Utility
# Version: 1.1.0
# Usage: snapshot <command> [options]

VERSION="1.1.0"
DISK_DIR="/var/lib/libvirt/images"

SCRIPT_NAME=$(basename "$0")
SCRIPT_DISPLAY_NAME="${SCRIPT_NAME%.sh}"

info() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
error() { printf 'Error: %s\n' "$*" >&2; }

show_help() {
    cat << EOF
$SCRIPT_DISPLAY_NAME version $VERSION - KVM/QEMU snapshot manager

USAGE:
    $SCRIPT_DISPLAY_NAME <command> [arguments]

COMMANDS:
    create <vm-name> [tag]    Create a snapshot; defaults to a timestamp tag
    list <vm-name>            List snapshots for a VM
    restore <vm-name> <tag>   Restore a shut-down VM to a snapshot
    delete <vm-name> <tag>    Delete one snapshot; use tag 'all' to delete all
    version                   Show version information
    help                      Show this help message

EXAMPLES:
    $SCRIPT_DISPLAY_NAME create <vm-name>
    $SCRIPT_DISPLAY_NAME create <vm-name> <snapshot-tag>
    $SCRIPT_DISPLAY_NAME list <vm-name>
    $SCRIPT_DISPLAY_NAME restore <vm-name> <snapshot-tag>
    $SCRIPT_DISPLAY_NAME delete <vm-name> <snapshot-tag>
    $SCRIPT_DISPLAY_NAME delete <vm-name> all

NOTES:
    - setup-vm places its expected primary disk at $DISK_DIR/<vm-name>.qcow2.
    - Snapshot operations use the domain's actual libvirt-managed storage.
    - Restore requires the VM to be fully shut off.
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

validate_snapshot_tag() {
    local tag="$1"

    if [[ ! "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
        error "Snapshot tag must be 1-128 characters using letters, numbers, dots, underscores, or hyphens."
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

check_libvirt() {
    require_commands || return 1

    if ! sudo -v; then
        error "Sudo authentication failed or was cancelled."
        return 1
    fi
    if ! sudo virsh list --all >/dev/null; then
        error "Could not connect to the system libvirt instance."
        return 1
    fi
}

vm_exists() {
    sudo virsh dominfo "$1" >/dev/null 2>&1
}

require_vm() {
    local name="$1"

    if ! vm_exists "$name"; then
        error "VM '$name' does not exist."
        return 1
    fi
}

snapshot_exists() {
    local vm_name="$1"
    local tag="$2"

    sudo virsh snapshot-info "$vm_name" "$tag" >/dev/null 2>&1
}

get_snapshot_names() {
    local vm_name="$1"
    local output_name="$2"
    local snapshot_output

    if ! snapshot_output=$(sudo virsh snapshot-list --name "$vm_name"); then
        error "Could not list snapshots for VM '$vm_name'."
        return 1
    fi
    printf -v "$output_name" '%s' "$snapshot_output"
}

get_domain_state() {
    local vm_name="$1"
    local output_name="$2"
    local domain_state

    if ! domain_state=$(LC_ALL=C sudo virsh domstate "$vm_name" 2>/dev/null); then
        error "Could not determine state for VM '$vm_name'."
        return 1
    fi
    printf -v "$output_name" '%s' "$domain_state"
}

show_storage_context() {
    local vm_name="$1"
    local expected_disk="$DISK_DIR/${vm_name}.qcow2"
    local block_output disk_sources source
    local expected_found=false

    if ! block_output=$(sudo virsh domblklist "$vm_name" --details 2>/dev/null); then
        error "Could not inspect storage attached to VM '$vm_name'."
        return 1
    fi

    disk_sources=$(printf '%s\n' "$block_output" | awk '$2 == "disk" && $4 != "-" { print $4 }')
    if [ -z "$disk_sources" ]; then
        error "VM '$vm_name' has no file-backed disk visible to libvirt."
        return 1
    fi

    info "VM storage managed by libvirt:"
    while IFS= read -r source; do
        [ -n "$source" ] || continue
        info "  $source"
        if [ "$source" = "$expected_disk" ]; then
            expected_found=true
        fi
    done <<< "$disk_sources"

    if [ "$expected_found" != true ]; then
        warn "Primary setup-vm path is not attached: $expected_disk"
        warn "Snapshot will follow the domain's actual libvirt storage shown above."
    fi
}

cmd_create() {
    local vm_name="${1:-}"
    local tag="${2:-}"
    local state

    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME create <vm-name> [tag]"
        return 2
    fi
    validate_vm_name "$vm_name" || return 1

    if [ -z "$tag" ]; then
        tag=$(date +'%Y-%m-%d-%H%M%S')
    fi
    validate_snapshot_tag "$tag" || return 1
    if [ "$tag" = "all" ]; then
        error "Snapshot tag 'all' is reserved by the delete command."
        return 1
    fi
    check_libvirt || return 1
    require_vm "$vm_name" || return 1
    if snapshot_exists "$vm_name" "$tag"; then
        error "Snapshot '$tag' already exists for VM '$vm_name'."
        return 1
    fi

    get_domain_state "$vm_name" state || return 1
    show_storage_context "$vm_name" || return 1
    info "VM state: $state"
    if [ "$state" != "shut off" ]; then
        warn "Creating a snapshot while the VM is '$state' may briefly pause guest I/O."
    fi

    info "Creating snapshot '$tag' for VM '$vm_name'..."
    if ! sudo virsh snapshot-create-as "$vm_name" "$tag" "Snapshot created by $SCRIPT_DISPLAY_NAME" --no-current; then
        error "Failed to create snapshot '$tag'."
        return 1
    fi
    info "Snapshot '$tag' created successfully."
}

cmd_list() {
    local vm_name="${1:-}"
    local snapshots

    if [ "$#" -ne 1 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME list <vm-name>"
        return 2
    fi
    validate_vm_name "$vm_name" || return 1
    check_libvirt || return 1
    require_vm "$vm_name" || return 1
    get_snapshot_names "$vm_name" snapshots || return 1

    info "Snapshots for VM '$vm_name':"
    if [ -z "$snapshots" ]; then
        info "  (none)"
        return 0
    fi

    while IFS= read -r snapshot_name; do
        [ -n "$snapshot_name" ] && info "  $snapshot_name"
    done <<< "$snapshots"
}

cmd_restore() {
    local vm_name="${1:-}"
    local tag="${2:-}"
    local state

    if [ "$#" -ne 2 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME restore <vm-name> <tag>"
        return 2
    fi
    validate_vm_name "$vm_name" || return 1
    validate_snapshot_tag "$tag" || return 1
    check_libvirt || return 1
    require_vm "$vm_name" || return 1
    if ! snapshot_exists "$vm_name" "$tag"; then
        error "Snapshot '$tag' not found for VM '$vm_name'."
        return 1
    fi
    get_domain_state "$vm_name" state || return 1
    if [ "$state" != "shut off" ]; then
        error "VM '$vm_name' must be fully shut off before restore; current state is '$state'."
        return 1
    fi

    show_storage_context "$vm_name" || return 1
    warn "Restore will replace the current VM state with snapshot '$tag'."
    if ! confirm_action "Restore VM '$vm_name' to '$tag'? (y/N): "; then
        info "Cancelled; the VM was not changed."
        return 0
    fi

    if ! sudo virsh snapshot-revert "$vm_name" "$tag"; then
        error "Failed to restore snapshot '$tag'."
        return 1
    fi
    info "VM '$vm_name' restored to snapshot '$tag'."
}

delete_all_snapshots() {
    local vm_name="$1"
    local snapshots snapshot_name
    local failures=0

    get_snapshot_names "$vm_name" snapshots || return 1
    if [ -z "$snapshots" ]; then
        info "No snapshots to delete."
        return 0
    fi

    warn "Every snapshot for VM '$vm_name' will be permanently deleted."
    if ! confirm_action "Delete all snapshots for '$vm_name'? (y/N): "; then
        info "Cancelled; no snapshots were deleted."
        return 0
    fi

    while IFS= read -r snapshot_name; do
        [ -n "$snapshot_name" ] || continue
        if sudo virsh snapshot-delete "$vm_name" "$snapshot_name"; then
            info "Deleted snapshot: $snapshot_name"
        else
            error "Failed to delete snapshot: $snapshot_name"
            failures=$((failures + 1))
        fi
    done <<< "$snapshots"

    if [ "$failures" -ne 0 ]; then
        error "$failures snapshot deletion(s) failed. Review the remaining snapshot list."
        return 1
    fi
    info "All snapshots deleted."
}

cmd_delete() {
    local vm_name="${1:-}"
    local tag="${2:-}"

    if [ "$#" -ne 2 ]; then
        error "Usage: $SCRIPT_DISPLAY_NAME delete <vm-name> <tag|all>"
        return 2
    fi
    validate_vm_name "$vm_name" || return 1
    validate_snapshot_tag "$tag" || return 1
    check_libvirt || return 1
    require_vm "$vm_name" || return 1

    if [ "$tag" = "all" ]; then
        delete_all_snapshots "$vm_name"
        return $?
    fi
    if ! snapshot_exists "$vm_name" "$tag"; then
        error "Snapshot '$tag' not found for VM '$vm_name'."
        return 1
    fi

    warn "Snapshot '$tag' for VM '$vm_name' will be permanently deleted."
    if ! confirm_action "Delete snapshot '$tag'? (y/N): "; then
        info "Cancelled; the snapshot was not deleted."
        return 0
    fi
    if ! sudo virsh snapshot-delete "$vm_name" "$tag"; then
        error "Failed to delete snapshot '$tag'."
        return 1
    fi
    info "Snapshot '$tag' deleted successfully."
}

main() {
    local command="${1:-help}"

    case $command in
        version|--version|-v)
            show_version
            return 0
            ;;
        help|--help|-h)
            show_help
            return 0
            ;;
        create|list|restore|delete)
            shift
            ;;
        *)
            error "Unknown command: $command"
            show_help >&2
            return 2
            ;;
    esac

    case $command in
        create) cmd_create "$@" ;;
        list) cmd_list "$@" ;;
        restore) cmd_restore "$@" ;;
        delete) cmd_delete "$@" ;;
    esac
}

main "$@"
