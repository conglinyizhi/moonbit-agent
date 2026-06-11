SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

ROOT := $(abspath .)
MOON := moon
TARGET := native
CONFIG ?= agent.example.toml

AGENT_EXE := ./_build/$(TARGET)/debug/build/cmd/agent/agent.exe
BETOOLS_EXE := ./_build/$(TARGET)/debug/build/cmd/better-edit-tools/better-edit-tools.exe

.PHONY: help build build-agent build-betools run agent betools mock-server mock-e2e \
	test test-agent test-betools clean

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make build         Build all native targets' \
		'  make build-agent   Build the agent executable' \
		'  make build-betools Build the better-edit-tools executable' \
		'  make run           Run the agent executable (CONFIG=agent.toml by default)' \
		'  make agent         Alias of make run' \
		'  make betools       Run the MCP tool server executable' \
		'  make mock-server   Run the mock chat completions server (.mbtx)' \
		'  make mock-e2e      Run the local mock end-to-end tool-call check' \
		'  make test          Run agent and betools native tests' \
		'  make test-agent    Run agent native tests' \
		'  make test-betools  Run betools native tests' \
		'  make clean         Remove build artifacts'

build:
	$(MOON) build --target $(TARGET)

build-agent:
	$(MOON) build cmd/agent --target $(TARGET)

build-betools:
	$(MOON) build cmd/better-edit-tools --target $(TARGET)

run: build-agent
	$(AGENT_EXE) --config $(CONFIG)

agent: run

betools: build-betools
	$(BETOOLS_EXE)

mock-server:
	$(MOON) run scripts/mock_chat_completions.mbtx --target $(TARGET)

mock-e2e:
	$(MOON) run scripts/run_mock_e2e.mbtx --target $(TARGET) $(ROOT)

test: test-agent test-betools

test-agent:
	$(MOON) test lib/agent --target $(TARGET)

test-betools:
	$(MOON) test lib/betools --target $(TARGET)

clean:
	$(MOON) clean
	rm -rf scripts/_build scripts/.mooncakes
