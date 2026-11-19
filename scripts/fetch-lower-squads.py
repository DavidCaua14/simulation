#!/usr/bin/env python3
"""Baixa os elencos reais dos clubes das Séries C e D do modo online (Wikipédia, seção do elenco atual).

Uso: python3 scripts/fetch-lower-squads.py [chave ...]
Saída: data/squads-lower/<chave>.txt no formato dos elencos do modo Temporadas:
  # club / # source / # accessed / # as_of e linhas numero|posicao|nacionalidade|nome|observacoes
Nada é inventado: só entra o que a página lista. Clube sem elenco na página fica sem arquivo (o jogo usa cartas geradas).
"""
import json, re, sys, time, urllib.error, urllib.parse, urllib.request, datetime, pathlib

UA = 'FootballSimSquadImport/1.0 (squad research; low volume)'
OUT = pathlib.Path(__file__).resolve().parent.parent / 'data' / 'squads-lower'
CLUBS = {
 # Série D (participantes de 2026 com elenco na Wikipédia)
 'atletico-alagoinhas': ['Alagoinhas Atlético Clube'],
 'velo-clube': ['Associação Esportiva Velo Clube Rioclarense'],
 'noroeste': ['Esporte Clube Noroeste'],
 'agua-santa': ['Esporte Clube Água Santa'],
 'crac': ['Clube Recreativo e Atlético Catalano'],
 'democrata-gv': ['Esporte Clube Democrata'],
 'cianorte': ['Cianorte Futebol Clube'],
 'decisao': ['Decisão Goiana Futebol Clube'],
 'madureira': ['Madureira Esporte Clube'],
 'america-rj': ['America Football Club (Rio de Janeiro)'],
 'marica': ['Maricá Futebol Clube'],
 'sao-luiz': ['Esporte Clube São Luiz'],
 'marcilio-dias': ['Clube Náutico Marcílio Dias'],
 # Série C 2027
 'maringa': ['Maringá FC'], 'ferroviaria': ['Associação Ferroviária de Esportes'],
 'inter-limeira': ['Associação Atlética Internacional (Limeira)'], 'santa-cruz': ['Santa Cruz Futebol Clube'],
 'amazonas': ['Amazonas FC'], 'anapolis': ['Anápolis Futebol Clube'], 'barra': ['Barra Futebol Clube', 'Barra FC'],
 'botafogo-pb': ['Botafogo Futebol Clube (PB)'], 'brusque': ['Brusque Futebol Clube'],
 'caxias': ['Sociedade Esportiva e Recreativa Caxias do Sul'], 'figueirense': ['Figueirense FC'],
 'floresta': ['Floresta Esporte Clube'], 'guarani': ['Guarani FC'], 'ituano': ['Ituano FC'],
 'maranhao': ['Maranhão Atlético Clube'], 'paysandu': ['Paysandu Sport Club'], 'volta-redonda': ['Volta Redonda FC'],
 'ypiranga-rs': ['Ypiranga Futebol Clube'], 'uberlandia': ['Uberlândia Esporte Clube'],
 'asa': ['Agremiação Sportiva Arapiraquense'], 'abc': ['ABC Futebol Clube'], 'gama': ['Sociedade Esportiva do Gama'],
 'goiatuba': ['Goiatuba Esporte Clube'], 'nacional-am': ['Nacional Futebol Clube'],
 # Série D
 'itabaiana': ['Associação Olímpica de Itabaiana'], 'confianca': ['Associação Desportiva Confiança'],
 'sergipe': ['Club Sportivo Sergipe'], 'treze': ['Treze Futebol Clube'], 'campinense': ['Campinense Clube'],
 'america-rn': ['América Futebol Clube (RN)'], 'ferroviario': ['Ferroviário Atlético Clube (CE)', 'Ferroviário Atlético Clube'],

 'moto-club': ['Moto Club de São Luís'],
 'fluminense-pi': ['Fluminense Esporte Clube (PI)', 'Fluminense Esporte Clube'], 'altos': ['Associação Atlética de Altos'],
 'juazeirense': ['Sociedade Desportiva Juazeirense'], 'jacuipense': ['Esporte Clube Jacuipense'],
 'brasiliense': ['Brasiliense Futebol Clube'],
 'portuguesa': ['Associação Portuguesa de Desportos'],
 'xv-piracicaba': ['Esporte Clube XV de Novembro (Piracicaba)'],
 'joinville': ['Joinville Esporte Clube'], 'sao-jose-rs': ['Esporte Clube São José'],


}

def api(params, lang='en'):
    """Chamada à API; respeita o limite de requisições (HTTP 429 + Retry-After). Falha de rede vira exceção."""
    url = f'https://{lang}.wikipedia.org/w/api.php?' + urllib.parse.urlencode({**params, 'format': 'json', 'formatversion': 2})
    for attempt in range(8):
        try:
            time.sleep(2)
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            wait = int(e.headers.get('Retry-After') or 20) + 3
            print(f'  limite da Wikipédia: esperando {wait} s', flush=True)
            time.sleep(wait)
        except Exception:
            time.sleep(5 * (attempt + 1))
    raise RuntimeError('Wikipédia indisponível')

def clean(s):
    s = re.sub(r'<ref[^>]*/>|<ref[^>]*>.*?</ref>', '', s or '', flags=re.S)
    s = re.sub(r'\{\{(?:sortname|sort name)\|([^|}]*)\|([^|}]*)[^}]*\}\}', r'\1 \2', s, flags=re.I)
    s = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', s)
    s = re.sub(r"'{2,}|\{\{[^}]*\}\}", '', s)
    return re.sub(r'\s+', ' ', s).strip()

def players_from(wt):
    out = []
    for m in re.finditer(r'\{\{\s*(?:Fs player|football squad player)\s*\|(.*?)\}\}(?=\s*(?:\{\{|$|\n))', wt, flags=re.I | re.S):
        body = m.group(1)
        # parâmetros nomeados no nível de cima (ignora | dentro de [[ ]])
        parts, depth, cur = [], 0, ''
        for ch in body:
            if ch in '[{': depth += 1
            if ch in ']}': depth -= 1
            if ch == '|' and depth == 0: parts.append(cur); cur = ''
            else: cur += ch
        parts.append(cur)
        kv = {}
        for p in parts:
            if '=' in p:
                k, v = p.split('=', 1); kv[k.strip().lower()] = v.strip()
        name = clean(kv.get('name', ''))
        if not name: continue
        out.append({'no': re.sub(r'\D', '', kv.get('no', '')) or '-', 'pos': kv.get('pos', '').upper()[:2], 'nat': kv.get('nat', 'BRA').upper()[:3] or 'BRA',
                    'name': name, 'other': clean(kv.get('other', ''))})
    return out

def squad(title):
    sec = api({'action': 'parse', 'page': title, 'prop': 'sections', 'redirects': 1}).get('parse')
    if not sec: return None, None
    real = sec.get('title', title)
    pri = lambda s: 0 if re.search(r'first.team|current', s['line'], re.I) else 1 if re.search(r'squad|elenco|plantel', s['line'], re.I) else 2
    cands = sorted([s for s in sec['sections'] if re.search(r'squad|current|first.team|players|elenco|plantel', s['line'], re.I)
                    and not re.search(r'loan|youth|under|reserve|women|former|notable|retired|record', s['line'], re.I)], key=pri)
    for s in cands:
        wt = api({'action': 'parse', 'page': real, 'prop': 'wikitext', 'section': s['index'], 'redirects': 1}).get('parse', {}).get('wikitext', '')
        # para nos subtítulos de emprestados, base, feminino...
        cut = re.search(r'^=+\s*[^=\n]*(loan|youth|under|reserve|women|academy|B team|II)[^=\n]*=+\s*$', wt, re.I | re.M)
        ps = players_from(wt[:cut.start()] if cut else wt)
        if len(ps) >= 11:
            upd = re.search(r'\{\{\s*updated\s*\|([^}|]*)', wt, re.I)
            return real, (ps, upd.group(1).strip() if upd else 'unknown')
        time.sleep(.6)
    return real, None

def batch_wikitext(titles, lang='en'):
    """Texto de até 50 páginas por chamada (segue redirecionamentos). Devolve {título pedido: (título real, texto)}."""
    out = {}
    for i in range(0, len(titles), 50):
        chunk = titles[i:i + 50]
        d = api({'action': 'query', 'prop': 'revisions', 'rvprop': 'content', 'rvslots': 'main', 'titles': '|'.join(chunk), 'redirects': 1}, lang)
        q = d.get('query', {})
        alias = {x['from']: x['to'] for x in q.get('normalized', []) + q.get('redirects', [])}
        pages = {p['title']: p for p in q.get('pages', [])}
        for t in chunk:
            real = t
            while real in alias: real = alias[real]
            p = pages.get(real)
            if p and p.get('revisions'):
                out[t] = (real, p['revisions'][0]['slots']['main']['content'])
    return out


def squad_from_text(wt):
    """Seção do elenco atual dentro do texto da página inteira (para nos emprestados, base, feminino...)."""
    heads = list(re.finditer(r'^(=+)\s*([^=\n]+?)\s*\1\s*$', wt, re.M))
    best = None
    for k, h in enumerate(heads):
        line = h.group(2)
        if not re.search(r'squad|current|first.team|players|elenco|plantel', line, re.I) or re.search(r'loan|youth|under|reserve|women|former|notable|retired|record', line, re.I):
            continue
        end = next((x.start() for x in heads[k + 1:] if len(x.group(1)) <= len(h.group(1)) or re.search(r'loan|youth|under|reserve|women|academy|B team', x.group(2), re.I)), len(wt))
        ps = players_from(wt[h.start():end])
        if len(ps) >= 11:
            upd = re.search(r'\{\{\s*updated\s*\|([^}|]*)', wt[h.start():end], re.I)
            pri = 0 if re.search(r'first.team|current', line, re.I) else 1
            if best is None or pri < best[0]:
                best = (pri, ps, upd.group(1).strip() if upd else 'unknown')
    return (best[1], best[2]) if best else None


def main():
    keys = sys.argv[1:] or list(CLUBS)
    today = datetime.date.today().isoformat()
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    for key in keys:
        got = None
        for title in CLUBS[key]:
            real, got = squad(title)
            time.sleep(.8)
            if got: break
        if not got:
            report.append(f'{key}: sem elenco na Wikipédia'); print(report[-1], flush=True); continue
        ps, asof = got
        src = 'https://en.wikipedia.org/wiki/' + urllib.parse.quote(real.replace(' ', '_'))
        lines = [f'# club: {key}', f'# source: {src}', f'# accessed: {today}', f'# as_of: {asof}']
        lines += [f"{p['no']}|{p['pos'] or 'MF'}|{p['nat']}|{p['name']}|{p['other']}" for p in ps]
        (OUT / f'{key}.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        report.append(f'{key}: {len(ps)} jogadores ({asof})'); print(report[-1], flush=True)
    return report

if __name__ == '__main__':
    main()
