HOST := beef.taco.moe
SSH := ssh -o RemoteCommand=none ${HOST}
REMOTE_TMP := C:\Users\Ryan\AppData\Local\Temp\rke2-sandbox

.PHONY: help
help:
	@echo "=== VARIABLES ==========================================================================="
	@echo
	@echo "   HOST: ${HOST}"
	@echo
	@echo "========================================================================================="
	@echo
	@echo "=== COMMANDS ============================================================================"
	@echo
	@echo "make help              - Show this message"
	@echo "make render-kickstarts - Render per-node kickstart files from inventory"
	@echo "make sandbox-create    - Create and start the pico-1/2/3 sandbox VMs on HOST"
	@echo "make sandbox-delete    - Tear down the pico-1/2/3 sandbox VMs and their VHDs"
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
