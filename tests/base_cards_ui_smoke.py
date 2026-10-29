"""Teste do navegador com API interceptada. Gere fixtures usando test-seasons-db.py.
Uso: python tests/seasons_ui_smoke.py /tmp/seasons-ui-fixtures.json
Requer Vite em execução e Python Playwright + Chromium.
"""
import base64
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import sync_playwright, expect

payload = json.loads(Path(sys.argv[1]).read_text())
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
    for width, region in [(390, 'BRA'), (1280, 'BRA'), (390, 'ENG'), (1280, 'ENG')]:
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
                data = json.loads(json.dumps(payload['hub'] if region == 'BRA' else payload['europeanHub']))
                data['coach']['club_id'] = club
                data['career']['club_id'] = club
                data['season']['region'] = region
            elif name == 'mgr_squad':
                data = payload['rivalSquad'] if args.get('p_club') and args['p_club'] != club else squad
            elif name == 'mgr_player_detail':
                data = next((x for x in squad['players'] + payload['rivalSquad']['players'] if x['id'] == args.get('p_player')), squad['players'][0])
            elif name == 'mgr_status': data = {**payload['hub']['coach'], 'club_id': club, 'next_event': payload['hub']['next_event']}
            elif name == 'mgr_opponent_report': data = payload['scout']
            elif name == 'mgr_match_start': data = payload['match']
            elif name == 'mgr_match_step':
                if args.get('p_auto'): data = payload['finishedMatch']
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
        expect(page.get_by_role('button', name='Comandar', exact=True)).to_be_visible()
        assert not page.get_by_text(re.compile('Coleção|Abrir caixas|Roleta|Carta em destaque')).count()
        assert 'card_claim_daily' not in calls
        page.locator('.tab-bar').get_by_role('button', name='Loja', exact=True).click()
        expect(page.get_by_role('tab', name='Energia', exact=True)).to_be_visible()
        expect(page.locator('.en-packs')).to_be_visible()
        assert page.locator('.sh-tabs [role=tab]').count() == 3
        assert not page.get_by_role('tab', name=re.compile('Destaque|Lenda|Roleta|Mercado')).count()
        page.get_by_role('button', name='Ver extrato', exact=True).click()
        expect(page.get_by_role('heading', name='Extrato', exact=True)).to_be_visible()
        page.get_by_role('dialog', name='Extrato').get_by_role('button', name='Fechar', exact=True).click()
        page.get_by_role('tab', name='Visual', exact=True).click()
        expect(page.locator('.vs')).to_be_visible()
        page.get_by_role('button', name='Voltar ao menu', exact=True).click()
        page.locator('.tab-bar').get_by_role('button', name='Perfil', exact=True).click()
        expect(page.locator('#pf-stats-title')).to_be_visible()
        assert not page.get_by_text('Carta em destaque', exact=True).count()
        expect(page.get_by_role('button', name='Personalizar', exact=True)).to_be_visible()
        page.locator('.tab-bar').get_by_role('button', name='Início', exact=True).click()
        page.locator('.tab-bar').get_by_role('button', name='Eventos', exact=True).click()
        expect(page.get_by_role('tab', name=re.compile('^Eventos'))).to_be_visible()
        assert not page.get_by_role('button', name='Abrir caixas', exact=True).count()
        assert not re.search(r'caixa|roleta', page.locator('.ev-streak').inner_text(), re.I)
        page.get_by_role('button', name='Voltar ao menu', exact=True).click()
        page.get_by_role('button', name='Comandar', exact=True).click()
        page.get_by_role('button', name='Time', exact=True).click()
        expect(page.locator('.pt .base-player-card')).to_have_count(11)
        expect(page.locator('.pt-cond')).to_have_count(11 + len(squad['lineup']['bench']))
        assert page.locator('.pt .ac:not(.t-basica)').count() == 0
        page.get_by_role('tab', name='Elenco', exact=True).click()
        expect(page.locator('.sq .base-player-card')).to_have_count(len(squad['players']))
        page.locator('#squad-position').select_option('GOL')
        keepers = sum(x['position'] == 'GOL' for x in squad['players'])
        expect(page.locator('.sq .base-player-card')).to_have_count(keepers)
        page.locator('.sq-row').first.click()
        expect(page.locator('.ps-head .base-player-card')).to_be_visible()
        expect(page.get_by_text('Rendimento por posição', exact=True)).to_be_visible()
        page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
        page.get_by_role('tab', name='Escalação', exact=True).click()
        page.locator('#squad-position').select_option('')
        page.locator('.pt-tok').first.click()
        expect(page.locator('.pk-list .base-player-card')).not_to_have_count(0)
        page.locator('#picker-position').select_option('GOL')
        expect(page.locator('.pk-list .base-player-card')).to_have_count(sum(x['position'] == 'GOL' and x['available'] for x in squad['players']))
        page.get_by_role('dialog').get_by_role('button', name='Fechar', exact=True).click()
        clipped = page.locator('.pt .pt-cond').evaluate_all('''els => els.filter(el => { const a = el.getBoundingClientRect(); const b = el.closest('.pt').getBoundingClientRect(); return a.bottom > b.bottom - 1 || a.top < b.top || a.left < b.left || a.right > b.right; }).length''')
        assert clipped == 0, f'Clipped fatigue bars: {clipped}'
        # Desktop and mobile snapshots include fatigue and positional overall.
        page.screenshot(path=f'/tmp/base-cards-{region}-{width}.png', full_page=True)
        if region == 'BRA':
            page.locator('.sn-nav button').filter(has_text='Início').click()
            page.get_by_role('button', name=re.compile('Jogar partida')).click()
            page.get_by_role('dialog').get_by_role('button', name=re.compile('Iniciar partida')).click()
            match_dialog = page.get_by_role('dialog', name='Partida ao vivo', exact=True)
            match_dialog.get_by_role('button', name='Pausar', exact=True).click()
            page.get_by_role('tab', name='Times', exact=True).click()
            expect(page.locator('.ml-lineups .base-player-card')).not_to_have_count(0)
            page.locator('.ml-base-button').first.click()
            expect(page.locator('.ps-head .base-player-card')).to_be_visible()
            page.get_by_role('button', name='Fechar', exact=True).last.click()
            match_dialog.get_by_role('button', name='Time', exact=True).click()
            expect(page.locator('.mle-pitch .base-player-card')).to_have_count(11)
            page.locator('.mle-pitch .pt-tok').first.click()
            page.get_by_role('button', name=re.compile('Ver ficha de ')).filter(has_text=re.compile('^Ver ficha de ')).last.click()
            expect(page.locator('.ps-head .base-player-card')).to_be_visible()
            page.get_by_role('button', name='Fechar', exact=True).last.click()
            page.get_by_role('button', name='Pronto', exact=True).click()
            match_dialog.get_by_role('button', name='Simular até o fim', exact=True).click()
            page.get_by_role('button', name=re.compile('Ver resumo da partida')).click(timeout=15000)
            expect(page.locator('.sn-rewards .coins')).to_be_visible()
            if payload['finishedMatch']['summary']['rewards']['energy']:
                expect(page.locator('.sn-rewards .energy')).to_contain_text('+1 energia')
            assert page.locator('.sn-rewards .xp').count() == 0
            assert not page.get_by_role('button', name=re.compile('Abrir caixa')).count()
        assert not errors, errors
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        prohibited = {'card_claim_daily','box_open','wheel_spin','wheel_catalog','shop_catalog','shop_buy_card','market_browse','profile_set_featured'}
        assert not prohibited.intersection(calls), prohibited.intersection(calls)
        print('PASS base cards, lineup/filters/details/fatigue, store, profile, events', width, region, flush=True)
        context.close()
    browser.close()
