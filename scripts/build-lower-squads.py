#!/usr/bin/env python3
"""Gera supabase/online/41_lower_squads_data.sql com os elencos reais das Séries C e D (data/squads-lower/*.txt).

Uso: python3 scripts/build-lower-squads.py
Regras (mesma ideia do modo Temporadas, scripts/build-squads.mjs):
  - Nome, número, nacionalidade e posição ampla (GK/DF/MF/FW) vêm da fonte; nada é inventado.
  - Posição detalhada: quando a fonte só traz a ampla, é ESTIMADA pelo número da camisa (2 lateral-direito, 6 lateral-esquerdo,
    5 volante, 8 meio-campista, 10 meia, 7 ponta-direita, 11 ponta-esquerda, 9 centroavante) e pelo que falta no elenco.
  - Nota: ESTIMATIVA de jogo — o nível da série no jogo (on_config.series_level) mais um ajuste de papel no elenco
    (titulares de camisa 1 a 11 e capitão um pouco acima, números altos de base abaixo) e uma variação fixa por jogador.
  - Elenco antigo (fonte com data anterior a 2025) fica de fora: o clube segue com cartas geradas.
"""
import hashlib, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'data' / 'squads-lower'
OUT = ROOT / 'supabase' / 'online' / '41_lower_squads_data.sql'
DETAIL = {'GK': 'GOL', 'CB': 'ZAG', 'RB': 'LD', 'LB': 'LE', 'DM': 'VOL', 'CM': 'MC', 'AM': 'MEI', 'RW': 'PD', 'LW': 'PE', 'CF': 'ATA', 'ST': 'ATA',
          'RM': 'PD', 'LM': 'PE', 'SS': 'ATA', 'WB': 'LD'}
BY_NUMBER = {'DF': {2: 'LD', 13: 'LD', 22: 'LD', 6: 'LE', 16: 'LE', 3: 'ZAG', 4: 'ZAG', 14: 'ZAG', 15: 'ZAG'},
             'MF': {5: 'VOL', 15: 'VOL', 8: 'MC', 10: 'MEI', 20: 'MEI'},
             'FW': {9: 'ATA', 19: 'ATA', 7: 'PD', 17: 'PD', 11: 'PE', 18: 'PE'}}
QUOTA = {'DF': ['LD', 'LE', 'ZAG', 'ZAG', 'LD', 'LE', 'ZAG', 'ZAG'], 'MF': ['VOL', 'MC', 'MEI', 'VOL', 'MC', 'MEI', 'MC'], 'FW': ['ATA', 'PD', 'PE', 'ATA', 'PD', 'PE']}


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def year(asof):
    m = re.search(r'(20\d\d)', asof or '')
    return int(m.group(1)) if m else None


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    rows, report = [], []
    for f in sorted(SRC.glob('*.txt')):
        meta, players = {}, []
        for line in f.read_text(encoding='utf-8').splitlines():
            if line.startswith('#'):
                k, _, v = line[1:].partition(':')
                meta[k.strip()] = v.strip()
            elif line.strip():
                no, pos, nat, name, other = (line.split('|') + [''] * 5)[:5]
                players.append({'no': int(no) if no.isdigit() else None, 'pos': pos.strip().upper(), 'nat': nat.strip() or 'BRA', 'name': name.strip(), 'other': other})
        key, y = meta.get('club') or f.stem, year(meta.get('as_of'))
        if y is not None and y < 2025:
            report.append(f'{key}: fonte de {y}, fora (cartas geradas)')
            continue
        used = {'DF': [], 'MF': [], 'FW': []}
        for p in players:
            broad = p['pos']
            if broad in DETAIL:
                p['dpos'], p['est'] = DETAIL[broad], False
                continue
            broad = {'GK': 'GK', 'DF': 'DF', 'MF': 'MF', 'FW': 'FW'}.get(broad[:2], 'MF')
            if broad == 'GK':
                p['dpos'], p['est'] = 'GOL', False
                continue
            dpos = BY_NUMBER[broad].get(p['no'])
            if not dpos:
                quota = list(QUOTA[broad])
                for x in used[broad]:
                    if x in quota: quota.remove(x)
                dpos = quota[0] if quota else QUOTA[broad][len(used[broad]) % len(QUOTA[broad])]
            used[broad].append(dpos)
            p['dpos'], p['est'] = dpos, True
        for p in players:
            role = 2 if (p['no'] or 99) <= 11 else -3 if (p['no'] or 0) >= 30 else 0
            if 'captain' in p['other'].lower(): role += 2
            off = role + round((h(key + p['name']) - .5) * 6)
            age = 18 + int(h(p['name'] + ':age') * 16)
            rows.append(f"({q(key)},{p['no'] if p['no'] is not None else 'null'},{q(p['dpos'])},{q(p['nat'][:3])},{q(p['name'][:40])},{age},{off},{str(p['est']).lower()},{q(meta.get('source', ''))},{q(meta.get('as_of', ''))})")
        report.append(f'{key}: {len(players)} jogadores ({meta.get("as_of")})')
    sql = ['-- GERADO por scripts/build-lower-squads.py a partir de data/squads-lower/*.txt (Wikipédia). Não edite à mão.',
           '-- Elencos reais das Séries C e D: nome, número, nacionalidade e posição da fonte; nota e idade são estimativas de jogo.',
           'delete from public.on_lower_players;',
           'insert into public.on_lower_players(club_key,no,pos,nat,name,age,lvl_off,pos_est,source,as_of) values']
    sql.append(',\n'.join(rows) + ';')
    OUT.write_text('\n'.join(sql) + '\n', encoding='utf-8')
    print('\n'.join(report))
    print(f'{len(rows)} jogadores em {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
