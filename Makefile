.PHONY: test app audit install snapshot icon clean

test:        ## Run all unit and real-system tests
	swift test

app:         ## Build dist/Vigil.app (ad-hoc signed)
	scripts/build-app.sh

audit:       ## Verify the safety claims against the source and the built app
	scripts/audit.sh

install: app ## Install into ~/Applications (no sudo)
	scripts/install.sh

snapshot:    ## Render the UI to PNGs from canned data (light + dark)
	swift build --product VigilApp
	.build/debug/VigilApp --snapshot dist/snapshots

icon:        ## Regenerate assets/AppIcon.icns from scripts/make-icon.swift
	scripts/make-icon.sh

clean:
	rm -rf .build dist
