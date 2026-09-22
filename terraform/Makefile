# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  Makefile  -  operacje na podzielonym labie / split-lab operations
# ----------------------------------------------------------------------------
#  PL: Lab jest podzielony na TRZY rooty z osobnym stanem:
#        base/       - pula golden + golden images + sieć lab  (BUDUJ PIERWSZY)
#        testboxes/  - deb11-13, ubu2204/2404/2604
#        infra/      - kdev, pbs, awx, docker, mon
#      Większość celów działa w katalogu wskazanym przez DIR (domyślnie
#      testboxes). Przykłady:
#        make base                         - zbuduj warstwę bazową
#        make apply DIR=testboxes          - zbuduj maszyny testowe
#        make plan  DIR=infra              - plan dla infra
#        make apply DIR=testboxes ONLY='["testdeb"]'   - tylko grupa testdeb
#        make restore DIR=testboxes VM=deb13           - odtwórz jedną VM
#        make restore DIR=testboxes GROUP=testdeb      - odtwórz grupę
#        make resize  VM=deb13 GB=30       - powiększ dysk (virsh, bez DIR)
#  EN: The lab is split into THREE roots with separate state: base/ (build
#      first), testboxes/, infra/. Most targets act in DIR (default testboxes).
# ============================================================================

TF   ?= terraform          # narzędzie / tool (terraform albo tofu)
URI  ?= qemu:///system     # libvirt URI
POOL ?= images             # pula z dyskami VM / pool holding VM disks
DIR  ?= testboxes          # base | testboxes | infra
ONLY ?=                    # filtr grup, np. '["testdeb"]' / group filter

# --- SSH: user / klucz / plik configu dla `make ssh-config` ------------------
# PL: Konto i klucz wstrzykiwane przez cloud-init (patrz testboxes/variables.tf:
#     username=admin, ssh_public_key_path=~/.ssh/id_ed25519.pub => klucz
#     PRYWATNY to ta sama ścieżka bez ".pub"). CONFLAB = generowany plik SSH,
#     ROOTS = katalogi-rooty, których VM mają trafić do configu.
# EN: Account/key injected by cloud-init. CONFLAB = generated ssh config file.
SSHUSER ?= admin
SSHKEY  ?= $(HOME)/.ssh/id_ed25519
CONFLAB ?= $(HOME)/.ssh/config-lab
ROOTS   ?= testboxes infra
# PL: JUMP = host przeskokowy (ProxyJump), gdy VM działają na innym hoście niż ten,
#     na którym generujemy config (maszyny na osobnym hoscie labu, ssh ze stacji roboczej - te same
#     podsieci NAT, więc bez przeskoku adres trafiłby do lokalnego virbr). Razem z
#     URI=qemu+ssh://<host>/system, np.:
#       make ssh-config URI=qemu+ssh://lab-host/system JUMP=lab-host
# EN: JUMP = ProxyJump host for VMs running on a remote libvirt host (pair with URI).
JUMP    ?=
JUMPLINE := $(if $(JUMP),    ProxyJump $(JUMP)\n,)

# PL: Jeśli ONLY ustawione, doklej -var='only_groups=...' do plan/apply.
# EN: If ONLY is set, append -var='only_groups=...' to plan/apply.
ONLYVAR := $(if $(ONLY),-var='only_groups=$(ONLY)',)

.DEFAULT_GOAL := help
.PHONY: help init plan apply destroy fmt validate base all groups ips \
        restore resize up down console ssh ssh-config

help: ## PL: ta pomoc / EN: this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	 awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- podstawy (działają w $(DIR)) / basics (operate in $(DIR)) ---------------
init: ## init wybranego roota / init the selected root (DIR=...)
	cd $(DIR) && $(TF) init

plan: ## plan roota / plan (DIR=..., ONLY='["testdeb"]')
	cd $(DIR) && $(TF) plan $(ONLYVAR)

apply: ## apply roota / apply (DIR=..., ONLY=...)
	cd $(DIR) && $(TF) apply $(ONLYVAR)

destroy: ## destroy roota / destroy ONE root (DIR=...)
	cd $(DIR) && $(TF) destroy $(ONLYVAR)

validate: ## validate roota / validate (DIR=...)
	cd $(DIR) && $(TF) validate

fmt: ## sformatuj wszystko / format the whole tree
	$(TF) fmt -recursive

# --- skróty na warstwy / layer shortcuts ------------------------------------
base: ## zbuduj warstwę bazową / build the base layer (pool, images, lab net)
	cd base && $(TF) init -input=false && $(TF) apply

all: ## zbuduj wszystko po kolei / build base -> testboxes -> infra
	cd base       && $(TF) init -input=false && $(TF) apply -auto-approve
	cd testboxes  && $(TF) init -input=false && $(TF) apply -auto-approve
	cd infra      && $(TF) init -input=false && $(TF) apply -auto-approve

# --- podgląd / inspection (w $(DIR)) ----------------------------------------
groups: ## wypisz grupy i ich VM / list groups and their VMs (DIR=...)
	@cd $(DIR) && $(TF) output -json vms_by_group | jq -r 'to_entries[] | "\(.key): \(.value | join(", "))"'

ips: ## tabela VM: grupa / IP / running (DIR=...)
	@cd $(DIR) && $(TF) output -json vms | jq -r 'to_entries[] | "\(.key)\t\(.value.group)\t\(.value.ip)\trunning=\(.value.running)"' | column -t

# PL: Generuje ~/.ssh/config-lab z ŻYWYMI IP (agent QEMU, fallback lease) dla VM
#     z rootów $(ROOTS) - `ssh deb11` działa bez DNS i bez roota. Plik jest W CAŁOŚCI
#     AUTO (nadpisywany), z backupem .bak. TRWAŁE wpisy (maszyny spoza tego kodu) trzymaj
#     w ~/.ssh/config-lab-persist (make go NIE rusza). User=$(SSHUSER), klucz=$(SSHKEY).
# EN: Writes ~/.ssh/config-lab (fully auto, backed up to .bak). Keep persistent hosts
#     in ~/.ssh/config-lab-persist. `ssh deb11` then works without DNS/root.
ssh-config: ## wygeneruj ~/.ssh/config-lab (auto, +backup .bak); trwałe wpisy -> config-lab-persist
	@command -v virsh >/dev/null || { echo "Brak virsh."; exit 1; }
	@[ -f $(CONFLAB) ] && cp -f $(CONFLAB) $(CONFLAB).bak || true
	@{ echo "# AUTO - generowane przez 'make ssh-config', NADPISYWANE W CAŁOŚCI."; \
	   echo "# Trwałe wpisy trzymaj w ~/.ssh/config-lab-persist (make go nie dotyka)."; \
	   echo "# generated $$(date)"; \
	   echo "# źródło IP: $(strip $(URI))$(if $(JUMP), | ProxyJump: $(JUMP),)"; echo; \
	   for r in $(ROOTS); do \
	     [ -f $$r/terraform.tfstate ] || continue; \
	     for v in $$(cd $$r && $(TF) output -json vms 2>/dev/null | jq -r 'keys[]?'); do \
	       ip=$$(virsh -c $(URI) domifaddr $$v --source agent 2>/dev/null | awk '/ipv4/{print $$4}' | cut -d/ -f1 | grep -v '^127' | head -1); \
	       [ -z "$$ip" ] && ip=$$(virsh -c $(URI) domifaddr $$v 2>/dev/null | awk '/ipv4/{print $$4}' | cut -d/ -f1 | grep -v '^127' | head -1); \
	       [ -z "$$ip" ] && { echo "   pomijam $$v (brak IP)" >&2; continue; }; \
	       printf 'Host %s\n    HostName %s\n$(JUMPLINE)    User %s\n    IdentityFile %s\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n\n' "$$v" "$$ip" "$(SSHUSER)" "$(SSHKEY)"; \
	     done; \
	   done; } > $(CONFLAB)
	@echo ">> zapisano $(CONFLAB) (backup: $(CONFLAB).bak):"; grep -E '^Host ' $(CONFLAB) 2>/dev/null || echo "   (brak VM z IP)"
	@echo ">> jednorazowo w ~/.ssh/config:  Include ~/.ssh/config-lab-persist  oraz  Include ~/.ssh/config-lab"

# --- ODTWARZANIE "na części" / partial RESTORE ------------------------------
# PL: -replace na ADRESACH W MODULE: zasoby VM żyją teraz w module.vms.*
# EN: -replace on MODULE addresses: VM resources now live under module.vms.*
restore: ## odtwórz VM=<nazwa> LUB GROUP=<grupa> w DIR / rebuild one VM or a group
ifdef VM
	cd $(DIR) && $(TF) apply \
	  -target='module.vms.libvirt_volume.vm_disk["$(VM)"]' \
	  -target='module.vms.libvirt_cloudinit_disk.vm_init["$(VM)"]' \
	  -target='module.vms.libvirt_domain.vm["$(VM)"]' \
	  -replace='module.vms.libvirt_volume.vm_disk["$(VM)"]' \
	  -replace='module.vms.libvirt_cloudinit_disk.vm_init["$(VM)"]' \
	  -replace='module.vms.libvirt_domain.vm["$(VM)"]'
else ifdef GROUP
	@cd $(DIR) && vms=$$($(TF) output -json vms_by_group | jq -r --arg g "$(GROUP)" '.[$$g][]?'); \
	if [ -z "$$vms" ]; then echo "Brak grupy / no such group: $(GROUP) w DIR=$(DIR). Dostępne / available:"; \
	  $(TF) output -json vms_by_group | jq -r 'keys[]'; exit 1; fi; \
	flags=""; for v in $$vms; do \
	  flags="$$flags -target=module.vms.libvirt_volume.vm_disk[\"$$v\"] -target=module.vms.libvirt_cloudinit_disk.vm_init[\"$$v\"] -target=module.vms.libvirt_domain.vm[\"$$v\"]"; \
	  flags="$$flags -replace=module.vms.libvirt_volume.vm_disk[\"$$v\"] -replace=module.vms.libvirt_cloudinit_disk.vm_init[\"$$v\"] -replace=module.vms.libvirt_domain.vm[\"$$v\"]"; \
	done; \
	echo ">> odtwarzam / rebuilding [$(GROUP)] w DIR=$(DIR): $$vms"; \
	$(TF) apply $$flags
else
	@echo "Użycie / Usage: make restore DIR=testboxes VM=deb13   |   make restore DIR=testboxes GROUP=testdeb"
endif

# --- POWIĘKSZANIE DYSKU (virsh, niezależne od DIR) / disk GROW --------------
resize: ## powiększ dysk / grow disk: make resize VM=deb13 GB=30
	@test -n "$(VM)" -a -n "$(GB)" || { echo "Użycie / Usage: make resize VM=deb13 GB=30"; exit 1; }
	virsh -c $(URI) vol-resize --pool $(POOL) "$(VM).img" $(GB)G
	-virsh -c $(URI) reboot $(VM)
	@echo ">> Po starcie sprawdź / after boot: df -h / (standardowy rozmiar ustaw przez disk_gib)"

# --- sterowanie pojedynczą VM (virsh) / single-VM control -------------------
up: ## włącz / start: make up VM=mon
	@test -n "$(VM)" || { echo "Użycie / Usage: make up VM=<nazwa>"; exit 1; }
	virsh -c $(URI) start $(VM)

down: ## wyłącz (graceful) / shutdown: make down VM=mon
	@test -n "$(VM)" || { echo "Użycie / Usage: make down VM=<nazwa>"; exit 1; }
	virsh -c $(URI) shutdown $(VM)

console: ## konsola szeregowa / serial console: make console VM=deb13
	@test -n "$(VM)" || { echo "Użycie / Usage: make console VM=<nazwa>"; exit 1; }
	virsh -c $(URI) console $(VM)

ssh: ## połącz po SSH / SSH in: make ssh DIR=testboxes VM=deb13
	@test -n "$(VM)" || { echo "Użycie / Usage: make ssh DIR=testboxes VM=deb13"; exit 1; }
	@cd $(DIR) && $(TF) output -json ssh | jq -r --arg v "$(VM)" '.[$$v]'
