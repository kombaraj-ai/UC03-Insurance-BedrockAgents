.PHONY: fmt validate lint checkov test preflight seed-policies seed-claims upload-kb-docs

TF_MODULES := $(shell find infra/modules -mindepth 1 -maxdepth 1 -type d)
TF_LIVE := infra/live/dev
SERVICES := services/policy_handler services/claims_handler services/kb_sync_handler services/client_api_handler
PYTHON ?= .venv/Scripts/python.exe

fmt:
	terraform fmt -recursive infra

validate:
	@for m in $(TF_MODULES) $(TF_LIVE); do \
		echo "==> validating $$m"; \
		(cd $$m && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

# Requires tflint + the aws ruleset plugin: https://github.com/terraform-linters/tflint
lint:
	@for m in $(TF_MODULES) $(TF_LIVE); do \
		echo "==> tflint $$m"; \
		(cd $$m && tflint) || exit 1; \
	done

# Requires checkov: pip install checkov
checkov:
	checkov -d infra --config-file .checkov.yaml

test:
	@for s in $(SERVICES); do \
		echo "==> pytest $$s"; \
		$(PYTHON) -m pytest $$s/tests -v || exit 1; \
	done

# Full local substitute for CI -- run before every `terraform apply`.
preflight: fmt validate test
	@echo "preflight OK (run 'make lint' / 'make checkov' too if those tools are installed)"

# --- Data seeding / KB doc upload (run once after the first apply) ---------

seed-policies:
	$(PYTHON) data-seed/seed_policies.py \
		--table $$(cd $(TF_LIVE) && terraform output -raw policies_table_name)

seed-claims:
	$(PYTHON) data-seed/seed_claims.py \
		--table $$(cd $(TF_LIVE) && terraform output -raw claims_table_name)

upload-kb-docs:
	bash knowledge-base/upload_seed_docs.sh \
		$$(cd $(TF_LIVE) && terraform output -raw kb_source_bucket_name)
