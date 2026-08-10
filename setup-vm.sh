#!/bin/bash
# setup-vm - KVM/QEMU Virtual Machine Manager & Installer
# Version: 2.0.1
# Usage: setup-vm [command] [options]

VERSION="2.0.1"
SRC_DIR="$HOME/Documents/Source"
ISO_DIR="$HOME/Documents/ISOs"
DISK_DIR="/var/lib/libvirt/images"

# Extract the clean script name (e.g., "setup-vm" or "setup-vm.sh")
# Then strip the .sh extension if present for a clean display name
SCRIPT_NAME=$(basename "$0")
SCRIPT_DISPLAY_NAME="${SCRIPT_NAME%.sh}"

# --- Helper Functions ---

show_help() {
    cat << EOF
$SCRIPT_DISPLAY_NAME v$VERSION - KVM VM Manager

USAGE:
    $SCRIPT_DISPLAY_NAME [command] [options]

COMMANDS:
    create [ISO]          Create a new VM from an ISO (Interactive prompts for RAM/Disk)
    list                  List all VMs (Running and Stopped)
    destroy <name>        Stop and remove a VM (undefine)
    cleanup <name>        Stop, remove, and delete disk for a VM
    version               Show version information
    help                  Show this help message

OPTIONS:
    --ram <GB>            Set RAM in GB (Default: 4)
    --disk <GB>           Set Disk Size in GB (Default: 40)
    --name <name>         Set VM Name (Default: Auto-generated or Prompt)
    --network <model>     Network Model (Default: rtl8139 for Kali/Parrot compatibility)

EXAMPLES:
    $SCRIPT_DISPLAY_NAME create kali-2024.iso
    $SCRIPT_DISPLAY_NAME create kali-2024.iso --ram 8 --disk 100 --name "MyKali"
    $SCRIPT_DISPLAY_NAME list
    $SCRIPT_DISPLAY_NAME destroy MyKali
    $SCRIPT_DISPLAY_NAME cleanup MyKali
EOF
}

show_version() {
    echo "$SCRIPT_DISPLAY_NAME version $VERSION"
}

# Check if libvirtd is running
check_libvirt() {
    if ! systemctl is-active --quiet libvirtd; then
        echo "Error: libvirtd service is not running."
        echo "Run: sudo systemctl start libvirtd"
        exit 1
    fi
}

# Ensure default network is active
ensure_network() {
    echo "Checking network..."
    if ! sudo virsh net-list --all | grep -q "default"; then
        echo "Creating default network..."
        sudo tee /etc/libvirt/networks/default.xml > /dev/null <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
        sudo virsh net-define /etc/libvirt/networks/default.xml
    fi

    if ! sudo virsh net-list --active | grep -q "default"; then
        echo "Starting default network..."
        sudo virsh net-start default
        sudo virsh net-autostart default
    fi
    echo "Network is active."
}

# --- Commands ---

cmd_create() {
    local iso_arg=""
    local ram_arg=""      # Start empty to detect if passed
    local disk_arg=""     # Start empty to detect if passed
    local name_arg=""
    local net_model="rtl8139"

    # 1. Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ram) ram_arg="$2"; shift 2 ;;
            --disk) disk_arg="$2"; shift 2 ;;
            --name) name_arg="$2"; shift 2 ;;
            --network) net_model="$2"; shift 2 ;;
            *) iso_arg="$1"; shift ;;
        esac
    done

    # 2. Interactive Prompts ONLY if not provided

    # ISO
    if [ -z "$iso_arg" ]; then
        echo "ISO File not provided."
        read -p "Enter ISO filename (e.g., kali-2024.iso) in $ISO_DIR: " iso_arg
    fi

    local iso_path="$ISO_DIR/$iso_arg"
    if [ ! -f "$iso_path" ]; then
        echo "Error: ISO not found at $iso_path"
        exit 1
    fi

    # Name
    if [ -z "$name_arg" ]; then
        read -p "Enter VM Name (Default: Kali-VM): " name_arg
        name_arg="${name_arg:-Kali-VM}"
    fi

    # RAM
    if [ -z "$ram_arg" ]; then
        read -p "Enter RAM in GB (Default: 4): " ram_input
        ram_arg="${ram_input:-4}"
    fi

    # Disk
    if [ -z "$disk_arg" ]; then
        read -p "Enter Disk Size in GB (Default: 40): " disk_input
        disk_arg="${disk_input:-40}"
    fi

    # Convert RAM to MB
    local ram_mb=$((ram_arg * 1024))

    local disk_path="$DISK_DIR/${name_arg}.qcow2"

    # Check if VM exists
    if sudo virsh dominfo "$name_arg" &>/dev/null; then
        echo "Error: VM '$name_arg' already exists."
        read -p "Do you want to overwrite it? (y/n): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
        sudo virsh destroy "$name_arg"
        sudo virsh undefine "$name_arg"
        sudo rm -f "$disk_path"
    fi

    echo "Deploying $name_arg with ${ram_mb}MB RAM and ${disk_arg}GB Disk..."
    
    ensure_network

    # Create Disk
    echo "Creating disk image..."
    sudo qemu-img create -f qcow2 "$disk_path" "${disk_arg}G"

    # Create VM
    echo "Installing OS..."
    sudo virt-install \
        --name "$name_arg" \
        --memory "$ram_mb" \
        --vcpus 2 \
        --disk path="$disk_path",size="$disk_arg",format=qcow2 \
        --cdrom "$iso_path" \
        --network network=default,model="$net_model" \
        --graphics vnc,listen=0.0.0.0 \
        --os-variant=debian12 \
        --boot cdrom,hd

    echo "Installation started! View in virt-manager or VNC."
    echo "To start later: sudo virsh start $name_arg"
}

cmd_list() {
    echo "Active VMs:"
    sudo virsh list
    echo -e "\nAll VMs (including stopped):"
    sudo virsh list --all
}

cmd_destroy() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: VM name required."
        echo "Usage: $SCRIPT_DISPLAY_NAME destroy <vm_name>"
        exit 1
    fi

    if ! sudo virsh dominfo "$name" &>/dev/null; then
        echo "Error: VM '$name' not found."
        exit 1
    fi

    read -p "Are you sure you want to stop and undefine '$name'? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    sudo virsh destroy "$name" 2>/dev/null
    sudo virsh undefine "$name"
    echo "VM '$name' has been destroyed and undefined."
}

cmd_cleanup() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: VM name required."
        exit 1
    fi

    if ! sudo virsh dominfo "$name" &>/dev/null; then
        echo "Error: VM '$name' not found."
        exit 1
    fi

    read -p "Are you sure you want to destroy, undefine, AND DELETE the disk of '$name'? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    sudo virsh destroy "$name" 2>/dev/null
    sudo virsh undefine "$name"
    sudo rm -f "$DISK_DIR/${name}.qcow2"
    echo "VM '$name' and its disk have been completely removed."
}

# --- Main Entry Point ---

check_libvirt

case "${1:-help}" in
    create)
        shift
        cmd_create "$@"
        ;;
    list)
        cmd_list
        ;;
    destroy)
        shift
        cmd_destroy "$@"
        ;;
    cleanup)
        shift
        cmd_cleanup "$@"
        ;;
    version|--version)
        show_version
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
