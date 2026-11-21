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
	@echo "make configure         - Configure the OS and RKE2 end-to-end on the sandbox nodes (idempotent)"
	@echo "make cluster-wait      - Block until all RKE2 nodes report Ready"
	@echo
	@echo "========================================================================================="

# Render per-node kickstart files from inventory. Doesn't use any vault
# vars itself, but Ansible loads all of group_vars/sandbox/ (including the
# encrypted vault.yml) for any host in rke2_cluster, so the vault password
# is still required.
.PHONY: render-kickstarts
render-kickstarts:
	ansible-playbook -i inventory/sandbox/hosts.yml kickstart/render_kickstarts.yml --vault-password-file ${VAULT_PASS_FILE}

# Create and start the pico-1/2/3 sandbox VMs on HOST, then block until
# they answer SSH - a VM existing isn't the same as Ansible being able to
# reach it yet (kickstart install + reboot takes a few minutes).
.PHONY: sandbox-create
sandbox-create: render-kickstarts
	${SSH} "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '${REMOTE_TMP}' | Out-Null\""
	scp -o RemoteCommand=none hyperv/Create-SandboxVMs.ps1 kickstart/rendered/*.ks "${HOST}:${REMOTE_TMP}/"
	${SSH} "powershell -NoProfile -Command \"& '${REMOTE_TMP}\\Create-SandboxVMs.ps1'\""
	${SSH} "powershell -NoProfile -Command \"Remove-Item -Recurse -Force '${REMOTE_TMP}' -ErrorAction SilentlyContinue\""
	${MAKE} sandbox-wait

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
# Doesn't use any vault vars itself, but Ansible loads all of
# group_vars/sandbox/ (including the encrypted vault.yml) for any host in
# rke2_cluster, so the vault password is still required.
.PHONY: sandbox-wait
sandbox-wait:
	ansible -i inventory/sandbox/hosts.yml rke2_cluster -m wait_for_connection -a "timeout=600" --vault-password-file ${VAULT_PASS_FILE}

# Configure the OS and RKE2 end-to-end on the sandbox nodes: Host Prep,
# RKE2 Config, and RKE2 Start in sequence (PLAN.md Build Sequence steps
# 2-5), then block until all nodes report Ready. Idempotent - safe to
# rerun against nodes fresh out of `sandbox-create` or against an
# already-configured cluster. Depends on `sandbox-wait` since nodes fresh
# out of `sandbox-create` aren't reachable yet. Reads the Ansible Vault
# password from VAULT_PASS_FILE (see
# inventory/sandbox/group_vars/sandbox/vault.yml).
.PHONY: configure
configure: sandbox-wait
	ansible-playbook -i inventory/sandbox/hosts.yml cluster.yml --vault-password-file ${VAULT_PASS_FILE}
	${MAKE} cluster-wait

# Block until all RKE2 nodes report Ready - confirms the cluster actually
# converged, not just that `configure` ran without error. Useful standalone
# after a node reboot too.
.PHONY: cluster-wait
cluster-wait:
	ansible-playbook -i inventory/sandbox/hosts.yml cluster_wait.yml --vault-password-file ${VAULT_PASS_FILE}
