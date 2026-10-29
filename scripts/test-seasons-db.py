#!/usr/bin/env python3
"""Instala e testa o banco em um container PostgreSQL local, sem acessar Supabase.
Uso: python scripts/test-seasons-db.py [nome-do-container]
Cria e remove somente um banco novo de nome aleatório. Não recebe DATABASE_URL.
"""
from pathlib import Path
import os
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import subprocess
import sys
import time
import uuid
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('container', nargs='?', default='simulation-seasons-test')
parser.add_argument('--ui-fixtures', type=Path)
parser.add_argument('--base-cards', action='store_true')
parser.add_argument('--skip-existing-tests', action='store_true')
parser.add_argument('--keep-db', action='store_true')
args = parser.parse_args()
CONTAINER = args.container
DATABASE = 'simulation_validation_' + uuid.uuid4().hex[:12]
ENV = {k: v for k, v in os.environ.items() if k not in ['DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH']}
DOCKER = ['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', CONTAINER]
files = ['supabase/evolution/tests/support/bootstrap.sql', 'supabase/schema.sql']
files += ['supabase/seasons/' + x for x in ['01_schema.sql', '02_seed.sql', '03_engine.sql', '04_features.sql']]
files += ['supabase/manager/01_schema.sql', 'supabase/evolution/01_schema.sql', 'supabase/evolution/02_reference_data.sql', 'supabase/manager/02_players_seed.sql']
files += ['supabase/manager/' + x for x in ['03_engine.sql', '04_career.sql', '05_permissions.sql']]
files += ['supabase/cards/' + x for x in ['01_cards.sql', '02_cards_seed.sql', '03_auto_cards.sql', '04_box_open_meta.sql']]
files += ['supabase/manager/06_cards_coach.sql']
files += ['supabase/evolution/' + x for x in ['03_engine.sql', '04_manager.sql', '05_career_start.sql', '06_economy_shop.sql', '07_shop_price_range.sql', '08_wheel.sql', '09_market.sql', '10_energy_packs.sql', '11_profile.sql', '12_friends.sql', '13_events.sql', '14_security.sql']]
updates = ['supabase/evolution/' + x for x in ['15_season_integrity.sql', '16_match_simulation.sql', '17_season_draws.sql', '18_swiss_certificates.sql', '19_opponent_analysis.sql', '20_pending_calendar_repair.sql']]
tests = ['supabase/evolution/tests/legacy_upgrade_tests.sql', 'supabase/manager/tests/manager_tests.sql'] + ['supabase/evolution/tests/' + x for x in ['competitions_tests.sql', 'season_restructure_tests.sql', 'swiss_certificates_tests.sql', 'match_calibration_tests.sql']]


def run_file(path):
    started = time.monotonic()
    result = subprocess.run(DOCKER + ['psql', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1'], input=(ROOT / path).read_bytes(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV)
    if result.returncode:
        print(result.stdout.decode()[-1000:])
        print(result.stderr.decode()[-5000:])
        raise RuntimeError('Falha em ' + path)
    print(f'PASS {path} ({time.monotonic() - started:.2f}s)', flush=True)
    for line in result.stderr.decode().splitlines():
        if 'PASS ' in line or 'CALIBRAÇÃO' in line or 'QUALIDADE' in line or 'T3:' in line:
            print(line, flush=True)


subprocess.run(DOCKER + ['createdb', '-U', 'postgres', DATABASE], check=True, env=ENV)
try:
    for path in files:
        run_file(path)
    run_file('supabase/evolution/tests/support/legacy_live_setup.sql')
    with tempfile.TemporaryDirectory(prefix='seasons-release-') as release_dir:
        bundle = Path(release_dir) / 'seasons-v2.sql'
        subprocess.run(['node', str(ROOT / 'scripts/build-seasons-release.mjs'), str(bundle)], cwd=ROOT, env=ENV, check=True, stdout=subprocess.DEVNULL)
        run_file(bundle)
    # As migrações também precisam suportar reaplicação.
    for path in updates:
        run_file(path)
    if not args.skip_existing_tests:
        for path in tests:
            run_file(path)
    if not args.skip_existing_tests:
        # Duas conexões concorrentes, não apenas chamadas sequenciais em uma transação.
        run_file('supabase/evolution/tests/support/concurrency_setup.sql')
        command = DOCKER + ['psql', '-U', 'postgres', '-d', DATABASE, '-At', '-v', 'ON_ERROR_STOP=1', '-c', "select public.sim_create_season('20202020-0000-0000-0000-0000000000ca','BRA')"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            concurrent = list(pool.map(lambda _: subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV), range(2)))
        if sorted(r.returncode == 0 for r in concurrent) != [False, True]:
            raise RuntimeError('Concorrência criou zero ou duas temporadas')
        losing = next(r for r in concurrent if r.returncode)
        if 'temporada ativa' not in losing.stderr.decode():
            raise RuntimeError('Falha concorrente inesperada: ' + losing.stderr.decode())
        count = subprocess.check_output(DOCKER + ['psql', '-U', 'postgres', '-d', DATABASE, '-Atc', "select count(*) from public.career_seasons where career_id='20202020-0000-0000-0000-0000000000ca'"], env=ENV).decode().strip()
        if count != '1':
            raise RuntimeError('Temporada duplicada após concorrência')
        print('PASS concorrência real: uma temporada criada, segunda requisição recusada', flush=True)
    if args.base_cards:
        run_file('supabase/evolution/tests/support/base_cards_setup.sql')
        run_file('supabase/releases/cartas_base.sql')
        run_file('supabase/evolution/tests/base_cards_tests.sql')
        run_file('supabase/evolution/tests/base_cards_gameplay_tests.sql')
        run_file('supabase/evolution/tests/support/base_cards_reapply_snapshot.sql')
        run_file('supabase/releases/cartas_base.sql')
        run_file('supabase/evolution/tests/base_cards_reapply_tests.sql')
        subprocess.run([sys.executable,str(ROOT/'tests/base_cards_compensation_concurrency.py'),CONTAINER,DATABASE],check=True,env=ENV)
    if args.ui_fixtures:
        result = subprocess.run(DOCKER + ['psql', '-U', 'postgres', '-d', DATABASE, '-At', '-v', 'ON_ERROR_STOP=1'], input=(ROOT / 'supabase/evolution/tests/support/ui_fixtures.sql').read_bytes(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV, check=True)
        data = next(json.loads(line) for line in result.stdout.decode().splitlines() if line.startswith('{'))
        args.ui_fixtures.write_text(json.dumps(data))
        print('Respostas fictícias de API salvas em', args.ui_fixtures, flush=True)
finally:
    if args.keep_db:
        print('Retained local test database:', DATABASE, flush=True)
    else:
        subprocess.run(DOCKER + ['dropdb', '-U', 'postgres', DATABASE], check=True, env=ENV)
