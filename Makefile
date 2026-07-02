# Makefile for Millennium Helpers local development automation

.PHONY: test lint format check-all

test:
	bash tests/run_tests.sh

lint:
	shellcheck *.sh scripts/*.sh tests/*.sh tests/unit/*.sh tests/behavioral/*.sh
	ruff check scripts/millennium-mcp.py

format:
	ruff format scripts/millennium-mcp.py

check-all: lint test
