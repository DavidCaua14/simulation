#!/usr/bin/env node
/**
 * Gera as cartas AUTOMATICAMENTE a partir dos atletas do jogo e da lista de lendas.
 *
 *   node scripts/build-auto-cards.mjs [--basica 300] [--destaque 200] [--epica 50]
 *
 * Gera supabase/cards/03_auto_cards.sql -> rode no Supabase (SQL Editor). Pode rodar de novo.
 *
 * - Épica    : os N atletas ATUAIS de maior overall (elencos 2026 importados em sim_players)
 * - Destaque : os N seguintes
 * - Básica   : N atletas do restante, distribuídos entre todos os clubes
 * - Lenda    : jogadores APOSENTADOS de data/cards/legends.json  [nome, posição, país, clube no jogo|null, clube (texto), overall]
 * O overall dos atuais é a nota estimada do jogo (sim_player_pos_ratings), o das lendas é uma estimativa de gameplay.
 * A arte da carta é desenhada pelo app (image = 'auto'): moldura da raridade, nota, posição, escudo e avatar ilustrado.
 * As cartas manuais antigas (supabase/cards/cards.json) são removidas — inclusive das coleções.
 */
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`)
  return i > 0 ? parseInt(process.argv[i + 1], 10) : def
}
const N = { epica: arg('epica', 50), destaque: arg('destaque', 200), basica: arg('basica', 300) }
const OLD = ['arrascaeta-78', 'arrascaeta-86', 'arrascaeta-92', 'arrascaeta-98', 'gabriel-86', 'juninho-96', 'ribamar-58', 'igor-bahia-51', 'flavio-caca-rato-51']

const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
const POS = new Set(['GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA'])

const legends = JSON.parse(await readFile(path.join(ROOT, 'data', 'cards', 'legends.json'), 'utf8'))
const ids = new Set()
const legendRows = legends.map(([name, pos, nat, club, clubName, ovr]) => {
  if (!POS.has(pos)) throw new Error(`Lenda ${name}: posição inválida ${pos}`)
  const id = `lenda-${slug(name)}`
  if (ids.has(id)) throw new Error(`Lenda repetida: ${name}`)
  ids.add(id)
  return `(${q(id)}, ${q(name)}, ${ovr}, ${q(pos)}, ${q(club)}, ${q(slug(name))}, ${q(JSON.stringify({ kind: 'lenda', nationality: nat, club_name: clubName, estimated: true }))}::jsonb)`
})

const sql = `-- =====================================================================
-- CARTAS AUTOMÁTICAS — gerado por scripts/build-auto-cards.mjs (não edite à mão)
-- Épica ${N.epica} · Destaque ${N.destaque} · Básica ${N.basica} (atletas atuais) · Lenda ${legends.length} (aposentados)
-- Rode no Supabase (SQL Editor) depois de supabase/manager (precisa de sim_players).
-- =====================================================================
begin;

-- 1) remove as cartas manuais antigas (e as cópias nas coleções)
delete from public.user_cards where card_id in (${OLD.map(q).join(', ')});
delete from public.cards where id in (${OLD.map(q).join(', ')});

-- 2) atletas atuais: épica = maiores overalls, destaque = os seguintes, básica = espalhadas entre os clubes
create temp table _pick on commit drop as
with base as (
  select p.id, p.short_name, p.full_name, p.position, p.club_id, p.nationality, p.shirt_number,
         round(r.eff)::int as ovr, c.name as club_name
    from public.sim_players p
    join public.sim_player_pos_ratings r on r.player_id = p.id and r.pos = p.position
    join public.sim_clubs c on c.id = p.club_id
   where p.active
), ranked as (
  select b.*, row_number() over (order by b.ovr desc, b.id) as rk from base b
), top as (
  select r.*, case when r.rk <= ${N.epica} then 'epica' else 'destaque' end as tier
    from ranked r where r.rk <= ${N.epica + N.destaque}
), rest as (
  select r.*, row_number() over (partition by r.club_id order by r.ovr desc, r.id) as club_rk
    from ranked r where r.rk > ${N.epica + N.destaque}
), basic as (
  select x.*, 'basica' as tier from (select * from rest order by club_rk, ovr desc, id limit ${N.basica}) x
)
select id, short_name, full_name, position, club_id, nationality, shirt_number, ovr, club_name, tier from top
union all
select id, short_name, full_name, position, club_id, nationality, shirt_number, ovr, club_name, tier from basic;

insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta)
select tier || '-' || id, short_name, tier, ovr, position, club_id, id, 'auto', 100, true,
       jsonb_build_object('kind', 'atual', 'full_name', full_name, 'nationality', nationality, 'number', shirt_number,
                          'club_name', club_name, 'estimated', true, 'season', 2026)
  from _pick
on conflict (id) do update set name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image, active = true, meta = excluded.meta;

-- cartas automáticas de atletas que saíram da seleção param de cair (quem já tem, continua tendo)
update public.cards set active = false
 where image = 'auto' and meta ->> 'kind' = 'atual' and id not in (select tier || '-' || id from _pick);

-- 3) lendas (aposentados)
insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta)
select v.id, v.name, 'lenda', v.ovr, v.pos, v.club, v.pkey, 'auto', 100, true, v.meta
  from (values
${legendRows.map((r) => '  ' + r).join(',\n')}
  ) as v(id, name, ovr, pos, club, pkey, meta)
on conflict (id) do update set name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image, active = true, meta = excluded.meta;

-- 4) caixa diária: todo dia, 1 caixa Destaque garantida (sem sorteio)
update public.box_sources set draws = 0, guaranteed = '{destaque}' where source = 'daily';

commit;

select tier, count(*) filter (where active) as ativas from public.cards group by tier order by tier;
`
await writeFile(path.join(ROOT, 'supabase', 'cards', '03_auto_cards.sql'), sql)
console.log(`✔ supabase/cards/03_auto_cards.sql  (épica ${N.epica} · destaque ${N.destaque} · básica ${N.basica} · lenda ${legends.length})`)
