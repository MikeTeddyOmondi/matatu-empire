#!/usr/bin/env python3
"""Generate a stylized low-poly matatu (14-seater minibus) mesh.

Pure numpy, no 3D libraries. Writes:
  assets/matatu.glb   - glTF binary, one node per material (Body, Livery, Glass, Lights, TailLights, Trim)
  assets/matatu.obj   - same geometry as OBJ + MTL, one object per material

Units are studs. +Y is up, the front of the van faces -Z, and the body sits on y = 0.
The game rescales the model to each tier's size, so only proportions matter.

Usage: python3 tools/make_matatu_mesh.py [out_dir]
"""

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

LENGTH = 18.0  # along Z
HALF_W = 4.0  # half width at the waist
HEIGHT = 5.4

# Axles (distance from the front), matching VehicleService: axleZ = L/2 - 3.
FRONT_AXLE = 3.0
REAR_AXLE = LENGTH - 3.0
WHEEL_CENTER_Y = -1.0  # the wheel centre sits 1 stud below the body bottom
ARCH_RADIUS = 2.4


def half_width(y: float) -> float:
    """Slight tumblehome: the upper body leans in toward the roof."""
    return HALF_W - 0.35 * max(0.0, (y - 3.0) / (HEIGHT - 3.0))


def to_z(s: float) -> float:
    """Profile distance-from-front -> model Z (front at -Z)."""
    return s - LENGTH / 2


# ---------------------------------------------------------------------------------------------
# Side profile, counter-clockwise in (s, y): s = distance from the front bumper, y = height.

def arch(center_s: float, steps: int = 10):
    a0 = math.asin((0 - WHEEL_CENTER_Y) / ARCH_RADIUS)  # angle where the circle meets y = 0
    start, end = math.pi - a0, a0  # front side of the arch to rear side, over the top
    pts = []
    for i in range(steps + 1):
        t = start + (end - start) * i / steps
        pts.append((center_s + ARCH_RADIUS * math.cos(t), WHEEL_CENTER_Y + ARCH_RADIUS * math.sin(t)))
    return pts


def profile():
    pts = [(0.35, 0.0)]
    pts += arch(FRONT_AXLE)
    pts += arch(REAR_AXLE)
    pts += [
        (17.65, 0.0),
        (18.0, 0.35),
        (18.0, 4.85),
        (17.85, 5.2),
        (17.5, 5.4),
        (4.1, 5.4),
        (3.65, 5.32),
        (3.35, 5.1),  # top of windscreen
        (1.95, 2.8),  # base of windscreen
        (0.75, 2.5),  # hood
        (0.3, 2.25),
        (0.08, 1.85),
        (0.0, 1.4),
        (0.0, 0.35),
    ]
    return pts


# ---------------------------------------------------------------------------------------------
# Triangulation (ear clipping) for the simple profile polygon.

def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _inside(p, a, b, c):
    d1, d2, d3 = _cross(a, b, p), _cross(b, c, p), _cross(c, a, p)
    return d1 > 1e-12 and d2 > 1e-12 and d3 > 1e-12


def triangulate(poly):
    idx = list(range(len(poly)))
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        clipped = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if _cross(a, b, c) <= 1e-12:
                continue  # reflex or degenerate
            if any(_inside(poly[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            clipped = True
            break
        if not clipped:
            raise RuntimeError("triangulation failed: polygon is not simple")
    tris.append(tuple(idx))
    return tris


# ---------------------------------------------------------------------------------------------
# Mesh building with explicit outward directions so winding is always correct.

class Mesh:
    def __init__(self):
        self.tris = []  # list of (3, 3) arrays

    def tri(self, a, b, c, outward):
        a, b, c = np.array(a, float), np.array(b, float), np.array(c, float)
        n = np.cross(b - a, c - a)
        if np.dot(n, outward) < 0:
            b, c = c, b
        self.tris.append(np.stack([a, b, c]))

    def quad(self, a, b, c, d, outward):
        self.tri(a, b, c, outward)
        self.tri(a, c, d, outward)

    def box(self, x0, x1, y0, y1, z0, z1):
        corners = {
            (i, j, k): (x1 if i else x0, y1 if j else y0, z1 if k else z0)
            for i in (0, 1)
            for j in (0, 1)
            for k in (0, 1)
        }
        c = corners
        self.quad(c[1, 0, 0], c[1, 1, 0], c[1, 1, 1], c[1, 0, 1], (1, 0, 0))
        self.quad(c[0, 0, 0], c[0, 1, 0], c[0, 1, 1], c[0, 0, 1], (-1, 0, 0))
        self.quad(c[0, 1, 0], c[1, 1, 0], c[1, 1, 1], c[0, 1, 1], (0, 1, 0))
        self.quad(c[0, 0, 0], c[1, 0, 0], c[1, 0, 1], c[0, 0, 1], (0, -1, 0))
        self.quad(c[0, 0, 1], c[1, 0, 1], c[1, 1, 1], c[0, 1, 1], (0, 0, 1))
        self.quad(c[0, 0, 0], c[1, 0, 0], c[1, 1, 0], c[0, 1, 0], (0, 0, -1))

    def arrays(self):
        tris = np.array(self.tris, dtype=np.float32)  # (n, 3, 3)
        positions = tris.reshape(-1, 3)
        normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        normals /= np.linalg.norm(normals, axis=1, keepdims=True)
        normals = np.repeat(normals, 3, axis=0).astype(np.float32)
        indices = np.arange(len(positions), dtype=np.uint32)
        return positions, normals, indices


def build_body(poly):
    m = Mesh()
    # Side panels.
    for side in (1, -1):
        for i0, i1, i2 in triangulate(poly):
            verts = []
            for s, y in (poly[i0], poly[i1], poly[i2]):
                verts.append((side * half_width(y), y, to_z(s)))
            m.tri(*verts, outward=(side, 0, 0))
    # Perimeter strip joining the two sides. Outward normal of a CCW edge (ds, dy) is (dy, -ds)
    # in (s, y); s maps to +Z.
    for k in range(len(poly)):
        (s0, y0), (s1, y1) = poly[k], poly[(k + 1) % len(poly)]
        ds, dy = s1 - s0, y1 - y0
        outward = (0.0, -ds, dy)  # (x, y, z): y-component = -ds, z-component = dy
        a = (half_width(y0), y0, to_z(s0))
        b = (half_width(y1), y1, to_z(s1))
        c = (-half_width(y1), y1, to_z(s1))
        d = (-half_width(y0), y0, to_z(s0))
        m.quad(a, b, c, d, outward)
    return m


def side_panel(m: Mesh, s0, s1, y0, y1, inset=0.03):
    """A flat panel hugging both body sides between s0..s1 and y0..y1."""
    for side in (1, -1):
        a = (side * (half_width(y0) + inset), y0, to_z(s0))
        b = (side * (half_width(y0) + inset), y0, to_z(s1))
        c = (side * (half_width(y1) + inset), y1, to_z(s1))
        d = (side * (half_width(y1) + inset), y1, to_z(s0))
        m.quad(a, b, c, d, (side, 0, 0))


def build_glass():
    m = Mesh()
    # Side windows split by pillars. The driver/passenger cab window is first.
    panes = [(4.35, 6.7), (7.0, 9.45), (9.75, 12.2), (12.5, 14.95), (15.25, 17.35)]
    for s0, s1 in panes:
        side_panel(m, s0, s1, 3.25, 4.95)
    # Windscreen along the slope from (1.95, 2.8) to (3.35, 5.1).
    ds, dy = 3.35 - 1.95, 5.1 - 2.8
    length = math.hypot(ds, dy)
    ns, ny = -dy / length, ds / length  # outward: forward and up
    off = 0.03
    lo = (1.95 + ds * 0.06 + ns * off, 2.8 + dy * 0.06 + ny * off)
    hi = (1.95 + ds * 0.94 + ns * off, 2.8 + dy * 0.94 + ny * off)
    wl, wh = half_width(lo[1]) - 0.35, half_width(hi[1]) - 0.35
    m.quad(
        (-wl, lo[1], to_z(lo[0])),
        (wl, lo[1], to_z(lo[0])),
        (wh, hi[1], to_z(hi[0])),
        (-wh, hi[1], to_z(hi[0])),
        (0, ny, ns),  # s maps to +Z, and ns < 0 points forward (-Z)
    )
    # Rear window.
    y0, y1 = 3.35, 4.75
    w0, w1 = half_width(y0) - 0.6, half_width(y1) - 0.6
    z = to_z(LENGTH) + 0.03
    m.quad((-w0, y0, z), (w0, y0, z), (w1, y1, z), (-w1, y1, z), (0, 0, 1))
    return m


def build_livery():
    m = Mesh()
    # Main waist stripe and a thinner pinstripe above the wheel arches.
    side_panel(m, 0.6, 17.6, 2.05, 2.75, inset=0.02)
    side_panel(m, 5.6, 12.4, 1.55, 1.8, inset=0.02)
    # Roof-edge band that reads well from the chase camera.
    side_panel(m, 4.3, 17.4, 5.0, 5.25, inset=0.02)
    return m


def build_trim():
    m = Mesh()
    zf, zr = to_z(0), to_z(LENGTH)
    # Bumpers.
    m.box(-HALF_W - 0.05, HALF_W + 0.05, 0.05, 0.7, zf - 0.35, zf + 0.3)
    m.box(-HALF_W - 0.05, HALF_W + 0.05, 0.05, 0.7, zr - 0.3, zr + 0.35)
    # Grille.
    m.box(-1.7, 1.7, 0.8, 1.25, zf - 0.08, zf + 0.1)
    # Side mirrors on short arms.
    for side in (1, -1):
        m.box(side * HALF_W, side * (HALF_W + 0.45), 2.95, 3.05, to_z(1.9), to_z(2.0))
        x0, x1 = sorted((side * (HALF_W + 0.35), side * (HALF_W + 0.75)))
        m.box(x0, x1, 2.7, 3.5, to_z(1.85), to_z(2.1))
    # Roof rails and cross bars (a matatu staple).
    for side in (1, -1):
        x0, x1 = sorted((side * 2.9, side * 3.15))
        m.box(x0, x1, HEIGHT, HEIGHT + 0.3, to_z(5.0), to_z(16.5))
    for s in (6.0, 9.5, 13.0, 16.0):
        m.box(-3.15, 3.15, HEIGHT + 0.3, HEIGHT + 0.42, to_z(s), to_z(s + 0.25))
    # Sliding door seam on the left (kerb) side; Kenya drives on the left.
    m.box(-HALF_W - 0.04, -HALF_W - 0.01, 0.3, 4.95, to_z(7.0), to_z(7.08))
    m.box(-HALF_W - 0.04, -HALF_W - 0.01, 0.3, 4.95, to_z(9.6), to_z(9.68))
    return m


def build_lights():
    m = Mesh()
    zf = to_z(0)
    for side in (1, -1):
        x0, x1 = sorted((side * 2.3, side * 3.55))
        m.box(x0, x1, 1.0, 1.55, zf - 0.12, zf + 0.15)
    return m


def build_taillights():
    m = Mesh()
    zr = to_z(LENGTH)
    for side in (1, -1):
        x0, x1 = sorted((side * 3.0, side * 3.75))
        m.box(x0, x1, 1.0, 2.6, zr - 0.15, zr + 0.1)
    return m


MATERIALS = {
    # name: (base color RGBA, emissive RGB, metallic, roughness)
    "Body": ((0.95, 0.95, 0.93, 1.0), (0, 0, 0), 0.1, 0.45),
    "Livery": ((1.0, 0.77, 0.0, 1.0), (0, 0, 0), 0.0, 0.5),
    "Glass": ((0.06, 0.08, 0.11, 1.0), (0, 0, 0), 0.2, 0.1),
    "Trim": ((0.14, 0.14, 0.15, 1.0), (0, 0, 0), 0.4, 0.6),
    "Lights": ((1.0, 0.97, 0.85, 1.0), (1.0, 0.95, 0.8), 0.0, 0.2),
    "TailLights": ((0.85, 0.08, 0.08, 1.0), (0.6, 0.02, 0.02), 0.0, 0.3),
}


def write_glb(parts, path: Path):
    buffer = bytearray()
    buffer_views, accessors, meshes, nodes, materials = [], [], [], [], []

    def add_view(data: bytes, target: int):
        while len(buffer) % 4:
            buffer.append(0)
        offset = len(buffer)
        buffer.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    for name, mesh in parts.items():
        positions, normals, indices = mesh.arrays()
        base, emissive, metallic, roughness = MATERIALS[name]
        materials.append(
            {
                "name": name,
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(base),
                    "metallicFactor": metallic,
                    "roughnessFactor": roughness,
                },
                "emissiveFactor": list(emissive),
            }
        )
        pv = add_view(positions.tobytes(), 34962)
        nv = add_view(normals.tobytes(), 34962)
        iv = add_view(indices.tobytes(), 34963)
        accessors.append(
            {
                "bufferView": pv,
                "componentType": 5126,
                "count": len(positions),
                "type": "VEC3",
                "min": positions.min(axis=0).tolist(),
                "max": positions.max(axis=0).tolist(),
            }
        )
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(normals), "type": "VEC3"})
        accessors.append({"bufferView": iv, "componentType": 5125, "count": len(indices), "type": "SCALAR"})
        a = len(accessors)
        meshes.append(
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {"POSITION": a - 3, "NORMAL": a - 2},
                        "indices": a - 1,
                        "material": len(materials) - 1,
                    }
                ],
            }
        )
        nodes.append({"name": name, "mesh": len(meshes) - 1})

    gltf = {
        "asset": {"version": "2.0", "generator": "matatu-empire make_matatu_mesh.py"},
        "scene": 0,
        "scenes": [{"name": "Matatu", "nodes": [len(nodes)]}],
        "nodes": nodes + [{"name": "Matatu", "children": list(range(len(nodes)))}],
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    while len(buffer) % 4:
        buffer.append(0)
    total = 12 + 8 + len(json_bytes) + 8 + len(buffer)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(buffer), 0x004E4942))
        f.write(bytes(buffer))


def write_obj(parts, obj_path: Path):
    mtl_path = obj_path.with_suffix(".mtl")
    with open(mtl_path, "w") as f:
        for name, (base, emissive, _metal, rough) in MATERIALS.items():
            f.write(f"newmtl {name}\nKd {base[0]:.3f} {base[1]:.3f} {base[2]:.3f}\n")
            f.write(f"Ke {emissive[0]:.3f} {emissive[1]:.3f} {emissive[2]:.3f}\nNs {(1 - rough) * 200:.1f}\n\n")
    with open(obj_path, "w") as f:
        f.write(f"mtllib {mtl_path.name}\n")
        v_offset = 1
        for name, mesh in parts.items():
            positions, normals, _ = mesh.arrays()
            f.write(f"o {name}\nusemtl {name}\n")
            for p in positions:
                f.write(f"v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}\n")
            for n in normals:
                f.write(f"vn {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}\n")
            for t in range(len(positions) // 3):
                a, b, c = (v_offset + 3 * t + k for k in range(3))
                f.write(f"f {a}//{a} {b}//{b} {c}//{c}\n")
            v_offset += len(positions)


def build_parts():
    poly = profile()
    return {
        "Body": build_body(poly),
        "Livery": build_livery(),
        "Glass": build_glass(),
        "Trim": build_trim(),
        "Lights": build_lights(),
        "TailLights": build_taillights(),
    }


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets")
    out.mkdir(parents=True, exist_ok=True)
    parts = build_parts()
    write_glb(parts, out / "matatu.glb")
    write_obj(parts, out / "matatu.obj")
    total = sum(len(m.tris) for m in parts.values())
    print(f"wrote {out/'matatu.glb'} and {out/'matatu.obj'}: {total} triangles")
    for name, m in parts.items():
        print(f"  {name}: {len(m.tris)} tris")


if __name__ == "__main__":
    main()
