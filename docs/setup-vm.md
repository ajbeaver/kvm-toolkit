# setup-vm

Current version: **3.0.0**

`setup-vm` provisions a KVM/QEMU virtual machine and starts its OS installer. Daily lifecycle management belongs to [`vmgr`](vmgr.md), while state preservation belongs to [`snapshot`](snapshot.md).

## Responsibility

`setup-vm` performs this workflow:

```text
validate inputs
    → authenticate sudo and connect to system libvirt
    → verify or define the default NAT network
    → show the installation plan
    → create a qcow2 disk
    → invoke virt-install
```

It exposes only three commands:

```text
setup-vm create
setup-vm version
setup-vm help
```

## Requirements

- `sudo`, `virsh`, `qemu-img`, and `virt-install`
- A working system libvirt/QEMU installation
- A readable installation ISO
- Sufficient storage beneath `/var/lib/libvirt/images`

## Usage

```text
setup-vm create [ISO] [OPTIONS]
```

Examples:

```bash
setup-vm create <iso-name>
setup-vm create <iso-name> --ram 8 --disk 100 --name <vm-name>
setup-vm create /absolute/path/to/<iso-name>
```

When the ISO argument is relative, it is resolved beneath:

```text
~/Documents/ISOs
```

When arguments are omitted, setup-vm prompts for the ISO, VM name, RAM, and disk size.

## Create Options

| Option | Default | Description |
| :--- | :---: | :--- |
| `--ram <GB>` | `4` | Guest RAM in whole gigabytes, from 1 through 512. |
| `--disk <GB>` | `40` | Primary disk size in whole gigabytes, from 1 through 16384. |
| `--name <vm-name>` | `Kali-VM` | Libvirt domain and disk basename. |
| `--network <model>` | `rtl8139` | Guest network adapter model. |
| `--vnc-listen <address>` | `127.0.0.1` | VNC listen address. |

VM names may contain letters, numbers, dots, underscores, and hyphens. They must begin with a letter or number and may be at most 63 characters.

## Compatibility Profile

The working default installation profile is intentionally conservative:

| Setting | Value |
| :--- | :--- |
| vCPUs | `2` |
| Disk format | `qcow2` |
| Network | libvirt `default` NAT network |
| Network model | `rtl8139` |
| OS variant | `debian12` |
| Boot order | CD-ROM, then disk |
| Graphics | VNC on `127.0.0.1` |

`rtl8139` is retained for compatibility with minimal Kali and Parrot installer environments. See [network-fix.md](network-fix.md) for details.

To expose VNC beyond localhost, it must be requested explicitly:

```bash
setup-vm create <iso-name> --vnc-listen 0.0.0.0
```

This prints a warning. Confirm firewall and VNC authentication settings before exposing a console to a network.

## Network Provisioning

The tool queries the exact libvirt network named `default`. If it does not exist, setup-vm defines a persistent NAT network using:

```text
bridge:       virbr0
host address: 192.168.122.1/24
DHCP range:   192.168.122.2–192.168.122.254
```

It starts the network when inactive and enables autostart. Host firewall policy is not modified automatically.

## Artifacts

The expected primary disk is:

```text
/var/lib/libvirt/images/<vm-name>.qcow2
```

The VM definition itself is managed by the system libvirt instance. Downstream tools query libvirt rather than relying solely on the expected filename:

- `vmgr` inspects actual attached disks before maintenance or removal.
- `snapshot` follows the domain's actual libvirt-managed storage.

## Existing VM Replacement

When the requested VM already exists, setup-vm:

1. Shows the complete new installation plan.
2. Requires explicit replacement confirmation.
3. Stops the existing VM if active.
4. Undefines its domain.
5. Removes only the expected setup-vm disk path.
6. Creates the replacement disk and starts installation.

If the expected disk exists without a matching VM, setup-vm refuses to overwrite it. Move or remove that disk explicitly after verifying its ownership.

## Failure Behavior

- Input, ISO, and dependency failures occur before destructive VM changes.
- Network, disk, and virt-install commands are checked individually.
- A failed disk creation stops before virt-install.
- A failed virt-install leaves the created disk in place for inspection or manual cleanup.
- Undefine failures mention common blockers such as snapshots, managed-save data, and NVRAM.

Use the other toolkit commands for follow-up work:

```bash
vmgr info <vm-name>
vmgr remove <vm-name>
snapshot list <vm-name>
```
