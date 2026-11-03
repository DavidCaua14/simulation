"""Teste do navegador com API interceptada. Gere fixtures usando test-seasons-db.py.
Uso: python tests/career_world_ui_smoke.py /tmp/seasons-ui-fixtures.json
Requer Vite em execução e Python Playwright + Chromium.
"""
import base64
import json
import re
import sys
import time
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import sync_playwright, expect

payload = json.loads(Path(sys.argv[1]).read_text())
original_payload = json.loads(json.dumps(payload))
variables = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line and not line.lstrip().startswith('#'))
host = urlsplit(variables['VITE_SUPABASE_URL'].strip().strip('\"\'')).hostname
uid = '11111111-1111-4111-8111-111111111111'
email = 'contatodavidcaua@gmail.com'
user = {'id': uid, 'email': email, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}
encode = lambda x: base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
expiry = int(time.time()) + 3600
token = encode({'alg': 'HS256', 'typ': 'JWT'}) + '.' + encode({'sub': uid, 'email': email, 'role': 'authenticated', 'exp': expiry}) + '.mock'
session = {'access_token': token, 'refresh_token': 'mock', 'expires_at': expiry, 'expires_in': 3600, 'token_type': 'bearer', 'user': user}

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox'])
    cases = [(390, 'BRA', 'legacy_backend'), (390, 'BRA', 'attention'), (320, 'BRA', 'normal'), (360, 'BRA', 'normal'), (390, 'BRA', 'normal'), (768, 'BRA', 'normal'), (1280, 'BRA', 'normal')]
    if '--market-policy' in sys.argv or '--club-economy' in sys.argv: cases = [(320, 'BRA', 'market_policy'), (1280, 'BRA', 'market_policy')]
    if '--renewal-window' in sys.argv: cases = [(w, 'BRA', mode) for w in [320,1280] for mode in ['market_policy','closed_window']]
    if '--club-investment' in sys.argv: cases = [(320,'BRA','investment'),(1280,'BRA','investment'),(320,'BRA','investment_low')]
    if '--roster-refresh' in sys.argv: cases = [(320,'BRA','roster'),(1280,'BRA','roster')]
    if '--match-revenue' in sys.argv: cases = [(390,'BRA','normal')]
    for width, region, scenario in cases:
        payload = json.loads(json.dumps(original_payload))
        payload['worldHub']['world']['needs_sync'] = True
        payload['worldHub']['next_event']['days_until'] = 14
        payload['worldHub']['next_event']['scheduled_on'] = (date.fromisoformat(payload['worldHub']['world']['today']) + timedelta(days=14)).isoformat()
        if scenario in ['market_policy','closed_window','investment','investment_low']:
            payload['worldHub']['world']['club']['window_open'] = scenario != 'closed_window'
            payload['worldMarket'][0].update(salary_demand=5000, project_reason='O atleta considera o nível esportivo do clube insuficiente.')
            payload['worldMarket'][1].update(club_id=None, monthly_salary=None, salary_demand=1800, minimum_signing_bonus=3600, project_reason=None)
            payload['worldMarket'][2].update(club_id='arsenal', project_reason=None)
            payload['worldDeals'][0].update(status='player_counter', buyer_club=payload['worldHub']['coach']['club_id'], monthly_salary=40, salary_demand=1800, signing_bonus=0, minimum_signing_bonus=3600)
        roster_control = {'mode':'initial','fresh':False}
        held_rosters = []
        registered = json.loads(json.dumps(payload['squad']['players'][0]))
        registered.update(id='registered-fixture-player',name='Reforço confirmado',short_name='Reforço confirmado',position='ZAG',available=True)
        if scenario == 'roster':
            payload['worldDeals'][0].update(status='completed',initiator='user',arrival_status='registered',player_id=registered['id'],player_name=registered['name'],buyer_club=payload['worldHub']['coach']['club_id'])
        if '--match-revenue' in sys.argv:
            payload['worldHub']['world']['club']['window_open'] = True
            payload['finishedMatch']['summary']['rewards']['club'] = {'gate':250,'prize':125,'operations':-50,'total':325}
        funding = {'credit':0, 'eligible':0, 'paid':0}
        investment_requests, funding_requests = [], []
        if scenario.startswith('investment'):
            payload['worldHub']['career']['coins'] = 5000 if scenario == 'investment' else 10
            payload['worldHub']['world']['club']['cash'] = 1000
            payload['worldHub']['world']['investment'] = {'board':{'bonus_cap':200,'bonus_remaining':200,'rate_percent':20},'signal':{'key':'funding-card','kind':'negotiation','player_name':'Reforço planejado','gap':600,'coins_needed':500,'action':'deals'}}
        advance_trace = []
        advance_state = {'partial': False, 'draining': False, 'backlog': 2}
        if width == 390:
            # Regression: a career stopped exactly three days before its next match.
            payload['worldHub']['world']['needs_sync'] = False
            event = payload['worldHub']['next_event']
            event['days_until'] = 3
            event['scheduled_on'] = (date.fromisoformat(payload['worldHub']['world']['today']) + timedelta(days=3)).isoformat()
            advance_state['backlog'] = 0
        if width == 360:
            payload['worldHub']['runtime_version'] = 0
            payload['worldHub']['calendar_versions'] = {c['id']: 'v1' for c in payload['worldHub']['competitions']}
        if scenario == 'attention':
            payload['worldHub']['attention'] = {'key': 'job:fixture', 'kind': 'job', 'action': 'offers'}
            payload['worldHub']['calendar_versions'] = {c['id']: 'v1' for c in payload['worldHub']['competitions']}
        context = browser.new_context(viewport={'width': width, 'height': 844})
        page = context.new_page()
        errors, calls, contract_requests, free_requests, bids = [], [], [], [], []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.add_init_script('localStorage.setItem(' + json.dumps('sb-' + host.split('.')[0] + '-auth-token') + ',' + json.dumps(json.dumps(session)) + ')')
        squad = payload['squad'] if region == 'BRA' else payload['europeanSquad']
        club = squad['club_id']
        def api(route):
            request = route.request
            url = urlsplit(request.url)
            name = url.path.rsplit('/', 1)[-1]
            calls.append(name)
            args = request.post_data_json if request.method == 'POST' else {}
            if scenario == 'legacy_backend' and name == 'career_hub_read':
                route.fulfill(status=404, content_type='application/json', body=json.dumps({'code':'PGRST202','message':'Could not find career_hub_read in the schema cache'}))
                return
            data = []
            if name == 'careers':
                data = {**payload['career'], 'club_id': club}
                if 'vnd.pgrst.object' not in (request.headers.get('accept') or ''): data = [data]  # como o PostgREST: lista sem .single()
            elif name in ['mgr_hub', 'career_hub_read', 'career_runtime_initialize']:
                data = json.loads(json.dumps(payload['worldHub']))
                data['coach']['club_id'] = club
                data['career']['club_id'] = club
                data['season']['region'] = region
            elif name == 'career_player_search': data = payload['worldContracts'] if args.get('p_club') == 'mine' else payload['worldMarket']
            elif name == 'career_news': data = payload['worldNews']
            elif name == 'career_negotiations': data = payload['worldDeals']
            elif name == 'career_finance_history': data = payload['worldFinance']
            elif name == 'career_attention_ack':
                payload['worldHub']['attention'] = None
                data = {'ok': True}
            elif name == 'career_calendar':
                data = [f for f in payload['fixtures'] if args.get('p_comp') is None or f['competition_id'] == args['p_comp']]
                if args.get('p_scope') in ['preview', 'mine']: data = [f for f in data if club in [f['home_club'], f['away_club']] or f.get('player_match')]
                if args.get('p_scope') == 'preview': data = data[:30]
                else: data = data[args.get('p_page', 0)*500:(args.get('p_page', 0)+1)*500]
            elif name in ['career_world_advance', 'career_world_prepare']:
                if name == 'career_world_prepare':
                    assert args['p_expected_version'] == payload['worldHub']['runtime_version']
                    payload['worldHub']['runtime_version'] += 1
                requested = args.get('p_days', 0)
                advance_trace.append(requested)
                days = requested
                more = False
                if advance_state['backlog'] > 0:
                    assert requested == 0
                    advance_state['backlog'] -= 1
                    more = advance_state['backlog'] > 0
                elif requested > 0 and not advance_state['partial']:
                    advance_state.update(partial=True, draining=True)
                    days, more = 2, True
                elif requested == 0 and advance_state['draining']:
                    advance_state['draining'] = False
                payload['worldHub']['world']['needs_sync'] = more
                today = date.fromisoformat(payload['worldHub']['world']['today']) + timedelta(days=days)
                payload['worldHub']['world']['today'] = today.isoformat()
                event = payload['worldHub'].get('next_event') or {}
                if event.get('scheduled_on'):
                    event['days_until'] = (date.fromisoformat(event['scheduled_on']) - today).days
                data = {'days':days, 'matches':24, 'more':more, 'today':today.isoformat(), 'stopped_for_match': event.get('days_until', 1) <= 0}
            elif name == 'career_funding_quote':
                funding_requests.append(args)
                owner = payload['worldHub']['coach']['club_id']
                gap = max(0,600 - funding['credit'])
                coins = next((n for n in range(gap+1) if n + min(200-funding['paid'],(funding['eligible']+n)//5-funding['paid']) >= gap),gap)
                reason = 'O atleta considera o nível esportivo do clube insuficiente.' if args.get('p_player') == payload['worldMarket'][0]['id'] else None
                renewal = any(n['id']==args.get('p_negotiation') and n.get('initiator')=='renewal' for n in payload['worldDeals'])
                if not payload['worldHub']['world']['club']['window_open'] and not renewal: reason = 'Janela de transferências fechada.'
                wallet = payload['worldHub']['career']['coins']
                data = {'club_id':owner,'blocked_reason':reason,'gap':gap,'coins_needed':coins,'personal_coins':wallet,'board_bonus':gap-coins,'can_invest':not reason and gap>0 and wallet>=coins,'fee':0,'signing_bonus':0,'performance_bonus':0,'salary_reserve':600,'current_payroll_reserve':1000,'reserved_other':0,'debt':0,'club_cash':payload['worldHub']['world']['club']['cash']}
            elif name == 'career_club_investment_preview':
                amount = args['p_amount']
                wallet = payload['worldHub']['career']['coins']
                cash = payload['worldHub']['world']['club']['cash']
                bonus = min(200-funding['paid'],(funding['eligible']+amount)//5-funding['paid'])
                data = {'club_id':club,'club_name':'Clube atual','amount':amount,'personal_before':wallet,'personal_after':wallet-amount,'cash_before':cash,'cash_after':cash+amount+bonus,'board_bonus':bonus,'club_credit':amount+bonus,'can_invest':wallet>=amount}
            elif name == 'career_club_investment_confirm':
                investment_requests.append(args)
                bonus = min(200-funding['paid'],(funding['eligible']+args['p_amount'])//5-funding['paid'])
                funding['credit'] += args['p_amount']+bonus
                funding['eligible'] = min(1000,funding['eligible']+args['p_amount'])
                funding['paid'] += bonus
                payload['worldHub']['career']['coins'] -= args['p_amount']
                payload['worldHub']['world']['club']['cash'] += args['p_amount']+bonus
                payload['worldHub']['world'].setdefault('investment',{})['board'] = {'bonus_cap':200,'bonus_remaining':200-funding['paid'],'rate_percent':20}
                data = {'ok':True,'board_bonus':bonus,'club_credit':args['p_amount']+bonus}
            elif name == 'career_funding_dismiss':
                payload['worldHub']['world']['investment']['signal'] = None
                data = {'ok':True}
            elif name == 'career_free_agent_offer':
                free_requests.append(args)
                payload['worldDeals'][0]['status'] = 'player_pending'
                data = {'ok': True, 'id': payload['worldDeals'][0]['id']}
            elif name == 'career_transfer_bid':
                bids.append(args)
                payload['worldDeals'][0]['status'] = 'player_counter'
                data = {'ok': True, 'id': payload['worldDeals'][0]['id']}
            elif name == 'career_contract_renew':
                payload['worldDeals'][0].update(initiator='renewal', status='player_counter', buyer_club=club)
                data = {'ok':True, 'id':payload['worldDeals'][0]['id'], 'salary_demand':1800}
            elif name == 'career_player_offer':
                contract_requests.append(args)
                data = {'ok': True}
            elif name.startswith('career_'): data = {'ok': True, 'id':'11111111-0000-0000-0000-000000000099'}
            elif name == 'mgr_squad':
                data = payload['rivalSquad'] if args.get('p_club') and args['p_club'] != club else squad
                if scenario == 'roster':
                    data = json.loads(json.dumps(data))
                    if roster_control['mode'] == 'hold':
                        held_rosters.append((route,data))
                        return
                    if roster_control['fresh']: data['players'].append(registered)

            elif name == 'mgr_player_detail':
                data = next((x for x in squad['players'] + payload['rivalSquad']['players'] if x['id'] == args.get('p_player')), squad['players'][0])
            elif name == 'mgr_status': data = {**payload['hub']['coach'], 'club_id': club, 'next_event': payload['hub']['next_event']}
            elif name == 'mgr_opponent_report': data = payload['scout']
            elif name == 'mgr_match_start':
                data = payload['match']
                payload['worldHub']['live_match'] = {'id': data.get('id', 1)}
            elif name == 'mgr_match_step':
                if args.get('p_auto'):
                    data = payload['finishedMatch']
                    payload['worldHub']['live_match'] = None
                    event = payload['worldHub']['next_event']
                    event['fixture_id'] += 1
                    event['days_until'] = 7
                    event['scheduled_on'] = (date.fromisoformat(payload['worldHub']['world']['today']) + timedelta(days=7)).isoformat()
                    payload['worldHub']['world']['needs_sync'] = True
                else: data = {**payload['match'], 'minute': args.get('p_to', 5)}
            elif name == 'mgr_lineup_save': data = {'ok': True, 'issues': []}
            elif name == 'sim_competitions': data = payload['competitions']
            elif name == 'sim_formations': data = payload['formations']
            elif name == 'season_fixtures':
                competition = parse_qs(url.query).get('competition_id', [''])[0].removeprefix('eq.')
                data = [f for f in payload['fixtures'] if f['competition_id'] == competition]
                offset = int(parse_qs(url.query).get('offset', ['0'])[0]); limit = int(parse_qs(url.query).get('limit', ['500'])[0])
                data = data[offset:offset + limit]
            elif name == 'refresh_wallet': data = payload['hub']['career']
            elif name in ['profile_me', 'profile_migrate_local', 'profile_set_privacy']: data = payload['profile']
            elif name == 'cosmetics_catalog': data = payload['cosmetics']
            elif name == 'energy_catalog': data = payload['energy']
            elif name == 'events_overview': data = payload['events']
            elif name == 'wallet_history': data = []
            if name == 'career_world_prepare': data['state_version'] = payload['worldHub']['runtime_version']
            route.fulfill(status=200, content_type='application/json', body=json.dumps(data))
        page.route('https://' + host + '/**', api)
        page.goto('http://127.0.0.1:5173/', wait_until='domcontentloaded')
        page.get_by_role('button', name='Comandar', exact=True).click()
        if scenario == 'roster':
            nav = page.get_by_role('navigation',name='Seções do modo Carreira')
            nav.get_by_role('button',name='Time',exact=True).click()
            expect(page.get_by_role('button',name='Atualizar elenco',exact=True)).to_be_visible()
            radios = page.get_by_role('radio')
            choice = next(r for r in radios.all() if r.get_attribute('aria-checked') == 'false')
            chosen_name = choice.inner_text()
            choice.click()
            page.get_by_role('tab',name='Elenco',exact=True).click()
            expect(page.locator('.sq-row').filter(has_text='Reforço confirmado')).to_have_count(0)
            for known in payload.get('registeredChecks',[]):
                member = next(p for p in squad['players'] if p['id']==known)
                expect(page.locator('.sq-row').filter(has_text=member['short_name'])).to_have_count(1)
            roster_control['mode'] = 'hold'
            page.get_by_role('button',name='Atualizar elenco',exact=True).click()
            page.wait_for_timeout(200)
            assert held_rosters,'Expected a delayed old roster response'
            roster_control.update(mode='fresh',fresh=True)
            page.get_by_role('button',name='Atualizar elenco',exact=True).click()
            expect(page.locator('.sq-row').filter(has_text='Reforço confirmado')).to_have_count(1)
            for old_route,old_data in held_rosters: old_route.fulfill(status=200,content_type='application/json',body=json.dumps(old_data))
            page.wait_for_timeout(200)
            expect(page.locator('.sq-row').filter(has_text='Reforço confirmado')).to_have_count(1)
            page.get_by_role('tab',name='Escalação',exact=True).click()
            expect(page.get_by_role('radio',name=chosen_name,exact=True)).to_have_attribute('aria-checked','true')
            page.locator('button.pt-tok').first.click()
            page.get_by_label('Buscar no elenco',exact=True).fill('reforco confirmado')
            expect(page.locator('.pk-main')).to_have_count(1)
            expect(page.locator('.pk-main')).to_contain_text('Reforço confirmado')
            page.get_by_role('dialog').get_by_role('button',name='Fechar',exact=True).click()
            nav.get_by_role('button',name='Mundo',exact=True).click()
            page.get_by_role('tab',name='Negociações',exact=True).click()
            page.get_by_role('button',name='Ver negociação',exact=True).first.click()
            page.get_by_role('button',name='Ver atleta no Time',exact=True).click()
            expect(page.get_by_role('dialog')).to_contain_text('Reforço confirmado')
            assert 'mgr_lineup_save' not in calls and advance_trace == [] and not errors,(advance_trace,errors)
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
            print('PASS roster UI',width,'new registration selectable, stale response ignored, unsaved formation retained, name search and direct arrival link; no date or lineup writes',flush=True)
            context.close()
            continue
        if scenario.startswith('investment'):
            nav = page.get_by_role('navigation', name='Seções do modo Carreira')
            card = page.get_by_role('region', name='Planejamento do clube')
            expect(card).to_be_visible()
            card.get_by_role('button',name='Ver negociações',exact=True).click()
            expect(page.get_by_role('tab',name='Negociações',exact=True)).to_have_attribute('aria-selected','true')
            nav.locator('button').filter(has_text='Início').click()
            page.get_by_role('button',name='Dispensar aviso de planejamento',exact=True).click()
            expect(card).to_have_count(0)
            nav.get_by_role('button',name='Mundo',exact=True).click()
            page.get_by_role('tab',name='Mercado',exact=True).click()
            page.locator('.cw-player').nth(1).click()
            advice = page.get_by_label('Planejamento da negociação',exact=True)
            expect(advice).to_contain_text('Faltam R$ 600.000')
            if scenario == 'investment_low':
                expect(advice).to_contain_text('Você tem 10 moedas')
                expect(advice.get_by_role('button',name='Planejar aporte',exact=True)).to_have_count(0)
                assert not investment_requests and advance_trace == [] and not errors
                print('PASS insufficient-wallet funding UI',width,'no unavailable investment offered',flush=True)
                context.close()
                continue
            advice.get_by_role('button',name='Planejar aporte',exact=True).click()
            confirmation = page.get_by_role('group',name='Confirmar aporte',exact=True)
            expect(confirmation).to_contain_text('5.000 → 4.500 moedas')
            expect(confirmation).to_contain_text('R$ 1.000.000 → R$ 1.600.000')
            expect(confirmation).to_contain_text('+ R$ 100.000')
            expect(confirmation).to_contain_text('permanece no clube se você sair')
            assert not investment_requests and not free_requests and not bids
            page.screenshot(path=f'/tmp/club-investment-confirmation-{width}.png',full_page=True)
            confirmation.get_by_role('button',name='Voltar à decisão',exact=True).click()
            expect(confirmation).to_have_count(0)
            assert not investment_requests
            advice.get_by_role('button',name='Planejar aporte',exact=True).click()
            confirm = confirmation.get_by_role('button',name='Confirmar aporte de 500 moedas',exact=True)
            expect(confirm).to_be_enabled()
            confirm.evaluate('el => { el.click(); el.click(); }')
            expect(confirmation).to_have_count(0)
            expect(advice).to_contain_text('Estas condições cabem no orçamento atual.')
            assert len(investment_requests) == 1 and investment_requests[0]['p_amount'] == 500
            assert investment_requests[0]['p_expected_bonus'] == 100
            assert not free_requests and not bids and not contract_requests,'Contribution submitted a player offer'
            page.get_by_role('dialog').get_by_role('button',name='Fechar',exact=True).click()
            page.locator('.cw-player').nth(0).click()
            advice = page.get_by_label('Planejamento da negociação',exact=True)
            expect(advice).to_contain_text('Um aporte não remove essa exigência.')
            expect(advice.get_by_role('button',name='Planejar aporte',exact=True)).to_have_count(0)
            page.get_by_role('dialog').get_by_role('button',name='Fechar',exact=True).click()
            page.get_by_role('tab',name='Finanças',exact=True).click()
            expect(page.get_by_label('Aporte ao clube',exact=True)).to_contain_text('Ainda disponível: R$ 100.000')
            page.get_by_label('Investir da sua carteira',exact=False).fill('100')
            page.get_by_role('button',name='Revisar aporte',exact=True).click()
            expect(confirmation).to_contain_text('4.500 → 4.400 moedas')
            confirmation.get_by_role('button',name='Confirmar aporte de 100 moedas',exact=True).click()
            expect(confirmation).to_have_count(0)
            expect(page.get_by_label('Aporte ao clube',exact=True)).to_contain_text('Ainda disponível: R$ 80.000')
            nav.locator('button').filter(has_text='Início').click()
            expect(card).to_have_count(0)
            assert len(investment_requests)==2 and 'career_club_invest' not in calls
            assert advance_trace==[] and not errors,(advance_trace,errors)
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'),'Funding UI overflow'
            page.screenshot(path=f'/tmp/club-investment-{width}.png',full_page=True)
            print('PASS funding UI',width,'context quote, full confirmation, optional cancellation, one request per double-click, board support, no implicit signing, home routing and dismissal',flush=True)
            context.close()
            continue
        if scenario == 'closed_window':
            page.get_by_role('navigation', name='Seções do modo Carreira').get_by_role('button', name='Mundo', exact=True).click()
            page.get_by_role('tab', name='Mercado', exact=True).click()
            expect(page.locator('.cw-player')).to_have_count(30)
            page.locator('.cw-player').nth(1).click()
            expect(page.get_by_text('Janela de transferências fechada.', exact=False)).to_be_visible()
            expect(page.get_by_role('button', name='Apresentar proposta ao atleta', exact=True)).to_be_disabled()
            page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
            page.locator('.cw-player').nth(2).click()
            expect(page.get_by_role('button', name='Enviar proposta', exact=True)).to_be_disabled()
            page.get_by_label('Pré-contrato sem taxa', exact=False).check()
            expect(page.get_by_role('button', name='Enviar proposta', exact=True)).to_be_disabled()
            page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
            page.get_by_role('tab', name='Negociações', exact=True).click()
            page.get_by_role('button', name='Ver negociação', exact=True).first.click()
            expect(page.get_by_role('button', name='Apresentar contrato', exact=True)).to_be_disabled()
            page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
            page.get_by_role('tab', name='Contratos', exact=True).click()
            page.locator('.cw-player').first.click()
            expect(page.get_by_role('button', name='Negociar renovação', exact=True)).to_be_enabled()
            page.get_by_role('button', name='Negociar renovação', exact=True).click()
            expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
            assert 'career_contract_renew' in calls
            page.get_by_role('button', name='Ver negociação', exact=True).first.click()
            expect(page.get_by_role('button', name='Apresentar contrato', exact=True)).to_be_enabled()
            page.get_by_role('button', name='Apresentar contrato', exact=True).click()
            expect(page.get_by_text('Contrato enviado ao atleta.', exact=False)).to_be_visible()
            assert not free_requests and not bids and len(contract_requests) == 1
            assert advance_trace == [] and not errors, (advance_trace,errors)
            print('PASS closed window UI',width,'free/owned/precontracts blocked; own renewal available; date unchanged',flush=True)
            context.close()
            continue
        if scenario == 'market_policy':
            page.get_by_role('navigation', name='Seções do modo Carreira').get_by_role('button', name='Mundo', exact=True).click()
            page.get_by_role('tab', name='Mercado', exact=True).click()
            expect(page.locator('.cw-player')).to_have_count(30)
            page.locator('.cw-player').nth(0).click()
            expect(page.get_by_text('O atleta considera o nível esportivo do clube insuficiente.', exact=True)).to_be_visible()
            expect(page.get_by_role('button', name='Enviar proposta', exact=True)).to_be_disabled()
            page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
            page.locator('.cw-player').nth(1).click()
            expect(page.get_by_text('Salário mensal pretendido:', exact=False)).to_contain_text('1.800.000')
            expect(page.get_by_text('Salário mensal pretendido:', exact=False)).to_contain_text('3.600.000')
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
            expect(page.get_by_label('Taxa fixa (R$)', exact=True)).to_have_count(0)
            expect(page.get_by_label('Parcelas mensais', exact=True)).to_have_count(0)
            expect(page.get_by_label('Salário mensal (R$)', exact=True)).to_have_value('1800000')
            expect(page.get_by_label('Luvas (R$)', exact=True)).to_have_value('3600000')
            page.get_by_role('button', name='Apresentar proposta ao atleta', exact=True).click()
            expect(page.get_by_text('Proposta enviada diretamente ao atleta.', exact=False)).to_be_visible()
            expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
            assert len(free_requests) == 1 and free_requests[0]['p_salary'] == 1800 and free_requests[0]['p_signing'] == 3600
            assert len(bids) == 0 and len(contract_requests) == 0, 'Free agent required a club bid or second form'
            page.get_by_role('tab', name='Mercado', exact=True).click()
            page.locator('.cw-player').nth(2).click()
            page.get_by_label('Taxa fixa (R$)', exact=True).fill('80000000')
            page.get_by_role('button', name='Enviar proposta', exact=True).click()
            expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
            assert len(bids) == 1 and bids[0]['p_fee'] == 80000
            page.get_by_role('button', name='Ver negociação', exact=True).first.click()
            expect(page.get_by_label('Salário mensal (R$)', exact=True)).to_have_value('1800000')
            expect(page.get_by_label('Luvas (R$)', exact=True)).to_have_value('3600000')
            page.get_by_role('button', name='Apresentar contrato', exact=True).click()
            expect(page.get_by_text('Contrato enviado ao atleta.', exact=False)).to_be_visible()
            assert len(contract_requests) == 1 and contract_requests[0]['p_salary'] == 1800 and contract_requests[0]['p_signing'] == 3600
            assert advance_trace == [] and not errors, (advance_trace, errors)
            print('PASS market policy UI', width, 'BRL salary/signing, direct free-agent offer, owned transfer preserved, exact API denomination and stable date', flush=True)
            context.close()
            continue
        # Processing starts only from the regular next-match button.
        advance_button = page.get_by_role('button', name='Avançar para a próxima partida', exact=True)
        expect(advance_button).to_be_enabled()
        if scenario == 'attention':
            expect(page.get_by_role('heading', name='Uma decisão precisa da sua atenção')).to_be_visible()
            advance_button.click()
            page.wait_for_timeout(500)
            assert advance_trace == [], 'Unseen proposal must stop all date movement'
            page.get_by_role('button', name='Continuar sem responder', exact=True).click()
            expect(page.get_by_role('heading', name='Uma decisão precisa da sua atenção')).to_have_count(0)
            assert 'career_attention_ack' in calls and 'career_calendar' in calls
            assert 'season_fixtures' not in calls, 'Home must use only the small calendar preview'
            assert not errors, errors
            print('PASS attention pause, explicit deferral and lazy calendar')
            context.close()
            continue
        assert advance_button.evaluate('el => el.scrollWidth <= el.clientWidth && el.scrollHeight <= el.clientHeight'), 'Advance button text clipped'
        page.wait_for_timeout(800)
        assert advance_trace == [], advance_trace
        advance_button.click()
        expect(page.get_by_role('button', name='Jogar partida', exact=False)).to_be_enabled(timeout=20000)
        expected = [3, 0, 1] if width == 390 else [0, 0, 7, 0, 7, 5]
        assert advance_trace == expected, advance_trace
        if scenario == 'legacy_backend': assert 'mgr_hub' in calls, 'Backend without migration must remain usable'
        page.wait_for_timeout(800)
        assert advance_trace == expected, 'Must stop before the user match'
        nav = page.get_by_role('navigation', name='Seções do modo Carreira')
        expect(nav.get_by_role('button')).to_have_count(6)
        nav.get_by_role('button', name='Mundo', exact=True).click()
        expect(nav.get_by_role('button', name='Mundo', exact=True)).to_have_attribute('aria-current', 'page')
        assert page.get_by_role('button', name='Abrir calendário', exact=True).count() == 0
        assert page.get_by_role('button', name='Atualizar resultados', exact=True).count() == 0
        assert page.get_by_role('tab', name='Campeonatos', exact=True).count() == 0
        for button in nav.get_by_role('button').all():
            box = button.bounding_box()
            assert box['width'] >= 44 and box['height'] >= 44, box
        expect(page.get_by_role('heading', name='Mundo do futebol', exact=True)).to_be_visible()
        expect(page.get_by_text('NOVA CONTRATAÇÃO', exact=True)).to_be_visible()
        assert page.locator('.cw-announcement .base-player-card').count() == 1
        page.get_by_role('tab', name='Finanças', exact=True).click()
        expect(page.get_by_role('heading', name='Finanças do clube')).to_be_visible()
        page.get_by_label('Investir da sua carteira', exact=False).fill('50')
        page.get_by_role('button', name='Revisar aporte', exact=True).click()
        page.get_by_role('group',name='Confirmar aporte',exact=True).get_by_role('button',name='Confirmar aporte de 50 moedas',exact=True).click()
        expect(page.get_by_text('Investimento transferido ao clube.', exact=True)).to_be_visible()
        page.get_by_role('tab', name='Mercado', exact=True).click()
        expect(page.locator('.cw-player-grid .base-player-card')).to_have_count(30)
        page.get_by_label('Região', exact=True).select_option('ENG')
        expect(page.locator('.cw-player-grid .base-player-card')).to_have_count(30)
        page.locator('.cw-player').first.click()
        page.get_by_label('Taxa fixa (R$)', exact=True).fill('80000000')
        page.get_by_label('Parcelas mensais', exact=True).fill('3')
        page.get_by_role('button', name='Enviar proposta', exact=True).click()
        expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
        page.get_by_role('button', name='Ver negociação', exact=True).first.click()
        page.get_by_label('Salário mensal (R$)', exact=True).fill('1200000')
        page.get_by_label('Anos de contrato', exact=True).fill('3')
        page.get_by_role('button', name='Apresentar contrato', exact=True).click()
        expect(page.get_by_text('Contrato enviado ao atleta.', exact=False)).to_be_visible()
        page.get_by_role('tab', name='Contratos', exact=True).click()
        expect(page.locator('.cw-player-grid .base-player-card')).not_to_have_count(0)
        page.locator('.cw-player').first.click()
        expect(page.get_by_role('heading', name='Gestão do contrato', exact=True)).to_be_visible()
        page.get_by_role('button', name='Negociar renovação', exact=True).click()
        expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
        for area in ['Notícias','Finanças','Mercado','Negociações','Contratos']:
            page.get_by_role('tab', name=area, exact=True).click()
            page.wait_for_timeout(350)
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), 'Horizontal page overflow: '+area
        page.screenshot(path=f'/tmp/career-world-{width}.png', full_page=True)
        if width == 390:
            nav.locator('button').filter(has_text='Início').click()
            before_match = len(advance_trace)
            page.get_by_role('button', name=re.compile('Jogar partida')).click()
            page.get_by_role('dialog').get_by_role('button', name=re.compile('Iniciar partida')).click()
            match_dialog = page.get_by_role('dialog', name='Partida ao vivo', exact=True)
            expect(match_dialog).to_be_visible()
            page.wait_for_timeout(800)
            assert len(advance_trace) == before_match, 'Must pause while the user is playing'
            match_dialog.get_by_role('button', name='Simular até o fim', exact=True).click()
            page.get_by_role('button', name=re.compile('Ver resumo da partida')).click(timeout=15000)
            expect(page.get_by_role('dialog', name='Resumo da partida', exact=True)).to_be_visible()
            if '--match-revenue' in sys.argv:
                summary = page.get_by_role('dialog',name='Resumo da partida',exact=True)
                expect(summary).to_contain_text('Bilheteria bruta: R$ 250.000')
                expect(summary).to_contain_text('Bônus pelo resultado: +R$ 125.000')
                expect(summary).to_contain_text('Operação da partida: -R$ 50.000')
                expect(summary).to_contain_text('Saldo da partida no caixa: R$ 325.000')

            page.get_by_role('button', name='Continuar', exact=True).click()
            expect(advance_button).to_be_enabled()
            page.wait_for_timeout(800)
            assert len(advance_trace) == before_match, 'Post-match must wait for the next-match button'
            advance_button.click()
            expect(page.get_by_role('button', name=re.compile('Jogar partida'))).to_be_enabled(timeout=15000)
            assert advance_trace[before_match:] == [0, 7], advance_trace
            assert page.get_by_role('button', name='Abrir calendário', exact=True).count() == 0
        assert not errors, errors
        assert 'career_transfer_bid' in calls and 'career_player_offer' in calls and 'career_club_investment_confirm' in calls
        assert not any(n in calls for n in ['box_open','wheel_spin','market_buy','card_claim_daily'])
        print('PASS responsive career UI',width,'news, signing base card, calendar, finances, global market, athlete contract, renewals, no overflow')
        context.close()
    browser.close()
