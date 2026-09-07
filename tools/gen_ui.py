#!/usr/bin/env python3
"""Generate HUD icons / cards with Grok Imagine into godot/assets/ui/.

Icons are rendered on a flat magenta (#FF00FF) background; Godot keys that colour to alpha at load.
Usage: python3 tools/gen_ui.py [out_dir] [name ...]     (FORCE=1 to regenerate)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_textures as gt

ICON_STYLE = (
    "single cute game UI icon, soft hand-painted cartoon style, warm muted colours, "
    "thick rounded shapes, gentle shading, centered, large, fills most of the frame, "
    "on a completely flat solid magenta #FF00FF background, no text, no border, no shadow on background"
)
CARD_STYLE = (
    "cozy cartoon game art, soft hand-painted style, warm muted pastel colours, no text"
)

ITEMS = {
    "btn_decorate": "wooden hammer crossed with a small red sofa, tool and furniture icon",
    "btn_home": "tiny tropical beach hut with thatched roof and a palm tree",
    "btn_islands": "old paper treasure map with a compass rose and small islands",
    "btn_chat": "round speech bubble with three dots",
    "item_palm": "small tropical palm tree in a terracotta pot",
    "item_monstera": "monstera plant with big split leaves in a terracotta pot",
    "item_flower_pot": "terracotta pot overflowing with pink and yellow flowers",
    "item_cactus": "cute round cactus with a pink flower in a pot",
    "item_bed": "cozy single bed with blue blanket and white pillow, isometric view",
    "item_table": "small round wooden table with a cup of coffee, isometric view",
    "item_chair": "wooden chair with red cushion, isometric view",
    "item_lamp": "standing floor lamp with a yellow shade, glowing",
    "item_rug": "square woven rug, red and cream stripes, isometric view",
    "item_bookshelf": "small wooden bookshelf with colourful books and a plant",
    "item_portal": "glowing purple magic ring portal on a stone pedestal",
    "item_tree": "round leafy green tree with a chunky brown trunk, cute cartoon",
    "item_bench": "small wooden garden bench, isometric view, cute cartoon",
    "item_flower_bed": "wooden garden flower bed box full of colourful tulips, isometric view",
}
CARDS = {
    "portrait": "portrait avatar of a cheerful islander character with a straw hat, big eyes, "
    "chibi proportions, head and shoulders, on a cream #F7EEDC background, circular vignette",
    "sign": "wide wooden hanging sign board with rope, warm honey wood, decorated with a tiny palm tree "
    "and seashells on both sides, blank centre for text, on a completely flat solid magenta #FF00FF background",
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/ui"
    names = sys.argv[2:] or list(ITEMS) + list(CARDS)
    os.makedirs(out, exist_ok=True)
    for n in names:
        if any(
            os.path.exists(os.path.join(out, n + e)) for e in (".png", ".jpg")
        ) and not os.environ.get("FORCE"):
            print(f"{n}: exists, skip")
            continue
        if n in ITEMS:
            gt.gen(n, ITEMS[n], os.path.join(out, n + ".png"), style=ICON_STYLE)
        else:
            gt.gen(n, CARDS[n], os.path.join(out, n + ".png"), style=CARD_STYLE)


if __name__ == "__main__":
    main()
