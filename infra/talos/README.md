# Talos Bare Metal Cluster (KNG)

This repository documents the configuration and bootstrap procedures for a **High-Availability (HA) Bare Metal Kubernetes cluster** running on **Talos Linux**.

The architecture prioritizes performance and resilience:
* **OS:** Talos Linux (Immutable, API-managed).
* **Networking:** Cilium CNI (with KubeProxy disabled/replaced).
* **Storage:** Local NVMe.
* **HA:** 3 Control Plane nodes with a shared Virtual IP (VIP).
---
## 🛠 Prerequisites

* **Talosctl:** CLI tool for managing Talos.
  ```bash
  brew install siderolabs/tap/talosctl
  ```
* **Helm:** Kubernetes package manager (`brew install helm`).
* **Kubectl:** Kubernetes CLI (`brew install kubectl`).
* **Hardware:**
    * Bare metal nodes with NVMe drives.
    * Talos ISO.

---

## Configuration Structure

* `patches/common.yaml`: **Cluster-wide settings** applied to *all* nodes.
    * *Highlights:* NTP (Greece), Sysctls (10GbE tuning), Syslog, Extensions (Intel uCode).
* `patches/node-X.yaml`: **Node-specific settings**.
    * *Highlights:* Hostname, Static IP, VIP configuration, Routing metrics.
* `secrets.yaml`: *(GitIgnored)* Encrypted bundle used to regenerate configs if local files are lost.

### Reference: `patches/common.yaml`
<details>
<summary>Click to view template</summary>

```yaml
machine:
  time:
    servers:
      - 0.gr.pool.ntp.org
      - 1.gr.pool.ntp.org
      - time.google.com
  sysctls:
    fs.inotify.max_user_watches: "1048576"
    net.core.somaxconn: "65535"
    net.core.netdev_max_backlog: "4096"
  logging:
    destinations:
      - endpoint: udp://<SYSLOG>:514
        format: json_lines
  network:
    nameservers:
      - <DNS>
  install:
    disk: /dev/nvme0n1
    wipe: true
    extensions:
      - image: ghcr.io/siderolabs/intel-ucode:20240514
  certSANs:
    - <VIP>
    - 127.0.0.1
cluster:
  allowSchedulingOnControlPlanes: true
  network:
    cni:
      name: none       # Disables Flannel (Required for Cilium)
  proxy:
    disabled: true     # Disables KubeProxy (Required for Cilium)
  apiServer:
    certSANs:
      - <VIP>
```
</details>

### 📄 Reference: `patches/node-X.yaml`
<details>
<summary>Click to view template</summary>

```yaml
machine:
  network:
    interfaces:
      - interface: enp46s0       # 10GbE Primary
        dhcp: false
        addresses:
          - <NODE-IP>/24
        vip:
          ip: <VIP>              # Crucial: Must be on ALL control planes for HA
        routes:
          - network: 0.0.0.0/0
            gateway: <GW>
            metric: 100
        # mtu: 9000              # WARNING: Only enable if Switch + All Nodes support it
      - interface: enp86s0       # 1GbE Secondary
        dhcp: false
        addresses:
          - <SEC-IP>/24
        routes:
          - network: 0.0.0.0/0
            gateway: <GW>
            metric: 200
---
apiVersion: v1alpha1
kind: HostnameConfig
auto: off
hostname: <HOSTNAME>
```
</details>

---

## 🚀 Bootstrap Procedure

### Phase 1: Configuration Generation
Run this locally on your workstation to create the machine configuration files.

```bash
# Generate config using the Common patch
talosctl gen config <CLUSTER-NAME> https://<VIP>:6443 --config-patch @patches/common.yaml
```

### Phase 2: Bootstrap First Node (The Leader)
1.  **Boot** Node 1 from ISO.
2.  **Identify** its temporary DHCP IP (`<TEMP-IP>`).
3.  **Apply** the configuration + Node 1 patch:
    ```bash
    talosctl apply-config --insecure --nodes <TEMP-IP> --file controlplane.yaml --config-patch @patches/node-1.yaml
    ```
    *Note: The node will wipe itself, install Talos, and reboot to its static IP.*

4.  **Bootstrap Etcd** (Once the node is back online):
    ```bash
    # Update local tool to talk to the new Static IP
    talosctl config endpoint <NODE-1-IP>
    talosctl config node <NODE-1-IP>
    talosctl config merge ./talosconfig

    # Initialize the cluster
    talosctl bootstrap --nodes <NODE-1-IP>
    ```