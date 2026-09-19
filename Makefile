VERSION = $(shell cat version)
LIBRARY_DIR = /usr/local/lib/pam
LIBRARY_PREFIX = pam_watchid
LIBRARY_NAME = $(LIBRARY_PREFIX).so
LIBRARY_PATH = $(LIBRARY_DIR)/$(LIBRARY_NAME)
TARGET = apple-macosx10.15
# Host architecture only: the module is built where it runs, and macOS 27 toolchains no
# longer ship the x86_64 Swift compatibility libraries a universal build needs.
ARCH = $(shell uname -m)

all:
ifeq ($(shell [[ '$(shell xcode-select -p)' == '/Library/Developer/CommandLineTools' ]] && echo true),true)
# Legacy build
# For CLT due to poor support for building swift packages.
# Swift packages do work in macOS Sonoma and later with the CLT, but are an order of magnitude slower than Xcode.
	swiftc -O Sources/pam-watchid/pam_watchid.swift -o $(LIBRARY_NAME) -target $(ARCH)-$(TARGET) -emit-library
else
# Swift Package Manager build
	swift build -c release
	cp .build/release/libpam-watchid.dylib $(LIBRARY_NAME)
endif

# Installs the module only; wiring it into /etc/pam.d/sudo_local is left to the caller.
install: all
	sudo mkdir -p $(LIBRARY_DIR)
	sudo install -o root -g wheel -m 444 $(LIBRARY_NAME) $(LIBRARY_PATH).$(VERSION)

.PHONY: all install
