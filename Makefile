# ==============================================================================
# Makefile for Daemonette (Vala + Meson + Ninja wrapper)
# ==============================================================================

BUILD_DIR ?= build
BINARY    ?= $(BUILD_DIR)/daemonette
TEST_BIN  ?= $(BUILD_DIR)/daemonette-tests

ARGS      ?=

.DEFAULT_GOAL := help

.PHONY: all build setup run test clean distclean install uninstall release deb tarball help

## help: Display this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@echo "  build       Compile Daemonette and test binaries (sets up build/ if missing)"
	@echo "  run         Compile and run Daemonette"
	@echo "  test        Compile and run the unit test suite"
	@echo "  deb         Build standalone Debian/Ubuntu .deb package"
	@echo "  tarball     Build standalone universal Linux .tar.gz archive"
	@echo "  clean       Remove compiled binaries and object files inside $(BUILD_DIR)/"
	@echo "  distclean   Completely delete the $(BUILD_DIR)/ directory"
	@echo "  install     Install Daemonette to the system (may require sudo)"
	@echo "  uninstall   Remove Daemonette from the system (may require sudo)"
	@echo "  release     Bump version everywhere for a release (usage: make release VERSION=1.2.0)"
	@echo "  help        Show this help message"

# Configure the Meson build directory if it doesn't already exist
$(BUILD_DIR)/build.ninja:
	meson setup $(BUILD_DIR)

## setup: Initialize the Meson build directory
setup: $(BUILD_DIR)/build.ninja

## build: Compile all targets using Ninja
build: setup
	ninja -C $(BUILD_DIR)

all: build

## run: Build and launch Daemonette (pass flags via ARGS="...", e.g. make run ARGS="--version")
run: build
	./$(BINARY) $(ARGS)

## test: Build and execute the test suite with verbose output
test: build
	meson test -C $(BUILD_DIR) --verbose

## deb: Build a standalone .deb package for Debian/Ubuntu distributions
deb: build
	@./scripts/build_deb.sh

## release: Bump the app version across meson.build, metainfo and RPM changelog
release:
	@./scripts/release.sh "$(VERSION)"

## tarball: Build a portable universal Linux tarball (.tar.gz)
tarball: build
	@./scripts/build_tarball.sh

## clean: Clean compiled artifacts without removing Meson configuration
clean:
	@if [ -d "$(BUILD_DIR)" ] && [ -f "$(BUILD_DIR)/build.ninja" ]; then \
		ninja -C $(BUILD_DIR) clean; \
	fi

## distclean: Completely wipe the build directory
distclean:
	rm -rf $(BUILD_DIR)

## install: Install Daemonette into prefix directory (system-wide)
install: build
	ninja -C $(BUILD_DIR) install

## uninstall: Uninstall Daemonette from prefix directory
uninstall:
	ninja -C $(BUILD_DIR) uninstall
