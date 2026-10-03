# Nomad: personal cloud dev box. One command: `make up`. See README.md.

SHELL   := /bin/bash
TF      := terraform -chdir=terraform
REGION  ?= us-east-1
PROJECT ?= nomad

export TF_VAR_region := $(REGION)
# AWS CLI v2 shows output in a pager (less) when it goes to a terminal, which
# takes over the screen and waits for `q`. Never page anything make runs.
export AWS_PAGER :=
# The box's name (AWS tags and its tailnet name) follows PROJECT, so a second box,
# e.g. `make up PROJECT=nomadtest REGION=us-west-2`, is fully separate: its own
# state bucket, AWS resources and tailnet name.
export TF_VAR_name := $(PROJECT)
export TF_VAR_tailscale_hostname := $(PROJECT)

# Deterministic, globally-unique Terraform state bucket derived from the AWS
# account, so there is nothing to name or wire up by hand. Lazy (=) so plain
# `make help` does not call AWS.
# Looked up once, on first use (after preflight has signed you in), then reused.
ACCOUNT_ID   = $(eval ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null))$(ACCOUNT_ID)
STATE_BUCKET = $(PROJECT)-tfstate-$(ACCOUNT_ID)-$(REGION)
STATE_KEY    = $(PROJECT)/terraform.tfstate

# Hands Terraform the AWS CLI's current credentials, however you signed in
# (access keys, `aws login` console sign-in, SSO), so it never has to support
# each method itself.
AWS_CREDS = eval "$$(aws configure export-credentials --format env 2>/dev/null)";

# Output styling (matches lib/ui.sh) and quiet SSH (no "Permanently added" notes).
OK  := \033[38;5;114m
BAD := \033[38;5;203m
DIM := \033[38;5;244m
R   := \033[0m
SSH_OPTS := -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR

.PHONY: help up down ssh plan init ensure-state fmt bootstrap preflight settings lock check

help:
	@echo "Nomad: personal cloud dev box"
	@echo ""
	@echo "  make up         Everything: checks/installs AWS CLI + Terraform, signs you in to AWS,"
	@echo "                  creates (or updates) the box, waits for it on your tailnet, then"
	@echo "                  installs the dev environment. SKIP_BOOTSTRAP=1 to stop after Terraform."
	@echo "  make bootstrap  (Re)install the dev environment on the box (over your tailnet)."
	@echo "  make settings   Review your git identity and sign-in accounts (config/)."
	@echo "  make lock       Turn on tailnet lock (new devices need your approval to join)."
	@echo "  make ssh        Connect: ssh ubuntu@$(PROJECT) (over your tailnet)"
	@echo "  make plan       Preview changes"
	@echo "  make down       Tear everything down (and offer to remove it from your tailnet)"
	@echo "  make fmt        terraform fmt"
	@echo "  make check      Run the checks every pull request must pass"
	@echo ""
	@echo "First time: just run make up. It walks you through AWS and Tailscale."

# Idempotent: create the state bucket only if it does not already exist.
ensure-state:
	@test -n "$(ACCOUNT_ID)" || { printf '  $(BAD)✗ Not signed in to AWS. Run make up (it walks you through it), or set AWS_PROFILE.$(R)\n'; exit 1; }
	@aws s3api head-bucket --bucket "$(STATE_BUCKET)" >/dev/null 2>&1 || { \
		aws s3api create-bucket --bucket "$(STATE_BUCKET)" --region "$(REGION)" \
			$(if $(filter us-east-1,$(REGION)),,--create-bucket-configuration LocationConstraint=$(REGION)) >/dev/null; \
		aws s3api put-bucket-versioning --bucket "$(STATE_BUCKET)" --versioning-configuration Status=Enabled; \
		aws s3api put-bucket-encryption --bucket "$(STATE_BUCKET)" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'; \
		aws s3api put-public-access-block --bucket "$(STATE_BUCKET)" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true; \
		printf '  $(OK)✓$(R) %-18s $(DIM)created s3://%s (encrypted, versioned, private)$(R)\n' "State bucket" "$(STATE_BUCKET)"; \
	}

# Checks this computer and offers to fix what is missing (see bootstrap/preflight.sh).
preflight:
	@bash bootstrap/preflight.sh

# Your git identity and sign-in accounts for the box, saved in config/
# (gitignored). make up asks only for what is missing; this reviews everything.
settings:
	@bash bootstrap/settings.sh --edit

# Tailnet lock: new devices join only with a signing device's approval.
# Signers: this computer and the box. Shows recovery secrets to save.
lock:
	@bash bootstrap/tailscale.sh lock $(PROJECT)

# make up's version: asks only for what is not saved yet.
.PHONY: _settings
_settings:
	@bash bootstrap/settings.sh

init: ensure-state
	@log="$$(mktemp)"; $(AWS_CREDS) $(TF) init -input=false -reconfigure -no-color \
		-backend-config="bucket=$(STATE_BUCKET)" \
		-backend-config="key=$(STATE_KEY)" \
		-backend-config="region=$(REGION)" \
		-backend-config="encrypt=true" \
		-backend-config="use_lockfile=true" >"$$log" 2>&1 \
	&& { printf '  $(OK)✓$(R) %-18s $(DIM)ready · s3://%s$(R)\n' "Terraform state" "$(STATE_BUCKET)"; rm -f "$$log"; } \
	|| { cat "$$log"; rm -f "$$log"; printf '  $(BAD)✗ Terraform init failed (above).$(R)\n'; exit 1; }

# One command, start to finish: check this computer, your settings, Terraform
# (bootstrap/apply.sh: plan, summarize, confirm, apply; a new box joins your
# tailnet first), then wait for the box and run `make bootstrap`.
up: preflight _settings init
	@$(AWS_CREDS) bash bootstrap/apply.sh $(PROJECT) $(REGION)
	@# Plain `make`, not $$(MAKE): make runs any line naming $$(MAKE) even under
	@# `make -n`, and nothing here should run during a dry run. The sub-make still
	@# inherits PROJECT, REGION and the like through MAKEFLAGS.
	@[ -n "$(SKIP_BOOTSTRAP)" ] || { bash bootstrap/wait-for-box.sh $(PROJECT) && make --no-print-directory bootstrap; }
	@# A just-created box: offer tailnet lock once (make lock any time later).
	@if [ -f terraform/.nomad-new-box ] && [ -z "$(SKIP_BOOTSTRAP)" ]; then \
		rm -f terraform/.nomad-new-box; bash bootstrap/tailscale.sh lock $(PROJECT) --offer; fi

plan: init
	@$(AWS_CREDS) $(TF) plan

# Destroys the box and everything Terraform made for it (you type its name to
# confirm), then offers to remove it from your tailnet too (bootstrap/destroy.sh).
down: init
	@$(AWS_CREDS) bash bootstrap/destroy.sh $(PROJECT) $(REGION)

ssh:
	@ssh $(SSH_OPTS) ubuntu@$(PROJECT)

# Install (or update) the full dev environment on the box. Idempotent: safe to
# re-run after editing bootstrap/setup.sh. Runs over the tailnet, so it must be
# invoked from a machine on your tailnet (phone/laptop), not from CI. Credentials
# are still seeded by hand afterwards (see README).
# Copies bin/, lib/, auth/, config/ and skills/ too: setup.sh installs the
# helper scripts (t, auth, note), their shared code, your sign-in settings and
# the Claude Code skills.
bootstrap:
	@bash bootstrap/ssh-alias.sh add $(PROJECT)
	@ssh $(SSH_OPTS) ubuntu@$(PROJECT) 'rm -rf /tmp/nomad && mkdir -p /tmp/nomad'
	@scp -q -r $(SSH_OPTS) bootstrap bin lib auth config skills ubuntu@$(PROJECT):/tmp/nomad/
	@ssh $(SSH_OPTS) ubuntu@$(PROJECT) "NOMAD_HOSTNAME=$(PROJECT) NOMAD_CONNECT='$$(bash bootstrap/ssh-alias.sh connect $(PROJECT))' bash /tmp/nomad/bootstrap/setup.sh"

fmt:
	@$(TF) fmt

# The checks every pull request must pass (scripts/check.sh; CI runs the same).
check:
	@bash scripts/check.sh
