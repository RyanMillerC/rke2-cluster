HOST := beef.taco.moe
REMOTE_TMP := C:\Users\Ryan\AppData\Local\Temp\rke2-sandbox
SSH := ssh -o RemoteCommand=none $(HOST)

.PHONY: render-kickstarts sandbox-create sandbox-delete

render-kickstarts:
	ansible-playbook -i inventory/sandbox/hosts.yml kickstart/render_kickstarts.yml

sandbox-create: render-kickstarts
	$(SSH) "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$(REMOTE_TMP)' | Out-Null\""
	scp -o RemoteCommand=none hyperv/Create-SandboxVMs.ps1 kickstart/rendered/*.ks "$(HOST):$(REMOTE_TMP)/"
	$(SSH) "powershell -NoProfile -Command \"& '$(REMOTE_TMP)\\Create-SandboxVMs.ps1'\""
	$(SSH) "powershell -NoProfile -Command \"Remove-Item -Recurse -Force '$(REMOTE_TMP)' -ErrorAction SilentlyContinue\""

sandbox-delete:
	$(SSH) "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$(REMOTE_TMP)' | Out-Null\""
	scp -o RemoteCommand=none hyperv/Delete-SandboxVMs.ps1 "$(HOST):$(REMOTE_TMP)/"
	$(SSH) "powershell -NoProfile -Command \"& '$(REMOTE_TMP)\\Delete-SandboxVMs.ps1'\""
	$(SSH) "powershell -NoProfile -Command \"Remove-Item -Recurse -Force '$(REMOTE_TMP)' -ErrorAction SilentlyContinue\""
