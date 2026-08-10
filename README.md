# KVM Toolkit

A robust, interactive Bash toolkit for managing KVM/QEMU virtual machines on Arch Linux.

Designed specifically to solve the common issues faced when installing security distributions (Kali, Parrot) in a virtual environment, this tool automates network configuration, dependency checks, and VM provisioning. It now includes a dedicated snapshot management utility for safe state preservation and restoration.

## Features

- **One-Command Provisioning**: Create VMs with a single command, automatically handling disk creation and OS installation.
- **Network Fix**: Automatically detects and resolves the "no network" issue common in Kali/Parrot installers by forcing the `rtl8139` network model.
- **Smart Dependency Checks**: Verifies `libvirtd`, `dnsmasq`, and network bridges are active before starting.
- **Snapshot Management**: Create, list, restore, and delete VM snapshots with automatic timestamp generation and safety checks.
- **Interactive and CLI Modes**: Fully interactive prompts with sensible defaults, or non-interactive flags for scripting (`--ram`, `--disk`, `--name`).
- **Lifecycle Management**: Built-in commands to list, destroy, and cleanup VMs and their associated disk images.
- **Safety First**: Prompts before overwriting existing VMs, deleting disk images, or restoring snapshots (requires VM shutdown).

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/ajbeaver/kvm-toolkit.git
cd kvm-toolkit
```

### 2. Deploy the Tools (Optional but Recommended)

To use `setup-vm` and `snapshot` from anywhere in your terminal without typing the full path:

```bash
# Move the scripts to your system PATH
sudo cp setup-vm.sh /usr/local/bin/setup-vm
sudo cp snapshot.sh /usr/local/bin/snapshot
sudo chmod +x /usr/local/bin/setup-vm /usr/local/bin/snapshot
```

*Alternatively, if you have the `deploy.sh` utility from your arch-utilities collection, you can use:*

```bash
./deploy.sh setup-vm
./deploy.sh snapshot
```

## Usage

### Quick Start (Interactive)

The `setup-vm` script will prompt you for the ISO filename, VM name, RAM, and disk size.

```bash
# Ensure your ISO is in ~/Documents/ISOs/
setup-vm create kali-linux-2024.1-installer-amd64.iso
```

### Managing Snapshots

**Create a snapshot** (auto-generates a timestamp tag):
```bash
snapshot create MyKali
# Output: Creating snapshot '2026-08-10-1430' for VM 'MyKali'...
```

**Create a snapshot with a custom tag**:
```bash
snapshot create MyKali before-update
```

**List all snapshots**:
```bash
snapshot list MyKali
```

**Restore a snapshot**:
*Note: The VM must be shut down before restoring.*
```bash
snapshot restore MyKali before-update
```

**Delete a snapshot**:
```bash
snapshot delete MyKali before-update
# Or delete all snapshots
snapshot delete MyKali all
```

### Managing VMs

List all virtual machines:
```bash
setup-vm list
```

Stop and remove a specific VM (undefine):
```bash
setup-vm destroy MyKali
```

Stop, remove, and delete the disk image:
```bash
setup-vm cleanup MyKali
```

## Command Reference

### `setup-vm` Commands

| Command | Description |
| :--- | :--- |
| `create [ISO]` | Create a new VM. Prompts for details if flags are omitted. |
| `list` | Show running and stopped VMs. |
| `destroy <name>` | Stop and undefine a VM (keeps disk). |
| `cleanup <name>` | Stop, undefine, and delete the disk image. |
| `--help` | Show usage information. |
| `--version` | Show script version. |

**Options for `create`**:
- `--ram <GB>`: Set RAM in GB (Default: 4).
- `--disk <GB>`: Set Disk Size in GB (Default: 40).
- `--name <name>`: Set VM Name (Default: Auto-generated or Prompt).
- `--network <model>`: Network Model (Default: `rtl8139` for compatibility).

### `snapshot` Commands

| Command | Description |
| :--- | :--- |
| `create <vm> [tag]` | Create a new snapshot. Generates timestamp if tag is omitted. |
| `list <vm>` | List all snapshots for a specific VM. |
| `restore <vm> <tag>` | Restore a VM to a specific snapshot (VM must be off). |
| `delete <vm> <tag>` | Delete a snapshot. Use `all` to remove all snapshots. |
| `--help` | Show usage information. |
| `--version` | Show script version. |

## Troubleshooting

### Network Issues
If the VM installer cannot connect to the internet, this tool automatically applies the `rtl8139` network model, which is the most compatible driver for minimal installer kernels. If issues persist, ensure the host `default` network is active:

```bash
sudo virsh net-start default
```

See `docs/network-fix.md` for a detailed explanation of the Arch Linux libvirt network configuration issue.

### Snapshot Failures
- **"VM is running"**: You must shut down the VM before restoring a snapshot.
- **"Snapshot not found"**: Verify the tag name using `snapshot list <vm_name>`.
- **"Permission denied"**: Ensure your user is in the `libvirt` group or use `sudo` if running directly.

## Requirements

- **OS**: Arch Linux (or derivatives like Manjaro)
- **Packages**: `libvirt`, `qemu`, `dnsmasq`, `bridge-utils`
- **Permissions**: `sudo` access for `virt-install`, `virsh`, and network management
- **Group**: User should be in the `libvirt` group for non-sudo `virsh` operations (though this toolkit enforces `sudo` for safety).

## License

MIT License. See `LICENSE` for details.
