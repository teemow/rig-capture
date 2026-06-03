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
	@find third_party/MIDISpy/_src -name 'MIDISpyClient.h' -o -name 'MessagePortBroadcaster.h' \
		-o -name 'MessageQueue.h' | while read -r f; do cp "$$f" Sources/CSpy/include/; done
	@find third_party/MIDISpy/_src -name 'MIDISpyClient.m' -o -name 'MessagePortBroadcaster.m' \
		-o -name 'MessageQueue.m' | while read -r f; do cp "$$f" Sources/CSpy/; done
	@if [ -f Sources/CSpy/include/MIDISpyClient.h ]; then \
		echo "OK: MIDISpyClient.h in place; CSpy will compile the real tap."; \
	else \
		echo "WARN: MIDISpyClient.h not found in the clone; verify the repo layout."; \
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
