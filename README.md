# rke2

Builds a 3-node HA RKE2 Kubernetes cluster, replacing a single-node K3s
homelab cluster. Everything is rebuildable from code: this repo bootstraps
the cluster (VMs, OS, RKE2, kube-vip, Cilium, and Argo CD itself); from
there, [rke2-gitops](https://github.com/RyanMillerC/rke2-gitops) owns
everything Argo CD deploys on top (platform config and apps).

See [`PLAN.md`](PLAN.md) for the full design doc - architecture decisions,
network plan, build sequence, and acceptance tests.

## Environments

| | Sandbox (now) | Lab (later) |
|---|---|---|
| **Cluster nickname** | `pico` | `guac` |
| **Hosts** | 3x Hyper-V VMs | 3x Beelink EQR5 |

Only `pico` (sandbox) is built today; `guac` (the real Beelink hardware) is
unstarted. Both are meant to come from the same roles with per-environment
inventory and `group_vars`.

## Prerequisites

- Ansible core 2.21+ with the `community.general` collection
- An Ansible Vault password at `~/.rke2-vault-pass` (or pass
  `VAULT_PASS_FILE=<path>` to `make`), protecting
  `inventory/sandbox/group_vars/sandbox/vault.yml` (RHSM credentials, RKE2
  join token)
- SSH access to `beef.taco.moe`, the Hyper-V host (sandbox VM lifecycle only)

## Usage

```
make help            # show all targets
make sandbox-create  # create and boot the pico-1/2/3 VMs, wait for SSH
make configure       # Host Prep + RKE2 + Argo CD bootstrap, wait for Ready
make kubeconfig      # fetch KUBECONFIG, pointed at the API VIP
```

`sandbox-create` is **not** idempotent - it errors if the VMs already exist
(run `make sandbox-delete` first for a clean rebuild). `configure` **is**
idempotent - safe to rerun against a live cluster.

## Layout

- `hyperv/` - PowerShell scripts run on `beef.taco.moe` to create/delete the
  sandbox VMs
- `kickstart/` - RHEL kickstart template and per-node rendered output,
  delivered via OEMDRV
- `inventory/sandbox/` - Ansible inventory, group/host vars, and the
  encrypted vault for the `pico` environment
- `roles/`, `playbooks/` - Ansible: Host Prep, RKE2 Config, RKE2 Start, Argo
  CD bootstrap
- `Makefile` - the only interface meant for day-to-day use; wraps the above
