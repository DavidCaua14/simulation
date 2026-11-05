#!/usr/bin/env python3
"""Gera os atlas de animação da transmissão 2.5D a partir das folhas de sprites.

Entradas (fundo transparente, 8 quadros por linha):
  src/features/match25d/assets/source/player_sheet.webp
    linha 0: parado nas 8 direções; linhas 1-8: corrida (8 quadros) em S, SE, L, NE, N, NO, O, SO; linha 9: comemoração
  src/features/match25d/assets/source/keeper_sheet.webp
    linhas 0-8 como acima; 9: mergulho à esquerda; 10: mergulho à direita; 11: defesa alta; 12: defesa baixa;
    13: reposição com a mão; 14: tiro de meta; 15: comemoração
Saídas: assets/sprite_player.webp, assets/sprite_keeper.webp e assets/sprites.json
  frames: nome → [x, y, w, h, âncora_x, âncora_y] (âncora = ponto dos pés no quadro)

As linhas são separadas pelas faixas transparentes (as alturas não são uniformes) e os quadros pelas colunas vazias;
quando uma faixa junta duas linhas ou os quadros se tocam, divide pelo ponto de menor ocupação.
Uso: python3 scripts/build-sprite-atlases.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'src/features/match25d/assets'
DIRS = ['S', 'SE', 'E', 'NE', 'N', 'NW', 'W', 'SW']
PLAYER_ROWS = ['idle'] + [f'run_{d}' for d in DIRS] + ['celebrate']
KEEPER_ROWS = PLAYER_ROWS[:-1] + ['dive_left', 'dive_right', 'catch_high', 'catch_low', 'throw', 'kick', 'celebrate']
ALPHA = 40


def bands(mask, axis, min_gap=1):
    prof = mask.sum(axis=axis)
    out, start = [], None
    for i, v in enumerate(prof):
        if v > 0 and start is None:
            start = i
        elif v == 0 and start is not None:
            out.append([start, i])
            start = None
    if start is not None:
        out.append([start, len(prof)])
    return out, prof


def split_to(bands_, prof, n, nominal):
    """Garante n faixas: divide as mais largas pelo vale de menor ocupação ou junta fragmentos pequenos."""
    bands_ = [b for b in bands_ if b[1] - b[0] > 3]
    while len(bands_) < n:
        i = max(range(len(bands_)), key=lambda k: bands_[k][1] - bands_[k][0])
        a, b = bands_[i]
        guess = int(round((b - a) / max(1, round((b - a) / nominal)))) if b - a > nominal * 1.4 else (b - a) // 2
        lo, hi = a + int(guess * 0.6), min(b - 1, a + int(guess * 1.4))
        cut = lo + int(np.argmin(prof[lo:hi])) if hi > lo else a + guess
        bands_[i:i + 1] = [[a, cut], [cut, b]]
    while len(bands_) > n:
        i = min(range(len(bands_) - 1), key=lambda k: bands_[k + 1][0] - bands_[k][1])
        bands_[i:i + 2] = [[bands_[i][0], bands_[i + 1][1]]]
    return bands_


def frames_of(sheet_path, row_names):
    img = Image.open(sheet_path).convert('RGBA')
    arr = np.array(img)
    mask = arr[:, :, 3] > ALPHA
    rows, rprof = bands(mask, 1)
    rows = split_to(rows, rprof, len(row_names), img.height / len(row_names))
    out = {}
    for name, (y0, y1) in zip(row_names, rows):
        band = mask[y0:y1]
        cols, cprof = bands(band, 0)
        cols = split_to(cols, cprof, 8, img.width / 8)
        for i, (x0, x1) in enumerate(cols):
            m = band[:, x0:x1]
            ys, xs = np.nonzero(m)
            if not len(ys):
                continue
            by0, by1, bx0, bx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            tile = img.crop((x0 + bx0, y0 + by0, x0 + bx1, y0 + by1))
            # pés: média horizontal dos pixels nas últimas linhas ocupadas
            foot = m[max(by0, by1 - max(3, (by1 - by0) // 10)):by1, bx0:bx1]
            fx = np.nonzero(foot)[1]
            ax = float(fx.mean()) if len(fx) else (bx1 - bx0) / 2
            out[f'{name}_{i}'] = (tile, ax, float(by1 - by0))
    return out


def pack(frames, pad=2, width=1024):
    x = y = rowh = 0
    placed = {}
    for name, (tile, ax, ay) in frames.items():
        w, h = tile.size
        if x + w + pad > width:
            x, y, rowh = 0, y + rowh + pad, 0
        placed[name] = (x, y, w, h, round(ax, 1), round(ay, 1))
        x += w + pad
        rowh = max(rowh, h)
    atlas = Image.new('RGBA', (width, y + rowh + pad), (0, 0, 0, 0))
    for name, (tile, _, _) in frames.items():
        px, py = placed[name][:2]
        atlas.paste(tile, (px, py))
    return atlas, placed


def main():
    meta = {'directions': DIRS, 'atlases': {}}
    for key, sheet, rows in [('player', 'player_sheet.webp', PLAYER_ROWS), ('keeper', 'keeper_sheet.webp', KEEPER_ROWS)]:
        frames = frames_of(ASSETS / 'source' / sheet, rows)
        atlas, placed = pack(frames)
        out = ASSETS / f'sprite_{key}.webp'
        atlas.save(out, 'WEBP', quality=82, method=6)
        idle_h = sorted(placed[f'idle_{i}'][3] for i in range(8) if f'idle_{i}' in placed)
        meta['atlases'][key] = {'file': out.name, 'w': atlas.width, 'h': atlas.height,
                                'visible_height': idle_h[len(idle_h) // 2], 'frames': placed}
        print(key, atlas.size, len(placed), 'frames', out.stat().st_size // 1024, 'KB')
    (ASSETS / 'sprites.json').write_text(json.dumps(meta, separators=(',', ':')))


if __name__ == '__main__':
    main()
