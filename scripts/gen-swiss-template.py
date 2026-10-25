#!/usr/bin/env python3
"""
Gera modelos (templates) do calendário da FASE DE LIGA da Champions League (formato desde 2024/25):
36 clubes em 4 potes de 9; cada clube faz 8 jogos: 2 adversários de CADA pote (um em casa, um fora),
nunca o mesmo adversário duas vezes, 4 jogos em casa e 4 fora, e uma partida por rodada (8 rodadas).

O modelo usa "vagas" (pote p, posição i). A cada temporada o jogo sorteia quais clubes ocupam as vagas
de cada pote (evitando clubes do mesmo país no mesmo jogo), então o calendário muda todo ano.

  python3 scripts/gen-swiss-template.py 4 > data/competitions/ucl_swiss_templates.json
"""
import json, random, sys

POTS, SIZE, ROUNDS = 4, 9, 8

def slot(p, i):
    return p * SIZE + i

def build_edges(rng):
    edges = []  # (home, away)
    # dentro do pote: ciclo de 9 (i recebe i+1), depois de embaralhar
    for p in range(POTS):
        order = list(range(SIZE)); rng.shuffle(order)
        for k in range(SIZE):
            edges.append((slot(p, order[k]), slot(p, order[(k + 1) % SIZE])))
    # entre potes: duas permutações, sem repetir adversário
    for p in range(POTS):
        for q in range(p + 1, POTS):
            while True:
                sigma = list(range(SIZE)); rng.shuffle(sigma)
                tau = list(range(SIZE)); rng.shuffle(tau)   # Pq_j recebe Pp_tau[j]
                inv = {tau[j]: j for j in range(SIZE)}
                if all(sigma[i] != inv[i] for i in range(SIZE)):
                    break
            for i in range(SIZE):
                edges.append((slot(p, i), slot(q, sigma[i])))
            for j in range(SIZE):
                edges.append((slot(q, j), slot(p, tau[j])))
    return edges

def color(edges, rng, limit=200000):
    n = len(edges)
    busy = [[False] * ROUNDS for _ in range(POTS * SIZE)]
    col = [-1] * n
    order = list(range(n)); rng.shuffle(order)
    steps = [0]
    def options(e):
        h, a = edges[e]
        return [r for r in range(ROUNDS) if not busy[h][r] and not busy[a][r]]
    def dfs(done):
        steps[0] += 1
        if steps[0] > limit:
            return False
        if done == n:
            return True
        # MRV: aresta não colorida com menos opções
        best, bopts = None, None
        for e in range(n):
            if col[e] != -1:
                continue
            o = options(e)
            if bopts is None or len(o) < len(bopts):
                best, bopts = e, o
                if len(o) <= 1:
                    break
        if not bopts:
            return False
        rng.shuffle(bopts)
        h, a = edges[best]
        for r in bopts:
            col[best] = r; busy[h][r] = busy[a][r] = True
            if dfs(done + 1):
                return True
            col[best] = -1; busy[h][r] = busy[a][r] = False
        return False
    return col if dfs(0) else None

def valid(edges, col):
    for t in range(POTS * SIZE):
        games = [(e, k) for k, e in enumerate(edges) if t in e]
        assert len(games) == 8
        assert sum(1 for e, _ in games if e[0] == t) == 4
        opp = [e[1] if e[0] == t else e[0] for e, _ in games]
        assert len(set(opp)) == 8
        for p in range(POTS):
            mine = [e for e, _ in games if (e[1] if e[0] == t else e[0]) // SIZE == p]
            assert len(mine) == 2 and sum(1 for e in mine if e[0] == t) == 1
        assert sorted(col[k] for _, k in games) == list(range(ROUNDS))
    return True

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    rng = random.Random(20260828)   # determinístico (data do sorteio real da fase de liga 2026/27)
    out = []
    while len(out) < n:
        edges = build_edges(rng)
        col = color(edges, rng)
        if col is None:
            continue
        valid(edges, col)
        out.append(sorted([[col[k] + 1, h, a] for k, (h, a) in enumerate(edges)]))
    json.dump({"about": "Modelos do calendário da fase de liga da UCL: [rodada, vaga_mandante, vaga_visitante]; vaga = pote*9 + posição (0..35). Gerado por scripts/gen-swiss-template.py.",
               "templates": out}, sys.stdout, separators=(",", ":"))

main()
