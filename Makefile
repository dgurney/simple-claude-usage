APP = build/Claude Usage.app

.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	scripts/make-app.sh

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/Claude Usage.app"
	cp -R "$(APP)" /Applications/

clean:
	rm -rf .build build
