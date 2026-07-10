# Makefile for Millennium Helpers local development automation

.PHONY: test lint format check-all test-debian test-ubuntu test-fedora test-all-distros

test:
	bash tests/run_tests.sh

test-debian:
	docker run --rm -v $$(pwd):/workspace -w /workspace debian:12 bash tests/run_tests.sh

test-ubuntu:
	docker run --rm -v $$(pwd):/workspace -w /workspace ubuntu:24.04 bash tests/run_tests.sh

test-fedora:
	docker run --rm -v $$(pwd):/workspace -w /workspace fedora:latest bash tests/run_tests.sh

test-all-distros: test test-debian test-ubuntu test-fedora

lint:
	shellcheck *.sh scripts/*.sh scripts/lib/*.sh tests/*.sh tests/unit/*.sh tests/behavioral/*.sh
	ruff check scripts/millennium-mcp.py

format:
	ruff format scripts/millennium-mcp.py

check-all: lint test
