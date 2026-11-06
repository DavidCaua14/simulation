#!/usr/bin/env python3
"""Gera o catálogo das ligas de fundo (nível B) a partir de data/tier-b/.

    python scripts/build-tier-b.py

Entradas (versionadas):
  data/tier-b/leagues.json   ligas, calendário (BRA/ENG) e tema
  data/tier-b/clubs.tsv      clubes: id, nome, sigla, força, cores (revisado à mão)
  data/tier-b/squads.json    elencos: Wikipedia (en; es para 6 clubes) e datas de nascimento do Wikidata, coletados em 2026-11-06

Saídas:
  supabase/migrations/20261106220000_tier_b_catalog.sql   idempotente; só INSERE (nada existente é alterado)
  src/features/club/data/clubCatalogB.js                  nome, sigla e cores para a interface

Regras:
  - Clube que já existe no banco (Libertadores, Champions) entra só na liga: elenco, força e cores ficam como estão.
  - Clube novo nasce com lazy = true: notas por posição e valores-base só são gravados quando ele entra num mundo
    (sim_ensure_club_catalog). No catálogo fica uma linha compacta por atleta (attr_pos + attr_level).
  - source_url fica nulo por atleta (a fonte de cada elenco está em data/tier-b/squads.json): economiza ~400 KB.
  - Atributos = estimativa de gameplay, mesma conta do build-squads.mjs (força do clube + camisa + perfil da posição).
"""
import json, re, unicodedata
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data' / 'tier-b'
OUT_SQL = ROOT / 'supabase' / 'migrations' / '20261106220000_tier_b_catalog.sql'
OUT_JS = ROOT / 'src' / 'features' / 'club' / 'data' / 'clubCatalogB.js'
TODAY = date(2026, 11, 6)
MAX_SQUAD = 30

# --- mesmos números de scripts/build-squads.mjs -----------------------------------------
BROAD = {'DF': 'DEF', 'MF': 'MID', 'FW': 'ATT', 'GK': 'GK'}
LINE_OF = {'GOL': 'GK', 'LD': 'DEF', 'LE': 'DEF', 'ZAG': 'DEF', 'VOL': 'MID', 'MC': 'MID', 'MEI': 'MID', 'PD': 'ATT', 'PE': 'ATT', 'ATA': 'ATT'}
EST_SECONDARY = {'LD': ['LE'], 'LE': ['LD'], 'ZAG': [], 'VOL': ['MC'], 'MC': ['VOL', 'MEI'], 'MEI': ['MC'], 'PD': ['PE'], 'PE': ['PD'], 'ATA': [], 'GOL': []}
NUMBER_HINT = {
    'DEF': {2: 'LD', 12: 'LD', 22: 'LD', 6: 'LE', 16: 'LE', 26: 'LE', 36: 'LE', 3: 'ZAG', 4: 'ZAG', 5: 'ZAG', 13: 'ZAG', 14: 'ZAG', 15: 'ZAG', 33: 'ZAG', 44: 'ZAG'},
    'MID': {5: 'VOL', 15: 'VOL', 25: 'VOL', 8: 'MC', 18: 'MC', 28: 'MC', 10: 'MEI', 20: 'MEI', 30: 'MEI'},
    'ATT': {7: 'PD', 17: 'PD', 27: 'PD', 11: 'PE', 21: 'PE', 77: 'PD', 9: 'ATA', 19: 'ATA', 99: 'ATA'},
}
QUOTA = {'DEF': ['LD', 'LE', 'ZAG', 'ZAG', 'LD', 'LE', 'ZAG', 'ZAG'], 'MID': ['VOL', 'MC', 'MEI', 'VOL', 'MC', 'MEI'], 'ATT': ['ATA', 'PD', 'PE', 'ATA', 'PD', 'PE']}
ATTRS = ['gk_reflexes', 'gk_handling', 'gk_positioning', 'marking', 'tackling', 'positioning', 'heading',
         'passing', 'vision', 'technique', 'stamina', 'finishing', 'off_ball', 'pace', 'dribbling', 'strength']
_T = lambda *v: dict(zip(ATTRS, v))
TEMPLATE = {
    'GOL': _T(6, 4, 4, -38, -38, -30, -28, -16, -20, -22, -14, -48, -46, -24, -36, -6),
    'ZAG': _T(-52, -52, -52, 6, 6, 6, 7, -6, -12, -10, -2, -26, -20, -6, -16, 5),
    'LD': _T(-52, -52, -52, 1, 2, 0, -7, -1, -6, -3, 6, -18, -5, 6, -2, -4),
    'LE': _T(-52, -52, -52, 1, 2, 0, -7, -1, -6, -3, 6, -18, -5, 6, -2, -4),
    'VOL': _T(-52, -52, -52, 4, 5, 4, -2, 1, -3, -2, 5, -16, -12, -6, -8, 3),
    'MC': _T(-52, -52, -52, -3, -1, -1, -7, 5, 3, 3, 5, -9, -4, -4, -1, -2),
    'MEI': _T(-52, -52, -52, -16, -14, -12, -12, 5, 7, 6, -1, -4, 2, -3, 4, -6),
    'PD': _T(-52, -52, -52, -18, -16, -16, -12, -2, -4, 3, 2, -3, 3, 8, 6, -6),
    'PE': _T(-52, -52, -52, -18, -16, -16, -12, -2, -4, 3, 2, -3, 3, 8, 6, -6),
    'ATA': _T(-52, -52, -52, -24, -22, -20, 2, -8, -9, -2, -4, 8, 6, 1, -1, 3),
}
ROLE_WEIGHTS = {
    'GOL': {'gk_reflexes': 4, 'gk_handling': 3, 'gk_positioning': 3, 'passing': 0.5},
    'ZAG': {'marking': 3, 'tackling': 3, 'positioning': 3, 'heading': 2.5, 'strength': 1.5, 'pace': 1, 'passing': 1},
    'LD': {'tackling': 2, 'marking': 2, 'positioning': 1.5, 'pace': 2.5, 'stamina': 2, 'passing': 1.5, 'dribbling': 1, 'technique': 1},
    'LE': {'tackling': 2, 'marking': 2, 'positioning': 1.5, 'pace': 2.5, 'stamina': 2, 'passing': 1.5, 'dribbling': 1, 'technique': 1},
    'VOL': {'tackling': 3, 'marking': 2, 'positioning': 2.5, 'passing': 2, 'stamina': 2, 'strength': 1, 'vision': 1},
    'MC': {'passing': 3, 'vision': 2, 'technique': 2, 'stamina': 2, 'tackling': 1, 'positioning': 1, 'off_ball': 0.5, 'finishing': 0.5},
    'MEI': {'vision': 3, 'passing': 2.5, 'technique': 2.5, 'dribbling': 2, 'off_ball': 1.5, 'finishing': 1.5},
    'PD': {'pace': 2.5, 'dribbling': 2.5, 'technique': 2, 'off_ball': 1.5, 'finishing': 1.5, 'passing': 1, 'stamina': 1},
    'PE': {'pace': 2.5, 'dribbling': 2.5, 'technique': 2, 'off_ball': 1.5, 'finishing': 1.5, 'passing': 1, 'stamina': 1},
    'ATA': {'finishing': 3.5, 'off_ball': 2.5, 'heading': 1.5, 'strength': 1.5, 'pace': 1.5, 'technique': 1, 'dribbling': 1},
}

def hash01(s):
    """Igual a hash01 (build-squads.mjs) e sim_hash01 (banco)."""
    h = 2166136261
    for ch in s:
        h = (h ^ ord(ch)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5bd1e995) & 0xFFFFFFFF
    h ^= h >> 15
    return h / 4294967296

def jsround(x):
    import math
    return math.floor(x + 0.5)

def slug(s):
    s = unicodedata.normalize('NFD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')

def short_name(full):
    if len(full) <= 18: return full
    parts = full.split(' ')
    s = f'{parts[0][0]}. {" ".join(parts[1:])}'
    return s if len(s) <= 20 else f'{parts[0][0]}. {parts[-1]}'

def rating(attrs, pos):
    w = ROLE_WEIGHTS[pos]
    return sum(attrs[k] * v for k, v in w.items()) / sum(w.values())

def attr_level(pid, pos, club_strength, num, youth):
    role = 0
    if num is not None: role += 3 if num <= 11 else 0 if num <= 25 else -3 if num <= 39 else -5
    if youth: role = -7
    level = max(40, min(90, jsround(club_strength + role + (hash01(f'lvl:{pid}') - 0.5) * 9)))
    attrs = {a: level + TEMPLATE[pos][a] + jsround((hash01(f'{a}:{pid}') - 0.5) * 10) for a in ATTRS}
    return level + jsround(level - rating(attrs, pos))

def assign_positions(players):
    for line in ['DEF', 'MID', 'ATT']:
        group = [p for p in players if p['broad'] == line]
        have = {}
        rest = []
        for p in group:
            hint = NUMBER_HINT[line].get(p['num']) if p['num'] is not None else None
            if hint: p['pos'] = hint; have[hint] = have.get(hint, 0) + 1
            else: rest.append(p)
        rest.sort(key=lambda p: hash01('pos:' + p['id']))
        for p in rest:
            need = next((pos for i, pos in enumerate(QUOTA[line]) if have.get(pos, 0) < QUOTA[line][:i + 1].count(pos)), None)
            p['pos'] = need or QUOTA[line][int(hash01('q:' + p['id']) * 3)]
            have[p['pos']] = have.get(p['pos'], 0) + 1
        for p in group: p['sec'] = EST_SECONDARY[p['pos']]
    for p in players:
        if p['broad'] == 'GK': p['pos'] = 'GOL'; p['sec'] = []

def q(v):
    if v is None: return 'null'
    return "'" + str(v).replace("'", "''") + "'"

def main():
    leagues = json.loads((DATA / 'leagues.json').read_text(encoding='utf-8'))['leagues']
    by_country = {l['country']: l for l in leagues}
    clubs = []
    for line in (DATA / 'clubs.tsv').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'): continue
        lg, title, cid, name, short, st, c1, c2, city = (line.split('\t') + [''] * 9)[:9]
        clubs.append(dict(lg=lg, title=title, id=cid, name=name, short=short, strength=int(st), c1=c1, c2=c2, city=city or None))
    squads = json.loads((DATA / 'squads.json').read_text(encoding='utf-8'))
    existing = json.loads((DATA / 'existing.json').read_text(encoding='utf-8'))
    old_clubs, old_players = set(existing['clubs']), set(existing['players'])

    players, used = [], set(old_players)
    for c in clubs:
        if c['id'] in old_clubs: continue
        sq = squads[c['id']]
        rows = []
        for no, nat, pos, name, birth in sq['players']:
            if pos not in BROAD: continue
            num = int(no) if str(no).isdigit() else None
            rows.append(dict(name=name, nat=(nat or None) and nat.upper()[:3], num=num, broad=BROAD[pos], birth=birth))
        rows = rows[:MAX_SQUAD]
        for p in rows:
            base = slug(p['name']) + (f"-{p['nat'].lower()}" if p['nat'] else '')
            pid = base if base not in used else f"{base}-{c['id']}"
            n = 2
            while pid in used: pid = f"{base}-{c['id']}-{n}"; n += 1
            used.add(pid); p['id'] = pid
        assign_positions(rows)
        for p in rows:
            p['club'] = c['id']; p['source'] = sq['source']
            p['level'] = attr_level(p['id'], p['pos'], c['strength'], p['num'], False)
            if p['birth']:
                b = date.fromisoformat(p['birth'])
                p['age'] = TODAY.year - b.year - ((TODAY.month, TODAY.day) < (b.month, b.day))
            else:
                p['age'] = None
        players.extend(rows)

    sql = ['-- Catálogo das ligas de fundo (nível B). GERADO por scripts/build-tier-b.py: não edite à mão.',
           '-- Só insere: clubes, ligas e atletas que já existem não são alterados (progresso das carreiras intacto).',
           '-- Clubes novos nascem lazy: notas e valores-base só são gravados quando o clube entra num mundo.', 'begin;', '']
    new = [c for c in clubs if c['id'] not in old_clubs]
    sql.append('insert into public.sim_clubs(id,name,short_name,country,tier,strength,color_primary,color_secondary,full_name,city,region,lazy) values')
    sql.append(',\n'.join(f"({q(c['id'])},{q(c['name'])},{q(c['short'])},{q(c['lg'])},'foreign',{c['strength']},{q(c['c1'])},{q(c['c2'])},{q(c['title'])},{q(c['city'])},null,true)" for c in new))
    sql.append('on conflict (id) do nothing;\n')
    for i, l in enumerate(leagues):
        members = [c for c in clubs if c['lg'] == l['country']]
        n = len(members)
        rounds = (n - 1) * l['legs']
        rules = {'bench': 12, 'format': 'league', 'points': {'win': 3, 'draw': 1}, 'champion': 'league', 'max_subs': 5, 'sub_windows': 3,
                 'phases': [{'id': 'league', 'legs': l['legs'], 'rank': 1, 'type': 'league', 'label': 'Pontos corridos'}],
                 'zones': [{'from': 1, 'to': 4, 'kind': 'continental', 'label': l['zone']}],
                 'objectives': [
                     {'label': 'Brigar pelo título: terminar entre os 3 primeiros', 'target': 3, 'priority': 3, 'rank_max': 2},
                     {'label': 'Terminar entre os 4 primeiros', 'target': 4, 'priority': 3, 'rank_max': 5},
                     {'label': 'Terminar na metade de cima', 'target': n // 2, 'priority': 3, 'rank_max': n // 2 + 1},
                     {'label': 'Fazer uma campanha segura', 'target': n - 3, 'priority': 3, 'rank_max': 99}],
                 'tiebreakers': ['points', 'wins', 'gd', 'gf', 'h2h_pts', 'reds', 'yellows'], 'yellow_limit': 3,
                 'season_matches': rounds, 'calendar_rounds': rounds, 'calendar_priority': 5}
        theme = {'c1': l['c1'], 'c2': l['c2'], 'code': l['code'], 'kicker': 'Liga estrangeira'}
        sql.append('insert into public.sim_competitions(id,name,short_name,sort_order,xp_mult,rules,region,kind,division,ref_season,sources,theme,active,background) values')
        sql.append(f"({q(l['id'])},{q(l['name'])},{q(l['short'])},{200 + i},{l['xp']},{q(json.dumps(rules, ensure_ascii=False))}::jsonb,{q(l['region'])},'league',1,'2026',{q(json.dumps([l['source']]))}::jsonb,{q(json.dumps(theme))}::jsonb,true,true)")
        sql.append('on conflict (id) do nothing;')
        sql.append('insert into public.sim_competition_clubs(competition_id,club_id) values ' + ','.join(f"({q(l['id'])},{q(c['id'])})" for c in members) + ' on conflict do nothing;\n')
    for i in range(0, len(players), 500):
        chunk = players[i:i + 500]
        sql.append('insert into public.sim_players(id,full_name,short_name,club_id,shirt_number,position,secondary_positions,position_estimated,nationality,birth_date,age,active,source_url,source_as_of,attr_pos,attr_level) values')
        sql.append(',\n'.join(
            f"({q(p['id'])},{q(p['name'])},{q(short_name(p['name']))},{q(p['club'])},{p['num'] if p['num'] is not None and p['num'] < 32768 else 'null'},{q(p['pos'])},"
            f"'{{{','.join(p['sec'])}}}',true,{q(p['nat'])},{q(p['birth'])},{p['age'] if p['age'] is not None else 'null'},true,null,'2026-11-06',{q(p['pos'])},{p['level']})"
            for p in chunk))
        sql.append('on conflict (id) do nothing;\n')
    sql.append('commit;')
    OUT_SQL.write_text('\n'.join(sql) + '\n', encoding='utf-8')

    js = ['// GERADO por scripts/build-tier-b.py (data/tier-b/clubs.tsv). Clubes das ligas de fundo. Não edite à mão.',
          'export const CLUB_CATALOG_B = {']
    for c in new:
        js.append(f"  {json.dumps(c['id'])}: {{ id: {json.dumps(c['id'])}, name: {json.dumps(c['name'], ensure_ascii=False)}, short: {json.dumps(c['short'])}, "
                  f"country: {json.dumps(c['lg'])}, region: null, tier: 'foreign', colors: [{json.dumps(c['c1'])}, {json.dumps(c['c2'])}] }},")
    js.append('}')
    js.append('')
    js.append('export const LEAGUES_B = ' + json.dumps({l['id']: {'name': l['name'], 'short': l['short'], 'country': l['country']} for l in leagues}, ensure_ascii=False, indent=2))
    OUT_JS.write_text('\n'.join(js) + '\n', encoding='utf-8')
    print(f'{len(new)} clubes novos, {len(clubs) - len(new)} já existentes, {len(players)} atletas, {len(leagues)} ligas')
    print(f'com nascimento: {sum(1 for p in players if p["birth"])}')

if __name__ == '__main__':
    main()
