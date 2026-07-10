# Makefile for Millennium Helpers local development automation

.PHONY: setup test test-windows lint format check-all check-version check-man check-winget check-completions sync-pkgver test-debian test-ubuntu test-fedora test-all-distros

setup:
	@echo "Setting up local development dependencies..."
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
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoProfile -Command "Invoke-Pester -Path tests/windows -Output Detailed"; \
	else \
		echo "pwsh not found; skip Windows Pester suite (install PowerShell 7+)." >&2; \
		exit 1; \
	fi

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

check-winget:
	bash scripts/ci/check-winget-manifests.sh

check-completions:
	bash tests/unit/test_completions.sh

# Refresh packaging/PKGBUILD pkgver + .SRCINFO from git HEAD (no build/install).
sync-pkgver:
	bash scripts/ci/update-pkgbuild-pkgver.sh

lint:
	shellcheck *.sh scripts/*.sh scripts/lib/*.sh scripts/ci/*.sh tests/*.sh tests/lib/*.sh tests/unit/*.sh tests/behavioral/*.sh
	ruff check scripts/millennium-mcp.py
	@test -s VERSION || (echo "VERSION file missing or empty" >&2; exit 1)
	@$(MAKE) check-version
	@$(MAKE) check-man
	@$(MAKE) check-completions

format:
	ruff format scripts/millennium-mcp.py

check-all: lint test
