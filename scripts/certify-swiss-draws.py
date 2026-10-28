#!/usr/bin/env python3
"""Certifica os modelos suíços para todas as associações elegíveis da região.
Dependência de geração: pip install -r scripts/requirements-swiss.txt
Não usa credenciais, rede ou banco. O jogo não depende de Python/OR-Tools.
"""
from collections import Counter
from itertools import product
from pathlib import Path
import json
import subprocess
from ortools.sat.python import cp_model

ROOT = Path(__file__).resolve().parents[1]
config = json.loads((ROOT / 'data/competitions/competitions.json').read_text())
templates = json.loads((ROOT / 'data/competitions/ucl_swiss_templates.json').read_text())['templates']
clubs = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    "import {CLUB_CATALOG} from './src/features/club/data/clubCatalog.js';process.stdout.write(JSON.stringify(CLUB_CATALOG))"], cwd=ROOT))
comp = next(c for c in config['competitions'] if c['id'] == 'ucl')
region = comp['region']
pots = config['participants']['ucl_pots']
base = [Counter() for _ in range(4)]
regional_places = []
for pot, ids in pots.items():
    for club_id in ids:
        if clubs[club_id]['region'] == region:
            regional_places.append(int(pot) - 1)
        else:
            base[int(pot) - 1][clubs[club_id]['country']] += 1
eligible = Counter(c['country'] for c in clubs.values() if c['region'] == region)
signatures = {}
for entries in product(sorted(eligible), repeat=len(regional_places)):
    if any(n > eligible[c] for c, n in Counter(entries).items()):
        continue
    counts = [x.copy() for x in base]
    for pot, country in zip(regional_places, entries):
        counts[pot][country] += 1
    signature = [dict(sorted(c.items())) for c in counts]
    signatures[json.dumps(signature, sort_keys=True)] = counts

certificates = []
for _, counts in sorted(signatures.items()):
    found = 0
    all_countries = set().union(*(c.keys() for c in counts))
    for ti, tpl in enumerate(templates):
        model = cp_model.CpModel()
        x = {(s, c): model.new_bool_var(f'{s}-{c}') for s in range(36) for c in counts[s // 9]}
        for slot in range(36):
            model.add_exactly_one(x[slot, c] for c in counts[slot // 9])
        for pot in range(4):
            for country, n in counts[pot].items():
                model.add(sum(x[s, country] for s in range(pot * 9, pot * 9 + 9)) == n)
        adj = {s: [] for s in range(36)}
        for _, a, b in tpl:
            adj[a].append(b)
            adj[b].append(a)
            for country in counts[a // 9].keys() & counts[b // 9].keys():
                model.add(x[a, country] + x[b, country] <= 1)
        for slot in range(36):
            for country in all_countries:
                model.add(sum(x.get((n, country), 0) for n in adj[slot]) <= 2)
        for seed in range(3):
            solver = cp_model.CpSolver()
            solver.parameters.max_time_in_seconds = 20
            solver.parameters.num_workers = 1
            solver.parameters.random_seed = 1400 + seed
            status = solver.solve(model)
            if status == cp_model.INFEASIBLE:
                break
            if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
                raise RuntimeError(f'Busca inconclusiva no modelo {ti}; não gerar certificado inválido')
            assignment = [next(c for c in counts[s // 9] if solver.value(x[s, c])) for s in range(36)]
            # Validação independente da resposta do solver.
            for pot in range(4):
                assert Counter(assignment[pot*9:pot*9+9]) == counts[pot]
            for a in range(36):
                assert all(assignment[a] != assignment[b] for b in adj[a])
                assert max(Counter(assignment[b] for b in adj[a]).values()) <= 2
            certificate = {'signature': [dict(sorted(c.items())) for c in counts], 'template': ti, 'assignment': assignment}
            if certificate not in certificates:
                certificates.append(certificate)
                found += 1
    if found == 0:
        raise RuntimeError(f'Nenhum modelo válido para {counts}')
result = {'about': 'Associações por vaga certificadas; clubes reais são sorteados no servidor por carreira.', 'certificates': certificates}
(ROOT / 'data/competitions/ucl_draw_certificates.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
encoded = json.dumps(certificates, ensure_ascii=False, separators=(',', ':'))
sql = "-- GERADO por scripts/certify-swiss-draws.py; sem nomes de usuários ou clubes classificados.\nbegin;\n"
sql += "update public.sim_competitions set rules=jsonb_set(rules,'{swiss_certificates}',$cert$" + encoded + "$cert$::jsonb) where id='ucl';\ncommit;\n"
(ROOT / 'supabase/evolution/18_swiss_certificates.sql').write_text(sql)
print(f'{len(signatures)} configurações de associações, {len(certificates)} sorteios certificados')
