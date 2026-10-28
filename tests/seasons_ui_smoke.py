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
    for width, backend in [(390, 'v2'), (1280, 'v2'), (390, 'legacy')]:
        context = browser.new_context(viewport={'width': width, 'height': 844})
        page = context.new_page()
        errors = []
        calls = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.add_init_script('localStorage.setItem(' + json.dumps('sb-' + host.split('.')[0] + '-auth-token') + ',' + json.dumps(json.dumps(session)) + ')')

        def api(route):
            request = route.request
            url = urlsplit(request.url)
            name = url.path.rsplit('/', 1)[-1]
            calls.append(name)
            data = []
            if name == 'careers':
                data = payload['career']
            elif name == 'mgr_hub':
                data = dict(payload['hub'])
                if backend == 'legacy':
                    data.pop('simulation_version', None)
            elif name == 'mgr_status':
                data = {**payload['hub']['coach'], 'next_event': payload['hub']['next_event'], 'season': payload['hub']['season']}
            elif name == 'mgr_squad':
                data = payload['squad']
            elif name == 'mgr_opponent_report':
                data = payload['scout']
            elif name in ['mgr_match_start', 'mgr_match_step']:
                data = payload['match']
            elif name == 'sim_competitions':
                data = payload['competitions']
            elif name == 'sim_formations':
                data = payload['formations']
            elif name == 'season_fixtures':
                competition = parse_qs(url.query).get('competition_id', [''])[0].removeprefix('eq.')
                data = [f for f in payload['fixtures'] if f['competition_id'] == competition]
            elif name == 'refresh_wallet':
                data = payload['hub']['career']
            elif name == 'get_profile':
                data = {}
            route.fulfill(status=200, content_type='application/json', body=json.dumps(data))

        page.route('https://' + host + '/**', api)
        page.goto('http://127.0.0.1:5173/', wait_until='domcontentloaded')
        page.get_by_role('button', name='Comandar', exact=True).click()
        summary = page.locator('.opponent-scout > summary')
        if backend == 'v2':
            expect(summary).to_be_visible()
            summary.click()
            expect(page.get_by_text(re.compile('Plano provável'))).to_be_visible()
            expect(page.locator('.opponent-analysis')).to_contain_text(payload['scout']['formation'])
            assert calls.count('mgr_opponent_report') == 1
        else:
            assert summary.count() == 0
            assert 'mgr_opponent_report' not in calls
        page.get_by_role('button', name='Time', exact=True).click()
        page.get_by_role('tab', name='Táticas', exact=True).click()
        tackles = page.get_by_role('radiogroup', name='Entradas', exact=True)
        if backend == 'v2':
            expect(tackles).to_be_visible()
            tackles.get_by_role('radio', name='Cautelosas', exact=True).click()
            expect(tackles.get_by_role('radio', name='Cautelosas', exact=True)).to_have_attribute('aria-checked', 'true')
            page.locator('.sn-nav button').filter(has_text='Início').click()
            page.get_by_role('button', name=re.compile('Ir para o jogo')).click()
            page.get_by_role('tab', name='Times', exact=True).click()
            expect(page.get_by_text(re.compile('Plano atual em campo'))).to_be_visible()
        else:
            assert tackles.count() == 0
        assert not errors, errors
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        print('PASS análise de rival, entradas e compatibilidade de versão', width, backend, flush=True)
        context.close()
    browser.close()
