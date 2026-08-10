# vmgr

Current version: **1.0.0**

`vmgr` handles daily operation, inspection, access, and guarded maintenance for VMs in the system libvirt instance:

```text
qemu:///system
```

Provision new VMs with [`setup-vm`](setup-vm.md) and manage state history with [`snapshot`](snapshot.md).

## Requirements

- `sudo` and `virsh`
- A working `qemu:///system` libvirt connection
- `virt-viewer` for graphical access
- A serial console configured in the guest for `vmgr console`

Run `vmgr` as your normal user. The tool authenticates sudo for libvirt operations. `virt-viewer` is deliberately launched without sudo so it can use the current desktop session.

## Inspection

```bash
vmgr list
vmgr status <vm-name>
vmgr info <vm-name>
vmgr disks <vm-name>
vmgr network <vm-name>
```

| Command | Description |
| :--- | :--- |
| `list` | List all running and stopped domains. |
| `status` | Print a concise libvirt state. |
| `info` | Show `virsh dominfo`, the expected setup-vm disk, and actual attached disks. |
| `disks` | Show detailed block-device attachments. |
| `network` | Show attached network interfaces. |

## Lifecycle

### Start

```bash
vmgr start <vm-name>
```

Starting an already active VM is an informational no-op.

### Launch

```bash
vmgr launch <vm-name>
```

`launch` starts a shut-down VM when needed and then opens `virt-viewer`.

### Graceful shutdown

```bash
vmgr shutdown <vm-name>
vmgr shutdown <vm-name> --wait 60
```

Without `--wait`, vmgr submits the shutdown request and returns. With `--wait`, it polls for up to the requested 1–3600 seconds.

If the timeout expires, vmgr reports the current state and leaves the VM running. It never escalates a graceful shutdown into force-stop automatically.

### Reboot

```bash
vmgr reboot <vm-name>
```

Reboot requires the VM to be running. A stopped VM is not silently started.

### Force-stop

```bash
vmgr force-stop <vm-name>
```

Force-stop uses libvirt's immediate power-off operation. It warns about potential guest-data corruption and requires confirmation.

## Console Access

Open a graphical console:

```bash
vmgr view <vm-name>
```

`view` requires an active VM. Use `launch` when the VM may be stopped.

Connect to a configured serial console:

```bash
vmgr console <vm-name>
```

Press `Ctrl+]` to leave the virsh console.

## Autostart

```bash
vmgr autostart <vm-name> enable
vmgr autostart <vm-name> disable
```

This controls whether libvirt starts the domain automatically with the host's virtualization service.

## Undefine Versus Remove

### Keep storage

```bash
vmgr undefine <vm-name>
```

`undefine` requires a fully shut-down VM, refuses remaining snapshots, removes only the libvirt domain definition, and keeps attached storage.

### Remove storage

```bash
vmgr remove <vm-name>
```

`remove` is deliberately conservative. Before confirmation it requires:

- A fully shut-down VM
- No remaining libvirt snapshots
- File-backed disk metadata that can be parsed unambiguously
- Every candidate disk beneath `/var/lib/libvirt/images`
- No candidate disk attached to another domain

It refuses external paths, shared disks, paths containing ambiguous whitespace, and domains with snapshots. CD-ROM devices are excluded from removal candidates.

After confirmation, vmgr undefines the domain first. Disks are deleted only if undefine succeeds. Partial disk-deletion failures are reported with the exact remaining paths.

## Relationship to setup-vm Artifacts

The expected setup-vm primary disk is:

```text
/var/lib/libvirt/images/<vm-name>.qcow2
```

vmgr treats that as context, not proof. Inspection and removal use actual block-device attachments from libvirt.

## Recovery Notes

- If shutdown times out, inspect with `vmgr status`; choose force-stop only after accepting guest corruption risk.
- If undefine fails, check for snapshots, managed-save state, or NVRAM.
- If remove refuses snapshots, inspect them with `snapshot list <vm-name>`.
- If remove refuses external/shared storage, handle that storage deliberately rather than bypassing the guard.
- If disk deletion partially fails after undefine, the reported paths remain for manual inspection.
