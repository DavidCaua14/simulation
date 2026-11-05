#!/usr/bin/env python3
"""Converte os kits visuais (PNG grandes) em WebP leves para o jogo.

Uso: python3 scripts/build-kit-assets.py <pasta football_simulator_assets> <pasta kit_manager_instalacoes_gestao>
Saída: src/features/match25d/assets/*.webp + kitData.json e src/features/clubdev/assets/*.webp.
Os atlas são reduzidos por um fator único; retângulos e pontos de apoio do manifesto são escalados junto.
"""
import json, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MATCH, CLUB = Path(sys.argv[1]), Path(sys.argv[2])
OUT = ROOT / 'src/features/match25d/assets'
OUTC = ROOT / 'src/features/clubdev/assets'
OUT.mkdir(parents=True, exist_ok=True); OUTC.mkdir(parents=True, exist_ok=True)
man = json.loads((MATCH / 'manifest.json').read_text())

def save(src, dst, width=None, scale=None, q=82):
    im = Image.open(src).convert('RGBA')
    if scale: im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    elif width and im.width > width: im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dst, 'WEBP', quality=q, method=6)
    return im.size

data = {'scene': man['scene'], 'scoreboard': man['scoreboard'], 'images': {}}
for name, rel, width in [('stadium', 'cenario/estadio.png', 1672), ('grass', 'cenario/gramado.png', 1100), ('ball', 'cenario/bola.png', 48),
                         ('scoreboard', 'interface/placar_base.png', 1086), ('goal', 'interface/gol.png', 900), ('yellow', 'interface/cartao_amarelo.png', 280),
                         ('red', 'interface/cartao_vermelho.png', 280), ('second_yellow', 'interface/segundo_amarelo_expulsao.png', 300),
                         ('offside', 'interface/impedimento.png', 280), ('injury', 'interface/lesao.png', 280), ('sub', 'interface/substituicao.png', 360),
                         ('referee', 'personagens/arbitro_falta.png', 260), ('flag', 'tecnicos/bandeirinha_campo.png', 64),
                         ('shadow', 'tecnicos/sombra_jogador.png', 80), ('ring', 'tecnicos/selecao_jogador.png', 80)]:
    w, h = save(MATCH / rel, OUT / f'{name}.webp', width=width)
    data['images'][name] = {'file': f'{name}.webp', 'w': w, 'h': h}

# Os atletas animados vêm de scripts/build-sprite-atlases.py (8 direções); os atlas antigos de 4 direções saíram.
(OUT / 'kitData.json').write_text(json.dumps(data, ensure_ascii=False, indent=1))

for rel in ['instalacoes/centro_treinamento_nivel_1.png', 'instalacoes/centro_treinamento_nivel_2.png', 'instalacoes/centro_treinamento_nivel_3.png',
            'instalacoes/categorias_base.png', 'instalacoes/departamento_medico.png', 'instalacoes/academia.png', 'instalacoes/sala_tatica.png',
            'instalacoes/vestiario.png', 'instalacoes/sala_trofeus.png', 'instalacoes/sala_imprensa.png', 'infraestrutura/obras_infraestrutura.png',
            'infraestrutura/onibus_clube.png']:
    save(CLUB / rel, OUTC / (Path(rel).stem + '.webp'), width=640, q=80)
for rel in ['gestao/contratos.png', 'gestao/financas.png', 'gestao/olheiros.png', 'gestao/transferencias.png']:
    save(CLUB / rel, OUTC / (Path(rel).stem + '.webp'), width=192, q=85)
print('ok')
