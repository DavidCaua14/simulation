#!/usr/bin/env python3
"""Baixa os escudos oficiais dos clubes das Séries C e D do modo online (imagem principal da página na Wikipédia).

Uso: python3 scripts/fetch-online-crests.py
Saída: public/crests/online/<chave>.svg (ou .webp, convertido de PNG em 256 px) e data/clubs/online_crest_sources.json
(de onde veio cada um). Os clubes das Séries A e B usam os escudos do modo Temporadas (public/crests/<id>.svg).
Só aceita imagem cujo nome de arquivo parece escudo (logo, escudo, crest, emblem, badge, brasão ou .svg) — foto de
estádio ou de time fica de fora e o clube segue com o escudo desenhado.
"""
import importlib.util, io, json, pathlib, re, time, urllib.parse, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('squads', ROOT / 'scripts' / 'fetch-lower-squads.py')
sq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sq)
OUT = ROOT / 'public' / 'crests' / 'online'
SOURCES = ROOT / 'data' / 'clubs' / 'online_crest_sources.json'
LOOKS_LIKE_CREST = re.compile(r'logo|escudo|crest|emblem|badge|bras[aã]o|shield|\.svg$|\.png$', re.I)


def download(url):
    for attempt in range(30):
        try:
            time.sleep(4)
            req = urllib.request.Request(url, headers={'User-Agent': sq.UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code != 429: raise
            wait = int(e.headers.get('Retry-After') or 30) + 5
            print(f'  limite de downloads: esperando {wait} s', flush=True)
            time.sleep(wait)
    raise RuntimeError('download falhou')


def infobox_image(wt):
    """Arquivo do escudo na caixa de informações (en: image/logo; pt: imagem/escudo/logo)."""
    m = re.search(r'^\s*\|\s*(?:image|logo|imagem|escudo|símbolo)\s*=\s*(?:\[\[)?(?:File:|Ficheiro:|Arquivo:|Imagem:|Image:)?([^|\]\n<{]+\.(?:svg|png|jpg|jpeg|gif|webp))', wt, re.I | re.M)
    return m.group(1).strip() if m else None


def file_urls(files, lang):
    """URL original de cada arquivo (no mesmo pedido, até 50)."""
    out = {}
    for i in range(0, len(files), 50):
        chunk = files[i:i + 50]
        d = sq.api({'action': 'query', 'prop': 'imageinfo', 'iiprop': 'url', 'iiurlwidth': 250, 'titles': '|'.join('File:' + f for f in chunk)}, lang)
        q = d.get('query', {})
        alias = {x['to']: x['from'] for x in q.get('normalized', [])}
        for p in q.get('pages', []):
            info = (p.get('imageinfo') or [{}])[0]
            if info.get('thumburl') or info.get('url'):  # miniatura padrão de 250 px (a Wikimedia limita o arquivo original)
                out[alias.get(p['title'], p['title'])[5:]] = info.get('thumburl') or info['url']
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cache = ROOT / 'data' / 'clubs' / '.online_crest_urls.json'
    found = json.loads(cache.read_text()) if cache.exists() else {}
    sources = json.loads(SOURCES.read_text())['crests'] if SOURCES.exists() else {}
    for lang in ([] if found else ('en', 'pt')):
        titles = {t: k for k, ts in sq.CLUBS.items() for t in ts if k not in found}
        texts = sq.batch_wikitext(list(titles), lang)
        files = {}
        for t, (real, wt) in texts.items():
            f = infobox_image(wt)
            if f and LOOKS_LIKE_CREST.search(f) and titles[t] not in files.values():
                files[f] = titles[t]
        urls = file_urls(list(files), lang)
        for f, k in files.items():
            if f in urls and k not in found:
                found[k] = urls[f]
        print(f'{lang}: {len(found)} escudos encontrados', flush=True)
    cache.write_text(json.dumps(found, indent=1))
    from PIL import Image
    for k, url in sorted(found.items()):
        if k in sources and (ROOT / 'public' / sources[k]['file']).exists():
            continue
        clean = url.split('?')[0]
        data = download(clean)
        if clean.lower().endswith('.svg') and not data[:4] == b'\x89PNG':
            (OUT / f'{k}.svg').write_bytes(data)
            name = f'{k}.svg'
        else:
            im = Image.open(io.BytesIO(data)).convert('RGBA')
            im.thumbnail((256, 256), Image.LANCZOS)
            im.save(OUT / f'{k}.webp', 'WEBP', quality=90, method=6)
            name = f'{k}.webp'
        sources[k] = {'file': f'crests/online/{name}', 'source': clean}
        print(f'{k}: {urllib.parse.unquote(clean.rsplit("/", 1)[-1])}', flush=True)
        SOURCES.write_text(json.dumps({'crests': sources, 'missing': []}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    missing = [k for k in sq.CLUBS if k not in found]
    SOURCES.write_text(json.dumps({'crests': sources, 'missing': missing}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'{len(sources)} escudos; sem escudo: {", ".join(missing) or "nenhum"}')


if __name__ == '__main__':
    main()
