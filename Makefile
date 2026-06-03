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

## Fetch the BSD-licensed MIDISpy sources into third_party/MIDISpy.
vendor-midispy:
	@if [ -d third_party/MIDISpy/.git ]; then \
		echo "MIDISpy already vendored"; \
	else \
		git clone --depth 1 $(MIDISPY_REPO) third_party/MIDISpy/_src; \
		echo "Copy the MIDISpy framework/client sources out of _src as needed."; \
	fi

## Install the MIDISpy CoreMIDI driver into the user MIDI Drivers directory.
install-driver:
	@mkdir -p "$(DRIVER_DIR)"
	@echo "Place the built MIDISpy .driver bundle into: $(DRIVER_DIR)"

clean:
	swift package clean
	rm -rf .build
