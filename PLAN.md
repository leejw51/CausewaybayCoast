# Causeway Bay Coast — Plan

A tiny social platform: everyone owns a tiny house on a tropical island, decorates it with
plants and cute items, and hops to friends' rooms through portals. Rendered as a 3D isometric
scene in Godot, styled after console-era Wonder Boy (chunky shapes, saturated flat colours,
thick outlines, bouncy motion).

## Stack

| Layer          | Tech                                  | Notes                                        |
|----------------|---------------------------------------|----------------------------------------------|
| Backend        | Rust (axum + tokio-tungstenite)       | One binary: `server`. Port 8787.             |
| Database       | SQLite via `rusqlite` (bundled)       | File `data/coast.db`, schema auto-migrated.  |
| Protocol       | JSON over WebSocket                   | `{"type": "...", ...}` envelopes, see below.  |
| Test client    | Rust CLI (`coastcli`)                 | Scripted verification of the backend.        |
| Main frontend  | Godot 4.7 (GDScript)                  | 3D isometric orthographic camera.            |
| Web            | Godot Web export (later)              | Protocol is browser-safe (plain `ws://`).    |
| Modeling       | Blender 5.2 via MCP, exported as GLB  | `blender/build_assets.py` regenerates GLBs + `coast_assets.blend`. |
| Textures / UI  | Grok Imagine (xAI image API)          | `tools/gen_textures.py`, `tools/gen_ui.py` (needs `XAI_API_KEY`). |
| Build          | Makefile                              | `make server`, `make cli`, `make godot`...   |

## Repo layout

```
CausewaybayCoast/
  Makefile
  PLAN.md
  backend/        # cargo workspace: server + coastcli + shared protocol crate
    Cargo.toml
    crates/protocol/   # JSON message types (serde), shared by server & cli
    crates/server/     # axum ws server, sqlite, room state
    crates/coastcli/   # test/verification CLI
  blender/
    build_assets.py    # headless script: builds every model, exports GLB, saves coast_assets.blend
    coast_assets.blend # all models laid out on a grid (open in Blender)
  tools/
    gen_textures.py    # Grok Imagine -> godot/assets/textures/*.jpg (seamless, triplanar-mapped)
    gen_ui.py          # Grok Imagine -> godot/assets/ui/*.jpg (icons on magenta, keyed in Godot)
  dist/                # `make package`: release server + coastcli binaries, godot project copy
  godot/
    project.godot      # GL Compatibility renderer (web-export ready)
    assets/models/*.glb
    scenes/Main.tscn   # single root node; everything else is built in code
    scripts/Main.gd Room.gd Avatar.gd HUD.gd Net.gd Assets.gd
    shaders/toon.gdshader outline.gdshader   # cel shading + inverted-hull outline
```

## Game / social model

- **Player**: name, colour, current room.
- **Room**: one per player ("tiny house on an island"), 14×14 grid of tiles: tiles 0..7 × 0..7
  are the raised plank floor of the house, the rest is garden. The pond (around tile 11,10)
  is not buildable.
- **Item**: placed decoration in a room: kind (`palm`, `monstera`, `flower_pot`, `bed`,
  `table`, `chair`, `lamp`, `rug`, `bookshelf`, `cactus`, `portal`, `tree`, `bench`,
  `flower_bed`), tile x/y, rotation.
- **Portal**: a special item that links to another room; walking into it teleports the
  player (room switch on the server, scene reload on the client).
- **Presence**: everyone in the same room sees each other move in realtime.
- **Chat**: room-scoped text chat, shown as bubbles over heads.
- **NPCs**: four server-driven islanders (Momo the gardener, Kai the fisher, Coco the seller,
  Pip the postie) with negative player ids and `is_npc: true`. Every inhabited island gets at
  least one. They wander (sometimes towards players), chatter, greet arrivals, hop between
  islands, and hold dialogues: click them or press E, pick a reply (1-4). Replies can give tips,
  tell stories, gift an item (owner only, placed beside you), list where people are, or make the
  islander follow you for a minute. Lives in `crates/server/src/npc.rs`.

## WebSocket protocol (JSON)

Client → Server
```
{"type":"hello","name":"lee","colour":"#ff8844"}
{"type":"move","x":3.5,"y":2.0}
{"type":"place_item","kind":"palm","tx":2,"ty":3,"rot":0}
{"type":"remove_item","id":12}
{"type":"link_portal","id":12,"target_room":7}
{"type":"enter_portal","id":12}
{"type":"go_home"}
{"type":"chat","text":"hi"}
{"type":"list_rooms"}
{"type":"talk","npc_id":-2}              // start a dialogue (NPC walks up, sends its menu)
{"type":"talk","npc_id":-2,"choice":1}   // pick a reply
```
Server → Client
```
{"type":"welcome","player_id":1,"room":{...full room state...}}
{"type":"room_state","room":{...}}             // sent on every room change
{"type":"player_joined","player":{...}}
{"type":"player_left","player_id":2}
{"type":"player_moved","player_id":2,"x":..,"y":..}
{"type":"item_placed","item":{...}}
{"type":"item_removed","id":12}
{"type":"portal_linked","id":12,"target_room":7}
{"type":"chat","player_id":2,"name":"bob","text":"hi"}
{"type":"rooms","rooms":[{"id":1,"owner":"lee","visitors":2},...]}
{"type":"dialogue","npc_id":-2,"name":"Kai the fisher","text":"...","options":["Any tips?", ...]}
{"type":"error","message":"..."}
```

## Persistence

Server: `~/.causewaybaycoast/server/` (override `COAST_DIR`)
- `coast.db` (SQLite): `players(id, name UNIQUE, colour, home_room)`, `rooms(id, owner_id, name)`,
  `items(id, room_id, kind, tx, ty, rot, target_room NULL)`
- `events.jsonl`: append-only audit log, one JSON object per line
  (`join`, `leave`, `place_item`, `remove_item`, `link_portal`, `switch_room`, `chat`, with `ts` ms).

Client: `~/.causewaybaycoast/client/` (`user://` on web)
- `settings.jsonl`: append-only, newest line wins (`name`, `url`, `zoom`, `muted`)
- `chat.jsonl`: every chat line seen (`ts`, `room`, `name`, `text`)

Live positions are in-memory only.

## Art direction: Wonder Boy console style

Bold saturated colours, thick dark outlines (inverted hull), two hard cel bands plus a thin
highlight, chunky rounded shapes. Not a copy of any reference game.

- Models are one material per colour (no UVs). Godot maps Grok-generated seamless textures
  onto them in world space (triplanar) and modulates the palette colour by the texture's
  luminance, so the painted palette stays in control (`Assets.gd` `TEX` table).
- `player.glb` is mesh-modelled in Blender, not assembled from primitives: subdivision cages
  (`profile_cage`, `sphere_cage`, `cube_cage`) are sculpted (`sculpt`) and extruded
  (`extrude`, `extrude_region`: ears, nose, boot toes, sleeves, hair tufts and fringe) with a
  Subdivision Surface modifier, then skinned to an armature (Root/Spine/Head/ArmL/ArmR/LegL/LegR)
  with keyframed `Walk`, `Idle`, `Wave` actions exported as glTF animations. `Avatar.gd` plays
  them through Godot's AnimationPlayer and scales playback with the eased walking speed.
- Interchangeable parts are baked into the same GLB as `Var_<category>_<name>` meshes (hair:
  bob / ponytail / curly / bun; hat: straw / cap / flower / goggles; back: backpack; neck:
  necklace / bowtie; outfit: overalls / sailor / apron). `Avatar._assemble` keeps at most one
  per category, chosen from the player's name hash, so every islander looks different and the
  same on every client. Tunic / hair / shorts colours are tinted per player.
- Every asset is generated from scratch by `build_assets.py` (no third-party models), so the
  whole repo can be MIT licensed. Textures and icons are generated with Grok Imagine.

Built by `blender/build_assets.py` (also writes `blender/coast_assets.blend`):

- `island.glb`   — 14×14 island: sand, water, foam ring, grass garden, raised checker plank
  floor in the back corner with hedges + steps, pond (stone rim, lily pads, reeds, duck),
  stepping-stone path, lamp posts, pier + boat, umbrella, rocks, shells, flower clumps
- `tree.glb`, `bench.glb`, `flower_bed.glb` — garden items
- `house.glb`    — bungalow back walls: wainscot, thatched eaves, shuttered window with flower
  box, door with porthole, shelf, picture, hanging lantern
- `player.glb`   — Wonder Boy hero: big head, spiky hair, red headband, tunic + belt, boots
- `cloud.glb`    — drifting clouds orbiting the island (cast shadows on the water)
- `palm.glb`, `monstera.glb`, `flower_pot.glb`, `cactus.glb`
- `bed.glb`, `table.glb`, `chair.glb`, `lamp.glb`, `rug.glb`, `bookshelf.glb`
- `portal.glb`   — swirling ring on a pedestal

## Godot

- `Main.gd`: orthographic camera at 45° yaw for the isometric look, sun + ambient, spawns
  island/hut, routes server messages, handles click-to-walk and decorate input.
- `Net.gd` autoload: WebSocketPeer, JSON envelope dispatch → signals.
- `Assets.gd` autoload: loads GLBs, swaps materials for `toon.gdshader` + outline `next_pass`,
  tints `M_body` with the player colour.
- `Room.gd`: instantiates items (tile → world) and avatars from `room_state`.
- `Avatar.gd`: click-to-move with a cosine ease-in/out speed profile driving the Blender
  Walk/Idle clips; chat bubbles; local avatar streams `move` at 10 Hz.
- Every menu, toast, popup, item pop-in/out, zoom and room transition uses cosine
  (`TRANS_SINE`) ease in/out with fades (`HUD.reveal`, `HUD.fade_out/fade_in`).
- Views: third-person isometric (orthographic) and first-person (perspective, eye height),
  toggled with V or the 👁 button; the camera flies between them with a cosine ease.
- Controls, keyboard or mouse for everything: WASD / arrows move (screen-relative in iso,
  camera-relative in first person; Q/E or ←/→ turn, right-drag to look), click to walk, E or
  click to talk / place / use a portal, Tab decorate, 1-9 pick an item or a dialogue reply,
  R rotate, H home, I islands, Enter chat, Esc close.
- `HUD.gd`: cream/brown Wonder Boy panels: info, Home/Decorate, item palette, chat, portal
  link popup, login.
- Decorate mode: pick item → click tile → `place_item`. Right click → `remove_item`.
- Portal: select portal → choose room from list → `link_portal`. Walk onto it → `enter_portal`.

## Makefile targets

```
make build     # cargo build (server + cli)
make server    # run backend
make test      # cargo test + coastcli smoke test against a live server
make assets    # blender headless -> godot/assets/models/*.glb + blender/coast_assets.blend
make textures  # Grok Imagine -> godot/assets/textures (skips existing; FORCE=1 to redo)
make ui        # Grok Imagine -> godot/assets/ui icons / portrait / sign
make package   # release binaries + godot project -> dist/
make godot     # open the Godot project in the editor
make run       # run the Godot game (imports assets first)
make shot      # headless visual check -> build/shot.png  (HOP=1 also teleports)
make web       # export web build (placeholder until wasm export templates installed)
```

## Milestones

1. [x] PLAN.md
2. [x] Backend: protocol crate, server with sqlite, rooms/items/portals/chat
3. [x] coastcli: connect, hello, place, portal hop, chat; `smoke` subcommand (20 checks)
4. [x] Blender assets built + exported to GLB (14 models, `make assets`)
5. [x] Godot: scene, net, room rendering, movement, decorate UI, portals
6. [x] Makefile wiring, end-to-end verification (`make test`, `make shot`, `make shot HOP=1`)
7. [x] Polish pass: Grok textures + UI icons, rigged walking avatar, chat bubbles, clouds,
       animated water, placement tweens, portal sparkles, procedural SFX, zoom, teleport flash,
       JSONL persistence in ~/.causewaybaycoast, `make package`
8. [ ] Later: web export (`make web` once export templates are installed), more items,

## How to run

```
make server            # terminal 1: backend on ws://127.0.0.1:8787/ws
make run               # terminal 2: Godot client (imports GLBs first)
make cli NAME=bob      # extra terminal: text client to test multiplayer
make test              # unit tests + CLI smoke scenario on a scratch DB
make assets            # regenerate GLBs from blender/build_assets.py
```

In game: click the floor to walk. **Decorate** (owner only) opens the palette: click a tile to
place, right-click to remove, ↻ / R to rotate, click a portal to link it to another island.
Walk onto a linked portal to teleport. **Home** returns to your island.
