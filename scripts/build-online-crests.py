#!/usr/bin/env python3
"""Gera supabase/online/42_crests.sql: escudo oficial de cada clube real do modo online (on_real_clubs.crest).

A e B: escudos do modo Temporadas (public/crests/<id do catálogo>.*). C e D: data/clubs/online_crest_sources.json
(scripts/fetch-online-crests.py). Clube sem escudo segue com o escudo desenhado. Clubes de técnicos não mudam.
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
seed = (ROOT / 'supabase' / 'online' / '38_series.sql').read_text(encoding='utf-8')
rows = re.findall(r"^ \('([a-z0-9-]+)','[^']*','[^']*','([ABCD])',(null|'[a-z0-9-]+')", seed, re.M)
lower = json.loads((ROOT / 'data' / 'clubs' / 'online_crest_sources.json').read_text(encoding='utf-8'))['crests']
out, missing = [], []
for key, div, sim in rows:
    path = None
    if sim != 'null':
        sim = sim.strip("'")
        f = next(iter(sorted((ROOT / 'public' / 'crests').glob(f'{sim}.*'))), None)
        path = f'crests/{f.name}' if f else None
    elif key in lower:
        path = lower[key]['file']
    if path:
        out.append(f"('{key}','{path}')")
    else:
        missing.append(key)
sql = f"""-- MODO ONLINE — Fase 38: escudos oficiais dos clubes reais (bots). GERADO por scripts/build-online-crests.py.
-- O escudo vai em on_real_clubs.crest e em on_clubs.colors.crest (todas as telas que já mostram escudo passam a mostrar
-- o oficial). Clubes de técnicos seguem com o escudo desenhado e personalizável; quando um técnico assume um clube de
-- bot, o escudo oficial sai (on_take_seat). Sem escudo oficial ({len(missing)}): {', '.join(missing) or 'nenhum'}.
update public.on_real_clubs rc set crest=x.crest from(values
{(','+chr(10)).join(out)}
) x(key,crest) where rc.key=x.key;
update public.on_clubs k set colors=k.colors||jsonb_build_object('crest',rc.crest)
 from public.on_real_clubs rc where rc.key=k.real_key and k.user_id is null and rc.crest is not null;
"""
(ROOT / 'supabase' / 'online' / '42_crests.sql').write_text(sql, encoding='utf-8')
print(f'{len(out)} escudos; sem: {missing}')
