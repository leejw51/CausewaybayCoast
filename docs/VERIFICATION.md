# Verification — 2026-09-07

Latest development-command and public-source review:

- `make start` / `make stop`: both processes start and stop; repeated calls work.
- `make format` / `make format-check`: Rust, Python and GDScript pass.
- Rust tests: protocol roundtrip and repeatable demo-friend seeding pass.
- Expanded headless gameplay flow: all 55 checks pass, including default-friend travel
  without another player, returning Home, and literal rendering of chat markup.
- `make package`: creates a universal arm64/x86_64 native macOS client app and ZIP,
  plus a native arm64 release server in `dist/bin/server`.
- Exported client launches headlessly without the editor; app signature verification passes.
- Security/privacy findings and remaining hosting limitations are in `SECURITY.md`.

Earlier visual verification:

- Rust `cargo test --offline`: passed (protocol serialization roundtrip).
- Two-player CLI smoke: all 23 checks passed on a temporary local SQLite server.
- Godot gameplay flow: all 51 checks passed in headless and rendered runs, including Remove mode selection, mutually exclusive editing modes, server-confirmed removal, particle creation and cleanup, Escape cancellation, visitor restrictions, mouse look, rotation, zoom, portal travel, beach movement, and reconnect.
- Removal effect preview: `docs/remove-effect.png`. The GPU particle burst uses native geometry and needs no new raster assets.
- Rendered flow screenshots: login, furniture palette, first-person view, NPC dialogue, and gameplay in `build/visual-check/`.
- Final overview: `docs/home-island.png`.
- Portal effects close-up: `docs/portal-effects.png`. Beach and sky previews: `docs/beach-walking.png` and `docs/skybox-sea.png`.
- Character export: 3.2 MB GLB, one skin, Idle / Walk / Wave; source concept is preserved.

The checks exercise the actual Godot scene, HUD signals, network messages, scene updates, animation availability, destination movement, and reconnect. They do not substitute for subjective art review or exhaustive manual testing on every device. The visual review was performed with Godot 4.7.2 Forward+ / Metal on Apple M4.

Initial visual passes exposed excessive lighting, visible ocean disc edges, temporary material lifetime errors, an obstructive furniture menu, and notification layout overflow. These were addressed before the final checks. The first remove-item test failure was a float ID in the test harness; the game's input handler already sends integer IDs, and the corrected harness passes.
