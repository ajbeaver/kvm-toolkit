# KVM Toolkit

A robust, interactive Bash toolkit for managing KVM/QEMU virtual machines on Arch Linux.

Designed specifically to solve the common issues faced when installing security distributions (Kali, Parrot) in a virtual environment, this tool automates network configuration, dependency checks, and VM provisioning.

## Features

- **One-Command Provisioning**: Create VMs with a single command, automatically handling disk creation and OS installation.
- **Network Fix**: Automatically detects and resolves the "no network" issue common in Kali/Parrot installers by forcing the `rtl8139` network model.
- **Smart Dependency Checks**: Verifies `libvirtd`, `dnsmasq`, and network bridges are active before starting.
- **Interactive and CLI Modes**: Fully interactive prompts with sensible defaults, or non-interactive flags for scripting (`--ram`, `--disk`, `--name`).
- **Lifecycle Management**: Built-in commands to list, destroy, and cleanup VMs and their associated disk images.
- **Safety First**: Prompts before overwriting existing VMs or deleting disk images.

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/kvm-toolkit.git
cd kvm-toolkit
```

### 2. Deploy the Tool (Optional but Recommended)

To use `setup-vm` from anywhere in your terminal without typing the full path:

```bash
# Move the script to your system PATH
sudo cp setup-vm.sh /usr/local/bin/setup-vm
sudo chmod +x /usr/local/bin/setup-vm
```

*Alternatively, if you have the `deploy.sh` utility from my arch-utilities, you can use:*

```bash
./deploy.sh setup-vm
```

## Usage

### Quick Start (Interactive)

The script will prompt you for the ISO filename, VM name, RAM, and disk size.

```bash
# Ensure your ISO is in ~/Documents/ISOs/
setup-vm create kali-linux-2024.1-installer-amd64.iso
```

### Non-Interactive Mode (CLI)

Provide all arguments to skip prompts entirely.

```bash
setup-vm create --ram 8 --disk 100 --name "MyKali" kali-linux-2024.1-installer-amd64.iso
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

| Command | Description |
| :--- | :--- |
| `create [ISO]` | Create a new VM. Prompts for details if flags are omitted. |
| `list` | Show running and stopped VMs. |
| `destroy <name>` | Stop and undefine a VM (keeps disk). |
| `cleanup <name>` | Stop, undefine, and delete the disk image. |
| `--help` | Show usage information. |
| `--version` | Show script version. |

### Options for `create`

- `--ram <GB>`: Set RAM in GB (Default: 4).
- `--disk <GB>`: Set Disk Size in GB (Default: 40).
- `--name <name>`: Set VM Name (Default: Auto-generated or Prompt).
- `--network <model>`: Network Model (Default: `rtl8139` for compatibility).

## Troubleshooting

### Network Issues
If the VM installer cannot connect to the internet, this tool automatically applies the `rtl8139` network model, which is the most compatible driver for minimal installer kernels. If issues persist, ensure the host `default` network is active:

```bash
sudo virsh net-start default
```

See `docs/network-fix.md` for a detailed explanation of the Arch Linux libvirt network configuration issue.

## Requirements

- **OS**: Arch Linux (or derivatives like Manjaro)
- **Packages**: `libvirt`, `qemu`, `dnsmasq`, `bridge-utils`
- **Permissions**: `sudo` access for `virt-install` and network management

## License

MIT License. See `LICENSE` for details.
