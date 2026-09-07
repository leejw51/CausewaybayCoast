# Blender → Godot pipeline

The game uses an original island setting with a soft, miniature life-sim presentation: a restrained coastal palette, continuous water, rounded shoreline, soft directional shadows, ambient occlusion, and temporal anti-aliasing. Desktop rendering uses Godot Forward+; the mobile override remains Compatibility.

## Character

`modeling/island_adventurer.blend` is the untouched source concept. Run `make adventurer` to produce `blender/adventurer_game.blend` and `godot/assets/models/adventurer.glb`. The exporter removes the studio lights, camera, floor, and display plinth; evaluates curves and bounded subdivision; adds a six-bone rigid-part rig; and exports Idle, Walk, and Wave animations. The character faces Blender -Y / Godot +Z and is scaled to the existing world. The rig is suitable for these simple game actions; it is not a full deformation rig for arbitrary poses.

`Avatar.gd` uses the new GLB for players and NPCs. Cloth tint distinguishes residents. The existing models for furniture, vegetation, and buildings remain editable through `blender/build_assets.py`.

## World

`make assets` rebuilds the original asset set, exports the adventurer, and rebuilds the polished island. `blender/polish_island.py` can rebuild just the island, producing `blender/island_game.blend` and `island.glb`. Shoreline geometry is authored in `build_assets.py`, so full rebuilds preserve the improvements.

`Assets.gd` preserves imported PBR materials and applies named coastal palette overrides. `water.gdshader` adds subtle moving ripples. `Main.gd` owns lighting and camera settings. Godot imports the GLBs with `make import`; `make run` launches the client.

The sea uses Grok generated `ocean_caustics.jpg`; the beach uses `beach_sand.jpg`. Their `.generation.json` files record the xAI model and exact prompt. Regenerate them with `make textures` (the existing files are kept unless `FORCE=1` is set).

The mouse wheel and the `+`/`-` buttons zoom the isometric camera. In first-person (`V`), the same controls adjust field of view. FPS mode captures the mouse for look control; `Esc` releases it, clicking the viewport captures it again, and the crosshair indicates active look control.

Third-person camera rotation uses `Q` / `C`, right-drag (outside decorating), middle-drag, or the two curved-arrow buttons. The orbit is preserved when switching back from first-person. The skybox is a native Godot sky shader with a blue horizon, a sun glow, and slowly drifting clouds; it requires no additional raster images.

Players can walk anywhere inside the island's 12-unit shoreline radius, including the beach. Client and server enforce the same boundary; furniture placement still uses the original 14 × 14 grid. Avatar height follows the house, grass, and beach surfaces. Restart the backend after updating so other players receive the expanded movement coordinates.

The sea has moving Grok caustics, crossing wave normals, a shallow-to-deep color gradient, and animated shore foam. The pond uses its own calmer ripple settings and concentric rings centered on the pond.

Portals are server-linked to a room from the island directory. When an owner selects a destination, the avatar walks to the portal automatically. Walking into a linked portal or pressing `E` on it intensifies orbital particle trails, fades the screen, switches the WebSocket session to the other room, fades back in, and spawns an arrival burst. The server persists each user's room and portal links, so an island can also be visited while its owner is offline.

Clicking the visible portal ring opens the island selector directly, even outside decorating. This uses the portal's projected 3D volume, so it also works after rotating the camera and with the FPS crosshair. Selecting a destination links the owner's portal and starts the walk to it.

## Native Godot portal effects

`PortalFX.gd` combines nine orbital GPU ribbon trails, 52 rim sparks, and 24 interior sparks. A custom particle shader advances each particle around its orbit and tapers its lifetime. `portal_aperture.gdshader` samples the opaque scene behind the aperture, applies animated swirl distortion and a restrained color split, and leaves the interior see-through. Entry boosts particle brightness; arrival uses a short-lived vortex. The fixed torus and white core have been removed from the Blender export; `make portal-assets` rebuilds its stone pedestal in `blender/portal_game.blend` and `portal.glb`.

The implementation follows Godot's [GPU particle trail setup](https://docs.godotengine.org/en/stable/tutorials/3d/particles/trails.html) and [screen-reading shader pipeline](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html). Trails target the project's Forward+ desktop renderer. Screen refraction samples the local opaque scene, not a live view of the destination island; transparent objects are not captured in that buffer.

## Verification

Start a local server with `make server`, then run:

```
make test
make flow-check
```

The Rust smoke client verifies two-player presence, movement, chat, ownership, decoration, portal links and travel, return home, NPC dialogue, and reconnect persistence. The Godot flow scene checks login, avatar clips, walking, chat input, palette and rotation, placement/removal, island directory, camera switching, mute, NPC UI, portal linking and visiting with a second player, return home, and reconnect.

To capture the rendered flow screens:

```
COAST_FLOW_SHOTS="$PWD/build/visual-check" /Applications/Godot.app/Contents/MacOS/Godot --path godot res://tests/FlowCheck.tscn
```

Create the destination directory first. Set `COAST_CLIENT_DIR` to isolate settings/chat during testing. The flow test uses temporary player names on the local server. Visual evidence is in `build/visual-check`; the current overview is `docs/home-island.png`.
