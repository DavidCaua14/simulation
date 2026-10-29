"""Jornada completa do treinador no mundo paralelo, com uma transação por chamada (como o app).
Só aceita bancos descartáveis simulation_validation_*.
Uso: python tests/career_world_journey.py <container> <banco>    (PG_LOCAL=1 usa o psql local com PGHOST/PGPORT)

Fases: (1) treinador empregado no Brasil joga até a janela europeia; (2) sai do clube e recebe propostas,
assume um clube europeu no meio do calendário e continua de onde a temporada inglesa está; (3) joga lá,
sai e volta a um clube brasileiro. Ao final verifica IA de transferências (janelas, elencos, contratos),
satisfação/pedidos de saída, contratos (prazos, vencimentos, pré-contratos) e as mensagens geradas.
"""
import json, os, subprocess, sys, uuid, time
from datetime import date

container, database = sys.argv[1:3]
if not database.startswith('simulation_validation_'): raise SystemExit('Disposable test database required')
if os.environ.get('PG_LOCAL'):
    cmd = ['psql', '-U', 'postgres', '-d', database, '-At', '-v', 'ON_ERROR_STOP=1', '-q']
else:
    cmd = ['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', container, 'psql', '-U', 'postgres', '-d', database, '-At', '-v', 'ON_ERROR_STOP=1', '-q']
uid, cid = '51515151-0000-0000-0000-000000000001', '51515151-0000-0000-0000-000000000011'
HDR = f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
checks, notes = [], []


def sql(src):
    r = subprocess.run(cmd, input=src.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode: raise RuntimeError(r.stderr.decode()[-3000:])
    return [l for l in r.stdout.decode().splitlines() if l.strip()]


def rpc(call):
    out = sql(HDR + f"select jsonb_build_object('v', to_jsonb(({call})));commit;")
    return json.loads(out[-1])['v'] if out else None


def one(q):
    out = sql(q)
    return out[-1] if out else None


def check(ok, label, detail=''):
    checks.append((bool(ok), label, detail))
    print(('PASS ' if ok else 'FAIL ') + label + (f' — {detail}' if detail else ''), flush=True)


def hub():
    return rpc('public.mgr_hub()')


def play_until(stop_date, max_days=400, label=''):
    """Avança o calendário e joga as partidas do seu clube até stop_date (ou até ficar sem clube)."""
    played = 0
    for _ in range(max_days * 3):
        sql(f"update public.careers set bonus_energy=200 where id='{cid}';")
        h = hub()
        w = h['world']
        if w['today'] >= stop_date or h['coach']['status'] != 'employed': return h, played
        ev = h.get('next_event') or {}
        if h.get('live_match'):
            fx = h['live_match'] if isinstance(h['live_match'], int) else h['live_match'].get('id')
            rpc(f"public.mgr_match_step({fx},0,120,null,true,0)"); played += 1; continue
        if not w['needs_sync'] and ev.get('kind') == 'mine' and (ev.get('days_until') or 0) <= 0:
            rpc("public.mgr_lineup_auto(null)")
            m = rpc("public.mgr_match_start()")
            rpc(f"public.mgr_match_step({m['fixture_id']},{m.get('minute') or 0},120,null,true,0)"); played += 1; continue
        days = 0 if w['needs_sync'] else max(1, min(7, ev.get('days_until') or 7))
        if h['season']['status'] == 'finished':
            r = rpc(f"public.career_world_advance(7,'{uuid.uuid4()}')")
            if r.get('next_season_ready'): rpc('public.mgr_season_next()')
            continue
        rpc(f"public.career_world_advance({days},'{uuid.uuid4()}')")
    raise AssertionError('Calendário não chegou a ' + stop_date)


def wait_offers(region=None, max_days=60):
    """Sem clube: avança até chegar proposta (de uma região, se informada)."""
    for _ in range(max_days):
        h = hub()
        offers = h['offers']
        regions = {o['club_id']: one(f"select public.cw_region('{o['club_id']}')") for o in offers}
        good = [o for o in offers if region is None or regions[o['club_id']] == region]
        if good: return h, good, regions
        rpc(f"public.career_world_advance({0 if h['world']['needs_sync'] else 1},'{uuid.uuid4()}')")
    return hub(), [], {}


def accept(offer):
    h = hub()
    while h['world']['needs_sync']:
        rpc(f"public.career_world_advance(0,'{uuid.uuid4()}')"); h = hub()
    return rpc(f"public.mgr_offer_respond('{offer['id']}',true)")


def season_state(region):
    sid = one(f"select ws.season_id from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id='{cid}' and ws.region='{region}' and s.status='active' order by ws.starts_on limit 1")
    if not sid: return None
    played = int(one(f"select count(*) from public.season_fixtures where season_id='{sid}' and status='played'"))
    return {'season': sid, 'played': played}


started = time.monotonic()
sql(f"insert into auth.users(id) values('{uid}') on conflict do nothing;"
    f"insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values('{cid}','{uid}','Journey','palmeiras','BR',30,200) on conflict do nothing;")
h = hub()
start_today = h['world']['today']
check(h['coach']['status'] == 'employed' and h['coach']['club_id'] == 'palmeiras', 'carreira começa empregada no Palmeiras', start_today)

# ---------------- FASE 1: Brasil, primeiro semestre ----------------
h, n1 = play_until(f"{start_today[:4]}-06-20", label='Brasil')
own = h['coach']['club_id']
print(f'Fase 1: {n1} partidas jogadas, hoje {h["world"]["today"]}, clube {own}, status {h["coach"]["status"]}', flush=True)
offers_employed = sql(f"select from_club||'|'||public.cw_region(from_club)||'|'||status from public.season_offers where career_id='{cid}' and kind='coach'")
notes.append(f'propostas recebidas empregado no Brasil (jan–jun): {len(offers_employed)} {offers_employed[:6]}')

# satisfação do elenco: quem joga x quem não joga
rows = sql(f"""select cp.player_id||'|'||round(cp.morale)||'|'||cp.transfer_requested||'|'||cp.promised_role||'|'||coalesce((select sum(a.minutes) from public.cw_appearances a where a.career_id=cp.career_id and a.player_id=cp.player_id and a.club_id='{own}'),0)
 from public.cw_players cp join public.mgr_players mp using(career_id,player_id) where cp.career_id='{cid}' and mp.club_id='{own}'""")
squad = [dict(zip(['id', 'morale', 'req', 'role', 'minutes'], r.split('|'))) for r in rows]
for p in squad: p['morale'] = int(p['morale']); p['minutes'] = int(p['minutes']); p['req'] = p['req'] in ('t', 'true')
regular = [p for p in squad if p['minutes'] >= 900]
benched_promised = [p for p in squad if p['minutes'] < 200 and p['role'] in ('key', 'starter')]
avg = lambda xs: round(sum(x['morale'] for x in xs) / len(xs), 1) if xs else None
check(regular and avg(regular) >= 60, 'titulares que jogam ficam satisfeitos', f'média {avg(regular)} ({len(regular)} atletas)')
if benched_promised:
    check(avg(benched_promised) < avg(regular), 'quem tem papel de titular e não joga fica insatisfeito', f'média {avg(benched_promised)} ({len(benched_promised)} atletas)')
else:
    notes.append('nenhum titular prometido ficou sem jogar na fase 1')
check(all(p['morale'] < 30 for p in squad if p['req']) and all(not p['req'] for p in squad if p['morale'] >= 30), 'pedido de saída só abaixo de 30 de satisfação',
      f"{sum(p['req'] for p in squad)} pediram para sair")
msgs = sql(f"select category||'|'||kind||'|'||title from public.mgr_messages where career_id='{cid}' order by id")
notes.append(f'mensagens após a fase 1: {len(msgs)} — por assunto ' + json.dumps({c: sum(1 for m in msgs if m.startswith(c + "|")) for c in ["squad", "market", "club", "career"]}))

# ---------------- FASE 2: sai e vai para a Europa ----------------
rep = float(h['coach']['reputation'])
rpc('public.mgr_resign()')
h, first, regions = wait_offers(None, 30)
low_regions = sorted(set(regions.values()))
check(first, 'sem clube, recebe propostas', f"reputação {rep}: regiões {low_regions}")
if rep < 22: check('ENG' not in low_regions, 'com reputação baixa não chegam clubes europeus (todos acima do alcance)', f'reputação {rep}')
# Treinador consagrado (alavanca de teste): reputação 55 → alcance cobre clubes ingleses.
sql(f"update public.mgr_coach set reputation=55 where career_id='{cid}';update public.season_offers set status='declined' where career_id='{cid}' and status='pending';")
h, eng_offers, regions = wait_offers('ENG', 120)
check(eng_offers, 'com reputação alta, recebe proposta de clube europeu', f"hoje {h['world']['today']}; regiões {sorted(set(regions.values()))}")
if eng_offers:
    before_today = h['world']['today']
    eng_mid = season_state('ENG')
    res = accept(eng_offers[0])
    h = hub()
    eng_club = h['coach']['club_id']
    check(res.get('accepted') and one(f"select public.cw_region('{eng_club}')") == 'ENG', 'assume clube europeu', eng_club)
    check(h['world']['today'] == before_today, 'a data do mundo não volta nem pula ao trocar de liga', h['world']['today'])
    check(h['season']['region'] == 'ENG' and h['season']['id'] == eng_mid['season'], 'a temporada inglesa em andamento vira a principal (não recomeça)',
          f"{eng_mid['played']} jogos já disputados nela")
    nxt = h.get('next_event') or {}
    pending_first = one(f"""select min(f.round_no) from public.season_fixtures f where f.season_id='{eng_mid['season']}' and f.status='pending' and f.competition_id='{nxt.get('competition')}' and '{eng_club}' in(f.home_club,f.away_club)""")
    check(nxt.get('kind') in ('mine', 'free') and (nxt.get('kind') != 'mine' or str(nxt.get('round')) == str(pending_first)), 'próximo jogo é a rodada pendente do novo clube (continua de onde está)',
          f"{nxt.get('competition')} rodada {nxt.get('round')}")
    bra = season_state('BRA')
    h, n2 = play_until(f"{start_today[:4]}-09-20", label='Inglaterra')
    bra_after = season_state('BRA')
    check(bra_after is None or bra_after['played'] > bra['played'], 'o Brasileirão segue sendo disputado pela IA enquanto você está fora',
          f"{bra['played']} → {bra_after['played'] if bra_after else 'temporada encerrada'} jogos")
    print(f'Fase 2: {n2} partidas na Inglaterra, hoje {h["world"]["today"]}', flush=True)

    # ---------------- FASE 3: volta ao Brasil ----------------
    if h['coach']['status'] == 'employed': rpc('public.mgr_resign()')
    sql(f"update public.season_offers set status='declined' where career_id='{cid}' and status='pending';")
    h, bra_offers, regions = wait_offers('BRA', 120)
    check(bra_offers, 'estando na Europa, recebe proposta de clube brasileiro', f"regiões: {sorted(set(regions.values()))}")
    if bra_offers:
        bra_mid = season_state('BRA')
        today_before = h['world']['today']
        accept(bra_offers[0]); h = hub()
        check(h['season']['region'] == 'BRA' and h['season']['id'] == bra_mid['season'] and h['world']['today'] == today_before,
              'volta ao Brasil na mesma temporada e data, continuando a rodada', f"{h['coach']['club_id']} · {bra_mid['played']} jogos já disputados")
        h, n3 = play_until(f"{int(start_today[:4]) + 1}-02-10", label='Brasil 2 (virada do ano)')
        print(f'Fase 3: {n3} partidas, hoje {h["world"]["today"]}', flush=True)

# ---------------- IA do mercado, contratos e janelas ----------------
bad_window = int(one(f"""select count(*) from public.cw_negotiations n where n.career_id='{cid}' and n.status='completed' and n.initiator<>'renewal'
 and n.seller_club is not null and n.agreed_owner_contract is not null
 and not public.cw_window_open(public.cw_region(n.buyer_club),n.register_on)
 and not exists(select 1 from public.cw_contracts c where c.id=n.agreed_owner_contract and c.expires_on<n.register_on)"""))
done = int(one(f"select count(*) from public.cw_negotiations where career_id='{cid}' and status='completed' and initiator<>'renewal'"))
check(done > 0, 'clubes da IA fazem contratações ao longo do ano', f'{done} transferências concluídas')
check(bad_window == 0, 'transferências com clube vendedor só são registradas com a janela aberta (pré-contratos à parte)', f'{bad_window} fora da janela')
by_month = sql(f"""select m||' '||r||' '||n from (select to_char(register_on,'YYYY-MM') m,public.cw_region(buyer_club) r,count(*) n from public.cw_negotiations where career_id='{cid}' and status='completed' and initiator<>'renewal' group by 1,2) x order by m,r""")
notes.append('transferências por mês/região: ' + ', '.join(r.replace(' ', ':', 1) for r in by_month))
long_contracts = int(one(f"select count(*) from public.cw_contracts where career_id='{cid}' and status='active' and expires_on>starts_on+interval '5 years 1 day'"))
check(long_contracts == 0, 'nenhum contrato ativo passa de 5 anos', f'{long_contracts} acima')
early_pre = int(one(f"""select count(*) from public.cw_negotiations n join public.cw_contracts c on c.id=n.agreed_owner_contract where n.career_id='{cid}' and n.status in('precontract','completed') and n.register_on is not null and n.fee=0 and n.seller_club is not null and n.created_on<c.expires_on-181"""))
check(early_pre == 0, 'pré-contratos só nos seis meses finais do vínculo', f'{early_pre} antecipados')
stale = int(one(f"select count(*) from public.cw_contracts where career_id='{cid}' and status='active' and expires_on<(select today from public.cw_world where career_id='{cid}')"))
check(stale == 0, 'contratos vencidos são encerrados (atleta fica livre ou muda de clube)', f'{stale} vencidos ainda ativos')
expired = int(one(f"select count(*) from public.cw_contracts where career_id='{cid}' and status='expired'"))
free_now = int(one(f"select count(*) from public.mgr_players where career_id='{cid}' and club_id is null"))
free_signed = int(one(f"select count(*) from public.cw_negotiations where career_id='{cid}' and status='completed' and seller_club is null and initiator<>'renewal'"))
notes.append(f'contratos vencidos no período: {expired}; atletas livres agora: {free_now}; livres contratados: {free_signed}')
tiny = sql(f"select club_id||':'||count(*) from public.mgr_players where career_id='{cid}' and club_id is not null group by club_id having count(*)<18 order by count(*) limit 8")
check(not tiny, 'nenhum clube da IA fica com elenco curto demais (menos de 18)', ', '.join(tiny))
huge = sql(f"select club_id||':'||count(*) from public.mgr_players where career_id='{cid}' and club_id is not null group by club_id having count(*)>55 order by count(*) desc limit 8")
check(not huge, 'nenhum clube da IA incha o elenco (mais de 55)', ', '.join(huge))
neg_cash = int(one(f"select count(*) from public.cw_clubs where career_id='{cid}' and cash<0"))
check(neg_cash == 0, 'nenhum caixa negativo')
renew_ai = int(one(f"select count(*) from public.cw_news where career_id='{cid}' and event_key like 'ai-renew:%'"))
notes.append(f'renovações feitas pela IA: {renew_ai}')
coach_offers = sql(f"select to_char(created_at,'MM-DD')||' '||from_club||' '||public.cw_region(from_club)||' '||status from public.season_offers where career_id='{cid}' and kind='coach' order by created_at")
notes.append(f'propostas de emprego ({len(coach_offers)}): ' + '; '.join(coach_offers[:20]))
world = sql(f"""select r||' '||n||' '||m||' '||pct from (select cp.promised_role r,count(*) n,round(avg(cp.morale)) m,round(100.0*avg((cp.morale<30)::int),1) pct from public.cw_players cp join public.mgr_players mp using(career_id,player_id) where cp.career_id='{cid}' and mp.club_id is not null group by 1) x order by r""")
notes.append('satisfação no mundo (papel, atletas, média, % pedindo saída): ' + '; '.join(world))
wd = {r.split()[0]: float(r.split()[3]) for r in world}
check(wd.get('rotation', 0) <= 8 and wd.get('prospect', 0) <= 8, 'reservas e promessas raramente pedem para sair', f"rotação {wd.get('rotation')}% · promessa {wd.get('prospect')}%")
check(wd.get('starter', 100) <= 35, 'titulares prometidos insatisfeitos são minoria', f"{wd.get('starter')}%")
cats = sql(f"select c||':'||n from (select category c,count(*) n from public.mgr_messages where career_id='{cid}' group by 1) x order by c")
# virada do ano: contratos que venceram, pré-contratos registrados e livres contratados
pre_done = int(one(f"select count(*) from public.cw_negotiations where career_id='{cid}' and status='completed' and fee=0 and register_on is not null and initiator='ai' and seller_club is not null"))
notes.append(f'pré-contratos concluídos (saída de graça): {pre_done}')
misaligned = sql(f"""select public.cw_region(club_id)||' '||to_char(expires_on,'MM-DD') from public.cw_contracts where career_id='{cid}' and status='active' and starts_on>(select started_on from public.cw_world where career_id='{cid}')
 and not ((public.cw_region(club_id)='ENG' and to_char(expires_on,'MM-DD')='06-30') or (public.cw_region(club_id)<>'ENG' and to_char(expires_on,'MM-DD')='12-31')) limit 5""")
newc = int(one(f"select count(*) from public.cw_contracts where career_id='{cid}' and starts_on>(select started_on from public.cw_world where career_id='{cid}')"))
check(not misaligned, 'contratos novos terminam no fim da temporada do país (BRA 31/12, ENG 30/06)', f'{newc} contratos novos; fora do padrão: {misaligned}')
notes.append('mensagens por assunto: ' + ', '.join(cats))
check(any(c.startswith('market:') for c in cats), 'mensagens de mercado chegam na caixa')

print('\n'.join('NOTE ' + n for n in notes), flush=True)
fails = [c for c in checks if not c[0]]
print(f'RESULT {len(checks) - len(fails)}/{len(checks)} checks passed in {round(time.monotonic() - started)}s', flush=True)
if fails: raise SystemExit(1)
