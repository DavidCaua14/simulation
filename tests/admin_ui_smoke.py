"""Teste do painel administrativo com API interceptada (desktop e celular).
Uso: python tests/admin_ui_smoke.py <fixtures-do-jogo.json> <fixtures-do-painel.json> [pasta-para-prints]
Requer Vite em execução e Python Playwright + Chromium.
"""
import base64
import json
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright, expect

game = json.loads(Path(sys.argv[1]).read_text())
admin = json.loads(Path(sys.argv[2]).read_text())
shots = Path(sys.argv[3]) if len(sys.argv) > 3 else None
variables = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line and not line.lstrip().startswith('#'))
host = urlsplit(variables['VITE_SUPABASE_URL'].strip().strip('"\'')).hostname
encode = lambda x: base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')


def session_for(email):
    uid = '11111111-1111-4111-8111-111111111111'
    expiry = int(time.time()) + 3600
    user = {'id': uid, 'email': email, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}
    token = encode({'alg': 'HS256', 'typ': 'JWT'}) + '.' + encode({'sub': uid, 'email': email, 'role': 'authenticated', 'exp': expiry}) + '.mock'
    return {'access_token': token, 'refresh_token': 'mock', 'expires_at': expiry, 'expires_in': 3600, 'token_type': 'bearer', 'user': user}


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox'])
    for email, width in [('contatodavidcaua@gmail.com', 1440), ('contatodavidcaua@gmail.com', 390), ('outro@example.com', 1440)]:
        context = browser.new_context(viewport={'width': width, 'height': 900})
        page = context.new_page()
        errors, calls = [], []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.add_init_script('localStorage.setItem(' + json.dumps('sb-' + host.split('.')[0] + '-auth-token') + ',' + json.dumps(json.dumps(session_for(email))) + ')')

        def api(route):
            request = route.request
            name = urlsplit(request.url).path.rsplit('/', 1)[-1]
            args = request.post_data_json if request.method == 'POST' else {}
            calls.append((name, args))
            data = []
            if name == 'careers':
                data = {**game['career'], 'club_id': game['squad']['club_id']}
                if 'vnd.pgrst.object' not in (request.headers.get('accept') or ''): data = [data]
            elif name == 'admin_overview': data = admin['overview']
            elif name == 'admin_players': data = admin['players']
            elif name == 'admin_events_list': data = admin['events']
            elif name == 'admin_actions_list': data = admin['actions']
            elif name == 'admin_player_grant': data = {'coins': 1600, 'diamonds': 0, 'bonus_energy': 0}
            elif name == 'admin_broadcast': data = {'recipients': 27}
            elif name in ['profile_me', 'profile_migrate_local', 'profile_set_privacy']: data = game['profile']
            elif name == 'events_overview': data = game['events']
            elif name == 'release_gift_claim': data = {'eligible': False}
            route.fulfill(status=200, content_type='application/json', body=json.dumps(data))
        page.route('https://' + host + '/**', api)
        page.goto('http://127.0.0.1:5173/#admin', wait_until='domcontentloaded')

        if email != 'contatodavidcaua@gmail.com':
            page.wait_for_timeout(2500)
            assert page.locator('.ad').count() == 0, 'Outro usuário abriu o painel'
            assert not any(n.startswith('admin_') for n, _ in calls), 'Outro usuário chamou o painel'
            print('PASS outro usuário não vê o painel nem chama suas funções')
            context.close()
            continue

        expect(page.get_by_role('heading', name='Visão geral')).to_be_visible(timeout=15000)
        expect(page.get_by_text('Jogadores cadastrados')).to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Rolagem horizontal na visão geral'
        if shots: page.screenshot(path=str(shots / f'admin-overview-{width}.png'), full_page=True)

        nav = page.get_by_role('navigation', name='Seções do painel')
        nav.get_by_role('button', name='Eventos').click()
        expect(page.get_by_role('heading', name='Eventos')).to_be_visible()
        page.wait_for_timeout(600)
        if shots: page.screenshot(path=str(shots / f'admin-events-{width}.png'), full_page=True)

        nav.get_by_role('button', name='Jogadores').click()
        expect(page.get_by_role('heading', name='Jogadores')).to_be_visible()
        page.get_by_role('button', name='Enviar itens').first.click()
        page.get_by_label('Motivo').fill('Compensação de teste')
        page.get_by_role('button', name='Confirmar').click()
        expect(page.get_by_text('Enviado: 100 Moedas')).to_be_visible()
        grant = [a for n, a in calls if n == 'admin_player_grant'][-1]
        assert grant['p_currency'] == 'coins' and grant['p_amount'] == 100 and grant['p_reason'] == 'Compensação de teste', grant
        if shots: page.screenshot(path=str(shots / f'admin-players-{width}.png'), full_page=True)

        nav.get_by_role('button', name='Avisos').click()
        page.get_by_label('Título').fill('Manutenção programada')
        page.get_by_label('Mensagem').fill('O jogo fica fora do ar amanhã das 3h às 4h.')
        page.get_by_role('button', name='Enviar para todos').click()
        page.get_by_role('button', name='Enviar', exact=True).click()
        expect(page.get_by_text('Aviso enviado para 27 jogadores.')).to_be_visible()

        nav.get_by_role('button', name='Registro').click()
        expect(page.get_by_role('heading', name='Registro')).to_be_visible()
        page.wait_for_timeout(400)
        if shots: page.screenshot(path=str(shots / f'admin-log-{width}.png'), full_page=True)

        page.get_by_role('button', name='Voltar ao jogo').click()
        expect(page.locator('.ad')).to_have_count(0)
        assert errors == [], errors
        print(f'PASS painel {width}px: visão geral, eventos, envio de itens, aviso, registro e volta ao jogo')
        context.close()
    browser.close()
