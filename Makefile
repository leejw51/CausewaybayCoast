# Causeway Bay Coast — tiny-island social platform
GODOT   ?= /Applications/Godot.app/Contents/MacOS/Godot
BLENDER ?= /Applications/Blender.app/Contents/MacOS/Blender
PORT    ?= 8787
# Persistence: ~/.causewaybaycoast/server (sqlite + events.jsonl) and ~/.causewaybaycoast/client (jsonl)
DATA    ?= $(HOME)/.causewaybaycoast/server
DIST    ?= dist

.PHONY: all build release server start stop format format-check cli test smoke assets adventurer portal-assets flow-check textures ui import godot run shot web package clean

all: build

build:
	cd backend && cargo build

release:
	cd backend && cargo build --release

server:
	cd backend && COAST_PORT=$(PORT) COAST_DIR=$(DATA) cargo run -p server

start: build import
	python3 tools/manage.py start --godot "$(GODOT)" --port "$(PORT)" --data "$(DATA)"

stop:
	python3 tools/manage.py stop

build/format-env/.installed: requirements-dev.txt
	python3 -m venv build/format-env
	build/format-env/bin/python -m pip install -r requirements-dev.txt
	touch $@

format: build/format-env/.installed
	cd backend && cargo fmt --all
	build/format-env/bin/ruff format tools blender modeling/scripts
	build/format-env/bin/gdformat godot/scripts godot/tests

format-check: build/format-env/.installed
	cd backend && cargo fmt --all -- --check
	build/format-env/bin/ruff format --check tools blender modeling/scripts
	build/format-env/bin/gdformat --check godot/scripts godot/tests

cli:
	cd backend && cargo run -p coastcli -- --url ws://127.0.0.1:$(PORT)/ws shell --name $(or $(NAME),cli)

# Unit tests, then spin up a throwaway server on a scratch dir and run the CLI smoke scenario.
test:
	cd backend && cargo test
	$(MAKE) smoke PORT=8799 DATA=build/smoke

smoke:
	cd backend && cargo build -p server -p coastcli
	rm -rf $(DATA) && mkdir -p $(DATA)
	COAST_PORT=$(PORT) COAST_DIR=$(DATA) ./backend/target/debug/server & echo $$! > .server.pid; \
	sleep 1; \
	./backend/target/debug/coastcli --url ws://127.0.0.1:$(PORT)/ws smoke; rc=$$?; \
	kill `cat .server.pid`; rm -f .server.pid; exit $$rc

# Rebuild every GLB (and blender/coast_assets.blend) from Blender, headless.
flow-check: import
	$(GODOT) --headless --path godot res://tests/FlowCheck.tscn

adventurer:
	$(BLENDER) --background --python blender/export_adventurer.py

portal-assets:
	$(BLENDER) --background --python blender/export_portal.py

assets:
	$(BLENDER) --background --python blender/build_assets.py -- godot/assets/models
	$(MAKE) adventurer
	$(BLENDER) --background --python blender/polish_island.py

# Grok Imagine (xAI) image generation. Needs XAI_API_KEY. Existing files are kept; FORCE=1 regenerates.
textures:
	python3 tools/gen_textures.py godot/assets/textures

ui:
	python3 tools/gen_ui.py godot/assets/ui

# (Re)import GLBs headlessly so `make run` works without opening the editor first.
import:
	$(GODOT) --headless --path godot --import

godot:
	$(GODOT) --path godot --editor &

run: import
	$(GODOT) --path godot

# Headless visual check: connects as "shotbot", decorates, saves a PNG. HOP=1 also portals to another island.
shot: import
	COAST_SHOT=$(CURDIR)/build/shot.png $(if $(HOP),COAST_SHOT_HOP=1,) $(GODOT) --path godot 2>&1 | grep -i -E "error|saved"

# Web export needs export templates installed in Godot (Editor > Manage Export Templates).
web: import
	mkdir -p build/web
	$(GODOT) --path godot --headless --export-release "Web" ../build/web/index.html

# Standalone macOS release client plus backend binaries. Export errors fail the target.
build/templates/macos.zip: tools/export_templates.py
	python3 tools/export_templates.py

package: release import build/templates/macos.zip
	mkdir -p "$(DIST)/bin"
	"$(GODOT)" --headless --path godot --export-release "macOS" "$(abspath $(DIST))/CausewayBayCoast.app"
	cp backend/target/release/server backend/target/release/coastcli "$(DIST)/bin/"
	cp README.md "$(DIST)/"
	ditto -c -k --sequesterRsrc --keepParent "$(DIST)/CausewayBayCoast.app" "$(DIST)/CausewayBayCoast-macOS.zip"
	@echo "Release client: $(DIST)/CausewayBayCoast.app (share the macOS.zip archive)"

clean:
	cd backend && cargo clean
	rm -rf build dist
