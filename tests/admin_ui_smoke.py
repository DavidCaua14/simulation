"""Teste do painel administrativo e da caixa de entrada com API interceptada (desktop e celular).
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
OWNER = 'contatodavidcaua@gmail.com'


def session_for(email):
    uid = '11111111-1111-4111-8111-111111111111'
    expiry = int(time.time()) + 3600
    user = {'id': uid, 'email': email, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}
    token = encode({'alg': 'HS256', 'typ': 'JWT'}) + '.' + encode({'sub': uid, 'email': email, 'role': 'authenticated', 'exp': expiry}) + '.mock'
    return {'access_token': token, 'refresh_token': 'mock', 'expires_at': expiry, 'expires_in': 3600, 'token_type': 'bearer', 'user': user}


def open_page(browser, email, width, url):
    context = browser.new_context(viewport={'width': width, 'height': 900})
    page = context.new_page()
    state = {'errors': [], 'calls': [], 'pending': json.loads(json.dumps(admin['pending'])), 'inbox': json.loads(json.dumps(admin['inbox']))}
    page.on('pageerror', lambda e: state['errors'].append(str(e)))
    page.add_init_script('localStorage.setItem(' + json.dumps('sb-' + host.split('.')[0] + '-auth-token') + ',' + json.dumps(json.dumps(session_for(email))) + ')')

    def api(route):
        request = route.request
        name = urlsplit(request.url).path.rsplit('/', 1)[-1]
        args = request.post_data_json if request.method == 'POST' else {}
        state['calls'].append((name, args))
        data = []
        if name == 'careers':
            data = {**game['career'], 'club_id': game['squad']['club_id']}
            if 'vnd.pgrst.object' not in (request.headers.get('accept') or ''): data = [data]
        elif name == 'admin_overview': data = admin['overview']
        elif name == 'admin_players': data = admin['players']
        elif name == 'admin_events_list': data = admin['events']
        elif name == 'admin_actions_list': data = admin['actions']
        elif name == 'admin_announcements': data = admin['announcements']
        elif name == 'admin_announcement_save': data = admin['announcements'][0]
        elif name in ('admin_career', 'admin_career_set_club', 'admin_career_adjust'):
            data = json.loads(json.dumps(admin['career']))
            if name == 'admin_career_set_club': data['coach']['club_id'] = args['p_club']
        elif name == 'admin_player_grant': data = {'coins': 1600, 'diamonds': 0, 'bonus_energy': 0, 'inbox': True}
        elif name == 'inbox_pending': data = state['pending']
        elif name == 'inbox_list': data = state['inbox']
        elif name == 'inbox_seen':
            seen = {(i['type'], i['id']) for i in args['p_items']}
            state['pending'] = [i for i in state['pending'] if (i['type'], i['id']) not in seen]
            data = {'ok': True}
        elif name == 'inbox_claim':
            data = {'ok': True, 'reward': {}}
            for i in state['inbox']['items']:
                if i['id'] == args['p_id']: i['claimable'] = False; i['claimed_at'] = '2026-10-30T12:00:00Z'
            state['inbox']['claimable'] = sum(1 for i in state['inbox']['items'] if i['claimable'])
        elif name in ['profile_me', 'profile_migrate_local', 'profile_set_privacy']: data = game['profile']
        elif name == 'events_overview': data = game['events']
        elif name == 'release_gift_claim': data = {'eligible': False}
        elif name == 'ranking_overall': data = admin['ranking']
        elif name == 'ranking_photos': data = admin.get('ranking_photos', {})
        route.fulfill(status=200, content_type='application/json', body=json.dumps(data))
    page.route('https://' + host + '/**', api)
    page.goto(url, wait_until='domcontentloaded')
    return context, page, state


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox'])

    # 1) painel do dono (desktop e celular)
    for width in (1440, 390):
        context, page, st = open_page(browser, OWNER, width, 'http://127.0.0.1:5173/#admin')
        calls = st['calls']
        expect(page.get_by_role('heading', name='Visão geral')).to_be_visible(timeout=15000)
        expect(page.get_by_text('Partidas jogadas')).to_be_visible()
        expect(page.get_by_text('Cadastros por dia (14 dias)')).to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Rolagem horizontal na visão geral'
        if shots: page.screenshot(path=str(shots / f'admin-overview-{width}.png'), full_page=True)
        nav = page.get_by_role('navigation', name='Seções do painel')

        nav.get_by_role('button', name='Temporadas').click()
        expect(page.get_by_role('heading', name='Temporadas')).to_be_visible()
        page.get_by_role('button', name='Gerenciar').first.click()
        expect(page.get_by_text('Ações no modo Temporadas')).to_be_visible()
        page.get_by_label('Clube').select_option(index=3)
        page.get_by_label('Motivo (o jogador vê)').first.fill('Convite especial')
        page.get_by_role('button', name='Transferir técnico').click()
        expect(page.get_by_text('agora treina')).to_be_visible()
        move = [a for n, a in calls if n == 'admin_career_set_club'][-1]
        assert move['p_reason'] == 'Convite especial' and move['p_club'], move
        page.get_by_label('Valor (negativo retira)').fill('250000')
        page.get_by_label('Motivo (o jogador vê)').nth(1).fill('Patrocínio')
        page.get_by_role('button', name='Aplicar').first.click()
        expect(page.get_by_text('Caixa ajustado')).to_be_visible()
        if shots: page.screenshot(path=str(shots / f'admin-seasons-{width}.png'), full_page=True)

        nav.get_by_role('button', name='Avisos').click()
        page.get_by_label('Título').fill('Copa de inverno')
        page.get_by_label('Mensagem').fill('Evento especial no fim de semana.')
        page.get_by_label('Moedas').fill('500')
        page.get_by_role('button', name='Publicar aviso').click()
        page.get_by_role('button', name='Publicar', exact=True).click()
        expect(page.get_by_text('Aviso criado.')).to_be_visible()
        saved = [a for n, a in calls if n == 'admin_announcement_save'][-1]['p']
        assert saved['title'] == 'Copa de inverno' and saved['reward'] == {'coins': 500} and saved['ends_at'] > saved['starts_at'], saved
        if shots: page.screenshot(path=str(shots / f'admin-announcements-{width}.png'), full_page=True)

        nav.get_by_role('button', name='Jogadores').click()
        page.get_by_role('button', name='Premiar').first.click()
        page.get_by_label('Motivo (o jogador vê)').fill('Compensação de teste')
        page.get_by_role('button', name='Confirmar').click()
        expect(page.get_by_text('enviada para a caixa de entrada')).to_be_visible()

        nav.get_by_role('button', name='Registro').click()
        expect(page.get_by_role('heading', name='Registro')).to_be_visible()
        page.get_by_role('button', name='Voltar ao jogo').click()
        expect(page.locator('.ad')).to_have_count(0)
        assert st['errors'] == [], st['errors']
        print(f'PASS painel {width}px: visão geral, Temporadas (troca de clube e caixa), avisos com período, premiação e registro')
        context.close()

    # 2) jogador: modal na tela inicial (um por vez) e caixa de entrada
    context, page, st = open_page(browser, 'jogador@example.com', 390, 'http://127.0.0.1:5173/')
    modal = page.get_by_role('dialog')
    expect(modal.get_by_role('heading', name='Manutenção programada')).to_be_visible(timeout=15000)
    expect(modal.get_by_text('1 de 3')).to_be_visible()
    page.wait_for_timeout(500)
    if shots: page.screenshot(path=str(shots / 'player-modal-announcement.png'))
    modal.get_by_role('button', name='Resgatar').click()
    expect(modal.get_by_role('heading', name='Você recebeu uma premiação')).to_be_visible()
    modal.get_by_role('button', name='Depois (fica na caixa)').click()
    expect(modal.get_by_role('heading', name='Reforço no caixa do clube')).to_be_visible()
    page.wait_for_timeout(500)
    if shots: page.screenshot(path=str(shots / 'player-modal-club.png'))
    modal.get_by_role('button', name='Entendi').click()
    expect(page.get_by_role('dialog')).to_have_count(0)
    assert sum(1 for n, _ in st['calls'] if n == 'inbox_claim') == 1
    assert sum(1 for n, _ in st['calls'] if n == 'inbox_seen') == 3
    page.get_by_role('button', name='Mensagens').click()
    expect(page.get_by_role('heading', name='Caixa de entrada')).to_be_visible()
    page.get_by_role('button', name='Resgatar').first.click()
    expect(page.get_by_text('Premiação resgatada!')).to_be_visible()
    page.get_by_role('tab', name='Premiações').click()
    if shots: page.screenshot(path=str(shots / 'player-inbox.png'), full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Rolagem horizontal na caixa de entrada'
    page.get_by_role('button', name='Voltar').click()
    # faixa da tela inicial usa o ranking geral; o card Ranking abre a tela
    expect(page.locator('.hm-rank-entry').first).to_contain_text(admin['ranking']['entries'][0]['nickname'])
    expect(page.locator('.hm-rank-me b')).to_have_text(f"#{admin['ranking']['me']['position']}")
    page.get_by_role('button', name='Ranking', exact=True).click()
    expect(page.get_by_role('heading', name='Ranking')).to_be_visible()
    expect(page.get_by_label('Pódio')).to_contain_text(admin['ranking']['entries'][0]['nickname'])
    expect(page.get_by_label('Sua posição')).to_contain_text(f"{admin['ranking']['me']['position']}º")
    assert page.locator('.rk-row').count() == len(admin['ranking']['entries'])
    assert page.locator('.rk-podium .rk-av img').count() >= 2, 'Pódio sem avatares'
    expect(page.locator('.rk-camp-nums .w b')).to_have_text(str(admin['ranking']['me']['wins']))
    assert page.evaluate('[...document.querySelectorAll(".rk-camp-nums b, .rk-me-stats b")].every(b => b.scrollWidth <= b.clientWidth + 1)'), 'Números cortados no cartão'
    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Rolagem horizontal no ranking'
    page.wait_for_timeout(400)
    if shots: page.screenshot(path=str(shots / 'player-ranking.png'), full_page=True)
    page.get_by_role('button', name='Pontuação').click()
    dialog = page.get_by_role('dialog')
    expect(dialog.get_by_text('500 pontos por título no modo Temporadas')).to_be_visible()
    expect(dialog.get_by_text('Seus pontos')).to_be_visible()
    expect(dialog.locator('tfoot')).to_contain_text(f"{admin['ranking']['me']['points']:,}".replace(',', '.'))
    if shots: page.screenshot(path=str(shots / 'player-ranking-scoring.png'))
    dialog.get_by_role('button', name='Fechar').click()
    expect(page.get_by_role('dialog')).to_have_count(0)
    assert st['errors'] == [], st['errors']
    print('PASS jogador: avisos e comunicados em modal um por vez, resgate, caixa de entrada e ranking')
    context.close()

    # 3) outra conta não vê o painel
    context, page, st = open_page(browser, 'outro@example.com', 1440, 'http://127.0.0.1:5173/#admin')
    page.wait_for_timeout(2500)
    assert page.locator('.ad').count() == 0, 'Outro usuário abriu o painel'
    assert not any(n.startswith('admin_') for n, _ in st['calls']), 'Outro usuário chamou o painel'
    print('PASS outro usuário não vê o painel nem chama suas funções')
    context.close()
    browser.close()
