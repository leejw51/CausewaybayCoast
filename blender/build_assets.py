"""Build all Causeway Bay Coast models in Blender and export them as GLB.

Wonder Boy style: chunky primitives, saturated flat colours, no textures.
Every model is one material per colour so Godot can render it unshaded/toon.

Usage (headless):
    blender --background --python blender/build_assets.py -- godot/assets/models
Inside a running Blender (e.g. via MCP) you can also call `showcase()` to lay
every model out in a row for inspection.
"""

import math
import os
import sys

import bpy

# ---------------------------------------------------------------- palette
PAL = {
    "sand": "#EFD9A8",
    "sand_dark": "#DCC08A",
    "water": "#A6D2DC",
    "water_deep": "#8FC0CE",
    "wood": "#B98A5C",
    "wood_dark": "#8A5F3C",
    "wood_light": "#D3A876",
    "plank": "#C89A66",
    "wall": "#F4EBD6",
    "wall_trim": "#C97A5A",
    "roof": "#D9B36B",
    "roof_dark": "#B08B4E",
    "leaf": "#7FB069",
    "leaf_dark": "#5E8C4A",
    "leaf_light": "#A3C98A",
    "trunk": "#9C7350",
    "trunk_dark": "#7A5740",
    "shorts": "#6F8FC9",
    "shoe": "#5A4033",
    "shoe_sole": "#8A6A4A",
    "body_dark": "#3A8C46",
    "hair_light": "#FFE08A",
    "iris": "#3A7BD5",
    "straw": "#E8C46A",
    "freckle": "#C98A6A",
    "pot": "#C9856A",
    "pot_rim": "#E0A488",
    "soil": "#6E4E3A",
    "pink": "#E8A0B4",
    "yellow": "#EBCB6E",
    "red": "#D9706A",
    "purple": "#9B86C8",
    "blue": "#7E9CD1",
    "cyan": "#9FD3D6",
    "white": "#FBF7EE",
    "cream": "#F7EEDC",
    "skin": "#F5D3B3",
    "hair": "#6B4A3A",
    "eye": "#3A2A24",
    "body": "#E39B6A",
    "metal": "#9A9AA6",
    "metal_dark": "#5A5A66",
    "lamp": "#FFF0C2",
    "portal": "#8C7BD8",
    "portal_glow": "#D6CCF5",
    "stone": "#BDB6A6",
    "stone_dark": "#968E7C",
    "rug_base": "#D98C7A",
    "cloud": "#FFFFFF",
    "grass": "#8CC66B",
    "pond": "#7FC8DC",
    "hedge": "#6FA85E",
    "hedge_dark": "#528646",
    "lamp_post": "#4E5548",
    "book1": "#D9706A",
    "book2": "#7E9CD1",
    "book3": "#EBCB6E",
    "book4": "#7FB069",
}

_mats = {}


def hex2rgb(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    # sRGB -> linear so the GLB base colour matches the palette on screen
    lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


def mat(name, emission=0.0):
    key = (name, emission)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(f"M_{name}" + ("_glow" if emission else ""))
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    col = hex2rgb(PAL[name])
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    if emission:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emission
    _mats[key] = m
    return m


# ---------------------------------------------------------------- helpers
def _finish(obj, name, m, smooth):
    obj.name = name
    obj.data.materials.append(mat(m) if isinstance(m, str) else m)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def cube(name, loc, size, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    if bevel:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
    return _finish(o, name, m, False)


def sphere(name, loc, r, m, scale=(1, 1, 1), seg=16):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=r, location=loc, segments=seg, ring_count=max(6, seg // 2)
    )
    o = bpy.context.object
    o.scale = scale
    return _finish(o, name, m, True)


def cyl(name, loc, r, h, m, verts=16, rot=(0, 0, 0), r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=r, depth=h, location=loc, vertices=verts, rotation=rot
        )
    else:
        bpy.ops.mesh.primitive_cone_add(
            radius1=r, radius2=r2, depth=h, location=loc, vertices=verts, rotation=rot
        )
    return _finish(bpy.context.object, name, m, verts > 8)


def torus(name, loc, R, r, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        location=loc,
        rotation=rot,
        major_radius=R,
        minor_radius=r,
        major_segments=24,
        minor_segments=10,
    )
    return _finish(bpy.context.object, name, m, True)


def leaf(name, loc, length, width, m, yaw, pitch=0.5, thick=0.06):
    """A chunky leaf: flattened ellipsoid pointing outwards from its base."""
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=1, location=loc, segments=12, ring_count=6
    )
    o = bpy.context.object
    o.scale = (length / 2, width / 2, thick)
    o.rotation_euler = (0, pitch, yaw)
    # move origin to inner tip so the leaf grows outward from loc
    o.location = (
        loc[0] + math.cos(yaw) * math.cos(pitch) * length / 2,
        loc[1] + math.sin(yaw) * math.cos(pitch) * length / 2,
        loc[2] - math.sin(pitch) * length / 2,
    )
    return _finish(o, name, m, True)


class Model:
    """Collects objects created inside `with` into one joined mesh."""

    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.before = set(bpy.data.objects)
        return self

    def __exit__(self, *a):
        objs = [
            o for o in bpy.data.objects if o not in self.before and o.type == "MESH"
        ]
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")  # applies modifiers
        bpy.ops.object.join()
        self.obj = bpy.context.object
        self.obj.name = self.name
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        MODELS[self.name] = self.obj


MODELS = {}


class Part:
    """Like Model, but the joined mesh gets its origin at `pivot` and is parented to `root`."""

    def __init__(self, name, root, pivot):
        self.name, self.root, self.pivot = name, root, pivot

    def __enter__(self):
        self.before = set(bpy.data.objects)
        return self

    def __exit__(self, *a):
        objs = [
            o for o in bpy.data.objects if o not in self.before and o.type == "MESH"
        ]
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = self.name
        bpy.context.scene.cursor.location = self.pivot
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.context.scene.cursor.location = (0, 0, 0)
        obj.parent = self.root
        obj.matrix_parent_inverse = self.root.matrix_world.inverted()
        self.obj = obj


# ---------------------------------------------------------------- mesh modelling helpers (bmesh + subsurf)
import bmesh


def _mesh_obj(name, bm, m, subsurf=2, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat(m) if isinstance(m, str) else m)
    if subsurf:
        mod = o.modifiers.new("subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
    if smooth:
        for p_ in o.data.polygons:
            p_.use_smooth = True
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    return o


def profile_cage(name, rings, m, segments=12, subsurf=2, cap=True, offset=(0, 0, 0)):
    """Box-modelling style cage: stacked rings (z, rx, ry[, cx, cy]) bridged with quads, capped, subdivided."""
    bm = bmesh.new()
    loops = []
    for r in rings:
        z, rx, ry = r[0], r[1], r[2]
        cx, cy = (r[3], r[4]) if len(r) > 4 else (0.0, 0.0)
        loop = []
        for i in range(segments):
            a_ = 2 * math.pi * i / segments
            loop.append(
                bm.verts.new(
                    (
                        offset[0] + cx + math.cos(a_) * rx,
                        offset[1] + cy + math.sin(a_) * ry,
                        offset[2] + z,
                    )
                )
            )
        loops.append(loop)
    for lo, hi in zip(loops, loops[1:]):
        for i in range(segments):
            bm.faces.new((lo[i], lo[(i + 1) % segments], hi[(i + 1) % segments], hi[i]))
    if cap:
        bm.faces.new(loops[0][::-1])
        bm.faces.new(loops[-1])
    bm.normal_update()
    return _mesh_obj(name, bm, m, subsurf)


def sphere_cage(
    name, center, radius, m, segments=12, rings=8, scale=(1, 1, 1), subsurf=2, keep=None
):
    """UV-sphere cage; `keep(x, y, z)` (local, unscaled) filters which faces survive (e.g. a hair cap)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    if keep is not None:
        drop = [f for f in bm.faces if not keep(*(f.calc_center_median() / radius))]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
    for v in bm.verts:
        v.co = mathutils.Vector(
            (
                v.co.x * scale[0] + center[0],
                v.co.y * scale[1] + center[1],
                v.co.z * scale[2] + center[2],
            )
        )
    bm.normal_update()
    return _mesh_obj(name, bm, m, subsurf)


def cube_cage(name, center, size, m, subsurf=2, cuts=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    for v in bm.verts:
        v.co = mathutils.Vector(
            (
                v.co.x * size[0] + center[0],
                v.co.y * size[1] + center[1],
                v.co.z * size[2] + center[2],
            )
        )
    bm.normal_update()
    return _mesh_obj(name, bm, m, subsurf)


def sculpt(obj, fn):
    """Move every vertex: fn(Vector) -> Vector. Cheap stand-in for grab/smooth sculpting."""
    for v in obj.data.vertices:
        v.co = fn(mathutils.Vector(v.co))


def extrude_region(obj, select, length, shrink=1.0, direction=None):
    """Extrude all selected faces together as one region (like selecting a patch and pressing E),
    move it along the patch's average normal (or `direction`) and shrink it about the patch centre."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    faces = [f for f in bm.faces if select(f.calc_center_median(), f.normal)]
    if faces:
        avg_n = sum((f.normal for f in faces), mathutils.Vector()).normalized()
        centre = sum((f.calc_center_median() for f in faces), mathutils.Vector()) / len(
            faces
        )
        res = bmesh.ops.extrude_face_region(bm, geom=faces)
        verts = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
        d = mathutils.Vector(direction).normalized() if direction is not None else avg_n
        top = centre + d * length
        for v in verts:
            v.co = top + (v.co - centre) * shrink
        bmesh.ops.delete(bm, geom=faces, context="FACES_ONLY")
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    for p_ in obj.data.polygons:
        p_.use_smooth = True


def extrude(obj, select, length, shrink=1.0, direction=None, count=1):
    """Extrude the faces for which select(center, normal) is true, along their normal (or `direction`),
    then shrink them about their centre. The Blender 'E then S' move, scripted."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    faces = [f for f in bm.faces if select(f.calc_center_median(), f.normal)]
    for f in faces:
        geom = [f]
        for _ in range(count):
            res = bmesh.ops.extrude_face_region(bm, geom=geom)
            new_faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
            verts = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
            nf = new_faces[0]
            d = (
                mathutils.Vector(direction)
                if direction is not None
                else nf.normal.copy()
            )
            c = nf.calc_center_median()
            for v in verts:
                v.co = c + (v.co - c) * shrink + d * (length / count)
            geom = new_faces
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    for p_ in obj.data.polygons:
        p_.use_smooth = True


import mathutils


# ---------------------------------------------------------------- extra helpers
def capsule(name, a, b, r, m, verts=10):
    """Cylinder between points a and b with spherical caps."""
    import mathutils

    va, vb = mathutils.Vector(a), mathutils.Vector(b)
    d = vb - va
    mid = (va + vb) / 2
    rot = d.to_track_quat("Z", "Y").to_euler()
    cyl(name, tuple(mid), r, d.length, m, verts=verts, rot=tuple(rot))
    sphere(name + "_a", a, r, m, seg=verts)
    sphere(name + "_b", b, r, m, seg=verts)


def rbox(name, loc, size, m, r=0.06):
    """Rounded box (bevelled cube)."""
    return cube(name, loc, size, m, bevel=min(r, min(size) * 0.45))


def frond(name, base, yaw, length=2.0, droop=0.9, m="leaf", segs=7, width=0.55):
    """A palm frond: a chain of flattened, tapering slabs following a drooping arc."""
    x, y, z = base
    px, py, pz = x, y, z
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs

        # arc: rises slightly then droops
        def pt(t):
            h = math.sin(t * math.pi) * 0.35 - droop * t * t
            return (
                x + math.cos(yaw) * length * t,
                y + math.sin(yaw) * length * t,
                z + h,
            )

        a, b = pt(t0), pt(t1)
        mid = tuple((a[k] + b[k]) / 2 for k in range(3))
        dx, dy, dz = (b[k] - a[k] for k in range(3))
        seg_len = math.sqrt(dx * dx + dy * dy + dz * dz)
        pitch = -math.atan2(dz, math.sqrt(dx * dx + dy * dy))
        w = width * (1.0 - t0 * 0.75) * (0.6 + 0.4 * math.sin(t0 * math.pi + 0.4))
        bpy.ops.mesh.primitive_cube_add(size=1, location=mid, rotation=(0, pitch, yaw))
        o = bpy.context.object
        o.scale = (seg_len * 1.08, w, 0.05)
        _finish(o, f"{name}_{i}", m if i % 2 == 0 else "leaf_dark", False)


def curved_trunk(name, base, top_offset, height, r0=0.24, r1=0.15, segs=9, m="trunk"):
    """Stacked cone segments along a quadratic curve; returns the tip position."""
    x, y, z = base
    ox, oy = top_offset
    prev = None
    tip = None
    for i in range(segs + 1):
        t = i / segs
        p = (x + ox * t * t, y + oy * t * t, z + height * t)
        if prev is not None:
            mid = tuple((prev[k] + p[k]) / 2 for k in range(3))
            d = tuple(p[k] - prev[k] for k in range(3))
            import mathutils

            rot = mathutils.Vector(d).to_track_quat("Z", "Y").to_euler()
            r_a = r0 + (r1 - r0) * (i - 1) / segs
            r_b = r0 + (r1 - r0) * i / segs
            cyl(
                f"{name}_{i}",
                mid,
                r_a,
                mathutils.Vector(d).length * 1.05,
                m,
                verts=10,
                rot=tuple(rot),
                r2=r_b,
            )
            # ring notch every other segment
            if i % 2 == 0:
                cyl(
                    f"{name}_ring{i}",
                    p,
                    r_b * 1.12,
                    0.08,
                    "trunk_dark",
                    verts=10,
                    rot=tuple(rot),
                )
        prev = p
        tip = p
    return tip


# ---------------------------------------------------------------- models
def build_island():
    """Big tiny island: 14x14 buildable tiles = house floor (tiles 0..8, back corner) + garden.
    Blender coords: Godot tile (tx, ty) -> (tx - 6.5, -(ty - 6.5)). Pond at tile (11, 10)."""
    with Model("island"):
        bpy.ops.mesh.primitive_plane_add(size=800, location=(0, 0, -0.34))
        _finish(bpy.context.object, "Ocean", "water", False)
        for name, z, radius, height, material in [
            ("sand_wet", -0.30, 13.2, 0.25, "sand_dark"),
            ("sand", -0.15, 12.5, 0.5, "sand"),
            ("grass", -0.02, 9.9, 0.3, "grass"),
            ("grass_rim", -0.08, 10.2, 0.18, "leaf_dark"),
        ]:
            shore = cyl(name, (0, 0, z), radius, height, material, verts=128)
            for vertex in shore.data.vertices:
                angle = math.atan2(vertex.co.y, vertex.co.x)
                factor = (
                    1 + 0.018 * math.sin(5 * angle) + 0.014 * math.cos(3 * angle + 0.4)
                )
                vertex.co.x *= factor
                vertex.co.y *= factor
            bevel = shore.modifiers.new("Soft shore", "BEVEL")
            bevel.width = 0.10
            bevel.segments = 3
            shore.modifiers.new("Shore normals", "WEIGHTED_NORMAL")
        # --- house floor (raised planks) at tiles 0..8
        fx, fy = -3.0, 3.0
        rbox("floor", (fx, fy, 0.05), (8.3, 8.3, 0.24), "wood_dark", r=0.05)
        for i in range(8):
            for j in range(8):
                rbox(
                    f"tile{i}{j}",
                    (fx - 3.5 + i, fy - 3.5 + j, 0.17),
                    (0.96, 0.96, 0.08),
                    "plank" if (i + j) % 2 else "wood_light",
                    r=0.02,
                )
        for x, y, sx, sy in [
            (fx, fy + 4.2, 8.5, 0.25),
            (fx, fy - 4.2, 8.5, 0.25),
            (fx + 4.2, fy, 0.25, 8.5),
            (fx - 4.2, fy, 0.25, 8.5),
        ]:
            rbox(f"beam{x}{y}", (x, y, 0.2), (sx, sy, 0.16), "wood_dark", r=0.03)
        # hedge border along the two open edges (gaps for the steps)
        for j in range(9):
            t = fy - 4.0 + j
            if abs(t - (fy - 1.5)) > 1.2:
                sphere(
                    f"hedge_x{j}",
                    (fx + 4.55, t, 0.42),
                    0.5,
                    "hedge" if j % 2 else "hedge_dark",
                    scale=(0.8, 1.05, 0.75),
                    seg=10,
                )
            t2 = fx - 4.0 + j
            if abs(t2 - (fx + 1.5)) > 1.2:
                sphere(
                    f"hedge_y{j}",
                    (t2, fy - 4.55, 0.42),
                    0.5,
                    "hedge" if j % 2 else "hedge_dark",
                    scale=(1.05, 0.8, 0.75),
                    seg=10,
                )
        rbox(
            "hedge_box_x",
            (fx + 4.55, fy + 1.0, 0.25),
            (0.6, 6.4, 0.2),
            "wood_dark",
            r=0.03,
        )
        rbox(
            "hedge_box_y",
            (fx - 1.0, fy - 4.55, 0.25),
            (6.4, 0.6, 0.2),
            "wood_dark",
            r=0.03,
        )
        for i, z in enumerate((0.1, 0.0)):
            rbox(
                f"step_x{i}",
                (fx + 4.45 + i * 0.35, fy - 1.5, z),
                (0.4, 2.0, 0.12 - i * 0.02),
                "wood",
                r=0.03,
            )
            rbox(
                f"step_y{i}",
                (fx + 1.5, fy - 4.45 - i * 0.35, z),
                (2.0, 0.4, 0.12 - i * 0.02),
                "wood",
                r=0.03,
            )
        # --- garden: pond with stone rim, lily pads, reeds, a duck
        px, py = 5.0, -4.0
        cyl("pond_bed", (px, py, 0.05), 2.4, 0.2, "soil", verts=32)
        cyl("pond", (px, py, 0.12), 2.2, 0.08, "pond", verts=32)
        for k in range(14):
            a_ = k * 2 * math.pi / 14
            sphere(
                f"pond_stone{k}",
                (px + math.cos(a_) * 2.3, py + math.sin(a_) * 2.3, 0.16),
                0.28 + (k % 3) * 0.06,
                "stone" if k % 2 else "stone_dark",
                scale=(1.3, 1, 0.6),
                seg=8,
            )
        for k, (ox, oy) in enumerate([(-0.9, 0.5), (0.7, -0.8), (0.3, 1.1)]):
            cyl(f"lily{k}", (px + ox, py + oy, 0.18), 0.32, 0.04, "leaf", verts=12)
            if k == 0:
                sphere("lily_flower", (px + ox, py + oy, 0.26), 0.1, "pink", seg=8)
        for k in range(5):
            a_ = 2.4 + k * 0.25
            cyl(
                f"reed{k}",
                (px + math.cos(a_) * 1.9, py + math.sin(a_) * 1.9, 0.5),
                0.03,
                1.0 + (k % 2) * 0.3,
                "leaf_dark",
                verts=6,
            )
            sphere(
                f"reed_top{k}",
                (px + math.cos(a_) * 1.9, py + math.sin(a_) * 1.9, 1.0 + (k % 2) * 0.3),
                0.06,
                "wood_dark",
                scale=(1, 1, 2),
                seg=6,
            )
        sphere(
            "duck_body",
            (px - 0.2, py - 0.3, 0.26),
            0.22,
            "yellow",
            scale=(1.3, 1, 0.8),
            seg=10,
        )
        sphere("duck_head", (px + 0.05, py - 0.3, 0.5), 0.14, "yellow", seg=10)
        cube("duck_beak", (px + 0.2, py - 0.3, 0.48), (0.14, 0.1, 0.05), "pot")
        sphere("duck_eye", (px + 0.12, py - 0.2, 0.54), 0.025, "eye", seg=6)
        # --- stepping stone path from the steps to the pier
        for k in range(9):
            t = k / 8
            x = fx + 1.5 + (3.0 - (fx + 1.5)) * t + (0.25 if k % 2 else -0.25)
            y = fy - 5.2 + (-12.3 - (fy - 5.2)) * t
            cyl(
                f"path{k}",
                (x, y, 0.03),
                0.45,
                0.08,
                "stone" if k % 2 else "stone_dark",
                verts=9,
            )
        # --- lamp posts at garden corners
        for x, y in [(7.2, -7.2), (7.2, 7.0), (-7.0, -7.2)]:
            cyl(f"lp_base{x}{y}", (x, y, 0.15), 0.22, 0.3, "lamp_post", verts=10)
            cyl(f"lp_pole{x}{y}", (x, y, 1.4), 0.07, 2.4, "lamp_post", verts=8)
            rbox(f"lp_head{x}{y}", (x, y, 2.75), (0.4, 0.4, 0.45), "lamp_post", r=0.04)
            sphere(
                f"lp_glow{x}{y}", (x, y, 2.75), 0.14, mat("lamp", emission=2.0), seg=8
            )
            cyl(f"lp_cap{x}{y}", (x, y, 3.05), 0.3, 0.12, "lamp_post", verts=8, r2=0.05)
        # --- pier + boat (front)
        for i in range(8):
            rbox(
                f"pier{i}",
                (3.0, -12.6 - i * 0.55, -0.02),
                (1.6, 0.48, 0.1),
                "plank" if i % 2 else "wood_light",
                r=0.02,
            )
        for x, y in [(2.3, -12.8), (3.7, -12.8), (2.3, -16.4), (3.7, -16.4)]:
            cyl(f"pierpost{x}{y}", (x, y, -0.35), 0.11, 1.0, "wood_dark", verts=8)
        sphere(
            "boat_hull",
            (5.8, -14.8, -0.25),
            1.0,
            "red",
            scale=(0.75, 1.5, 0.45),
            seg=14,
        )
        sphere(
            "boat_in", (5.8, -14.8, -0.1), 0.85, "cream", scale=(0.6, 1.35, 0.3), seg=14
        )
        rbox("boat_seat", (5.8, -14.8, 0.0), (1.0, 0.25, 0.08), "wood", r=0.02)
        # --- beach: umbrella, towel, rocks, shells, grass tufts
        ux, uy = 10.6, 3.2
        cyl("umb_pole", (ux, uy, 0.8), 0.04, 1.9, "metal", verts=8)
        cyl("umb_top", (ux, uy, 1.85), 1.0, 0.5, "pink", verts=12, r2=0.04)
        for k in range(6):
            a_ = k * math.pi / 3
            cube(
                f"umb_stripe{k}",
                (ux + math.cos(a_) * 0.5, uy + math.sin(a_) * 0.5, 1.87),
                (0.9, 0.16, 0.02),
                "white",
                rot=(0, -0.45, a_),
            )
        rbox("towel", (ux - 0.8, uy - 1.4, 0.12), (1.0, 1.7, 0.06), "cyan", r=0.02)
        rbox(
            "towel_stripe",
            (ux - 0.8, uy - 1.4, 0.16),
            (1.0, 0.3, 0.02),
            "white",
            r=0.01,
        )
        for i, (x, y) in enumerate(
            [
                (-11.2, -3.5),
                (-9.0, -8.0),
                (0.5, -11.6),
                (-11.0, 5.5),
                (6.5, 10.8),
                (11.4, -1.0),
            ]
        ):
            sphere(f"rock{i}", (x, y, 0.05), 0.45, "stone", scale=(1.3, 1, 0.7), seg=10)
            sphere(
                f"rock{i}b",
                (x + 0.4, y - 0.2, 0.02),
                0.25,
                "stone_dark",
                scale=(1.1, 1, 0.7),
                seg=8,
            )
        for i, (x, y) in enumerate(
            [
                (11.2, -6.5),
                (-10.5, 1.0),
                (2.5, 11.3),
                (-5.0, -11.0),
                (11.6, 1.8),
                (-6.5, 10.4),
                (8.5, -9.8),
            ]
        ):
            for k in range(3):
                a_ = k * 2.1 + i
                sphere(
                    f"tuft{i}{k}",
                    (x + math.cos(a_) * 0.22, y + math.sin(a_) * 0.22, 0.12),
                    0.24,
                    "leaf_light",
                    scale=(0.8, 0.8, 1.3),
                    seg=8,
                )
        for i, (x, y) in enumerate(
            [(9.5, -9.9), (-12.0, -0.5), (4.5, 11.8), (-8.5, 8.5)]
        ):
            sphere(
                f"shell{i}",
                (x, y, 0.08),
                0.13,
                "pink" if i % 2 else "cream",
                scale=(1, 1.2, 0.6),
                seg=8,
            )
        # a few flower clumps on the grass
        for i, (x, y) in enumerate(
            [(-7.5, -5.5), (7.5, 3.0), (2.0, -8.5), (-4.5, -8.6), (8.3, -0.5)]
        ):
            sphere(f"clump{i}", (x, y, 0.12), 0.3, "leaf", scale=(1, 1, 0.7), seg=8)
            for k in range(3):
                a_ = k * 2.1
                sphere(
                    f"clump_fl{i}{k}",
                    (x + math.cos(a_) * 0.2, y + math.sin(a_) * 0.2, 0.32),
                    0.08,
                    ["pink", "yellow", "white"][k],
                    seg=6,
                )


def build_tree():
    with Model("tree"):
        cyl("trunk", (0, 0, 0.6), 0.22, 1.2, "trunk", verts=10, r2=0.17)
        cyl("root", (0, 0, 0.08), 0.32, 0.16, "trunk_dark", verts=10, r2=0.22)
        sphere("crown", (0, 0, 1.75), 0.85, "leaf", scale=(1, 1, 0.9))
        sphere("crown2", (0.45, 0.3, 1.5), 0.55, "leaf_dark", seg=12)
        sphere("crown3", (-0.4, -0.35, 1.55), 0.5, "leaf_light", seg=12)
        sphere("crown4", (0.1, -0.1, 2.3), 0.5, "leaf_light", seg=12)
        for k in range(4):
            a_ = k * 1.6
            sphere(
                f"fruit{k}",
                (math.cos(a_) * 0.75, math.sin(a_) * 0.75, 1.6 + (k % 2) * 0.4),
                0.09,
                "red",
                seg=6,
            )


def build_bench():
    with Model("bench"):
        for k in range(3):
            rbox(
                f"seat{k}", (0, -0.2 + k * 0.2, 0.45), (1.7, 0.16, 0.06), "wood", r=0.02
            )
        for k in range(2):
            rbox(
                f"back{k}", (0, 0.32, 0.75 + k * 0.2), (1.7, 0.06, 0.14), "wood", r=0.02
            )
        for sx in (-1, 1):
            rbox(
                f"leg{sx}",
                (sx * 0.7, 0.0, 0.22),
                (0.1, 0.55, 0.44),
                "wood_dark",
                r=0.02,
            )
            rbox(
                f"post{sx}",
                (sx * 0.7, 0.32, 0.7),
                (0.1, 0.06, 0.55),
                "wood_dark",
                r=0.02,
            )


def build_flower_bed():
    with Model("flower_bed"):
        rbox("box", (0, 0, 0.18), (1.8, 0.9, 0.36), "wood", r=0.03)
        rbox("soil", (0, 0, 0.34), (1.6, 0.7, 0.08), "soil", r=0.02)
        for i in range(5):
            for j in range(2):
                x = -0.6 + i * 0.3
                y = -0.18 + j * 0.36
                cyl(f"stem{i}{j}", (x, y, 0.55), 0.02, 0.4, "leaf_dark", verts=6)
                sphere(
                    f"tulip{i}{j}",
                    (x, y, 0.78),
                    0.1,
                    ["red", "yellow", "pink", "purple", "white"][(i + j) % 5],
                    scale=(1, 1, 1.4),
                    seg=8,
                )
                leaf(
                    f"tleaf{i}{j}",
                    (x, y, 0.4),
                    0.3,
                    0.12,
                    "leaf",
                    1.2 + j,
                    pitch=-0.9,
                    thick=0.02,
                )


def build_house():
    """Back walls of a beach bungalow: wainscot, thatched eaves, shuttered window, door, shelf."""
    with Model("house"):
        h = 2.6
        # walls along +Y (back-left) and -X (back-right)
        rbox("wall_a", (0.1, 4.28, h / 2 + 0.2), (8.6, 0.32, h), "wall", r=0.02)
        rbox("wall_b", (-4.28, 0, h / 2 + 0.2), (0.32, 8.3, h), "wall", r=0.02)
        rbox("wain_a", (0.1, 4.2, 0.62), (8.7, 0.4, 0.85), "wood", r=0.03)
        rbox("wain_b", (-4.2, 0, 0.62), (0.4, 8.4, 0.85), "wood", r=0.03)
        rbox("wain_cap_a", (0.1, 4.16, 1.06), (8.72, 0.5, 0.08), "wood_dark", r=0.02)
        rbox("wain_cap_b", (-4.16, 0, 1.06), (0.5, 8.42, 0.08), "wood_dark", r=0.02)
        # thatched eaves tilted outward over each wall
        cube(
            "eave_a",
            (0.1, 4.55, h + 0.55),
            (9.2, 1.5, 0.28),
            "roof",
            rot=(0.55, 0, 0),
            bevel=0.04,
        )
        cube(
            "eave_a2",
            (0.1, 4.5, h + 0.4),
            (9.3, 1.5, 0.2),
            "roof_dark",
            rot=(0.55, 0, 0),
        )
        cube(
            "eave_b",
            (-4.55, 0, h + 0.55),
            (1.5, 9.2, 0.28),
            "roof",
            rot=(0, -0.55, 0),
            bevel=0.04,
        )
        cube(
            "eave_b2",
            (-4.5, 0, h + 0.4),
            (1.5, 9.3, 0.2),
            "roof_dark",
            rot=(0, -0.55, 0),
        )
        rbox("ridge_a", (0.1, 4.28, h + 0.32), (8.9, 0.5, 0.26), "wood_dark", r=0.03)
        rbox("ridge_b", (-4.28, 0, h + 0.32), (0.5, 8.9, 0.26), "wood_dark", r=0.03)
        # posts
        for x, y in [(-4.3, 4.3), (4.35, 4.3), (-4.3, -4.35)]:
            cyl(
                f"post{x}{y}", (x, y, h / 2 + 0.3), 0.24, h + 0.6, "wood_dark", verts=10
            )
            sphere(f"postcap{x}{y}", (x, y, h + 0.62), 0.28, "wood", seg=10)
        # hanging lantern on the back corner
        cyl("lantern_chain", (-3.6, 3.6, h + 0.1), 0.02, 0.5, "metal_dark", verts=6)
        rbox("lantern", (-3.6, 3.6, h - 0.35), (0.3, 0.3, 0.42), "wood_dark", r=0.04)
        sphere(
            "lantern_glow",
            (-3.6, 3.6, h - 0.35),
            0.13,
            mat("lamp", emission=2.5),
            seg=10,
        )
        # window with shutters + flower box (on wall_a)
        rbox("win_frame", (1.6, 4.2, 1.85), (1.5, 0.45, 1.15), "wall_trim", r=0.04)
        rbox("win_glass", (1.6, 4.14, 1.85), (1.2, 0.5, 0.85), "cyan", r=0.02)
        rbox("win_bar_v", (1.6, 4.1, 1.85), (0.07, 0.6, 0.85), "wall_trim", r=0.01)
        rbox("win_bar_h", (1.6, 4.1, 1.85), (1.2, 0.6, 0.07), "wall_trim", r=0.01)
        for s in (-1, 1):
            rbox(
                f"shutter{s}",
                (1.6 + s * 1.05, 4.1, 1.85),
                (0.45, 0.4, 1.15),
                "leaf_dark",
                r=0.03,
            )
            for k in range(4):
                rbox(
                    f"slat{s}{k}",
                    (1.6 + s * 1.05, 4.05, 1.5 + k * 0.24),
                    (0.36, 0.5, 0.06),
                    "leaf",
                    r=0.01,
                )
        rbox("flowerbox", (1.6, 3.95, 1.15), (1.5, 0.45, 0.32), "wood", r=0.03)
        for k in range(5):
            sphere(f"boxbush{k}", (1.0 + k * 0.3, 3.95, 1.36), 0.16, "leaf", seg=8)
            sphere(
                f"boxflower{k}",
                (1.0 + k * 0.3, 3.85, 1.48),
                0.08,
                ["pink", "yellow", "red", "white", "purple"][k],
                seg=8,
            )
        # door with porthole + mat (on wall_b)
        rbox("door_frame", (-4.18, -1.6, 1.15), (0.45, 1.5, 2.1), "wall_trim", r=0.04)
        rbox("door", (-4.12, -1.6, 1.1), (0.5, 1.2, 1.95), "wood", r=0.04)
        for k in range(3):
            rbox(
                f"doorplank{k}",
                (-4.02, -1.95 + k * 0.35, 1.1),
                (0.5, 0.06, 1.85),
                "wood_dark",
                r=0.01,
            )
        cyl(
            "porthole",
            (-3.95, -1.6, 1.7),
            0.2,
            0.15,
            "cyan",
            verts=12,
            rot=(0, math.pi / 2, 0),
        )
        torus(
            "porthole_rim",
            (-3.93, -1.6, 1.7),
            0.2,
            0.05,
            "wall_trim",
            rot=(0, math.pi / 2, 0),
        )
        sphere("knob", (-3.85, -1.25, 1.0), 0.08, "yellow", seg=8)
        rbox("doormat", (-3.55, -1.6, 0.25), (0.7, 1.1, 0.05), "roof_dark", r=0.02)
        # wall shelf with jar + a picture frame
        rbox("shelf", (-2.0, 3.95, 1.8), (1.4, 0.5, 0.08), "wood", r=0.02)
        cyl("jar", (-2.4, 3.95, 1.98), 0.14, 0.3, "cyan", verts=10)
        sphere("jar_lid", (-2.4, 3.95, 2.15), 0.12, "wall_trim", seg=8)
        sphere("shelf_ball", (-1.7, 3.95, 1.98), 0.13, "yellow", seg=10)
        rbox("frame", (-4.05, 1.6, 1.9), (0.1, 0.9, 0.7), "wood_dark", r=0.02)
        rbox("frame_in", (-3.99, 1.6, 1.9), (0.1, 0.7, 0.5), "water", r=0.01)
        sphere("frame_sun", (-3.95, 1.8, 2.02), 0.08, "yellow", seg=8)


def build_player():
    """Wonder Boy style hero, rigged in Blender: armature (Root/Spine/Head/ArmL/ArmR/LegL/LegR),
    one skinned mesh (rigid per-part weights), and keyframed Walk / Idle / Wave actions exported
    as glTF animations that Godot plays through its AnimationPlayer."""
    import mathutils

    # --- armature
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "PlayerRig"
    arm.data.name = "PlayerRig"
    eb = arm.data.edit_bones
    root = eb[0]
    root.name, root.head, root.tail = "Root", (0, 0, 0), (0, 0, 0.3)

    def bone(name, head, tail, parent):
        b_ = eb.new(name)
        b_.head, b_.tail, b_.parent = head, tail, parent
        return b_

    spine = bone("Spine", (0, 0, 0.3), (0, 0, 1.0), root)
    bone("Head", (0, 0, 1.0), (0, 0, 2.0), spine)
    bone("ArmL", (0, 0.31, 0.82), (0.08, 0.42, 0.46), spine)
    bone("ArmR", (0, -0.31, 0.82), (0.08, -0.42, 0.46), spine)
    bone("LegL", (0, 0.14, 0.36), (0, 0.14, 0.0), root)
    bone("LegR", (0, -0.14, 0.36), (0, -0.14, 0.0), root)
    bpy.ops.object.mode_set(mode="OBJECT")

    # --- parts (each becomes a rigid vertex group named after its bone)
    # Clean chibi built from sculpted subdivision cages: big smooth head, soft hair cap with a swept
    # fringe, egg-shaped tunic, stubby limbs. Few, large features so it reads at isometric scale.
    parts = []
    for s_ in (-1, 1):
        side = "L" if s_ > 0 else "R"
        with Part(f"Leg{side}", arm, (0, s_ * 0.15, 0.34)) as pt:
            profile_cage(
                f"leg{s_}",
                [(0.14, 0.1, 0.1), (0.26, 0.105, 0.105), (0.36, 0.12, 0.12)],
                "skin",
                segments=10,
                offset=(0, s_ * 0.15, 0),
            )
            boot = cube_cage(
                f"boot{s_}", (0.05, s_ * 0.15, 0.11), (0.32, 0.22, 0.2), "shoe"
            )
            extrude(
                boot, lambda c, n: n.x > 0.9 and c.z < 0.16, 0.1, shrink=0.7
            )  # rounded toe
            cube_cage(
                f"sole{s_}",
                (0.07, s_ * 0.15, 0.025),
                (0.42, 0.26, 0.05),
                "shoe_sole",
                subsurf=1,
            )
            torus(f"boot_band{s_}", (0.02, s_ * 0.15, 0.2), 0.12, 0.03, "cream")
        parts.append((pt.obj, f"Leg{side}"))
        with Part(f"Arm{side}", arm, (0.0, s_ * 0.33, 0.8)) as pt:
            # one smooth stubby arm: sleeve at the top, skin below, mitten hand
            profile_cage(
                f"sleeve{s_}",
                [
                    (0.66, 0.1, 0.1, 0.04, s_ * 0.4),
                    (0.78, 0.13, 0.13, 0.01, s_ * 0.37),
                    (0.88, 0.12, 0.12, -0.01, s_ * 0.33),
                ],
                "body",
                segments=10,
            )
            profile_cage(
                f"forearm{s_}",
                [
                    (0.5, 0.075, 0.075, 0.09, s_ * 0.45),
                    (0.6, 0.08, 0.08, 0.06, s_ * 0.43),
                    (0.7, 0.085, 0.085, 0.04, s_ * 0.41),
                ],
                "skin",
                segments=10,
            )
            hand = sphere_cage(
                f"hand{s_}",
                (0.11, s_ * 0.46, 0.44),
                0.1,
                "skin",
                segments=10,
                rings=8,
                scale=(1.05, 0.9, 1.1),
            )
        parts.append((pt.obj, f"Arm{side}"))
    with Part("Body", arm, (0, 0, 0.3)) as pt:
        # egg-shaped tunic: wide soft hem, narrow neck; short sleeves extruded from the shoulders
        body = profile_cage(
            "tunic",
            [
                (0.32, 0.4, 0.37),
                (0.4, 0.4, 0.37),
                (0.55, 0.37, 0.34),
                (0.72, 0.36, 0.33),
                (0.88, 0.33, 0.3),
                (0.98, 0.2, 0.19),
                (1.03, 0.11, 0.11),
            ],
            "body",
            segments=14,
        )
        extrude(
            body, lambda c, n: abs(n.y) > 0.85 and 0.78 < c.z < 0.95, 0.05, shrink=0.9
        )
        cyl("neck", (0, 0, 1.0), 0.1, 0.12, "skin", verts=8)
        # tunic trim: cream collar band + a big simple belt with a buckle, scarf with tail
        torus("collar", (0, 0, 0.99), 0.16, 0.035, "cream")
        torus("belt", (0, 0, 0.5), 0.37, 0.05, "shoe")
        rbox("buckle", (0.36, 0, 0.5), (0.05, 0.13, 0.13), "yellow", r=0.03)
        torus("scarf", (0, 0, 1.02), 0.2, 0.07, "red")
        profile_cage(
            "scarf_tail",
            [
                (0.0, 0.08, 0.035, -0.25, 0.05),
                (-0.12, 0.08, 0.04, -0.4, 0.08),
                (-0.26, 0.07, 0.035, -0.55, 0.1),
                (-0.36, 0.05, 0.025, -0.68, 0.14),
            ],
            "red",
            segments=8,
            offset=(0, 0, 1.0),
        )
        profile_cage(
            "shorts",
            [(0.24, 0.31, 0.28), (0.36, 0.34, 0.31)],
            "shorts",
            segments=12,
            subsurf=1,
        )
    parts.append((pt.obj, "Spine"))
    with Part("Head", arm, (0, 0, 1.0)) as pt:
        # head: sphere cage sculpted wider than tall with a soft jaw; nose is a tiny extrusion
        head = sphere_cage(
            "head",
            (0, 0, 1.5),
            0.56,
            "skin",
            segments=16,
            rings=12,
            scale=(1.0, 1.06, 0.9),
        )

        def skull(v):
            t = (v.z - 1.5) / 0.56
            if t < 0:
                k = 1.0 + 0.1 * t
                v.x *= k
                v.y *= k + 0.02
            return v

        sculpt(head, skull)
        extrude(
            head,
            lambda c, n: n.x > 0.97 and abs(c.y) < 0.09 and 1.33 < c.z < 1.42,
            0.04,
            shrink=0.5,
        )  # nose
        for s_ in (-1, 1):
            sphere_cage(
                f"ear{s_}",
                (0.0, s_ * 0.57, 1.46),
                0.09,
                "skin",
                segments=10,
                rings=8,
                scale=(0.7, 0.55, 1.0),
            )
        # hair: one smooth cap with a few soft tufts and a swept fringe over the forehead
        hair = sphere_cage(
            "hair",
            (-0.03, 0, 1.6),
            0.61,
            "hair",
            segments=16,
            rings=10,
            scale=(1.0, 1.04, 0.88),
            keep=lambda x, y, z: z > 0.02 or (x < -0.25 and z > -0.5),
        )
        # four big soft tufts (angular windows around the crown) + one swept fringe patch
        for k, (a0, a1, ln) in enumerate(
            [(-0.4, 0.5, 0.16), (1.0, 1.9, 0.14), (2.4, 3.4, 0.15), (-2.2, -1.2, 0.13)]
        ):
            extrude_region(
                hair,
                lambda c, n, a0=a0, a1=a1: n.z > 0.45
                and a0 < math.atan2(c.y, c.x + 0.03) < a1,
                ln,
                shrink=0.6,
            )
        extrude_region(
            hair,
            lambda c, n: n.x > 0.55 and 1.6 < c.z < 1.95 and abs(c.y) < 0.45,
            0.16,
            shrink=0.85,
            direction=(0.5, 0.1, -0.85),
        )
        for s_ in (-1, 1):
            profile_cage(
                f"lock{s_}",
                [
                    (1.3, 0.07, 0.06, 0.18, s_ * 0.5),
                    (1.45, 0.11, 0.08, 0.15, s_ * 0.52),
                    (1.58, 0.1, 0.07, 0.1, s_ * 0.52),
                ],
                "hair",
                segments=8,
            )
        # headband over the hair, knot + tails at the back
        torus("headband", (-0.02, 0, 1.66), 0.62, 0.06, "red", rot=(0, 0.1, 0))
        sphere_cage("knot", (-0.62, 0.05, 1.6), 0.09, "red", segments=8, rings=6)
        profile_cage(
            "band_tail",
            [
                (1.6, 0.05, 0.04, -0.67, 0.12),
                (1.43, 0.05, 0.04, -0.72, 0.16),
                (1.26, 0.04, 0.03, -0.7, 0.2),
            ],
            "red",
            segments=8,
        )
        # face: two big dark eyes with glints, rosy cheeks, small smile
        for s_ in (-1, 1):
            sphere(
                f"eye{s_}",
                (0.5, s_ * 0.2, 1.46),
                0.1,
                "eye",
                scale=(0.35, 0.85, 1.35),
                seg=12,
            )
            sphere(f"glint{s_}", (0.585, s_ * 0.23, 1.54), 0.032, "white", seg=10)
            sphere(f"glint2{s_}", (0.585, s_ * 0.17, 1.4), 0.016, "white", seg=8)
            sphere(
                f"cheek{s_}",
                (0.47, s_ * 0.37, 1.31),
                0.085,
                "pink",
                scale=(0.35, 1, 0.7),
                seg=8,
            )
        torus(
            "smile", (0.52, 0, 1.29), 0.06, 0.016, "wall_trim", rot=(0, math.pi / 2, 0)
        )
        cube("smile_mask", (0.49, 0, 1.325), (0.12, 0.16, 0.05), "skin")
    parts.append((pt.obj, "Head"))

    # --- skin: rigid weights per part, join into one mesh, armature modifier
    def rig(obj, bname):
        obj.parent = None
        vg = obj.vertex_groups.new(name=bname)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    for obj, bname in parts:
        rig(obj, bname)
    bpy.ops.object.select_all(action="DESELECT")
    for obj, _ in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0][0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = "PlayerMesh"
    mesh.modifiers.new("Armature", "ARMATURE").object = arm
    mesh.parent = arm

    # --- interchangeable parts: Var_<category>_<name>. Godot keeps one per category, chosen
    # from a hash of the player's name, so every player looks different but consistent.
    def variant(category, name, bone, build):
        with Part(f"Var_{category}_{name}", arm, (0, 0, 0)) as pt:
            build()
        rig(pt.obj, bone)
        pt.obj.modifiers.new("Armature", "ARMATURE").object = arm
        pt.obj.parent = arm

    # hair styles (the spiky one lives in the core head; these replace its silhouette on top)
    def hair_bob():
        bob = sphere_cage(
            "bob",
            (-0.04, 0, 1.58),
            0.62,
            "hair",
            segments=16,
            rings=10,
            scale=(1.0, 1.05, 0.9),
            keep=lambda x, y, z: z > -0.35 and not (x > 0.35 and z < 0.05),
        )
        extrude(
            bob,
            lambda c, n: n.x > 0.7 and 1.62 < c.z < 1.9,
            0.14,
            shrink=0.7,
            direction=(0.4, 0, -0.9),
        )

    def hair_ponytail():
        cap = sphere_cage(
            "pt_cap",
            (-0.04, 0, 1.62),
            0.6,
            "hair",
            segments=16,
            rings=10,
            scale=(1.0, 1.02, 0.82),
            keep=lambda x, y, z: z > -0.1,
        )
        extrude(
            cap,
            lambda c, n: n.x > 0.75 and 1.62 < c.z < 1.85,
            0.16,
            shrink=0.6,
            direction=(0.5, 0, -0.85),
        )
        torus("pt_band", (-0.55, 0, 1.6), 0.09, 0.04, "yellow", rot=(0, math.pi / 2, 0))
        profile_cage(
            "pt_tail",
            [
                (1.6, 0.11, 0.1, -0.6, 0.0),
                (1.42, 0.13, 0.11, -0.72, 0.0),
                (1.2, 0.11, 0.09, -0.8, 0.02),
                (1.0, 0.06, 0.05, -0.85, 0.05),
            ],
            "hair",
            segments=10,
        )

    def hair_curly():
        cur = sphere_cage(
            "curly",
            (-0.04, 0, 1.64),
            0.62,
            "hair",
            segments=16,
            rings=10,
            scale=(1.0, 1.05, 0.85),
            keep=lambda x, y, z: z > -0.2,
        )
        extrude(
            cur,
            lambda c, n: n.z > -0.2
            and int(round(math.atan2(c.y, c.x) * 5 + c.z * 7)) % 2 == 0,
            0.12,
            shrink=0.7,
        )

    def hair_bun():
        cap = sphere_cage(
            "bun_cap",
            (-0.04, 0, 1.62),
            0.6,
            "hair",
            segments=16,
            rings=10,
            scale=(1.0, 1.02, 0.8),
            keep=lambda x, y, z: z > -0.1,
        )
        extrude(
            cap,
            lambda c, n: n.x > 0.75 and 1.62 < c.z < 1.85,
            0.14,
            shrink=0.6,
            direction=(0.5, 0, -0.85),
        )
        sphere_cage("bun", (-0.15, 0, 2.15), 0.2, "hair", segments=10, rings=8)
        torus("bun_band", (-0.15, 0, 2.02), 0.12, 0.03, "pink")
        for s_ in (-1, 1):
            profile_cage(
                f"bun_side{s_}",
                [(1.3, 0.07, 0.06, 0.15, s_ * 0.48), (1.5, 0.1, 0.08, 0.12, s_ * 0.5)],
                "hair",
                segments=8,
            )

    variant("hair", "bob", "Head", hair_bob)
    variant("hair", "ponytail", "Head", hair_ponytail)
    variant("hair", "curly", "Head", hair_curly)
    variant("hair", "bun", "Head", hair_bun)

    # headgear
    def hat_straw():
        cyl("hat_brim", (0, 0, 1.98), 0.7, 0.05, "straw", verts=18)
        cyl("hat_top", (0, 0, 2.1), 0.42, 0.24, "straw", verts=18, r2=0.36)
        torus("hat_band", (0, 0, 2.02), 0.43, 0.035, "red")

    def hat_cap():
        sphere("cap", (-0.05, 0, 1.85), 0.52, "blue", scale=(1, 1, 0.55))
        rbox("cap_peak", (-0.6, 0, 1.78), (0.4, 0.5, 0.05), "blue", r=0.03)
        sphere("cap_button", (-0.05, 0, 2.14), 0.05, "yellow", seg=6)

    def hat_flower():
        sphere("flower_c", (0.15, 0.42, 1.95), 0.08, "yellow", seg=8)
        for k in range(6):
            a_ = k * math.pi / 3
            sphere(
                f"petal{k}",
                (0.15 + math.cos(a_) * 0.09, 0.42 + math.sin(a_) * 0.11, 1.95),
                0.06,
                "pink",
                scale=(1, 1, 0.5),
                seg=6,
            )

    def hat_goggles():
        for s_ in (-1, 1):
            torus(
                f"goggle{s_}",
                (0.35, s_ * 0.2, 1.82),
                0.11,
                0.035,
                "metal_dark",
                rot=(0, 1.2, 0),
            )
            cyl(
                f"lens{s_}",
                (0.36, s_ * 0.2, 1.82),
                0.09,
                0.03,
                "cyan",
                verts=12,
                rot=(0, 1.2, 0),
            )
        torus("goggle_strap", (0, 0, 1.78), 0.52, 0.03, "shoe", rot=(0, 0.2, 0))

    variant("hat", "straw", "Head", hat_straw)
    variant("hat", "cap", "Head", hat_cap)
    variant("hat", "flower", "Head", hat_flower)
    variant("hat", "goggles", "Head", hat_goggles)

    # back items
    def back_backpack():
        rbox("pack", (-0.36, 0, 0.72), (0.2, 0.34, 0.4), "roof_dark", r=0.06)
        rbox("pack_flap", (-0.4, 0, 0.9), (0.2, 0.36, 0.1), "roof", r=0.04)
        rbox("pack_pocket", (-0.47, 0, 0.62), (0.06, 0.2, 0.16), "roof", r=0.03)

    def back_shield():
        cyl(
            "shield",
            (-0.38, 0, 0.78),
            0.27,
            0.05,
            "wood",
            verts=16,
            rot=(0, math.pi / 2, 0),
        )
        sphere("shield_boss", (-0.42, 0, 0.78), 0.07, "yellow", seg=8)
        torus(
            "shield_rim",
            (-0.38, 0, 0.78),
            0.27,
            0.03,
            "metal_dark",
            rot=(0, math.pi / 2, 0),
        )

    def back_wings():
        for s_ in (-1, 1):
            leaf(
                f"wing{s_}",
                (-0.3, s_ * 0.1, 0.9),
                0.5,
                0.3,
                "white",
                math.pi + s_ * 0.9,
                pitch=-0.6,
                thick=0.03,
            )

    variant("back", "backpack", "Spine", back_backpack)

    # neckwear
    def neck_necklace():
        torus("necklace", (0.05, 0, 0.95), 0.2, 0.02, "yellow", rot=(0, 0.3, 0))
        sphere("pendant", (0.3, 0, 0.86), 0.05, "cyan", seg=8)

    def neck_bowtie():
        for s_ in (-1, 1):
            cube(
                f"bow{s_}",
                (0.28, s_ * 0.09, 0.97),
                (0.05, 0.14, 0.09),
                "pink",
                rot=(s_ * 0.3, 0, 0),
            )
        sphere("bow_knot", (0.3, 0, 0.97), 0.035, "red", seg=6)

    variant("neck", "necklace", "Spine", neck_necklace)
    variant("neck", "bowtie", "Spine", neck_bowtie)

    # outfit overlays
    def outfit_overalls():
        for s_ in (-1, 1):
            rbox(
                f"strap{s_}", (0.2, s_ * 0.16, 0.8), (0.05, 0.08, 0.36), "blue", r=0.02
            )
            sphere(f"stud{s_}", (0.26, s_ * 0.16, 0.95), 0.03, "yellow", seg=6)
        rbox("bib", (0.28, 0, 0.66), (0.1, 0.34, 0.24), "blue", r=0.04)
        rbox("bib_pocket", (0.34, 0, 0.62), (0.03, 0.18, 0.12), "shorts", r=0.02)

    def outfit_sailor():
        cube("collar_back", (-0.15, 0, 1.0), (0.3, 0.5, 0.04), "white")
        for s_ in (-1, 1):
            cube(
                f"collar_front{s_}",
                (0.2, s_ * 0.16, 0.9),
                (0.28, 0.12, 0.04),
                "white",
                rot=(0, -0.5, s_ * 0.5),
            )
        cube("collar_stripe", (-0.15, 0, 1.005), (0.28, 0.46, 0.04), "blue")
        cube("collar_stripe_in", (-0.15, 0, 1.01), (0.22, 0.38, 0.04), "white")

    def outfit_apron():
        rbox("apron", (0.3, 0, 0.5), (0.1, 0.42, 0.34), "cream", r=0.04)
        rbox("apron_pocket", (0.36, 0, 0.45), (0.03, 0.2, 0.12), "pot", r=0.02)
        torus("apron_tie", (0, 0, 0.66), 0.36, 0.02, "cream")

    variant("outfit", "overalls", "Spine", outfit_overalls)
    variant("outfit", "sailor", "Spine", outfit_sailor)
    variant("outfit", "apron", "Spine", outfit_apron)

    # --- animations
    arm.animation_data_create()
    sc = bpy.context.scene
    sc.render.fps = 24

    def swing_axis(bname):
        """Find which local euler axis swings the limb forward (+X in world)."""
        pb = arm.pose.bones[bname]
        best, best_dx = 0, -1
        for axis in range(3):
            pb.rotation_mode = "XYZ"
            rot = [0, 0, 0]
            rot[axis] = 0.6
            pb.rotation_euler = rot
            bpy.context.view_layer.update()
            dx = (arm.matrix_world @ pb.tail).x - (
                arm.matrix_world @ pb.bone.tail_local
            ).x
            if abs(dx) > best_dx:
                best, best_dx, sign = axis, abs(dx), 1 if dx > 0 else -1
            pb.rotation_euler = (0, 0, 0)
        return best, sign

    axes = {b_: swing_axis(b_) for b_ in ("ArmL", "ArmR", "LegL", "LegR")}
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"

    def key_pose(frame, rots, root_z=0.0, spine_scale=1.0):
        sc.frame_set(frame)
        for pb in arm.pose.bones:
            pb.rotation_euler = (0, 0, 0)
        for bname, (fwd, side, twist) in rots.items():
            pb = arm.pose.bones[bname]
            if bname in axes:
                ax, sign = axes[bname]
                rot = [0.0, 0.0, 0.0]
                rot[ax] = fwd * sign
                rot[(ax + 1) % 3] += side
                pb.rotation_euler = rot
            else:
                pb.rotation_euler = (fwd, side, twist)
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=frame)
        rb = arm.pose.bones["Root"]
        rb.location = (
            0,
            root_z,
            0,
        )  # bone-local Y is world Z for the upright root bone
        rb.keyframe_insert("location", frame=frame)
        sp = arm.pose.bones["Spine"]
        sp.scale = (1.0, spine_scale, 1.0)
        sp.keyframe_insert("scale", frame=frame)

    def make_action(name, keyer, length):
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        keyer()
        act.frame_range = (1, length)
        act.use_frame_range = True
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, act)
        arm.animation_data.action = None

    A = 0.8  # leg swing
    B = 0.7  # arm swing

    def walk():
        for i, t in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
            f = 1 + int(t * 24)
            s_ = math.sin(t * 2 * math.pi)
            hop = abs(math.sin(t * 2 * math.pi)) * 0.05
            key_pose(
                f,
                {
                    "LegL": (A * s_, 0, 0),
                    "LegR": (-A * s_, 0, 0),
                    "ArmL": (-B * s_, 0.12, 0),
                    "ArmR": (B * s_, -0.12, 0),
                    "Spine": (0.08, 0, 0.12 * s_),
                    "Head": (-0.05, 0, -0.08 * s_),
                },
                root_z=hop,
            )

    def idle():
        for i, t in enumerate((0.0, 0.5, 1.0)):
            f = 1 + int(t * 48)
            c = math.cos(t * 2 * math.pi)
            key_pose(
                f,
                {
                    "LegL": (0, 0, 0),
                    "LegR": (0, 0, 0),
                    "ArmL": (0.05 * c, 0.1, 0),
                    "ArmR": (0.05 * c, -0.1, 0),
                    "Spine": (0.02 * c, 0, 0),
                    "Head": (0.03 * c, 0.04 * c, 0),
                },
                spine_scale=1.0 + 0.02 * c,
            )

    def wave():
        for i, t in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
            f = 1 + int(t * 24)
            s_ = math.sin(t * 2 * math.pi)
            key_pose(
                f,
                {
                    "ArmL": (-2.6, 0.5 + 0.4 * s_, 0),
                    "ArmR": (0, -0.1, 0),
                    "Head": (0, 0, 0.15 * s_),
                },
            )

    make_action("Walk", walk, 25)
    make_action("Idle", idle, 49)
    make_action("Wave", wave, 25)
    sc.frame_set(1)
    MODELS["player"] = arm


def build_palm():
    with Model("palm"):
        tip = curved_trunk("trunk", (0, 0, 0), (0.7, 0.2), 3.4)
        sphere("crown", tip, 0.32, "trunk_dark", seg=10)
        for k in range(7):
            yaw = k * 2 * math.pi / 7 + 0.2
            frond(
                f"frond{k}",
                tip,
                yaw,
                length=2.1 if k % 2 else 1.8,
                droop=1.0 if k % 2 else 0.6,
                m="leaf" if k % 3 else "leaf_light",
            )
        for k in range(3):
            a = k * 2.1
            sphere(
                f"coco{k}",
                (
                    tip[0] + math.cos(a) * 0.28,
                    tip[1] + math.sin(a) * 0.28,
                    tip[2] - 0.25,
                ),
                0.17,
                "wood_dark",
                seg=10,
            )


def build_monstera():
    with Model("monstera"):
        cyl("pot", (0, 0, 0.32), 0.33, 0.64, "pot", verts=14, r2=0.42)
        torus("rim", (0, 0, 0.62), 0.42, 0.07, "pot_rim")
        cyl("soil", (0, 0, 0.64), 0.37, 0.05, "soil", verts=14)
        for k in range(5):
            yaw = k * 2 * math.pi / 5 + 0.5
            lean = 0.55 if k % 2 else 0.35
            capsule(
                f"stem{k}",
                (0, 0, 0.7),
                (math.cos(yaw) * 0.45, math.sin(yaw) * 0.45, 1.35 + (k % 2) * 0.3),
                0.035,
                "leaf_dark",
                verts=6,
            )
            leaf(
                f"leaf{k}",
                (math.cos(yaw) * 0.4, math.sin(yaw) * 0.4, 1.3 + (k % 2) * 0.3),
                1.05,
                0.8,
                "leaf",
                yaw,
                pitch=-lean,
                thick=0.06,
            )
            # monstera "holes": small dark notches on the leaf
            for j in range(2):
                sphere(
                    f"hole{k}{j}",
                    (
                        math.cos(yaw) * (0.75 + j * 0.25),
                        math.sin(yaw) * (0.75 + j * 0.25) + (j - 0.5) * 0.2,
                        1.45 + (k % 2) * 0.3 + (0.25 + j * 0.25) * lean,
                    ),
                    0.06,
                    "leaf_dark",
                    scale=(1.6, 1, 0.5),
                    seg=6,
                )


def build_flower_pot():
    with Model("flower_pot"):
        cyl("pot", (0, 0, 0.24), 0.28, 0.48, "pot", verts=14, r2=0.34)
        torus("rim", (0, 0, 0.47), 0.34, 0.06, "pot_rim")
        rbox("pot_band", (0, 0, 0.2), (0.62, 0.62, 0.1), "pot_rim", r=0.03)
        sphere("bush", (0, 0, 0.68), 0.34, "leaf", scale=(1, 1, 0.8))
        sphere("bush2", (0.15, -0.1, 0.8), 0.22, "leaf_light", seg=10)
        for k, c in enumerate(["pink", "yellow", "red", "purple", "white", "pink"]):
            a = k * 1.05
            x, y = math.cos(a) * 0.24, math.sin(a) * 0.24
            sphere(f"flower{k}", (x, y, 0.95), 0.12, c, seg=10)
            sphere(
                f"center{k}",
                (x, y, 1.06),
                0.05,
                "yellow" if c != "yellow" else "red",
                seg=6,
            )
        sphere("flower_top", (0, 0, 1.08), 0.13, "yellow", seg=10)


def build_cactus():
    with Model("cactus"):
        cyl("pot", (0, 0, 0.24), 0.28, 0.48, "pot", verts=14, r2=0.34)
        torus("rim", (0, 0, 0.47), 0.34, 0.06, "pot_rim")
        cyl("sand", (0, 0, 0.49), 0.28, 0.04, "sand", verts=14)
        capsule("body", (0, 0, 0.5), (0, 0, 1.55), 0.22, "leaf", verts=12)
        for k in range(6):
            a = k * math.pi / 3
            cube(
                f"rib{k}",
                (math.cos(a) * 0.21, math.sin(a) * 0.21, 1.0),
                (0.05, 0.05, 1.0),
                "leaf_dark",
                rot=(0, 0, a),
            )
        capsule("arm_l", (-0.2, 0, 1.0), (-0.5, 0, 1.0), 0.12, "leaf")
        capsule("arm_l_up", (-0.5, 0, 1.0), (-0.5, 0, 1.5), 0.12, "leaf")
        capsule("arm_r", (0.2, 0, 0.75), (0.45, 0, 0.75), 0.11, "leaf")
        capsule("arm_r_up", (0.45, 0, 0.75), (0.45, 0, 1.2), 0.11, "leaf")
        sphere("flower", (0, 0, 1.8), 0.11, "pink", seg=8)
        sphere("flower_c", (0, 0, 1.88), 0.05, "yellow", seg=6)
        for k in range(8):
            a = k * 0.8
            sphere(
                f"spike{k}",
                (math.cos(a) * 0.24, math.sin(a) * 0.24, 0.7 + k * 0.1),
                0.03,
                "cream",
                seg=4,
            )


def build_bed():
    with Model("bed"):
        rbox("frame", (0, 0, 0.22), (1.0, 1.95, 0.34), "wood_dark", r=0.05)
        rbox("mattress", (0, 0, 0.45), (0.92, 1.82, 0.22), "cream", r=0.08)
        rbox("blanket", (0, -0.22, 0.6), (0.94, 1.25, 0.14), "blue", r=0.06)
        rbox("blanket_fold", (0, 0.35, 0.62), (0.94, 0.22, 0.16), "cyan", r=0.05)
        sphere(
            "pillow", (0, 0.66, 0.64), 0.3, "white", scale=(1.05, 0.55, 0.45), seg=12
        )
        rbox("headboard", (0, 0.95, 0.75), (1.0, 0.1, 1.2), "wood", r=0.05)
        rbox("headboard_in", (0, 0.9, 0.85), (0.78, 0.06, 0.6), "wood_light", r=0.04)
        rbox("footboard", (0, -0.95, 0.42), (1.0, 0.1, 0.55), "wood", r=0.05)
        sphere("teddy", (0.25, 0.35, 0.78), 0.11, "wood_light", seg=10)
        sphere("teddy_head", (0.25, 0.35, 0.93), 0.08, "wood_light", seg=10)
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl(
                    f"leg{sx}{sy}",
                    (sx * 0.42, sy * 0.88, 0.05),
                    0.07,
                    0.1,
                    "wood_dark",
                    verts=8,
                )


def build_table():
    with Model("table"):
        cyl("top", (0, 0, 0.82), 0.5, 0.08, "wood", verts=20)
        cyl("cloth", (0, 0, 0.87), 0.42, 0.04, "cream", verts=20)
        cyl("leg", (0, 0, 0.42), 0.08, 0.8, "wood_dark", verts=10)
        cyl("foot", (0, 0, 0.04), 0.3, 0.08, "wood_dark", verts=16)
        cyl("cup", (0.2, -0.15, 0.95), 0.08, 0.14, "pink", verts=12)
        torus(
            "cup_handle",
            (0.3, -0.15, 0.95),
            0.06,
            0.02,
            "pink",
            rot=(math.pi / 2, 0, 0),
        )
        cyl("plate", (-0.18, 0.12, 0.9), 0.17, 0.03, "white", verts=14)
        sphere("cake", (-0.18, 0.12, 0.96), 0.1, "roof", scale=(1, 1, 0.6), seg=10)
        sphere("cherry", (-0.18, 0.12, 1.04), 0.04, "red", seg=6)
        cyl("vase", (0.05, 0.22, 0.96), 0.05, 0.16, "cyan", verts=10)
        sphere("vase_flower", (0.05, 0.22, 1.1), 0.07, "yellow", seg=8)


def build_chair():
    with Model("chair"):
        rbox("seat", (0, 0, 0.47), (0.62, 0.62, 0.1), "wood", r=0.04)
        rbox("cushion", (0, 0, 0.55), (0.52, 0.52, 0.1), "red", r=0.05)
        rbox("back", (0, 0.27, 0.9), (0.62, 0.09, 0.8), "wood", r=0.04)
        rbox("back_pad", (0, 0.22, 0.95), (0.44, 0.06, 0.5), "red", r=0.04)
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl(
                    f"leg{sx}{sy}",
                    (sx * 0.25, sy * 0.25, 0.22),
                    0.045,
                    0.44,
                    "wood_dark",
                    verts=8,
                )
        rbox("rail", (0, 0, 0.15), (0.5, 0.05, 0.05), "wood_dark", r=0.01)


def build_lamp():
    with Model("lamp"):
        cyl("base", (0, 0, 0.06), 0.28, 0.12, "metal_dark", verts=14)
        cyl("base2", (0, 0, 0.14), 0.18, 0.06, "metal", verts=14)
        cyl("pole", (0, 0, 0.9), 0.045, 1.6, "metal", verts=8)
        cyl("shade", (0, 0, 1.8), 0.42, 0.55, "yellow", verts=16, r2=0.24)
        torus("shade_rim", (0, 0, 1.53), 0.42, 0.03, "wall_trim")
        torus("shade_top", (0, 0, 2.07), 0.24, 0.03, "wall_trim")
        sphere("bulb", (0, 0, 1.62), 0.17, mat("lamp", emission=2.5), seg=10)


def build_rug():
    with Model("rug"):
        rbox("rug", (0, 0, 0.03), (1.9, 1.9, 0.06), "rug_base", r=0.03)
        for sx in (-1, 1):
            for i in range(5):
                rbox(
                    f"tassel{sx}{i}",
                    (sx * 1.0, -0.8 + i * 0.4, 0.03),
                    (0.12, 0.08, 0.04),
                    "cream",
                    r=0.01,
                )


def build_bookshelf():
    with Model("bookshelf"):
        rbox("back", (0, 0.4, 1.0), (0.95, 0.1, 2.0), "wood_dark", r=0.02)
        for z in (0.1, 0.72, 1.34, 1.96):
            rbox(f"shelf{z}", (0, 0.25, z), (0.95, 0.45, 0.08), "wood", r=0.02)
        for sx in (-1, 1):
            rbox(f"side{sx}", (sx * 0.45, 0.25, 1.0), (0.08, 0.45, 2.0), "wood", r=0.02)
        cols = ["book1", "book2", "book3", "book4"]
        for row, z in enumerate((0.42, 1.04)):
            for i in range(5):
                rbox(
                    f"book{row}{i}",
                    (-0.32 + i * 0.16, 0.25, z),
                    (0.12, 0.3, 0.55 - (i % 2) * 0.1),
                    cols[(i + row) % 4],
                    r=0.015,
                )
        rbox("book_flat", (0.1, 0.25, 1.42), (0.5, 0.3, 0.08), "book2", r=0.01)
        rbox("book_flat2", (0.05, 0.25, 1.5), (0.4, 0.28, 0.08), "book3", r=0.01)
        sphere("plant", (-0.25, 0.25, 1.75), 0.18, "leaf_light", seg=10)
        cyl("plantpot", (-0.25, 0.25, 1.6), 0.1, 0.16, "pot", verts=10)
        cyl("mug", (0.3, 0.25, 0.22), 0.08, 0.14, "cyan", verts=10)


def build_portal():
    with Model("portal"):
        cyl("pedestal", (0, 0, 0.12), 0.6, 0.25, "stone", verts=14)
        cyl("pedestal2", (0, 0, 0.3), 0.45, 0.15, "stone_dark", verts=14)
        cyl(
            "rune", (0, 0, 0.38), 0.32, 0.02, mat("portal_glow", emission=1.2), verts=16
        )
        # The aperture and circulating trails are real-time Godot effects (PortalFX.gd).
        for k in range(2):
            cube(
                f"crystal{k}",
                ((k - 0.5) * 1.0, 0.35, 0.55),
                (0.18, 0.18, 0.5),
                mat("portal", emission=0.6),
                rot=(0.2, 0.2 * (k - 0.5), math.pi / 4),
            )


def build_cloud():
    with Model("cloud"):
        for i, (x, y, r) in enumerate(
            [
                (0, 0, 0.9),
                (0.9, 0.1, 0.7),
                (-0.9, -0.1, 0.65),
                (0.3, 0.5, 0.6),
                (-0.3, -0.5, 0.55),
            ]
        ):
            sphere(f"puff{i}", (x, y, r * 0.6), r, "cloud", scale=(1, 1, 0.75), seg=12)
        rbox("base", (0, 0, 0.15), (2.6, 1.4, 0.3), "cloud", r=0.1)


BUILDERS = [
    build_cloud,
    build_tree,
    build_bench,
    build_flower_bed,
    build_island,
    build_house,
    build_player,
    build_palm,
    build_monstera,
    build_flower_pot,
    build_cactus,
    build_bed,
    build_table,
    build_chair,
    build_lamp,
    build_rug,
    build_bookshelf,
    build_portal,
]


# ---------------------------------------------------------------- driver
def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for b in list(block):
            if b.users == 0:
                block.remove(b)
    _mats.clear()
    MODELS.clear()


def build_all():
    clear_scene()
    bpy.context.scene.cursor.location = (0, 0, 0)
    for b in BUILDERS:
        b()
    return MODELS


def export_all(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, obj in MODELS.items():
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        for c in obj.children_recursive:
            c.select_set(True)
        bpy.context.view_layer.objects.active = obj
        obj.location = (0, 0, 0)
        path = os.path.join(out_dir, f"{name}.glb")
        rigged = obj.type == "ARMATURE"
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_apply=not rigged,
            export_yup=True,
            export_animations=rigged,
            export_animation_mode="ACTIONS",
            export_nla_strips=True,
            export_skins=rigged,
        )
        print("exported", path, os.path.getsize(path), "bytes")


def showcase():
    """Lay every model out in a row for a viewport screenshot."""
    build_all()
    x = -9.0
    for name, obj in MODELS.items():
        if name == "island":
            obj.location = (0, 14, 0)
            continue
        if name == "house":
            obj.location = (0, 14, 0)
            continue
        obj.location = (x, 0, 0)
        x += 2.4


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out = argv[0] if argv else "godot/assets/models"
    build_all()
    export_all(out)
    blend_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "coast_assets.blend")
    )
    # lay models out on a grid so the .blend is pleasant to open
    for i, (name, obj) in enumerate(MODELS.items()):
        obj.location = (
            ((i % 5) * 6.0, (i // 5) * -8.0, 0.0)
            if name not in ("island", "house")
            else (0.0, 20.0, 0.0)
        )
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True)
    print("saved", blend_path)
