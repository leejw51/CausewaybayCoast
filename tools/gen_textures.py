#!/usr/bin/env python3
"""Generate seamless game textures with Grok Imagine (xAI) into godot/assets/textures/.

Usage:  python3 tools/gen_textures.py [out_dir] [name ...]
Env:    XAI_API_KEY (or GROK_API_KEY), GROK_IMAGE_MODEL (default grok-imagine-image)
Skips textures that already exist unless FORCE=1.
"""

import base64
import json
import os
import sys
import urllib.request

API = "https://api.x.ai/v1/images/generations"
MODEL = os.environ.get("GROK_IMAGE_MODEL", "grok-imagine-image")
STYLE = (
    "seamless tileable texture, top-down flat view, hand-painted cartoon game art, "
    "soft restrained coastal colours, low contrast, clean edges, no text, no watermark, "
    "no perspective, evenly lit, repeats perfectly at the edges"
)

TEXTURES = {
    "ocean_caustics": "seamless shallow tropical sea water texture for a cozy island life-sim game, top-down turquoise water with delicate ivory caustic cells, organic overlapping ripple networks, subtle pale highlights, flat lighting, no horizon, no land, no objects, no harsh white glare",
    "beach_sand": "seamless fine cream beach sand texture for a cozy island life-sim game, very subtle wind-shaped ripples and sparse tiny pale grains, understated natural surface, flat even lighting, no footprints, no large shells or objects, no cast shadows, soft warm neutral beige",
    "planks": "warm honey-orange wooden floor planks with soft knots, cute cozy game style",
    "sand": "pale golden beach sand with tiny shells and light speckles, tropical island",
    "water": "calm soft muted teal sea water surface, gentle low-contrast ripples, subtle pale caustic lines, pastel, cartoon",
    "thatch": "golden palm-leaf thatched roof straw, layered rows, tropical hut",
    "rug": "cute woven rug pattern, red yellow and pink stripes with small diamond motifs",
    "grass": "soft muted sage green cartoon grass, gentle low-contrast blades, a few tiny pale flowers, pastel",
    "bark": "palm tree trunk bark, stacked brown fibrous rings, cartoon",
    "wood": "smooth caramel brown wood grain for furniture, cartoon",
    "leaf": "big glossy tropical monstera leaf surface, bright green veins, cartoon",
    "stone": "grey cobblestone pedestal rock, rounded stones, cartoon",
    "fabric": "soft sky blue quilted blanket fabric with tiny white stars, cute",
}


def gen(name, prompt, out_path, style=None):
    key = os.environ.get("XAI_API_KEY") or os.environ.get("GROK_API_KEY")
    if not key:
        sys.exit("XAI_API_KEY not set")
    body = {
        "model": MODEL,
        "prompt": f"{prompt}, {STYLE if style is None else style}",
        "n": 1,
        "response_format": "b64_json",
    }
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    item = data["data"][0]
    if "b64_json" in item:
        png = base64.b64decode(item["b64_json"])
    else:
        with urllib.request.urlopen(item["url"], timeout=180) as r:
            png = r.read()
    # The API may answer with JPEG bytes: name the file by its real format so Godot imports it.
    ext = ".jpg" if png[:2] == b"\xff\xd8" else ".png"
    out_path = os.path.splitext(out_path)[0] + ext
    with open(out_path, "wb") as f:
        f.write(png)
    with open(out_path + ".generation.json", "w") as provenance:
        json.dump(
            {"provider": "xAI Grok", "model": MODEL, "prompt": body["prompt"]},
            provenance,
            indent=2,
        )
    print(f"{name}: {len(png)} bytes -> {out_path}")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/textures"
    names = sys.argv[2:] or list(TEXTURES)
    os.makedirs(out, exist_ok=True)
    for n in names:
        path = os.path.join(out, f"{n}.png")
        exists = any(os.path.exists(os.path.join(out, n + e)) for e in (".png", ".jpg"))
        if exists and not os.environ.get("FORCE"):
            print(f"{n}: exists, skip (FORCE=1 to regenerate)")
            continue
        gen(n, TEXTURES[n], path)


if __name__ == "__main__":
    main()
