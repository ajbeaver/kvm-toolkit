# KVM Toolkit

A small, safety-minded toolkit for provisioning, operating, and snapshotting KVM/QEMU virtual machines through the system libvirt instance.

## Tools

| Tool | Version | Responsibility | Guide |
| :--- | :---: | :--- | :--- |
| `setup-vm` | 3.0.0 | Configure a VM, create its disk, and launch OS installation. | [Setup guide](docs/setup-vm.md) |
| `vmgr` | 1.0.0 | Inspect, launch, stop, access, and safely remove VMs. | [Management guide](docs/vmgr.md) |
| `snapshot` | 1.1.0 | Create, list, restore, and delete libvirt snapshots. | [Snapshot guide](docs/snapshot.md) |

```text
setup-vm   provision
vmgr       operate and maintain
snapshot   preserve and restore state
```

## Quick Start

Clone the repository:

```bash
git clone https://github.com/ajbeaver/kvm-toolkit.git
cd kvm-toolkit
```

The repository scripts are intentionally non-executable. Install them with the `deploy` utility:

```bash
deploy setup-vm --src .
deploy vmgr --src .
deploy snapshot --src .
```

Or install them directly:

```bash
sudo install -m 0755 setup-vm.sh /usr/local/bin/setup-vm
sudo install -m 0755 vmgr.sh /usr/local/bin/vmgr
sudo install -m 0755 snapshot.sh /usr/local/bin/snapshot
```

## Typical Workflow

```bash
# Create and install a VM
setup-vm create <iso-name> --name <vm-name>

# Start it later and open the graphical console
vmgr launch <vm-name>

# Preserve state before a risky change
snapshot create <vm-name> before-update

# Shut down and restore if needed
vmgr shutdown <vm-name> --wait 60
snapshot restore <vm-name> before-update
```

Relative ISO names are read from `~/Documents/ISOs`. Absolute ISO paths are also accepted.

## Requirements

- Bash 4.3 or newer
- `sudo`
- A working system libvirt/QEMU installation
- `virsh`, `qemu-img`, and `virt-install`
- `virt-viewer` for `vmgr launch` and `vmgr view`
- Host virtualization support and sufficient access to `/var/lib/libvirt/images`

The commands authenticate sudo internally for system libvirt operations. Run the installed tools normally; do not prefix graphical commands with sudo.

## Safety Model

- Help, version, and local argument validation run before sudo/libvirt checks.
- VM and snapshot names use strict, predictable character sets.
- Destructive operations require explicit confirmation.
- Snapshot restore requires a fully shut-down VM.
- VM removal follows actual libvirt storage and refuses snapshots, shared disks, external paths, or ambiguous metadata.
- Source scripts remain non-executable; deployed commands receive executable permissions.

## Documentation

- [Provisioning with setup-vm](docs/setup-vm.md)
- [Operating VMs with vmgr](docs/vmgr.md)
- [Managing snapshots](docs/snapshot.md)
- [Network compatibility and troubleshooting](docs/network-fix.md)

## License

Licensed under the MIT License. See [LICENSE](LICENSE).
