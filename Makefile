HOST := beef.taco.moe
SSH := ssh -o RemoteCommand=none ${HOST}
REMOTE_TMP := C:\Users\Ryan\AppData\Local\Temp\rke2-sandbox
VAULT_PASS_FILE := ${HOME}/.rke2-vault-pass

.PHONY: help
help:
	@echo "=== VARIABLES ==========================================================================="
	@echo
	@echo "   HOST:            ${HOST}"
	@echo "   VAULT_PASS_FILE: ${VAULT_PASS_FILE}"
	@echo
	@echo "========================================================================================="
	@echo
	@echo "=== COMMANDS ============================================================================"
	@echo
	@echo "make help              - Show this message"
	@echo "make render-kickstarts - Render per-node kickstart files from inventory"
	@echo "make sandbox-create    - Create and start the pico-1/2/3 sandbox VMs on HOST"
	@echo "make sandbox-delete    - Tear down the pico-1/2/3 sandbox VMs and their VHDs"
	@echo "make sandbox-wait      - Block until all 3 sandbox nodes answer SSH"
	@echo "make host-prep         - Run Host Prep (subscription, packages, RKE2 install) on the sandbox nodes"
	@echo "make rke2-config       - Write RKE2 config, kube-vip, and Cilium HelmChartConfig to the sandbox nodes"
	@echo "make rke2-start        - Start the first server, then join servers 2 and 3 through the API VIP"
	@echo
	@echo "========================================================================================="

# Render per-node kickstart files from inventory
.PHONY: render-kickstarts
render-kickstarts:
	ansible-playbook -i inventory/sandbox/hosts.yml kickstart/render_kickstarts.yml

# Create and start the pico-1/2/3 sandbox VMs on HOST
.PHONY: sandbox-create
sandbox-create: render-kickstarts
	${SSH} "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '${REMOTE_TMP}' | Out-Null\""
	scp -o RemoteCommand=none hyperv/Create-SandboxVMs.ps1 kickstart/rendered/*.ks "${HOST}:${REMOTE_TMP}/"
	${SSH} "powershell -NoProfile -Command \"& '${REMOTE_TMP}\\Create-SandboxVMs.ps1'\""
	${SSH} "powershell -NoProfile -Command \"Remove-Item -Recurse -Force '${REMOTE_TMP}' -ErrorAction SilentlyContinue\""

# Tear down the pico-1/2/3 sandbox VMs and their VHDs
.PHONY: sandbox-delete
sandbox-delete:
	${SSH} "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '${REMOTE_TMP}' | Out-Null\""
	scp -o RemoteCommand=none hyperv/Delete-SandboxVMs.ps1 "${HOST}:${REMOTE_TMP}/"
	${SSH} "powershell -NoProfile -Command \"& '${REMOTE_TMP}\\Delete-SandboxVMs.ps1'\""
	${SSH} "powershell -NoProfile -Command \"Remove-Item -Recurse -Force '${REMOTE_TMP}' -ErrorAction SilentlyContinue\""

# Block until all 3 sandbox nodes answer SSH - poll instead of guessing how
# long kickstart install + reboot takes. wait_for_connection retries on its
# own, so this is a single ansible call, not a shell loop. (Host key checking
# for the fresh-every-rebuild sandbox nodes is disabled in group_vars, not
# here, so every ansible/ansible-playbook call against them is covered.)
.PHONY: sandbox-wait
sandbox-wait:
	ansible -i inventory/sandbox/hosts.yml rke2_cluster -m wait_for_connection -a "timeout=600"

# Run Host Prep on the sandbox nodes: RHSM registration, packages, swap/
# SELinux/firewalld, NetworkManager unmanaged interfaces, RKE2 RPM install.
# Reads the Ansible Vault password from VAULT_PASS_FILE (see
# inventory/sandbox/group_vars/sandbox/vault.yml).
.PHONY: host-prep
host-prep:
	ansible-playbook -i inventory/sandbox/hosts.yml host_prep.yml --vault-password-file ${VAULT_PASS_FILE}

# Write RKE2 server config, the kube-vip static pod, and the Cilium
# HelmChartConfig override to the sandbox nodes. Does not start rke2-server.
# Reads the Ansible Vault password from VAULT_PASS_FILE (see
# inventory/sandbox/group_vars/sandbox/vault.yml).
.PHONY: rke2-config
rke2-config:
	ansible-playbook -i inventory/sandbox/hosts.yml rke2_config.yml --vault-password-file ${VAULT_PASS_FILE}

# Start the first server and initialize the cluster, then join servers 2
# and 3 through the API VIP. Reads the Ansible Vault password from
# VAULT_PASS_FILE (not strictly needed by this playbook, kept for consistency).
.PHONY: rke2-start
rke2-start:
	ansible-playbook -i inventory/sandbox/hosts.yml rke2_start.yml --vault-password-file ${VAULT_PASS_FILE}
