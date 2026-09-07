import bpy, math, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def mat(name, color, rough=0.65, metal=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*color, 1)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    return m


skin = mat("Warm peach skin", (0.72, 0.40, 0.24))
blush = mat("Rosy cheeks", (0.78, 0.25, 0.20))
hair = mat("Chestnut hair", (0.095, 0.035, 0.019))
teal = mat("Lagoon teal cloth", (0.025, 0.30, 0.28))
darkteal = mat("Deep teal hems", (0.012, 0.14, 0.13))
cream = mat("Linen", (0.87, 0.76, 0.49))
leather = mat("Chestnut leather", (0.22, 0.085, 0.031))
sole = mat("Boot soles", (0.09, 0.044, 0.027))
gold = mat("Warm brass", (0.87, 0.51, 0.12), 0.35, 0.55)
white = mat("Ivory", (0.99, 0.93, 0.78))
ink = mat("Espresso eyes", (0.023, 0.016, 0.012), 0.3)
leaf = mat("Leaf green", (0.23, 0.43, 0.11))
wood = mat("Carved maple", (0.58, 0.31, 0.11))
sand = mat("Warm sand", (0.64, 0.48, 0.29))
grass = mat("Island moss", (0.27, 0.43, 0.23))
bg = mat("Studio mint", (0.13, 0.23, 0.22))


def finish(o, name, m):
    o.name = name
    o.data.materials.append(m)
    if o.type == "MESH":
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def uv(name, loc, scale, m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, location=loc)
    o = bpy.context.object
    o.scale = scale
    return finish(o, name, m)


def cube(name, loc, scale, m, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new("Soft crafted edges", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return finish(o, name, m)


def link(name, a, b, r, m, r2=None):
    d = Vector(b) - Vector(a)
    mid = (Vector(a) + Vector(b)) / 2
    bpy.ops.mesh.primitive_cone_add(
        vertices=32,
        radius1=r,
        radius2=r if r2 is None else r2,
        depth=d.length,
        location=mid,
    )
    o = bpy.context.object
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return finish(o, name, m)


def curve(name, pts, r, m):
    c = bpy.data.curves.new(name, "CURVE")
    c.dimensions = "3D"
    c.bevel_depth = r
    c.bevel_resolution = 4
    s = c.splines.new("BEZIER")
    s.bezier_points.add(len(pts) - 1)
    for p, co in zip(s.bezier_points, pts):
        p.co = co
        p.handle_left_type = "AUTO"
        p.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, c)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    return o


# Feet forward is -Y. A friendly, oversized head and compact adventure silhouette.
for x in [-0.29, 0.29]:
    uv("Bare knee", (x, 0, 0.78), (0.15, 0.16, 0.28), skin)
    cube("Linen shorts", (x, 0, 1.08), (0.43, 0.46, 0.43), cream, 0.12)
    uv("Rounded leather boot", (x, -0.115, 0.30), (0.235, 0.34, 0.24), leather)
    cube("Dark boot sole", (x, -0.12, 0.15), (0.46, 0.62, 0.12), sole, 0.055)
    link("Folded boot cuff", (x, 0, 0.43), (x, 0, 0.58), 0.207, leather)
    for z in [0.38, 0.45]:
        curve(
            "Boot stitch",
            [(x - 0.085, -0.20, z), (x, -0.225, z + 0.012), (x + 0.085, -0.20, z)],
            0.012,
            cream,
        )
link("Flared tunic", (0, 0, 1.04), (0, 0, 1.72), 0.52, teal, 0.38)
link("Tunic lower border", (0, 0, 1.02), (0, 0, 1.10), 0.527, darkteal, 0.515)
link("Leather belt", (0, 0, 1.19), (0, 0, 1.29), 0.496, leather, 0.48)
cube("Brass buckle", (0, -0.49, 1.245), (0.19, 0.045, 0.145), gold, 0.025)
cube("Buckle inset", (0, -0.52, 1.245), (0.105, 0.02, 0.073), leather, 0.01)
link("Neck", (0, 0, 1.68), (0, 0, 1.91), 0.16, skin)
for side in [-1, 1]:
    link(
        "Short tunic sleeve",
        (side * 0.34, 0, 1.64),
        (side * 0.59, -0.015, 1.42),
        0.235,
        teal,
        0.20,
    )
    link(
        "Sleeve linen trim",
        (side * 0.55, -0.012, 1.46),
        (side * 0.61, -0.018, 1.40),
        0.209,
        cream,
        0.20,
    )
    link(
        "Forearm",
        (side * 0.61, -0.015, 1.40),
        (side * 0.72, -0.12, 1.14),
        0.13,
        skin,
        0.12,
    )
    uv("Mitten hand", (side * 0.735, -0.13, 1.08), (0.15, 0.14, 0.18), skin)
    uv("Thumb", (side * 0.63, -0.21, 1.10), (0.073, 0.077, 0.11), skin)
curve(
    "Left collar",
    [(-0.25, -0.27, 1.72), (-0.14, -0.38, 1.64), (0, -0.405, 1.70)],
    0.046,
    cream,
)
curve(
    "Right collar",
    [(0.25, -0.27, 1.72), (0.14, -0.38, 1.64), (0, -0.405, 1.70)],
    0.046,
    cream,
)
for z in [1.48, 1.58]:
    uv("Tunic button", (0, -0.423, z), (0.026, 0.016, 0.026), gold)

uv("Head", (0, -0.012, 2.34), (0.65, 0.51, 0.66), skin)
for side in [-1, 1]:
    uv("Ear", (side * 0.635, -0.005, 2.30), (0.135, 0.12, 0.18), skin)
    uv("Ear inset", (side * 0.68, -0.106, 2.30), (0.06, 0.027, 0.10), blush)
    uv("Eye white", (side * 0.235, -0.472, 2.36), (0.143, 0.055, 0.174), white)
    uv("Big dark iris", (side * 0.226, -0.525, 2.355), (0.080, 0.027, 0.118), ink)
    uv(
        "Eye sparkle",
        (side * 0.226 - 0.023, -0.551, 2.405),
        (0.026, 0.010, 0.034),
        white,
    )
    curve(
        "Eyebrow",
        [
            (side * 0.12, -0.468, 2.575),
            (side * 0.23, -0.47, 2.61),
            (side * 0.34, -0.44, 2.585),
        ],
        0.027,
        hair,
    )
uv("Button nose", (0, -0.542, 2.23), (0.085, 0.085, 0.077), skin)
curve(
    "Small smile",
    [(-0.115, -0.490, 2.10), (0, -0.516, 2.075), (0.115, -0.490, 2.10)],
    0.015,
    ink,
)
uv("Hair cap", (0, 0.067, 2.63), (0.655, 0.50, 0.43), hair)
# A continuous swept hairstyle replaces the disconnected spherical locks.
bpy.data.objects.remove(bpy.data.objects["Hair cap"], do_unlink=True)
verts = []
faces = []
rings = 32
segments = 96
for j in range(rings + 1):
    t = max(0.001, j / rings)
    for i in range(segments):
        a = 2 * math.pi * i / segments
        front = max(0, -math.sin(a))
        # Short fringe on the right, longer swept lock at the left temple.
        boundary = 1.83 - front * 0.68 + front * 0.18 * math.cos(a + 0.7)
        boundary += front * 0.065 * math.sin(5 * a + 0.5)
        theta = t * boundary
        x = 0.67 * math.sin(theta) * math.cos(a)
        y = 0.545 * math.sin(theta) * math.sin(a) + 0.035
        z = 2.37 + 0.70 * math.cos(theta)
        x += 0.065 * (1 - t) ** 2
        verts.append((x, y, z))
for j in range(rings):
    for i in range(segments):
        a = j * segments + i
        b = j * segments + (i + 1) % segments
        faces.append((a, b, b + segments, a + segments))
mesh = bpy.data.meshes.new("Swept hair surface")
mesh.from_pydata(verts, [], faces)
mesh.update()
o = bpy.data.objects.new("Sculpted swept hair", mesh)
bpy.context.collection.objects.link(o)
finish(o, o.name, hair)
mod = o.modifiers.new("Hair shell", "SOLIDIFY")
mod.thickness = 0.035
mod = o.modifiers.new("Smooth silhouette", "SUBSURF")
mod.levels = 2


# Tapered curved fringe surfaces, broad at the root and pointed at the tip.
def lock(name, points, width):
    vs = []
    fs = []
    for j, p in enumerate(points):
        t = j / (len(points) - 1)
        w = width * (1 - t) ** 0.65 + 0.002
        for k in range(9):
            u = k / 8 * 2 - 1
            vs.append(
                (p[0] + u * w, p[1] - 0.045 * (1 - u * u) * math.sin(math.pi * t), p[2])
            )
    for j in range(len(points) - 1):
        for k in range(8):
            a = j * 9 + k
            fs.append((a, a + 1, a + 10, a + 9))
    me = bpy.data.meshes.new(name)
    me.from_pydata(vs, [], fs)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    finish(ob, name, hair)
    m = ob.modifiers.new("Soft lock", "SUBSURF")
    m.levels = 2
    m = ob.modifiers.new("Lock thickness", "SOLIDIFY")
    m.thickness = 0.022


lock(
    "Long side swept fringe",
    [
        (0.20, -0.29, 2.98),
        (0.07, -0.43, 2.89),
        (-0.12, -0.51, 2.77),
        (-0.32, -0.50, 2.63),
        (-0.47, -0.42, 2.46),
    ],
    0.20,
)
lock(
    "Secondary fringe",
    [
        (0.39, -0.24, 2.92),
        (0.33, -0.41, 2.81),
        (0.20, -0.51, 2.70),
        (0.06, -0.53, 2.61),
    ],
    0.15,
)


# Shallow facial graphics follow the head rather than floating off its surface.
def face_y(x, z, offset=0):
    return (
        -0.012
        - 0.51 * math.sqrt(max(0.01, 1 - (x / 0.65) ** 2 - ((z - 2.34) / 0.66) ** 2))
        - offset
    )


def oval_patch(name, cx, cz, rx, rz, m, offset):
    vs = [(cx, face_y(cx, cz, offset), cz)]
    fs = []
    for i in range(64):
        a = 2 * math.pi * i / 64
        x = cx + rx * math.cos(a)
        z = cz + rz * math.sin(a)
        vs.append((x, face_y(x, z, offset), z))
    for i in range(64):
        fs.append((0, i + 1, (i + 1) % 64 + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(vs, [], fs)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    finish(ob, name, m)


for ob in list(bpy.data.objects):
    if ob.name.startswith(
        (
            "Eye white",
            "Big dark iris",
            "Eye sparkle",
            "Eyebrow",
            "Small smile",
            "Left collar",
            "Right collar",
        )
    ):
        bpy.data.objects.remove(ob, do_unlink=True)
for side in [-1, 1]:
    x = side * 0.23
    oval_patch("Clean ivory eye", x, 2.37, 0.112, 0.147, white, 0.007)
    oval_patch("Dark oval eye", x + 0.008, 2.363, 0.066, 0.111, ink, 0.012)
    oval_patch("Eye glint", x - 0.011, 2.408, 0.018, 0.024, white, 0.016)
    pts = []
    for i in range(9):
        xx = x - 0.082 + i * 0.0205
        zz = 2.567 + 0.022 * math.sin(i / 8 * math.pi)
        pts.append((xx, face_y(xx, zz, 0.008), zz))
    curve("Fine eyebrow", pts, 0.016, hair)
pts = []
for i in range(17):
    x = -0.095 + i * 0.19 / 16
    z = 2.106 - 0.024 * math.sin(i / 16 * math.pi)
    pts.append((x, face_y(x, z, 0.006), z))
curve("Understated smile", pts, 0.008, ink)
bpy.data.objects["Button nose"].scale = (0.064, 0.055, 0.058)
bpy.data.objects["Button nose"].location.y = -0.51


def collar_piece(side):
    vs = [
        (side * 0.04, -0.393, 1.73),
        (side * 0.22, -0.30, 1.77),
        (side * 0.31, -0.33, 1.66),
        (side * 0.17, -0.424, 1.57),
    ]
    me = bpy.data.meshes.new("Tailored collar")
    me.from_pydata(vs, [], [(0, 1, 2, 3)])
    me.update()
    ob = bpy.data.objects.new("Linen pointed collar", me)
    bpy.context.collection.objects.link(ob)
    finish(ob, ob.name, cream)
    m = ob.modifiers.new("Cloth thickness", "SOLIDIFY")
    m.thickness = 0.018
    m = ob.modifiers.new("Rounded collar corners", "BEVEL")
    m.width = 0.02
    m.segments = 3


for side in [-1, 1]:
    collar_piece(side)

# Satchel strap follows the body; a sculpted leaf flap marks the island theme.
curve(
    "Crossbody strap",
    [
        (0.29, 0.16, 1.75),
        (0.31, -0.30, 1.72),
        (0.12, -0.445, 1.51),
        (-0.13, -0.49, 1.30),
        (-0.48, -0.29, 1.03),
    ],
    0.042,
    leather,
)
uv("Leaf satchel", (-0.50, -0.23, 1.025), (0.23, 0.135, 0.27), leather)
o = uv("Green leaf flap", (-0.50, -0.359, 1.075), (0.20, 0.034, 0.235), leaf)
o.rotation_euler[1] = -0.3
curve(
    "Leaf midrib",
    [(-0.56, -0.398, 0.88), (-0.50, -0.402, 1.075), (-0.44, -0.391, 1.26)],
    0.011,
    gold,
)
for z in [1.0, 1.10, 1.18]:
    curve("Leaf vein", [(-0.50, -0.405, z), (-0.38, -0.387, z + 0.06)], 0.007, cream)
# A small wooden practice sword at the resident's right side.
link("Sword handle", (0.76, -0.12, 0.99), (0.79, -0.13, 0.75), 0.057, leather)
link("Wooden crossguard", (0.61, -0.13, 0.76), (0.98, -0.13, 0.80), 0.047, wood)
o = cube("Wooden blade", (0.84, -0.13, 0.49), (0.115, 0.065, 0.53), wood, 0.025)
o.rotation_euler[1] = -0.15
uv("Sword pommel", (0.75, -0.12, 1.005), (0.075, 0.072, 0.065), gold)

# Small island display plinth and scattered details.
link("Sand island", (0, 0, -0.10), (0, 0, 0.035), 1.32, sand)
link("Moss top", (0, 0, 0.035), (0, 0, 0.075), 1.29, grass)
for x, y in [(-0.95, 0.30), (0.87, 0.50), (-0.70, -0.67)]:
    for j in [-1, 0, 1]:
        link(
            "Grass shoot",
            (x, y, 0.08),
            (x + j * 0.06, y + 0.015, 0.22 + (0.07 if j == 0 else 0)),
            0.022,
            leaf,
            0.004,
        )
for x, y in [(0.8, -0.65), (-1, 0.05), (0.42, 0.94)]:
    uv("Beach pebble", (x, y, 0.095), (0.10, 0.075, 0.055), cream)
cube("Studio floor", (0, 0, -0.24), (200, 200, 0.10), bg, 0.02)

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.19, 0.27, 0.25, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.45


def aim(o, p):
    o.rotation_euler = (Vector(p) - o.location).to_track_quat("-Z", "Y").to_euler()


for name, loc, power, size, col in [
    ("Key", (-3, -4, 7), 500, 4, (1, 0.84, 0.65)),
    ("Fill", (4, -2, 4), 350, 3, (0.68, 0.87, 1)),
    ("Rim", (1, 3, 5), 650, 3, (1, 0.86, 0.59)),
]:
    bpy.ops.object.light_add(type="AREA", location=loc)
    o = bpy.context.object
    o.name = name
    o.data.energy = power
    o.data.shape = "DISK"
    o.data.size = size
    o.data.color = col
    aim(o, (0, 0, 1.5))
bpy.ops.object.camera_add(location=(4, -8, 4.0))
cam = bpy.context.object
cam.name = "Portrait camera"
aim(cam, (0, 0, 1.49))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 4.30
bpy.context.scene.camera = cam
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.render.resolution_x = 1100
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = os.path.join(ROOT, "island_adventurer.png")
scene["Character"] = "Tavi — Island Adventurer"
scene["Design"] = (
    "Original human island resident with a storybook action-adventure costume."
)
scene["Notes"] = "Editable separate mesh parts. Unrigged concept model. Front faces -Y."
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "island_adventurer.blend"))
bpy.ops.render.render(write_still=True)
