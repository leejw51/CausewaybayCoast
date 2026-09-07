"""Export the portal pedestal; Godot supplies the orbital particles and aperture."""

import bpy, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(__file__))
import build_assets as assets

assets.clear_scene()
assets.build_portal()
assets.export_all(os.path.join(ROOT, "godot/assets/models"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "blender/portal_game.blend"))
