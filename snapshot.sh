#!/bin/bash

# snapshot.sh - KVM Snapshot Management Utility
# Part of the Arch Linux KVM Toolkit

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0" .sh)

# Colors for output (disabled for strict no-emoji/plain text requirement, using bold/standard)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [options]

KVM Snapshot Management Utility for Arch Linux.

Commands:
    create <vm_name> [tag]    Create a new snapshot. If tag is omitted, a timestamp is generated.
    list <vm_name>            List all snapshots for a specific VM.
    restore <vm_name> [tag]   Restore a VM to a specific snapshot.
    delete <vm_name> [tag]    Delete a snapshot. Use 'all' to remove all snapshots.

Options:
    --help, -h                Show this help message.
    --version, -v             Show version information.

Examples:
    $SCRIPT_NAME create my-vm
    $SCRIPT_NAME create my-vm before-update
    $SCRIPT_NAME list my-vm
    $SCRIPT_NAME restore my-vm before-update
    $SCRIPT_NAME delete my-vm before-update
    $SCRIPT_NAME delete my-vm all

EOF
}

show_version() {
    echo "$SCRIPT_NAME version $VERSION"
}

# Helper function to print errors
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Helper function to print warnings
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Helper function to print success
info() {
    echo -e "${GREEN}$1${NC}"
}

# Check if a VM exists
check_vm_exists() {
    local vm_name="$1"
    if ! sudo virsh dominfo "$vm_name" > /dev/null 2>&1; then
        error "VM '$vm_name' does not exist."
    fi
}

# Check if a snapshot exists
check_snapshot_exists() {
    local vm_name="$1"
    local tag="$2"
    
    # Get list of snapshot names
    local snapshots
    snapshots=$(sudo virsh snapshot-list --name "$vm_name" 2>/dev/null)
    
    if echo "$snapshots" | grep -q "^${tag}$"; then
        return 0
    else
        return 1
    fi
}

cmd_create() {
    local vm_name="$1"
    local tag="$2"

    if [ -z "$vm_name" ]; then
        error "VM name is required. Usage: $SCRIPT_NAME create <vm_name> [tag]"
    fi

    check_vm_exists "$vm_name"

    if [ -z "$tag" ]; then
        # Generate timestamp tag: YYYY-MM-DD-HHMM
        tag=$(date +"%Y-%m-%d-%H%M")
    fi

    # Check if snapshot already exists to avoid conflicts
    if check_snapshot_exists "$vm_name" "$tag"; then
        error "Snapshot '$tag' already exists for VM '$vm_name'. Please choose a different tag."
    fi

    info "Creating snapshot '$tag' for VM '$vm_name'..."
    
    # Create the snapshot
    # Note: --no-metadata is often safer for scripts to avoid cluttering libvirt metadata if not needed,
    # but standard create-as usually works fine. We use standard flags.
    if sudo virsh snapshot-create-as "$vm_name" "$tag" "Snapshot created by $SCRIPT_NAME" --no-current; then
        info "Snapshot '$tag' created successfully."
    else
        error "Failed to create snapshot."
    fi
}

cmd_list() {
    local vm_name="$1"

    if [ -z "$vm_name" ]; then
        error "VM name is required. Usage: $SCRIPT_NAME list <vm_name>"
    fi

    check_vm_exists "$vm_name"

    echo "Snapshots for VM: $vm_name"
    echo "----------------------------------------"
    
    # Use --name to get just the list, then format
    local snapshots
    snapshots=$(sudo virsh snapshot-list --name "$vm_name" 2>/dev/null)
    
    if [ -z "$snapshots" ]; then
        echo "No snapshots found."
    else
        echo "$snapshots" | while read -r snap; do
            if [ -n "$snap" ]; then
                echo "- $snap"
            fi
        done
    fi
}

cmd_restore() {
    local vm_name="$1"
    local tag="$2"

    if [ -z "$vm_name" ]; then
        error "VM name is required. Usage: $SCRIPT_NAME restore <vm_name> [tag]"
    fi

    check_vm_exists "$vm_name"

    if [ -z "$tag" ]; then
        error "Snapshot tag is required for restore. Usage: $SCRIPT_NAME restore <vm_name> <tag>"
    fi

    if ! check_snapshot_exists "$vm_name" "$tag"; then
        error "Snapshot '$tag' not found for VM '$vm_name'."
    fi

    # Check if VM is running
    local state
    state=$(sudo virsh domstate "$vm_name" 2>/dev/null)
    
    if [ "$state" = "running" ]; then
        error "VM '$vm_name' is currently running. You must shut it down before restoring a snapshot."
    fi

    warn "Restoring VM '$vm_name' to snapshot '$tag'..."
    warn "This operation cannot be undone."
    
    if sudo virsh snapshot-revert "$vm_name" "$tag"; then
        info "VM '$vm_name' restored to snapshot '$tag'."
    else
        error "Failed to restore snapshot."
    fi
}

cmd_delete() {
    local vm_name="$1"
    local tag="$2"

    if [ -z "$vm_name" ]; then
        error "VM name is required. Usage: $SCRIPT_NAME delete <vm_name> <tag>"
    fi

    check_vm_exists "$vm_name"

    if [ -z "$tag" ]; then
        error "Snapshot tag is required. Use 'all' to delete all snapshots. Usage: $SCRIPT_NAME delete <vm_name> <tag>"
    fi

    if [ "$tag" = "all" ]; then
        local snapshots
        snapshots=$(sudo virsh snapshot-list --name "$vm_name" 2>/dev/null)
        
        if [ -z "$snapshots" ]; then
            info "No snapshots to delete."
            return 0
        fi

        warn "Deleting ALL snapshots for VM '$vm_name'..."
        echo "$snapshots" | while read -r snap; do
            if [ -n "$snap" ]; then
                if sudo virsh snapshot-delete "$vm_name" "$snap"; then
                    info "Deleted snapshot: $snap"
                else
                    error "Failed to delete snapshot: $snap"
                fi
            fi
        done
        info "All snapshots deleted."
    else
        if ! check_snapshot_exists "$vm_name" "$tag"; then
            error "Snapshot '$tag' not found for VM '$vm_name'."
        fi

        warn "Deleting snapshot '$tag' for VM '$vm_name'..."
        if sudo virsh snapshot-delete "$vm_name" "$tag"; then
            info "Snapshot '$tag' deleted successfully."
        else
            error "Failed to delete snapshot."
        fi
    fi
}

# Main execution logic
main() {
    # Handle flags first
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_help
        exit 0
    fi

    if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
        show_version
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        create)
            cmd_create "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        "")
            error "No command specified. Use --help for usage."
            ;;
        *)
            error "Unknown command: $command. Use --help for usage."
            ;;
    esac
}

# Run main function with all arguments
main "$@"
