SHELL := /bin/bash

MIDISPY_REPO ?= https://github.com/krevis/MIDIApps.git
DRIVER_DIR := $(HOME)/Library/Audio/MIDI Drivers

.PHONY: build release test format lint hidhook vendor-midispy install-driver clean

## Build the rig-capture executable (debug).
build:
	swift build

## Build optimized.
release:
	swift build -c release

## Run the decoder tests.
test:
	swift test

## Format Swift sources in place.
format:
	swift-format format -i -r Sources decoders Tests

## Lint Swift sources (used in CI).
lint:
	swift-format lint -r -s Sources decoders Tests

## Build just the injectable HID-hook dylib.
hidhook:
	swift build --product CHidHook
	@echo "dylib: $$(swift build --product CHidHook --show-bin-path)/libCHidHook.dylib"

## Fetch the BSD-licensed MIDISpy sources and copy the client shim sources into
## the CSpy target. With MIDISpyClient.h present, CSpy compiles the real tap
## (guarded by __has_include); without it, CSpy builds as a clean stub.
vendor-midispy:
	@if [ ! -d third_party/MIDISpy/_src/.git ]; then \
		git clone --depth 1 $(MIDISPY_REPO) third_party/MIDISpy/_src; \
	else \
		echo "MIDISpy sources already cloned in third_party/MIDISpy/_src"; \
	fi
	@echo "Copying MIDISpy client sources into Sources/CSpy ..."
	@# The client is a pure-C CFMessagePort implementation: MIDISpyClient.c plus
	@# its two headers. They are kept private (next to CSpy.c, not in include/) so
	@# they stay out of the public CSpy module. CSpy.c #include-guards on them, so
	@# without these files it builds as a clean stub (green CI without the
	@# BSD-licensed sources).
	@for n in MIDISpyClient.c MIDISpyClient.h MIDISpyShared.h; do \
		f=$$(find third_party/MIDISpy/_src -name "$$n" | head -1); \
		if [ -n "$$f" ]; then cp "$$f" Sources/CSpy/; else echo "WARN: $$n not found in clone"; fi; \
	done
	@if [ -f Sources/CSpy/MIDISpyClient.c ] && [ -f Sources/CSpy/MIDISpyClient.h ] && [ -f Sources/CSpy/MIDISpyShared.h ]; then \
		echo "OK: MIDISpy client sources in place; CSpy will compile the real tap."; \
	else \
		echo "WARN: MIDISpy sources incomplete; CSpy will build as the stub."; \
	fi

## Install the MIDISpy CoreMIDI driver into the user MIDI Drivers directory.
## The driver bundle is built from the vendored sources (Xcode project) or
## copied from an existing MIDI Monitor install; this only ensures the dir.
install-driver:
	@mkdir -p "$(DRIVER_DIR)"
	@echo "Place the built MIDISpy .driver bundle into: $(DRIVER_DIR)"
	@echo "(MIDISpyInstallDriverIfNecessary also installs a bundled copy at first run.)"

clean:
	swift package clean
	rm -rf .build
