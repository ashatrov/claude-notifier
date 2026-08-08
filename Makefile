APP := Claude Notifier Manager

.PHONY: build build-universal icon install run clean

# Build the .app bundle (native arch)
build:
	./app/build.sh

# Build a universal binary that also runs on Intel Macs
build-universal:
	ARCHS="arm64 x86_64" ./app/build.sh

# Redraw app/AppIcon.icns from the SF Symbol, then rebuild to pick it up
icon:
	./app/make-icon.swift

# Copy the checked-out bundle into ~/Applications (app must not be running)
install:
	./app/install.sh

# Launch the installed app
run:
	open "$(HOME)/Applications/$(APP).app"

# Remove SwiftPM build products
clean:
	rm -rf app/.build
