#!/bin/bash
# setup-vm - KVM/QEMU Virtual Machine Installer
# Version: 3.0.0
# Usage: setup-vm [command] [options]

VERSION="3.0.0"
ISO_DIR="$HOME/Documents/ISOs"
DISK_DIR="/var/lib/libvirt/images"
DEFAULT_RAM_GB=4
DEFAULT_DISK_GB=40
DEFAULT_NETWORK_MODEL="rtl8139"
DEFAULT_VNC_LISTEN="127.0.0.1"
DEFAULT_OS_VARIANT="debian12"
DEFAULT_VCPUS=2

SCRIPT_NAME=$(basename "$0")
SCRIPT_DISPLAY_NAME="${SCRIPT_NAME%.sh}"

info() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
error() { printf 'Error: %s\n' "$*" >&2; }

show_help() {
    cat << EOF
$SCRIPT_DISPLAY_NAME version $VERSION - KVM/QEMU VM installer

USAGE:
    $SCRIPT_DISPLAY_NAME <command> [options]

COMMANDS:
    create [ISO]          Configure and install a VM from an ISO
    version               Show version information
    help                  Show this help message

CREATE OPTIONS:
    --ram <GB>            RAM in GB (default: $DEFAULT_RAM_GB)
    --disk <GB>           Disk size in GB (default: $DEFAULT_DISK_GB)
    --name <name>         VM name (default: prompted, then Kali-VM)
    --network <model>     Network model (default: $DEFAULT_NETWORK_MODEL)
    --vnc-listen <addr>   VNC listen address (default: $DEFAULT_VNC_LISTEN)

EXAMPLES:
    $SCRIPT_DISPLAY_NAME create <iso-name>
    $SCRIPT_DISPLAY_NAME create <iso-name> --ram 8 --disk 100 --name <vm-name>
    $SCRIPT_DISPLAY_NAME create /absolute/path/to/<iso-name>

NOTES:
    - Relative ISO names are resolved beneath $ISO_DIR.
    - The compatibility profile remains: $DEFAULT_VCPUS vCPUs, $DEFAULT_NETWORK_MODEL networking,
      and OS variant $DEFAULT_OS_VARIANT.
    - VNC is local-only by default. Use --vnc-listen 0.0.0.0 only on a trusted network.
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

require_value() {
    local option="$1"
    local count="$2"
    local value="${3:-}"

    if [ "$count" -lt 2 ] || [ -z "$value" ] || [[ "$value" == --* ]]; then
        error "$option requires a value."
        return 1
    fi
}

validate_positive_integer() {
    local label="$1"
    local value="$2"
    local minimum="$3"
    local maximum="$4"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        error "$label must be a whole number."
        return 1
    fi

    value=$((10#$value))
    if [ "$value" -lt "$minimum" ] || [ "$value" -gt "$maximum" ]; then
        error "$label must be between $minimum and $maximum."
        return 1
    fi
}

validate_vm_name() {
    local name="$1"

    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]]; then
        error "VM name must be 1-63 characters using letters, numbers, dots, underscores, or hyphens."
        return 1
    fi
}

validate_network_model() {
    local model="$1"

    if [[ ! "$model" =~ ^[A-Za-z0-9_-]+$ ]]; then
        error "Network model contains unsupported characters."
        return 1
    fi
}

validate_vnc_listen() {
    local address="$1"

    if [[ ! "$address" =~ ^[A-Za-z0-9:._-]+$ ]]; then
        error "VNC listen address contains unsupported characters."
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

require_create_commands() {
    local command_name
    local missing=()

    for command_name in qemu-img virt-install; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing+=("$command_name")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing VM creation command(s): ${missing[*]}"
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
        error "Confirm that libvirt/QEMU is installed and its daemon or socket is available."
        return 1
    fi
}

ensure_network() {
    local network_xml=""
    local network_info

    info "Checking default network..."
    if ! network_info=$(LC_ALL=C sudo virsh net-info default 2>/dev/null); then
        info "Defining default NAT network..."
        network_xml=$(mktemp) || {
            error "Could not create a temporary network definition."
            return 1
        }
        cat > "$network_xml" <<'EOF'
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
        if ! sudo virsh net-define "$network_xml"; then
            rm -f -- "$network_xml"
            error "Could not define the default libvirt network."
            return 1
        fi
        rm -f -- "$network_xml"
        network_info=$(LC_ALL=C sudo virsh net-info default 2>/dev/null) || {
            error "The default network was defined but could not be queried."
            return 1
        }
    fi

    if ! printf '%s\n' "$network_info" | awk '$1 == "Active:" && $2 == "yes" { found=1 } END { exit !found }'; then
        info "Starting default network..."
        if ! sudo virsh net-start default; then
            error "Could not start the default libvirt network."
            return 1
        fi
    fi

    if ! sudo virsh net-autostart default >/dev/null; then
        error "Could not enable autostart for the default network."
        return 1
    fi

    info "Default network is active."
}

domain_exists() {
    sudo virsh dominfo "$1" >/dev/null 2>&1
}

domain_is_running() {
    local state
    state=$(LC_ALL=C sudo virsh domstate "$1" 2>/dev/null) || return 1
    [[ "$state" == "running" || "$state" == "paused" || "$state" == "pmsuspended" ]]
}

stop_and_undefine_domain() {
    local name="$1"

    if domain_is_running "$name"; then
        info "Stopping VM '$name'..."
        if ! sudo virsh destroy "$name"; then
            error "Could not stop VM '$name'."
            return 1
        fi
    fi

    info "Undefining VM '$name'..."
    if ! sudo virsh undefine "$name"; then
        error "Could not undefine VM '$name'. It may have snapshots, managed-save data, or NVRAM."
        return 1
    fi
}

resolve_iso_path() {
    local iso="$1"
    local output_name="$2"
    local resolved

    if [[ "$iso" = /* ]]; then
        resolved="$iso"
    else
        resolved="$ISO_DIR/$iso"
    fi
    printf -v "$output_name" '%s' "$resolved"
}

cmd_create() {
    local iso_arg=""
    local ram_arg=""
    local disk_arg=""
    local name_arg=""
    local net_model="$DEFAULT_NETWORK_MODEL"
    local vnc_listen="$DEFAULT_VNC_LISTEN"
    local ram_input disk_input iso_path disk_path ram_mb
    local iso_seen=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ram|--disk|--name|--network|--vnc-listen)
                require_value "$1" "$#" "${2:-}" || return 2
                case $1 in
                    --ram) ram_arg="$2" ;;
                    --disk) disk_arg="$2" ;;
                    --name) name_arg="$2" ;;
                    --network) net_model="$2" ;;
                    --vnc-listen) vnc_listen="$2" ;;
                esac
                shift 2
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            --*)
                error "Unknown create option: $1"
                return 2
                ;;
            *)
                if [ "$iso_seen" = true ]; then
                    error "Only one ISO argument may be provided."
                    return 2
                fi
                iso_arg="$1"
                iso_seen=true
                shift
                ;;
        esac
    done

    if [ -z "$iso_arg" ]; then
        info "ISO file not provided."
        prompt_value "Enter ISO filename in $ISO_DIR: " iso_arg || return 1
    fi
    if [ -z "$iso_arg" ]; then
        error "ISO filename cannot be empty."
        return 1
    fi
    resolve_iso_path "$iso_arg" iso_path
    if [ ! -f "$iso_path" ] || [ ! -r "$iso_path" ]; then
        error "ISO not found or unreadable: $iso_path"
        return 1
    fi

    if [ -z "$name_arg" ]; then
        prompt_value "Enter VM name (default: Kali-VM): " name_arg || return 1
        name_arg="${name_arg:-Kali-VM}"
    fi
    validate_vm_name "$name_arg" || return 1

    if [ -z "$ram_arg" ]; then
        prompt_value "Enter RAM in GB (default: $DEFAULT_RAM_GB): " ram_input || return 1
        ram_arg="${ram_input:-$DEFAULT_RAM_GB}"
    fi
    validate_positive_integer "RAM" "$ram_arg" 1 512 || return 1
    ram_arg=$((10#$ram_arg))

    if [ -z "$disk_arg" ]; then
        prompt_value "Enter disk size in GB (default: $DEFAULT_DISK_GB): " disk_input || return 1
        disk_arg="${disk_input:-$DEFAULT_DISK_GB}"
    fi
    validate_positive_integer "Disk size" "$disk_arg" 1 16384 || return 1
    disk_arg=$((10#$disk_arg))

    validate_network_model "$net_model" || return 1
    validate_vnc_listen "$vnc_listen" || return 1
    ram_mb=$((ram_arg * 1024))
    disk_path="$DISK_DIR/${name_arg}.qcow2"

    check_libvirt || return 1
    require_create_commands || return 1
    ensure_network || return 1

    info ""
    info "=== VM Installation Plan ==="
    info "Name:       $name_arg"
    info "ISO:        $iso_path"
    info "RAM:        ${ram_arg}GB (${ram_mb}MB)"
    info "vCPUs:      $DEFAULT_VCPUS"
    info "Disk:       $disk_path (${disk_arg}GB)"
    info "Network:    default ($net_model)"
    info "VNC listen: $vnc_listen"
    info "OS variant: $DEFAULT_OS_VARIANT"
    info "============================"

    if [ "$vnc_listen" = "0.0.0.0" ] || [ "$vnc_listen" = "::" ]; then
        warn "VNC will listen on all interfaces. Confirm firewall and authentication settings."
    fi

    if domain_exists "$name_arg"; then
        warn "VM '$name_arg' already exists."
        if ! confirm_action "Replace its definition and expected disk $disk_path? (y/N): "; then
            info "Cancelled; the existing VM was not changed."
            return 0
        fi
        stop_and_undefine_domain "$name_arg" || return 1
        if [ -e "$disk_path" ]; then
            if ! sudo rm -f -- "$disk_path"; then
                error "Could not remove existing disk: $disk_path"
                return 1
            fi
        fi
    elif [ -e "$disk_path" ]; then
        error "Disk already exists without a matching VM: $disk_path"
        error "Move or remove it explicitly before retrying; it will not be overwritten."
        return 1
    else
        if ! confirm_action "Create this VM? (y/N): "; then
            info "Cancelled; no VM or disk was created."
            return 0
        fi
    fi

    info "Creating disk image..."
    if ! sudo qemu-img create -f qcow2 "$disk_path" "${disk_arg}G"; then
        error "Disk creation failed: $disk_path"
        return 1
    fi

    info "Starting OS installation..."
    if ! sudo virt-install \
        --name "$name_arg" \
        --memory "$ram_mb" \
        --vcpus "$DEFAULT_VCPUS" \
        --disk path="$disk_path",size="$disk_arg",format=qcow2 \
        --cdrom "$iso_path" \
        --network network=default,model="$net_model" \
        --graphics vnc,listen="$vnc_listen" \
        --os-variant="$DEFAULT_OS_VARIANT" \
        --boot cdrom,hd; then
        error "virt-install failed. The disk remains at $disk_path for inspection or manual cleanup."
        return 1
    fi

    info "Installation started. View the VM in virt-manager or through its local VNC console."
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
        create)
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
    esac
}

main "$@"
