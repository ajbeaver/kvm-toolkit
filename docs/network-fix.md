Here is the content for `docs/network-fix.md`. It documents the specific issues encountered with Kali/Parrot installers on Arch Linux and the two-part solution implemented in your toolkit.

```markdown
# Network Connectivity Fix for KVM VMs

This document explains the common network connectivity issues encountered when installing security distributions (Kali Linux, Parrot OS) in a KVM/QEMU environment on Arch Linux, and the solutions implemented in this toolkit.

## The Problem

Users frequently report that VM installers fail to connect to the internet, displaying errors like "No network connection found" or "Cannot reach mirror servers," even when the host machine has internet access.

This issue typically stems from two distinct factors:

1.  **Driver Mismatch (Guest Side):**
    By default, `virt-install` creates a VM with a `virtio` network interface. While `virtio` offers high performance, the minimal kernels used in Linux installer environments often lack the necessary `virtio_net` modules or fail to load them automatically. This results in the installer detecting the hardware but failing to establish a connection.

2.  **Firewall Blocking (Host Side):**
    On Arch Linux, firewalls like `ufw` (Uncomplicated Firewall) often block traffic in the `FORWARD` chain by default. This prevents DHCP requests and data packets from passing between the virtual bridge (`virbr0`) and the host's physical network interface, effectively isolating the VM.

## The Solution

The `setup-vm` tool in this toolkit addresses both issues automatically:

### 1. Force Compatible Network Model
Instead of relying on `virtio`, the script forces the use of the `rtl8139` network model.
*   **Why:** `rtl8139` is a legacy driver supported by virtually every Linux kernel, including the minimal installer kernels of Kali and Parrot.
*   **Implementation:** The script adds `--network network=default,model=rtl8139` to the `virt-install` command.
*   **Alternative:** If `rtl8139` fails on specific hardware, `e1000` (Intel Gigabit) is a reliable secondary option.

### 2. Configure Host Firewall (UFW)
If `ufw` is active on the host, the toolkit (or the user) must allow traffic to pass through the virtual bridge.

**Required UFW Rules:**
Run these commands on the **Host** to allow VM traffic:

```bash
# Allow traffic on the virtual bridge interface
sudo ufw allow in on virbr0
sudo ufw allow out on virbr0

# Allow forwarding from the VM subnet to the outside world
sudo ufw route allow from 192.168.122.0/24

# Reload UFW to apply changes
sudo ufw reload
```

*Note: If you are using a specific physical interface (e.g., `eth0`), you can be more specific with the route rule: `sudo ufw route allow in on virbr0 out on eth0`.*

## Troubleshooting Steps

If a VM still fails to connect after creation:

1.  **Check Interface Status (Inside VM):**
    ```bash
    ip link show eth0
    # Should show state UP
    ```

2.  **Request DHCP (Inside VM):**
    ```bash
    sudo dhclient -v eth0
    ```
    If this times out, the firewall on the host is likely still blocking traffic.

3.  **Verify Host Bridge:**
    ```bash
    sudo brctl show virbr0
    # Should list vnet0 or similar
    ```

4.  **Switch Network Model:**
    If `rtl8139` fails, shut down the VM and edit its configuration to use `e1000`:
    ```bash
    sudo virsh edit <vm-name>
    # Change <model type='rtl8139'/> to <model type='e1000'/>
    ```

## Summary

By combining a universally compatible network driver (`rtl8139`) with correct firewall forwarding rules, the `kvm-toolkit` ensures that VMs can connect to the internet immediately upon boot, eliminating the most common barrier to entry for Arch Linux KVM users.
```

### How to add this to your repo:
1.  Create the file:
    ```bash
    mkdir -p docs
    nano docs/network-fix.md
    ```
2.  Paste the content above.
3.  Save and exit.
4.  Commit and push:
    ```bash
    git add docs/network-fix.md
    git commit -m "Add network troubleshooting documentation"
    git push origin main
    ```
