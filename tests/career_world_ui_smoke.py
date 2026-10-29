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
    for width, region in [(320, 'BRA'), (360, 'BRA'), (390, 'BRA'), (768, 'BRA'), (1280, 'BRA')]:
        payload = json.loads(json.dumps(original_payload))
        advance_trace = []
        advance_state = {'partial': False, 'draining': False, 'backlog': 2}
        if width == 390:
            # Regression: a career stopped exactly three days before its next match.
            payload['worldHub']['world']['needs_sync'] = False
            event = payload['worldHub']['next_event']
            event['days_until'] = 3
            event['scheduled_on'] = (date.fromisoformat(payload['worldHub']['world']['today']) + timedelta(days=3)).isoformat()
            advance_state['backlog'] = 0
        context = browser.new_context(viewport={'width': width, 'height': 844})
        page = context.new_page()
        errors, calls = [], []
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
            data = []
            if name == 'careers': data = {**payload['career'], 'club_id': club}
            elif name == 'mgr_hub':
                data = json.loads(json.dumps(payload['worldHub']))
                data['coach']['club_id'] = club
                data['career']['club_id'] = club
                data['season']['region'] = region
            elif name == 'career_player_search': data = payload['worldContracts'] if args.get('p_club') == 'mine' else payload['worldMarket']
            elif name == 'career_news': data = payload['worldNews']
            elif name == 'career_negotiations': data = payload['worldDeals']
            elif name == 'career_finance_history': data = payload['worldFinance']
            elif name == 'career_world_advance':
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
            elif name.startswith('career_'): data = {'ok': True, 'id':'11111111-0000-0000-0000-000000000099'}
            elif name == 'mgr_squad':
                data = payload['rivalSquad'] if args.get('p_club') and args['p_club'] != club else squad
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
            elif name == 'refresh_wallet': data = payload['hub']['career']
            elif name in ['profile_me', 'profile_migrate_local', 'profile_set_privacy']: data = payload['profile']
            elif name == 'cosmetics_catalog': data = payload['cosmetics']
            elif name == 'energy_catalog': data = payload['energy']
            elif name == 'events_overview': data = payload['events']
            elif name == 'wallet_history': data = []
            route.fulfill(status=200, content_type='application/json', body=json.dumps(data))
        page.route('https://' + host + '/**', api)
        page.goto('http://127.0.0.1:5173/', wait_until='domcontentloaded')
        page.get_by_role('button', name='Comandar', exact=True).click()
        # Processing starts only from the regular next-match button.
        advance_button = page.get_by_role('button', name='Avançar para a próxima partida', exact=True)
        expect(advance_button).to_be_enabled()
        assert advance_button.evaluate('el => el.scrollWidth <= el.clientWidth && el.scrollHeight <= el.clientHeight'), 'Advance button text clipped'
        page.wait_for_timeout(800)
        assert advance_trace == [], advance_trace
        advance_button.click()
        expect(page.get_by_role('button', name='Ir para o jogo', exact=False)).to_be_enabled(timeout=20000)
        expected = [3, 0, 1] if width == 390 else [0, 0, 7, 0, 7, 5]
        assert advance_trace == expected, advance_trace
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
        expect(page.get_by_role('heading', name='Mundo do futebol')).to_be_visible()
        expect(page.get_by_text('NOVA CONTRATAÇÃO', exact=True)).to_be_visible()
        assert page.locator('.cw-announcement .base-player-card').count() == 1
        page.get_by_role('tab', name='Finanças', exact=True).click()
        expect(page.get_by_role('heading', name='Finanças do clube')).to_be_visible()
        page.get_by_label('Investir da sua carteira', exact=False).fill('50')
        page.get_by_role('button', name='Transferir ao clube', exact=True).click()
        expect(page.get_by_text('Investimento transferido ao clube.', exact=True)).to_be_visible()
        page.get_by_role('tab', name='Mercado', exact=True).click()
        expect(page.locator('.cw-player-grid .base-player-card')).to_have_count(30)
        page.get_by_label('Região', exact=True).select_option('ENG')
        expect(page.locator('.cw-player-grid .base-player-card')).to_have_count(30)
        page.locator('.cw-player').first.click()
        page.get_by_label('Taxa fixa', exact=True).fill('80000')
        page.get_by_label('Parcelas mensais', exact=True).fill('3')
        page.get_by_role('button', name='Enviar proposta', exact=True).click()
        expect(page.get_by_role('tab', name='Negociações', exact=True)).to_have_attribute('aria-selected','true')
        page.get_by_role('button', name='Ver negociação', exact=True).first.click()
        page.get_by_label('Salário mensal', exact=True).fill('1200')
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
            page.get_by_role('button', name=re.compile('Ir para o jogo')).click()
            match_dialog = page.get_by_role('dialog', name='Partida ao vivo', exact=True)
            expect(match_dialog).to_be_visible()
            page.wait_for_timeout(800)
            assert len(advance_trace) == before_match, 'Must pause while the user is playing'
            match_dialog.get_by_role('button', name='Simular até o fim', exact=True).click()
            page.get_by_role('button', name=re.compile('Ver resumo da partida')).click(timeout=15000)
            expect(page.get_by_role('dialog', name='Resumo da partida', exact=True)).to_be_visible()
            page.get_by_role('button', name='Continuar', exact=True).click()
            expect(advance_button).to_be_enabled()
            page.wait_for_timeout(800)
            assert len(advance_trace) == before_match, 'Post-match must wait for the next-match button'
            advance_button.click()
            expect(page.get_by_role('button', name=re.compile('Ir para o jogo'))).to_be_enabled(timeout=15000)
            assert advance_trace[before_match:] == [0, 7], advance_trace
            assert page.get_by_role('button', name='Abrir calendário', exact=True).count() == 0
        assert not errors, errors
        assert 'career_transfer_bid' in calls and 'career_player_offer' in calls and 'career_club_invest' in calls
        assert not any(n in calls for n in ['box_open','wheel_spin','market_buy','card_claim_daily'])
        print('PASS responsive career UI',width,'news, signing base card, calendar, finances, global market, athlete contract, renewals, no overflow')
        context.close()
    browser.close()
