# Makefile for Millennium Helpers local development automation

.PHONY: setup test test-windows test-go build lint lint-go format check-all check-version check-man check-docs check-licensing check-winget check-packaging check-completions check-cli-contract sync-git-srcinfo sync-stable-srcinfo sync-bin-srcinfo bump-version test-debian test-ubuntu test-fedora test-all-distros

GO ?= go
CGO_ENABLED ?= 0
GO_LDFLAGS := -X github.com/bolens/millenium-helpers/internal/version.Version=$(shell tr -d '\n' < VERSION)

setup:
	@echo "Setting up local development dependencies..."
	@echo "Note: make setup only installs shellcheck + ruff."
	@echo "See CONTRIBUTING.md#development-requirements for pwsh, Docker, Go, zsh/fish/nu, etc."
	@if command -v brew >/dev/null 2>&1; then \
		echo "Detected Homebrew. Installing shellcheck and ruff..."; \
		brew install shellcheck ruff; \
	elif command -v pacman >/dev/null 2>&1; then \
		echo "Detected pacman. Installing shellcheck and ruff..."; \
		sudo pacman -S --noconfirm shellcheck ruff; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "Detected apt. Installing shellcheck and ruff..."; \
		sudo apt-get update && sudo apt-get install -y shellcheck ruff; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "Detected dnf. Installing shellcheck and ruff..."; \
		sudo dnf install -y shellcheck ruff; \
	else \
		echo "Could not detect package manager. Please install shellcheck and ruff manually." >&2; \
	fi

test:
	bash tests/run_tests.sh

test-windows:
	@if ! command -v pwsh >/dev/null 2>&1; then \
		echo "pwsh not found; skip Windows Pester suite (install PowerShell 7+)." >&2; \
		exit 1; \
	fi; \
	if ! pwsh -NoProfile -Command 'if (Get-Command Invoke-Pester -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }'; then \
		echo "Pester not installed; skip Windows Pester suite locally (CI Windows job still runs it)." >&2; \
		exit 0; \
	fi; \
	pwsh -NoProfile -Command "Invoke-Pester -Path tests/windows -Output Detailed"

test-go:
	@command -v $(GO) >/dev/null 2>&1 || (echo "go not found; install Go 1.22+ (see CONTRIBUTING.md)." >&2; exit 1)
	cd go && CGO_ENABLED=$(CGO_ENABLED) $(GO) test ./...

build:
	@command -v $(GO) >/dev/null 2>&1 || (echo "go not found; install Go 1.22+ (see CONTRIBUTING.md)." >&2; exit 1)
	mkdir -p bin
	cd go && CGO_ENABLED=$(CGO_ENABLED) $(GO) build -buildvcs=false -ldflags "$(GO_LDFLAGS)" -o ../bin/millennium ./cmd/millennium
	@echo "built bin/millennium"

test-debian:
	docker run --rm -v $$(pwd):/workspace -w /workspace debian:12 bash tests/run_tests.sh

test-ubuntu:
	docker run --rm -v $$(pwd):/workspace -w /workspace ubuntu:24.04 bash tests/run_tests.sh

test-fedora:
	docker run --rm -v $$(pwd):/workspace -w /workspace fedora:latest bash tests/run_tests.sh

test-all-distros: test test-debian test-ubuntu test-fedora

check-version:
	bash scripts/ci/check-version-sync.sh

check-man:
	bash scripts/ci/check-man-pages.sh

check-docs:
	bash scripts/ci/check-docs-crosslinks.sh

# Alias — licensing asserts are part of check-docs
check-licensing: check-docs

check-winget:
	bash scripts/ci/check-winget-manifests.sh

check-packaging:
	bash scripts/ci/check-packaging-manifests.sh

check-completions:
	bash tests/unit/test_completions.sh

check-cli-contract:
	python3 scripts/ci/check-cli-contract.py

# Regenerate packaging/millennium-helpers-git/.SRCINFO when the -git recipe changes.
# Does not bump pkgver every commit (AUR VCS policy). See CONTRIBUTING.md § Versioning.
sync-git-srcinfo:
	bash scripts/ci/sync-git-srcinfo.sh

# Regenerate packaging/millennium-helpers/.SRCINFO from PKGBUILD (from-source).
# See CONTRIBUTING.md § Versioning.
sync-stable-srcinfo:
	bash scripts/ci/sync-stable-srcinfo.sh

# Regenerate packaging/millennium-helpers-bin/.SRCINFO from PKGBUILD.
sync-bin-srcinfo:
	bash scripts/ci/sync-bin-srcinfo.sh

# Pre-tag bump: VERSION + packaging URLs/versions (keeps hashes). Usage: make bump-version VERSION=X.Y.Z
# See CONTRIBUTING.md § Versioning and docs/release_runbook.md.
bump-version:
	@test -n "$(VERSION)" || (echo "usage: make bump-version VERSION=X.Y.Z" >&2; exit 2)
	bash scripts/ci/bump-version.sh "$(VERSION)"


lint-go:
	@command -v $(GO) >/dev/null 2>&1 || (echo "go not found; install Go 1.22+ (see CONTRIBUTING.md)." >&2; exit 1)
	cd go && $(GO) vet ./...
	@out="$$(cd go && find . -name '*.go' -print0 | xargs -0 gofmt -l)"; \
		if [ -n "$$out" ]; then printf 'gofmt needed:\n%s\n' "$$out" >&2; exit 1; fi
	bash scripts/ci/check-govulncheck.sh

lint:
	shellcheck *.sh scripts/*.sh scripts/ci/*.sh tests/*.sh tests/lib/*.sh tests/unit/*.sh tests/behavioral/*.sh
	ruff check scripts/ci/check-cli-contract.py
	@test -s VERSION || (echo "VERSION file missing or empty" >&2; exit 1)
	@$(MAKE) check-version
	@$(MAKE) check-man
	@$(MAKE) check-docs
	@$(MAKE) check-completions
	@$(MAKE) check-cli-contract
	@$(MAKE) lint-go

format:
	ruff format scripts/ci/check-cli-contract.py

# Feature / CLI parity: test-go (+ CI go.yml on Linux/Windows/macOS).
# test = install-time Bash unit/behavioral (install, libs, packaging, completions).
check-all: lint test-go test
