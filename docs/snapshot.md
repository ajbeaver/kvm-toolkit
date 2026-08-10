# snapshot

Current version: **1.1.0**

`snapshot` manages libvirt snapshots for VMs provisioned by setup-vm or otherwise defined in the system libvirt instance.

## Requirements

- `sudo` and `virsh`
- A working system libvirt/QEMU installation
- Snapshot-compatible domain storage

The tool queries libvirt for the domain and its actual storage. It does not directly delete VM disk files.

## Usage

```text
snapshot <command> [arguments]
```

| Command | Description |
| :--- | :--- |
| `create <vm-name> [tag]` | Create a snapshot with an optional explicit tag. |
| `list <vm-name>` | List snapshot names for a VM. |
| `restore <vm-name> <tag>` | Confirm and restore a fully shut-down VM. |
| `delete <vm-name> <tag>` | Confirm and delete one snapshot. |
| `delete <vm-name> all` | Confirm and attempt deletion of every snapshot. |

## Snapshot Tags

When a tag is omitted, snapshot generates one with second-level resolution:

```text
YYYY-MM-DD-HHMMSS
```

Custom tags may contain letters, numbers, dots, underscores, and hyphens. They must begin with a letter or number and may be at most 128 characters.

The tag `all` is reserved by the delete command and cannot be used when creating a snapshot.

## Create

```bash
snapshot create <vm-name>
snapshot create <vm-name> before-update
```

Before creation, the tool:

1. Confirms the VM exists.
2. Rejects a duplicate tag.
3. Shows actual file-backed disks reported by libvirt.
4. Shows the current VM state.

Snapshot creation retains the established `virsh snapshot-create-as --no-current` behavior. When the VM is not shut off, the tool warns that snapshot creation may briefly pause guest I/O.

## List

```bash
snapshot list <vm-name>
```

An empty snapshot history is reported explicitly as `(none)`.

## Restore

```bash
snapshot restore <vm-name> before-update
```

Restore requires the VM state to be exactly `shut off`. Stop it gracefully first:

```bash
vmgr shutdown <vm-name> --wait 60
```

The tool verifies the tag, displays storage context, warns that current state will be replaced, and requires confirmation before invoking libvirt restore.

## Delete

Delete one snapshot:

```bash
snapshot delete <vm-name> before-update
```

Delete every snapshot:

```bash
snapshot delete <vm-name> all
```

Both operations require confirmation. Delete-all checks each libvirt deletion result independently, continues through the requested list, and reports partial failures without claiming full success.

## Storage Model

setup-vm's expected primary disk is:

```text
/var/lib/libvirt/images/<vm-name>.qcow2
```

Snapshot does not assume that path is attached. It shows actual file-backed disks reported by libvirt and warns when the expected setup-vm path is absent. Snapshot operations continue against the domain's real libvirt-managed storage.

Storage deletion belongs to [`vmgr remove`](vmgr.md#undefine-versus-remove), which applies additional snapshot, sharing, and path guards.

## Failure Behavior

- Invalid VM names and tags fail before sudo authentication.
- Missing domains and duplicate/missing tags stop without mutation.
- Running, paused, or otherwise active VMs cannot be restored.
- Cancellation returns without changing VM or snapshot state.
- Libvirt listing, creation, restore, and deletion failures are checked and reported.
