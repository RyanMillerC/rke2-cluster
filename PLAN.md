# RKE2 Lab Cluster Build Plan

**WHY IT MATTERS:** This replaces a single-node K3s cluster with a 3-node HA RKE2 cluster. Everything must be rebuildable from code: Ansible bootstraps the cluster, Argo CD deploys everything else.

**FOR THE BUILD AGENT:** Decisions below are final unless marked **OPEN**. Values in `<ANGLE_BRACKETS>` are placeholders; expose them as Ansible variables, never hardcode them.

---

## Environments

Build once, run in two places. Both must come from the same roles with per-environment inventory and group_vars.

| | Sandbox (now) | Lab (later) |
|---|---|---|
| **Cert issuer** | Let's Encrypt **staging** | Let's Encrypt **production** |
| **Hosts** | 3x Hyper-V VMs, 8 vCPU / 16GB static RAM | 3x Beelink EQR5, Ryzen 3 7330U (4c/8t), 16GB, 500GB SSD |
| **NIC name** | `eth0` | Different (e.g. `enp1s0`), verify on real hardware |

---

## Decisions

| Area | Decision |
|---|---|
| **API VIP** | kube-vip, **static pod**, control plane only, ARP mode, Services mode **off** |
| **App delivery** | Argo CD only, AppProjects `platform` and `apps` |
| **Certs (apps)** | cert-manager, DNS-01, wildcard `*.apps.taco.moe`. Reuse existing working K3s config |
| **CNI** | Cilium, kube-proxy replacement **on**, L2 announcements **on**, Hubble **on** |
| **Distribution** | RKE2, **pinned to v1.36 or later** |
| **Firewall** | firewalld **disabled**. Perimeter is UniFi VLAN rules. Cilium host firewall is day 2 |
| **Ingress** | RKE2 bundled Traefik (default in v1.36+) |
| **Load balancer (Services)** | Cilium LB IPAM + L2 announcements. **No MetalLB** |
| **Node roles** | All 3 nodes are servers (control plane + etcd + workloads). No taints |
| **OS** | RHEL 9, SELinux enforcing |
| **OS bootstrap** | Kickstart, **minimum config only** (networking, hostname, SSH key, SELinux enforcing, subscription). Everything else via Ansible |
| **Secrets** | External Secrets Operator + Vault **in-cluster**, AWS KMS auto-unseal |
| **Storage** | Synology NAS. NFS (csi-driver-nfs) default; iSCSI (Synology CSI) for databases, Prometheus, Vault |

---

## Network Plan

**OPEN:** Fill in before building. Every IP below must sit **outside the DHCP range**.

| Item | Value |
|---|---|
| **Domain** | `taco.moe` |
| **Cluster nickname** | `guac` |
| **API VIP** (kube-vip) | `<API_VIP>` |
| **API FQDN** | `api.guac.taco.moe` → `<API_VIP>` |
| **Apps IP** (Cilium LB, shared) | `<APPS_IP>` |
| **Apps wildcard** | `*.apps.taco.moe` → `<APPS_IP>` |
| **Cilium LB pool** | `<LB_POOL_CIDR>` (must contain `<APPS_IP>`) |
| **Cluster VLAN / subnet** | `<VLAN_ID>` / `<SUBNET>` |
| **Node IPs** | `guac-1.taco.moe`: `<NODE1_IP>`, `guac-2.taco.moe`: `<NODE2_IP>`, `guac-3.taco.moe`: `<NODE3_IP>` (static) |
| **Internal DNS** | **OPEN:** UniFi local DNS or existing resolver |

**UNIFI RULES:** Dedicated VLAN for the cluster. Allow inbound from admin network only to `<API_VIP>:6443`, `<APPS_IP>` (all exposed ports), and SSH to nodes. Everything else stays inside the cluster subnet.

---

## Build Sequence

Order matters. Each step depends on the one before it.

1. **OS install** via per-node kickstart — minimum config only (see OS Bootstrap). Prerequisite for Ansible access
2. **Host prep** on all 3 nodes (see Host Prep)
3. **RKE2 config + kube-vip static pod + Cilium HelmChartConfig** written to all 3 nodes **before first start**
4. **First server** starts and initializes the cluster
5. **Servers 2 and 3** join **through the API VIP** (port 9345)
6. **Argo CD bootstrap:** Ansible places an Argo CD `HelmChart` manifest and one root Application in RKE2's server manifests directory. RKE2's Helm controller installs Argo; Argo installs everything else
7. **Argo sync waves** (lowest first):
   1. Cilium LB IP pool + L2 announcement policy
   2. Storage drivers and StorageClasses
   3. cert-manager + issuers
   4. Vault
   5. External Secrets Operator + ClusterSecretStore
   6. Traefik configuration
   7. Apps

**ARGO MUST NOT MANAGE:** kube-vip and Cilium itself. Both must exist before Argo can run.

---

## Hyper-V VM Settings (Sandbox Only)

- **Automatic checkpoints:** off. Restoring one node's checkpoint corrupts etcd. Snapshot only with all 3 VMs shut down
- **Dynamic Memory:** off. Fixed 16GB
- **Generation:** 2, Secure Boot template **Microsoft UEFI Certificate Authority**
- **MAC address spoofing:** on (needed for VIP failover)
- **MAC addresses:** static
- **Time synchronization integration service:** off (chrony owns time)
- **Virtual switch:** External, VLAN ID set per VM adapter, UniFi port carries the VLAN tagged

---

## OS Bootstrap (Kickstart)

Gets a node from bare VM/hardware to "Ansible can reach it" — nothing more. Split rule: kickstart owns anything disk-destructive to change later, or required for SSH access to exist at all. Everything else is Ansible's job (see Host Prep), because it's idempotent and iterable without a reinstall.

- **Disk partitioning / LVM:** set here, not revisited by Ansible
- **Hostname + static network config:** so the node lands at its known inventory IP
- **Initial user + SSH key injection:** the hard dependency — without this, Ansible has nothing to connect to
- **SELinux:** set to `enforcing` at install, avoiding a relabel-and-reboot cycle later
- **Packages:** minimal — just Python + SSH. No chrony, no RKE2, nothing environment-specific
- **Delivery:** one templated `.ks.cfg`, per-node values (hostname, static IP) substituted in. Sandbox: served to Hyper-V Gen2 VMs via local HTTP or a mounted secondary virtual DVD. Lab: USB stick, verify delivery method on the Beelink boxes

**NOT kickstart's job:** chrony, firewalld, NetworkManager unmanaged-interface rules, subscription registration, `iscsi-initiator-utils`/`nfs-utils`, swap removal, RKE2 install/config, or anything else in Host Prep below — all revisable without touching the OS install.

---

## Host Prep (RHEL)

- **chrony:** enabled and synced
- **firewalld:** disabled
- **Hostnames:** unique, resolvable by all nodes
- **NetworkManager:** mark `cilium_*` and `lxc*` interfaces unmanaged
- **Packages:** `iscsi-initiator-utils` (with `iscsid` enabled), `nfs-utils`
- **RKE2 install:** from the **RKE2 RPM repo**, not the tarball, so `rke2-selinux` is installed
- **SELinux:** enforcing
- **Swap:** disabled, including removal from fstab
- **Subscription:** **OPEN:** Partner Connect NFR if available, otherwise Developer subscription

---

## RKE2 Config

Set on **every** server node:

- **CNI:** `cilium`
- **Embedded registry mirror:** enabled (reduces Docker Hub pulls on rebuild)
- **kube-proxy:** disabled (Cilium replaces it)
- **Metrics exposure:** expose etcd, kube-scheduler, and kube-controller-manager metrics beyond localhost. Not used until day 2, but must be set before first start
- **tls-san:** `<API_VIP>` and `api.guac.taco.moe`. Must be identical on all 3 nodes; a missing entry fails only after VIP failover
- **Version:** pinned

---

## Component Details

### Argo CD
- Installed via RKE2 Helm controller, not by Ansible applying manifests directly
- Git repo credentials come from the bootstrap secrets (ESO isn't running yet)
- AppProject `platform` for cluster components, `apps` for workloads

### cert-manager
- DNS-01 solver, existing working config from K3s
- Issuer selected per environment: staging (sandbox), production (lab)
- Verify `ingressClassName` used by Ingresses matches the class RKE2's Traefik registers

### Cilium (via RKE2 HelmChartConfig)
- `k8sServiceHost` points at the **local API server on each node** (127.0.0.1:6443), not the VIP
- Hubble relay and UI enabled
- kube-proxy replacement enabled
- L2 announcements enabled; tune client rate limits for lease traffic if needed
- LB IP pool (`CiliumLoadBalancerIPPool`) and `CiliumL2AnnouncementPolicy` delivered by Argo
- **Shared apps IP:** Traefik and all non-HTTP LoadBalancer Services share `<APPS_IP>` via Cilium's LB IPAM sharing-key annotation. Pin the IP in manifests

### kube-vip
- Static pod in RKE2's kubelet pod-manifests directory on each server
- ARP mode, control plane only, leader election on
- Interface name is a per-environment variable
- **Never** let Cilium announce `<API_VIP>`

### Storage
- **csi-driver-nfs:** default StorageClass, reclaim policy **Retain**, subdirectory naming by **namespace and PVC name** so rebuilt apps reattach to existing data
- **Synology CSI (iSCSI):** StorageClass for databases, Prometheus, and Vault Raft. Reclaim policy **Retain**
- Never put databases or Prometheus on NFS

### Traefik
- Bundled with RKE2, configured via HelmChartConfig
- Exposed as a **LoadBalancer Service on `<APPS_IP>`**, host ports disabled

### Vault + ESO
- Vault in-cluster, integrated Raft storage on iSCSI
- **Auto-unseal with AWS KMS**
- Seeded from the encrypted vars file after deploy. The vars file is the source of truth; Vault is rebuildable
- ESO authenticates with Vault's **Kubernetes auth method** using in-cluster config (no static credential)
- Sync order enforced by Argo waves: Vault → ESO → apps

---

## Bootstrap Secrets

Stored in an **Ansible Vault-encrypted vars file**, never plaintext in Git. Back it up outside the cluster and outside Git.

- Argo CD Git deploy key or token
- AWS credentials for Vault KMS auto-unseal
- DNS provider API token for cert-manager DNS-01
- RKE2 cluster join token
- Synology CSI credentials
- Vault seed secrets (everything apps will read through ESO)

---

## Acceptance Tests

The build is done when all of these pass:

- **Full rebuild:** destroy all 3 nodes, rerun Ansible, everything returns with no manual steps, including Vault seeding from the vars file
- **Cert issued:** wildcard cert present and served by Traefik on `*.apps.taco.moe`
- **LB reachability:** a non-HTTP LoadBalancer Service gets `<APPS_IP>` and is reachable from the admin network
- **Node reboot:** Vault auto-unseals; ESO refreshes secrets
- **PVC reattach:** after a rebuild, an NFS-backed app comes back with its old data
- **VIP failover:** shut down the VIP holder; kubectl via `api.guac.taco.moe` keeps working after failover (proves tls-san on all nodes)

---

## Out of Scope (Day 2)

- Cilium host firewall (start in audit mode)
- kube-prometheus-stack (disable kube-proxy monitoring) + Hubble metrics
- Loki, single-binary, on NAS
- RKE2 upgrade automation
- SSO for cluster access

---

## Open Items

- Internal DNS location
- IP plan values
- RHEL subscription source
- Whether **Full rebuild** (Acceptance Tests) means re-running kickstart (true bare-metal/VM reinstall) or assumes RHEL is already installed and only Ansible + RKE2 are torn down. Affects whether kickstart delivery needs to be automated end-to-end (e.g. Ansible driving Hyper-V PowerShell to recreate VMs)
