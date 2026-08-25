#!/usr/bin/env python3
"""make-app-icon.py — アプリアイコンの唯一の原典。

寸法・色・形はすべてこのファイルの中にある。生成物

    packaging/AppIcon.svg                                （プレビュー用）
    packaging/Assets.xcassets/AppIcon.appiconset/*.png   （同梱する実体）
    packaging/Assets.xcassets/AppIcon.appiconset/Contents.json

はリポジトリに入れてあるので、デザインを変えるときはこのスクリプトを直して
再生成し、生成物も一緒に commit すること。

なぜ .icns や Icon Composer を使わないのか
------------------------------------------
アセットカタログ（.xcassets）なら iOS と macOS の両方を 1 か所で表現でき、
Xcode がそれぞれの OS 向けに畳んでくれる。macOS 側は「単一サイズ」に頼らず
16〜512 の全サイズを実体として持たせてある（Xcode のバージョンによって
単一サイズの扱いが変わるため。欠けると「ビルドは通るが Dock に白紙」になる）。

依存は cairosvg（と Pillow）だけで、macOS 専用の iconutil に頼らない。
Linux のリモートセッションからでも再生成・確認できる。

    pip install cairosvg pillow
    python3 scripts/make-app-icon.py
"""

import json
import os

import cairosvg
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGING = os.path.join(ROOT, "packaging")
ICONSET = os.path.join(PACKAGING, "Assets.xcassets", "AppIcon.appiconset")

# --- 色（意味を持たせて 1 か所に置く） --------------------------------------
BG_TOP = "#1B1033"      # 夜の紫。ローカルで静かに動く感じ
BG_BOTTOM = "#0A0A14"
BUBBLE = "#F5F3FF"      # 吹き出し（＝チャット）
ACCENT = "#7C5CFF"      # MLX のアクセント
ACCENT_DIM = "#4A3AA8"
SPARK = "#FFC857"       # 生成の火花

# --- 形（1024 座標系で書き、書き出し時に縮小する） --------------------------
CANVAS = 1024


def svg() -> str:
	"""アイコンの SVG。吹き出し × チップ（格子）で「端末の中で喋る」を表す。"""
	# チップの格子。吹き出しの中に等間隔で並べる。
	grid = []
	x0, y0, step, count = 330, 360, 92, 4
	for row in range(3):
		for column in range(count):
			cx = x0 + column * step
			cy = y0 + row * step
			# 中央 2 マスだけ明るくして「動いている」ことを示す。
			lit = (row == 1 and column in (1, 2))
			color = SPARK if lit else ACCENT
			opacity = "1" if lit else "0.55"
			grid.append(
				f'<rect x="{cx}" y="{cy}" width="46" height="46" rx="12" '
				f'fill="{color}" opacity="{opacity}"/>'
			)
	cells = "\n\t\t".join(grid)

	return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
	<defs>
		<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
			<stop offset="0%" stop-color="{BG_TOP}"/>
			<stop offset="100%" stop-color="{BG_BOTTOM}"/>
		</linearGradient>
		<!-- 水平線に objectBoundingBox のグラデーションを当てるとバウンディング
		     ボックスの高さが 0 になり描画されない。座標系を明示する。 -->
		<linearGradient id="ring" gradientUnits="userSpaceOnUse"
		                x1="120" y1="380" x2="904" y2="600">
			<stop offset="0%" stop-color="{ACCENT}"/>
			<stop offset="100%" stop-color="{ACCENT_DIM}"/>
		</linearGradient>
	</defs>

	<!-- 背景。角丸は OS 側でマスクされるが、単体で見たときのために付けておく -->
	<rect width="{CANVAS}" height="{CANVAS}" rx="230" fill="url(#bg)"/>

	<!-- チップの脚（左右に伸びる線）。「これは端末の中で動く」の記号 -->
	<g stroke="url(#ring)" stroke-width="26" stroke-linecap="round" opacity="0.9">
		<path d="M124 400 H208"/>
		<path d="M124 490 H208"/>
		<path d="M124 580 H208"/>
		<path d="M816 400 H900"/>
		<path d="M816 490 H900"/>
		<path d="M816 580 H900"/>
	</g>

	<!-- 吹き出し本体 -->
	<path d="M300 236 H724 a76 76 0 0 1 76 76 V632 a76 76 0 0 1 -76 76 H520
	         l-118 118 v-118 H300 a76 76 0 0 1 -76 -76 V312 a76 76 0 0 1 76 -76 Z"
	      fill="{BUBBLE}"/>

	<!-- 吹き出しの中のチップ格子 -->
	<g>
		{cells}
	</g>
</svg>
"""


# --- 書き出し ---------------------------------------------------------------
# iOS は 1024 の単一サイズ（Xcode が各サイズへ畳む）。macOS は実体を全部置く。
IOS_SIZES = [("universal", "1024x1024", 1, 1024)]
MAC_SIZES = [
	("mac", "16x16", 1, 16),
	("mac", "16x16", 2, 32),
	("mac", "32x32", 1, 32),
	("mac", "32x32", 2, 64),
	("mac", "128x128", 1, 128),
	("mac", "128x128", 2, 256),
	("mac", "256x256", 1, 256),
	("mac", "256x256", 2, 512),
	("mac", "512x512", 1, 512),
	("mac", "512x512", 2, 1024),
]


def render(source: str, pixels: int, path: str) -> None:
	"""SVG を PNG にする。アルファは残さない（iOS のアイコンは透過不可）。"""
	png = cairosvg.svg2png(bytestring=source.encode("utf-8"),
	                       output_width=pixels, output_height=pixels)
	tmp = path + ".rgba"
	with open(tmp, "wb") as handle:
		handle.write(png)
	image = Image.open(tmp).convert("RGBA")
	flattened = Image.new("RGB", image.size, BG_BOTTOM)
	flattened.paste(image, mask=image.split()[3])
	flattened.save(path, format="PNG")
	os.remove(tmp)


def main() -> None:
	source = svg()
	os.makedirs(ICONSET, exist_ok=True)

	with open(os.path.join(PACKAGING, "AppIcon.svg"), "w") as handle:
		handle.write(source)

	images = []
	for idiom, size, scale, pixels in IOS_SIZES + MAC_SIZES:
		name = f"icon-{idiom}-{size.split('x')[0]}@{scale}x.png"
		render(source, pixels, os.path.join(ICONSET, name))
		entry = {"filename": name, "idiom": idiom, "scale": f"{scale}x", "size": size}
		if idiom == "universal":
			# iOS の単一サイズ指定。scale は付けない決まり。
			entry = {"filename": name, "idiom": "universal",
			         "platform": "ios", "size": size}
		images.append(entry)

	with open(os.path.join(ICONSET, "Contents.json"), "w") as handle:
		json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
		          handle, indent=2, sort_keys=True)
		handle.write("\n")

	root = os.path.join(PACKAGING, "Assets.xcassets", "Contents.json")
	with open(root, "w") as handle:
		json.dump({"info": {"author": "xcode", "version": 1}}, handle, indent=2)
		handle.write("\n")

	print(f"wrote {len(images)} images to {ICONSET}")


if __name__ == "__main__":
	main()
