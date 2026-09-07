"""Non-destructive production export of the supplied concept, with a rigid-part rig."""

import bpy, math, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(
    filepath=os.path.join(ROOT, "modeling/island_adventurer.blend")
)
excluded = ("Sand island", "Moss top", "Grass shoot", "Beach pebble", "Studio floor")
for obj in list(bpy.data.objects):
    if obj.type not in {"MESH", "CURVE"} or obj.name.startswith(excluded):
        bpy.data.objects.remove(obj, do_unlink=True)
parts = list(bpy.context.scene.objects)
# Evaluate curves and modifiers once, with a bounded subdivision level for real-time use.
for obj in parts:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        if mod.type == "SUBSURF":
            mod.levels = mod.render_levels = 1
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
rig_data = bpy.data.armatures.new("AdventurerRig")
rig = bpy.data.objects.new("AdventurerRig", rig_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name, head, tail in [
    ("Root", (0, 0, 0), (0, 0, 1)),
    ("Head", (0, 0, 1.8), (0, 0, 2.8)),
    ("ArmL", (-0.34, 0, 1.65), (-0.74, 0, 1.1)),
    ("ArmR", (0.34, 0, 1.65), (0.74, 0, 1.1)),
    ("LegL", (-0.29, 0, 1.04), (-0.29, 0, 0.2)),
    ("LegR", (0.29, 0, 1.04), (0.29, 0, 0.2)),
]:
    bone = rig_data.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    if name != "Root":
        bone.parent = rig_data.edit_bones["Root"]
bpy.ops.object.mode_set(mode="OBJECT")
for obj in parts:
    n = obj.name
    side = "L" if obj.location.x < 0 else "R"
    bone = "Root"
    if n.startswith(
        (
            "Bare knee",
            "Linen shorts",
            "Rounded leather boot",
            "Dark boot sole",
            "Folded boot cuff",
            "Boot stitch",
        )
    ):
        bone = "Leg" + side
    elif n.startswith(
        ("Short tunic sleeve", "Sleeve linen trim", "Forearm", "Mitten hand", "Thumb")
    ):
        bone = "Arm" + side
    elif n.startswith(("Sword", "Wooden blade", "Wooden crossguard")):
        bone = "ArmR"
    elif n.startswith(
        (
            "Head",
            "Ear",
            "Clean ivory eye",
            "Dark oval eye",
            "Eye glint",
            "Fine eyebrow",
            "Understated smile",
            "Button nose",
            "Sculpted swept hair",
            "Long side swept fringe",
            "Secondary fringe",
        )
    ):
        bone = "Head"
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("Adventurer animation", "ARMATURE")
    mod.object = rig
    obj.parent = rig
rig.animation_data_create()
for clip, end in [("Idle", 60), ("Walk", 24), ("Wave", 48)]:
    action = bpy.data.actions.new(clip)
    rig.animation_data.action = action
    for frame in range(1, end + 1):
        t = (frame - 1) / (end - 1)
        phase = t * math.tau
        for bone in rig.pose.bones:
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
            if clip == "Walk":
                if bone.name.startswith(("Arm", "Leg")):
                    sign = 1 if bone.name.endswith("L") else -1
                    if bone.name.startswith("Arm"):
                        sign = -sign
                    bone.rotation_euler.x = math.sin(phase) * 0.30 * sign
                if bone.name == "Root":
                    bone.location.z = abs(math.sin(phase)) * 0.035
            elif clip == "Idle" and bone.name == "Head":
                bone.rotation_euler.y = math.sin(phase) * 0.025
            elif clip == "Wave" and bone.name == "ArmR":
                bone.rotation_euler.z = -math.sin(math.pi * t) * 1.8
                bone.rotation_euler.x = (
                    math.sin(phase * 3) * 0.22 * math.sin(math.pi * t)
                )
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
    track = rig.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    rig.animation_data.action = None
for track in rig.animation_data.nla_tracks:
    track.mute = True
# Original concept is 3 units high. Match the game's 2.2-unit avatars and ground boots.
rig.scale = (0.72,) * 3
rig.location.z = -0.06
bpy.context.scene.render.fps = 30
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(
    filepath=os.path.join(ROOT, "blender/adventurer_game.blend")
)
for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.ops.export_scene.gltf(
    filepath=os.path.join(ROOT, "godot/assets/models/adventurer.glb"),
    export_format="GLB",
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,
)
print("Exported adventurer with Idle / Walk / Wave")
