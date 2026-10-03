.PHONY: build unit panel live test install cert cert-uninstall clean screenshots release

build:
	./build.sh

unit:
	mkdir -p build
	swiftc -swift-version 5 -O app/Core/*.swift tests/unit/*.swift -o build/unit && TRISPLIT_REPO=$(CURDIR) build/unit

panel:
	mkdir -p build
	swiftc -swift-version 5 -O -framework AppKit -framework WebKit tests/panel_runner.swift -o build/panel_runner && build/panel_runner panel.html tests/panel_tests.js

live: build
	./Trisplit.app/Contents/MacOS/Trisplit --selftest-live

test: unit panel

install: build
	rm -rf ~/Applications/Trisplit.app
	ditto --norsrc --noextattr Trisplit.app ~/Applications/Trisplit.app
	codesign --verify --deep --strict ~/Applications/Trisplit.app

cert:
	scripts/dev-cert.sh

cert-uninstall:
	scripts/dev-cert.sh --uninstall

screenshots:
	mkdir -p build/screenshot
	cp scripts/screenshot.swift build/screenshot/main.swift
	swiftc -swift-version 5 -O -framework AppKit -framework WebKit app/Core/*.swift app/Engine/*.swift app/Shell/AppIcons.swift build/screenshot/main.swift -o build/screenshot/screenshot
	build/screenshot/screenshot panel.html tests/fixtures/screenshot-state.json docs

release:
	scripts/release.sh

clean:
	rm -rf build Trisplit.app
