# Harvester (Homelab)

Declarative manifests for **Harvester**  in the homelab. This folder contains VirtualMachine specs, and related resources that are applied via **Rancher Fleet**.

> **UI‑friendly:** Manifests are authored to remain editable from the Harvester UI (where possible). Labels are duplicated at the VM and Pod template for easy filtering and consistently.

---

## Prerequisites

* A running **Harvester** cluster (v1.5+ recommended).
* **Rancher** with **Fleet** and Harvester cluster imported/registered. [Harvester ↔ Rancher Integration](https://docs.harvesterhci.io/v1.5/rancher/rancher-integration)

    *  I used **Rancher Manager** extentension, so Rancher is hosted within Harvester Cluster (splitted)
* (Optional) A GitOps workspace/namespace (e.g. `fleet-default`).
* Access to a **Cluster Network** (e.g. `mgmt`) and – if you use VLANs – the corresponding uplink/bridge configured in Harvester.


## Network Topology

* DNS and VLANs managed via external router (UDM in this case).
* VM's network manually routed and on VLAN 8.
* VLAN 8 - has DCHP Server with static IP/Domain on VMS
* Between VLAN 8 and other VLANs there is full isolation except from LB and DNS in particular IP.

---

## Deploying with Fleet (recommended)

Create a `GitRepo` in Rancher pointing to this repository and path `harvester/`. Example:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab-harvester
  namespace: fleet-default
spec:
  repo: https://github.com/tsotsos/homelab
  branch: main
  paths:
    - harvester
  targets:
    - name: harvester
      clusterSelector: {}
```

---

## Networking (Multus / VLAN / routes)

If you need a VLAN-backed secondary NIC or a routed L3 attachment, create a NetworkAttachmentDefinition. Example (UI‑round‑trippable):

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: test-network
  namespace: kng-cluster
  labels:
    network.harvesterhci.io/clusternetwork: mgmt
    network.harvesterhci.io/ready: "true"
    network.harvesterhci.io/type: L2VlanNetwork
    network.harvesterhci.io/vlan-id: "8"
  annotations:
    network.harvesterhci.io/route: '{"mode":"manual","cidr":"172.30.0.1/24","gateway":"172.30.0.1","serverIPAddr":"172.30.0.1","connectivity":"true"}'
spec:
  config: '{"cniVersion":"0.3.1","name":"test-network","type":"bridge","bridge":"mgmt-br","promiscMode":true,"vlan":8,"ipam":{}}'
```
---


## Local testing

Examine and verify your `yaml`

```bash
kustomize build harvester/ > all.yaml
```
Dry run
```bash
# Client-side validation
kubectl apply --dry-run=client -k harvester/

# Server-side validation (uses your cluster’s CRDs)
kubectl apply --dry-run=server -k harvester/
```
---

## Tips & conventions

* **UI edits vs. GitOps:** If you edit VMs/NADs in the UI and Fleet manages the same objects, Fleet will revert your changes on the next sync. Prefer PRs to this folder.
* **Requests/Limits:** Ensure VM request values satisfy any cluster LimitRanger/Quota. If the `virt-launcher` Pod can’t be scheduled, inspect `kubectl describe vm/<name>` and the corresponding Pod events.
* **Images:** To avoid re‑downloading cloud images repeatedly, consider defining `VirtualMachineImage` or pre‑seeded `DataVolume` templates and referencing them in your VMs.
* **Labels:** Use \[Kubernetes recommended app labels] consistently across both VM and template.

---

## References

* Harvester docs – Networking & Cluster Networks
* Harvester docs – VM management
* Harvester docs – Storage Network (NAD created automatically by setting)
* Rancher Fleet docs – GitRepo, structure, and Kustomize/Helm support