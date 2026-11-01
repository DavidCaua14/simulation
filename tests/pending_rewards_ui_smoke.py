"""Home -> old reward -> claim -> Home, using only intercepted Supabase responses.
Run with Vite on 127.0.0.1:5173 and Python Playwright + Chromium.
"""
import base64
import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright, expect

variables = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line and not line.lstrip().startswith('#'))
host = urlsplit(variables['VITE_SUPABASE_URL'].strip().strip('\"\'')).hostname
uid = '52525252-1111-4111-8111-111111111111'
user = {'id': uid, 'email': 'rewards@example.test', 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}}
encode = lambda x: base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
expiry = int(time.time()) + 3600
token = encode({'alg': 'HS256', 'typ': 'JWT'}) + '.' + encode({'sub': uid, 'role': 'authenticated', 'exp': expiry}) + '.mock'
session = {'access_token': token, 'refresh_token': 'mock', 'expires_at': expiry, 'expires_in': 3600, 'token_type': 'bearer', 'user': user}
career = {'id': 'saved-reward-career', 'user_id': uid, 'nickname': 'Rewards tester', 'club_id': 'avai', 'photo_id': '1', 'status': 'active', 'age': 30, 'level': 3, 'xp': 250, 'coins': 1000, 'diamonds': 5, 'energy': 10}
now = datetime.now(timezone.utc)
iso = lambda delta: (now + delta).isoformat()
reward = {'kind': 'coins', 'amount': 125}
current = {'id': 'daily-event', 'name': 'Vitória do dia', 'description': 'Vença uma partida.', 'category': 'daily', 'banner': {}, 'state': 'active', 'recurrence': 'daily', 'min_level': 1, 'completions_total': 2, 'starts_at': iso(timedelta(days=-10)), 'ends_at': iso(timedelta(days=10)), 'period_end': iso(timedelta(days=1)), 'objectives': [{'id': 'win', 'label': 'Vença uma partida', 'target': 1, 'progress': 1}], 'rewards': [reward], 'completion': {'id': 'today-claimed', 'claimable': False, 'claimed_at': iso(timedelta(minutes=-10)), 'claim_until': iso(timedelta(days=2))}}

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox'])
    for width in [320, 1280]:
        context = browser.new_context(viewport={'width': width, 'height': 844})
        page = context.new_page()
        page.clock.install()
        errors, claims = [], []
        state = {'pending': True, 'deadline': iso(timedelta(hours=1)), 'daily_claimed': True}
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.add_init_script('localStorage.setItem(' + json.dumps('sb-' + host.split('.')[0] + '-auth-token') + ',' + json.dumps(json.dumps(session)) + ');localStorage.setItem("progress-sentinel","preserved")')
        def overview():
            pending = {'id': 'daily-event', 'name': 'Vitória do dia', 'completion_id': 'yesterday-pending', 'period_key': 'previous-day', 'completed_at': iso(timedelta(days=-1)), 'claim_until': state['deadline'], 'rewards': [reward]}
            return {'now': now.isoformat(), 'active': [current], 'upcoming': [], 'ended': [], 'history': [], 'claimable': int(state['pending']), 'pending_rewards': [pending] if state['pending'] else [], 'streak': {'active': True, 'claimed_today': state['daily_claimed'], 'eligible_today': True, 'today_day': 4, 'current': 4, 'best': 4, 'cycle_days': 7, 'resets_at': iso(timedelta(days=1)), 'rewards': [{'day': d, 'coins': 10, 'diamonds': 0, 'energy': 0} for d in range(1, 8)]}}
        def api(route):
            name = urlsplit(route.request.url).path.rsplit('/', 1)[-1]
            data = []
            if name == 'user': data = user
            elif name == 'careers': data = [career]
            elif name == 'refresh_wallet': data = {'coins': 1000 + (125 if claims else 0), 'diamonds': 5, 'energy': 10}
            elif name == 'coach_ranking': data = {'entries': [], 'me': None}
            elif name == 'inbox_list': data = {'items': [], 'unread': 0, 'claimable': 0}
            elif name == 'inbox_pending': data = None
            elif name == 'release_gift_claim': data = {'eligible': False}
            elif name == 'events_overview': data = overview()
            elif name == 'event_claim':
                claims.append(route.request.post_data_json['p_completion'])
                assert claims == ['yesterday-pending'], claims
                state['pending'] = False
                data = {'ok': True, 'replayed': False, 'event': 'Vitória do dia', 'rewards': [reward]}
            elif name == 'streak_claim':
                state['daily_claimed'] = True
                data = {'ok': True, 'day': 4, 'current': 4, 'coins': 10, 'diamonds': 0, 'energy': 0}
            route.fulfill(status=200, content_type='application/json', body=json.dumps(data))
        page.route('https://' + host + '/**', api)
        page.goto('http://127.0.0.1:5173/', wait_until='domcontentloaded')
        expect(page.get_by_text('1 recompensa pronta', exact=True)).to_be_visible()
        page.locator('.hm-events').click()
        pending = page.get_by_role('region', name='Recompensas pendentes', exact=True)
        expect(pending).to_be_visible()
        expect(page.get_by_text('Recompensa resgatada — volte no próximo período!', exact=True)).to_be_visible()
        expect(page.get_by_role('button', name='Resgatar', exact=True)).to_have_count(1)
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        pending.get_by_role('button', name='Resgatar', exact=True).click()
        page.get_by_role('button', name='Continuar', exact=True).click()
        expect(pending).to_have_count(0)
        page.get_by_role('button', name='Voltar ao menu', exact=True).click()
        expect(page.locator('.hm-events.is-ready')).to_have_count(0)
        # A second tab claims a reward: returning focus must refresh the count.
        state['pending'] = True
        page.evaluate('window.dispatchEvent(new Event("focus"))')
        expect(page.get_by_text('1 recompensa pronta', exact=True)).to_be_visible()
        state['pending'] = False
        page.evaluate('window.dispatchEvent(new Event("focus"))')
        expect(page.locator('.hm-events.is-ready')).to_have_count(0)
        # An expiry updates the Home badge while it stays open, without extra claims.
        state['pending'] = True
        state['deadline'] = page.evaluate('new Date(Date.now() + 1000).toISOString()')
        page.evaluate('window.dispatchEvent(new Event("focus"))')
        expect(page.get_by_text('1 recompensa pronta', exact=True)).to_be_visible()
        state['pending'] = False
        page.clock.fast_forward(2000)
        expect(page.locator('.hm-events.is-ready')).to_have_count(0)
        # A genuine daily streak reward still appears and can be claimed.
        state['daily_claimed'] = False
        page.evaluate('window.dispatchEvent(new Event("focus"))')
        expect(page.get_by_text('1 recompensa pronta', exact=True)).to_be_visible()
        page.locator('.hm-events').click()
        expect(page.get_by_role('region', name='Recompensas pendentes', exact=True)).to_have_count(0)
        page.get_by_role('button', name='Resgatar dia 4', exact=True).click()
        page.get_by_role('button', name='Continuar', exact=True).click()
        page.get_by_role('button', name='Voltar ao menu', exact=True).click()
        expect(page.locator('.hm-events.is-ready')).to_have_count(0)
        assert claims == ['yesterday-pending'] and not errors, (claims, errors)
        assert page.evaluate('localStorage.getItem("progress-sentinel")') == 'preserved'
        print('PASS rewards UI', width, 'old reward reachable, one claim, cleared badge, focus/expiry refresh, daily streak preserved', flush=True)
        context.close()
    browser.close()
