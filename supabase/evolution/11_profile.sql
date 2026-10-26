-- =====================================================================
-- EVOLUÇÃO 11 — PERFIL DO JOGADOR: identidade no servidor, carta em destaque, insígnias e cosméticos
--
-- * player_profiles ... avatar, carta em destaque, cosméticos equipados e privacidade (o que OUTROS veem).
--                       Antes ficava só no navegador (localStorage); o app migra sozinho na primeira visita.
-- * Carta em destaque . só carta que o jogador TEM (qty > 0). Se ela for vendida, anunciada ou descartada até zerar,
--                       um gatilho tira o destaque na hora.
-- * Insígnias ......... concedidas SÓ pelo servidor a partir de dados verificáveis (títulos, nível, partidas, sequência
--                       de vitórias, temporadas, coleção, mercado, temporada do ano). O app não grava insígnias.
-- * Cosméticos ........ molduras, fundos, efeitos, emblemas e temas; comprados com diamantes (livro + idempotência),
--                       equipar/desequipar. Puramente visuais: não mexem em atributos de atletas nem de cartas.
-- Rode depois de evolution/10. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) COSMÉTICOS
-- ---------------------------------------------------------------------
create table if not exists public.cosmetics (
  id             text primary key,
  kind           text not null check (kind in ('frame', 'background', 'effect', 'emblem', 'theme')),
  label          text not null,
  description    text not null,
  rarity         text not null default 'comum' check (rarity in ('comum', 'raro', 'epico', 'lendario')),
  price_diamonds int  not null default 0 check (price_diamonds >= 0),   -- 0 = grátis para todos
  style          jsonb not null default '{}'::jsonb,                      -- só aparência (cores/gradientes/animação)
  sort_order     int  not null default 0,
  active         boolean not null default true
);

insert into public.cosmetics (id, kind, label, description, rarity, price_diamonds, style, sort_order) values
  -- fundos grátis (os 8 banners que já existiam no perfil)
  ('gramado',  'background', 'Gramado',        'O verde do campo.',                 'comum', 0, '{"css":"linear-gradient(135deg,#0b4a2a 0%,#1f9d55 100%)"}', 1),
  ('noite',    'background', 'Noite de jogo',  'Azul de jogo noturno.',             'comum', 0, '{"css":"linear-gradient(135deg,#0a1633 0%,#2447a8 100%)"}', 2),
  ('ouro',     'background', 'Ouro',           'Dourado clássico.',                 'comum', 0, '{"css":"linear-gradient(135deg,#6b4a06 0%,#e0a82e 100%)"}', 3),
  ('rubro',    'background', 'Rubro',          'Vermelho de clássico.',             'comum', 0, '{"css":"linear-gradient(135deg,#4d0a12 0%,#d6283a 100%)"}', 4),
  ('elite',    'background', 'Elite',          'Roxo de noite de gala.',            'comum', 0, '{"css":"linear-gradient(135deg,#2a1055 0%,#7a3df0 100%)"}', 5),
  ('grafite',  'background', 'Grafite',        'Discreto e elegante.',              'comum', 0, '{"css":"linear-gradient(135deg,#14181f 0%,#454f60 100%)"}', 6),
  ('laranja',  'background', 'Arquibancada',   'Calor da torcida.',                 'comum', 0, '{"css":"linear-gradient(135deg,#6b2a05 0%,#f08a24 100%)"}', 7),
  ('ciano',    'background', 'Mar aberto',     'Azul do litoral.',                  'comum', 0, '{"css":"linear-gradient(135deg,#053a4a 0%,#12b4cf 100%)"}', 8),
  -- fundos premium
  ('refletores', 'background', 'Refletores', 'Fachos de luz de estádio cortando a noite.', 'raro', 25,
   '{"css":"radial-gradient(60% 90% at 15% 0%,rgba(255,255,255,.35),transparent 60%),radial-gradient(60% 90% at 85% 0%,rgba(255,255,255,.3),transparent 60%),linear-gradient(180deg,#0b1020 0%,#14315e 100%)"}', 20),
  ('aurora', 'background', 'Aurora', 'Céu de inverno em verde e violeta.', 'epico', 30,
   '{"css":"radial-gradient(80% 120% at 20% 100%,rgba(34,211,153,.55),transparent 60%),radial-gradient(70% 120% at 85% 0%,rgba(167,92,255,.55),transparent 60%),linear-gradient(135deg,#071426,#0d1f3a)"}', 21),
  ('carbono', 'background', 'Carbono', 'Trama de fibra de carbono.', 'raro', 20,
   '{"css":"repeating-linear-gradient(45deg,#1b1f27 0 6px,#232833 6px 12px),linear-gradient(#1b1f27,#1b1f27)"}', 22),
  ('confete', 'background', 'Festa do título', 'Confete de campeão.', 'lendario', 35,
   '{"css":"radial-gradient(circle at 12% 30%,#fbbf24 0 3px,transparent 4px),radial-gradient(circle at 70% 20%,#38bdf8 0 3px,transparent 4px),radial-gradient(circle at 40% 70%,#f472b6 0 3px,transparent 4px),radial-gradient(circle at 85% 65%,#34d399 0 3px,transparent 4px),linear-gradient(135deg,#3a0d5c,#d6283a)","size":"90px 90px, 110px 110px, 80px 80px, 120px 120px, 100% 100%"}', 23),
  -- molduras do avatar
  ('aro_prata',   'frame', 'Aro de prata',    'Moldura metálica discreta.',              'comum',     10, '{"ring":"linear-gradient(135deg,#f1f5f9,#94a3b8,#e2e8f0)"}', 1),
  ('aro_ouro',    'frame', 'Aro de ouro',     'Para quem já levantou taça.',             'raro',      20, '{"ring":"linear-gradient(135deg,#fde68a,#d97706,#fbbf24)"}', 2),
  ('aro_neon',    'frame', 'Neon',            'Brilho ciano de estádio moderno.',        'raro',      25, '{"ring":"linear-gradient(135deg,#22d3ee,#0ea5e9)","glow":"#22d3ee"}', 3),
  ('aro_chamas',  'frame', 'Chamas',          'Moldura em brasa, animada.',              'epico',     40, '{"ring":"conic-gradient(#f97316,#ef4444,#fbbf24,#f97316)","spin":true,"glow":"#f97316"}', 4),
  ('aro_galaxia', 'frame', 'Galáxia',         'Anel cósmico girando devagar.',           'lendario',  50, '{"ring":"conic-gradient(#a855f7,#22d3ee,#f472b6,#a855f7)","spin":true,"glow":"#a855f7"}', 5),
  -- efeitos visuais
  ('pulso',         'effect', 'Pulso',          'O avatar pulsa como um coração em dia de final.', 'raro',     20, '{"type":"pulse","color":"#38bdf8"}', 1),
  ('faiscas',       'effect', 'Faíscas',        'Faíscas em volta do avatar.',                     'epico',    30, '{"type":"sparks","color":"#fde68a"}', 2),
  ('chuva_dourada', 'effect', 'Chuva dourada',  'Pontos dourados caindo no fundo do perfil.',      'lendario', 45, '{"type":"rain","color":"#fbbf24"}', 3),
  -- emblemas decorativos (ao lado do nome)
  ('emb_raio',    'emblem', 'Raio',    'Velocidade.',      'comum', 10, '{"icon":"zap","color":"#facc15"}', 1),
  ('emb_estrela', 'emblem', 'Estrela', 'Brilho próprio.',  'comum', 10, '{"icon":"star","color":"#fbbf24"}', 2),
  ('emb_escudo',  'emblem', 'Escudo',  'Defesa sólida.',   'comum', 10, '{"icon":"shield","color":"#38bdf8"}', 3),
  ('emb_chama',   'emblem', 'Chama',   'Sangue quente.',   'raro',  15, '{"icon":"flame","color":"#f97316"}', 4),
  ('emb_coroa',   'emblem', 'Coroa',   'Rei do campo.',    'raro',  15, '{"icon":"crown","color":"#fbbf24"}', 5),
  -- temas (cor de destaque da apresentação do perfil)
  ('tema_esmeralda', 'theme', 'Esmeralda', 'Destaques em verde.',    'comum', 15, '{"accent":"#10b981","accent2":"#34d399"}', 1),
  ('tema_rubi',      'theme', 'Rubi',      'Destaques em vermelho.', 'comum', 15, '{"accent":"#e11d48","accent2":"#fb7185"}', 2),
  ('tema_safira',    'theme', 'Safira',    'Destaques em azul.',     'comum', 15, '{"accent":"#2563eb","accent2":"#60a5fa"}', 3),
  ('tema_ouro',      'theme', 'Ouro',      'Destaques dourados.',    'raro',  25, '{"accent":"#d97706","accent2":"#fbbf24"}', 4)
on conflict (id) do nothing;

create table if not exists public.player_cosmetics (
  career_id   uuid not null references public.careers (id) on delete cascade,
  cosmetic_id text not null references public.cosmetics (id),
  source      text not null default 'shop' check (source in ('shop', 'reward', 'event')),
  request_id  uuid,
  acquired_at timestamptz not null default now(),
  primary key (career_id, cosmetic_id)
);

-- ---------------------------------------------------------------------
-- B) PERFIL
-- ---------------------------------------------------------------------
create table if not exists public.player_profiles (
  career_id     uuid primary key references public.careers (id) on delete cascade,
  avatar_data   text check (avatar_data is null or avatar_data ~ '^preset:[a-z0-9_-]{1,20}$'
                             or (avatar_data like 'data:image/jpeg;base64,%' and length(avatar_data) <= 90000)),   -- foto enviada OU foto pronta do jogo
  featured_card text references public.cards (id),
  background_id text references public.cosmetics (id),
  frame_id      text references public.cosmetics (id),
  effect_id     text references public.cosmetics (id),
  emblem_id     text references public.cosmetics (id),
  theme_id      text references public.cosmetics (id),
  privacy       jsonb not null default '{"show_career": true, "show_stats": true, "show_collection": true, "show_titles": true}'::jsonb,
  migrated_local boolean not null default false,       -- preferências antigas do navegador já foram trazidas
  updated_at    timestamptz not null default now()
);

-- carta em destaque some se o jogador deixar de ter a carta (venda, anúncio, descarte)
create or replace function public.profile_featured_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update public.player_profiles set featured_card = null, updated_at = now()
     where career_id = old.career_id and featured_card = old.card_id;
    return old;
  end if;
  if new.qty <= 0 then
    update public.player_profiles set featured_card = null, updated_at = now()
     where career_id = new.career_id and featured_card = new.card_id;
  end if;
  return new;
end;
$$;
drop trigger if exists profile_featured_guard on public.user_cards;
create trigger profile_featured_guard after update of qty or delete on public.user_cards
  for each row execute function public.profile_featured_guard();

-- ---------------------------------------------------------------------
-- C) INSÍGNIAS
-- ---------------------------------------------------------------------
create table if not exists public.badges (
  id          text primary key,
  label       text not null,
  description text not null,          -- a regra, escrita para o jogador ("Conquiste 3 títulos")
  icon        text not null default 'award',
  tier        text not null default 'bronze' check (tier in ('bronze', 'prata', 'ouro')),
  kind        text not null,          -- titles | level | coach_matches | win_streak | seasons_done | collection | own_epica | market_sales | season_year | event
  threshold   numeric not null,
  sort_order  int not null default 0,
  active      boolean not null default true
);
insert into public.badges (id, label, description, icon, tier, kind, threshold, sort_order) values
  ('titulo_1',     'Primeira taça',        'Conquiste um título como treinador.',                    'trophy',  'bronze', 'titles',        1,   1),
  ('titulo_3',     'Colecionador de taças','Conquiste 3 títulos como treinador.',                    'trophy',  'prata',  'titles',        3,   2),
  ('titulo_10',    'Dinastia',             'Conquiste 10 títulos como treinador.',                   'trophy',  'ouro',   'titles',       10,   3),
  ('sequencia_5',  'Embalado',             'Vença 5 partidas seguidas.',                             'flame',   'bronze', 'win_streak',    5,  10),
  ('sequencia_10', 'Imparável',            'Vença 10 partidas seguidas.',                            'flame',   'ouro',   'win_streak',   10,  11),
  ('jogos_50',     'Rodado',               'Comande o time em 50 partidas.',                         'activity','bronze', 'coach_matches',50,  20),
  ('jogos_200',    'Maratonista',          'Comande o time em 200 partidas.',                        'activity','prata',  'coach_matches',200, 21),
  ('temporada_1',  'Temporada completa',   'Termine uma temporada inteira.',                         'calendar','bronze', 'seasons_done',  1,  30),
  ('temporada_5',  'Longevidade',          'Termine 5 temporadas.',                                  'calendar','prata',  'seasons_done',  5,  31),
  ('nivel_5',      'Em ascensão',          'Chegue ao nível 5.',                                     'star',    'bronze', 'level',         5,  40),
  ('nivel_10',     'Veterano',             'Chegue ao nível 10.',                                    'star',    'prata',  'level',        10,  41),
  ('nivel_25',     'Lenda viva',           'Chegue ao nível 25.',                                    'star',    'ouro',   'level',        25,  42),
  ('colecao_50',   'Colecionador',         'Tenha 50 cartas diferentes na coleção.',                 'layers',  'bronze', 'collection',   50,  50),
  ('colecao_150',  'Álbum recheado',       'Tenha 150 cartas diferentes na coleção.',                'layers',  'prata',  'collection',  150,  51),
  ('colecao_400',  'Enciclopédia',         'Tenha 400 cartas diferentes na coleção.',                'layers',  'ouro',   'collection',  400,  52),
  ('epica_1',      'Toque épico',          'Consiga uma carta Épica.',                               'gem',     'prata',  'own_epica',     1,  53),
  ('mercado_1',    'Negociante',           'Venda uma carta no mercado.',                            'store',   'bronze', 'market_sales',  1,  60),
  ('sazonal_2026', 'Temporada 2026',       'Termine uma temporada de 2026 (Brasil 2026 ou Inglaterra 2026/27).', 'calendar', 'prata', 'season_year', 2026, 70)
on conflict (id) do nothing;

create table if not exists public.player_badges (
  career_id  uuid not null references public.careers (id) on delete cascade,
  badge_id   text not null references public.badges (id),
  value      numeric,                    -- o número que liberou (para conferência)
  awarded_at timestamptz not null default now(),
  primary key (career_id, badge_id)
);

-- valor atual de cada tipo de regra (tudo calculado de tabelas que só o servidor escreve)
create or replace function public.badge_metric(p_career uuid, p_kind text, p_threshold numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v numeric;
begin
  case p_kind
    when 'titles' then
      select coalesce(sum(jsonb_array_length(coalesce(titles, '[]'::jsonb))), 0) into v from public.mgr_spells where career_id = p_career;
    when 'level' then
      select level into v from public.careers where id = p_career;
    when 'coach_matches' then
      select matches into v from public.mgr_coach where career_id = p_career;
    when 'seasons_done' then
      select seasons into v from public.mgr_coach where career_id = p_career;
    when 'collection' then
      select count(*) into v from public.user_cards where career_id = p_career;     -- cartas diferentes já conquistadas
    when 'own_epica' then
      select count(*) into v from public.user_cards uc join public.cards c on c.id = uc.card_id where uc.career_id = p_career and c.tier = 'epica';
    when 'market_sales' then
      select count(*) into v from public.market_listings where seller_career = p_career and status = 'sold';
    when 'season_year' then
      select case when exists (select 1 from public.career_seasons where career_id = p_career and mode = 'coach' and status = 'finished'
                                and year = p_threshold::int) then p_threshold else 0 end into v;
    when 'win_streak' then
      -- maior sequência de vitórias nas partidas do treinador (ilhas de vitórias seguidas)
      select coalesce(max(n), 0) into v from (
        select count(*) as n from (
          select w, sum(case when w then 0 else 1 end) over (order by played_at, id) as grp
            from (select f.id, f.played_at,
                         case when f.home_club = f.coach_club then f.home_goals > f.away_goals else f.away_goals > f.home_goals end as w
                    from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
                   where s.career_id = p_career and f.player_match and f.status = 'played' and f.coach_club is not null) x
        ) y where w group by grp) z;
    else v := 0;   -- tipos de outras etapas (ex.: 'event') são avaliados por elas
  end case;
  return coalesce(v, 0);
end;
$$;

-- concede as insígnias que a carreira já cumpriu (só insere; nunca remove). Devolve as novas.
create or replace function public.badges_refresh(p_career uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.badges; v numeric; v_new jsonb := '[]';
begin
  for b in select * from public.badges where active
             and id not in (select badge_id from public.player_badges where career_id = p_career) order by sort_order loop
    v := public.badge_metric(p_career, b.kind, b.threshold);
    if v >= b.threshold then
      insert into public.player_badges (career_id, badge_id, value) values (p_career, b.id, v) on conflict do nothing;
      v_new := v_new || jsonb_build_object('id', b.id, 'label', b.label, 'tier', b.tier);
    end if;
  end loop;
  return v_new;
end;
$$;

alter table public.cosmetics        enable row level security;
alter table public.player_cosmetics enable row level security;
alter table public.player_profiles  enable row level security;
alter table public.badges           enable row level security;
alter table public.player_badges    enable row level security;
revoke all on public.cosmetics, public.player_cosmetics, public.player_profiles, public.badges, public.player_badges from anon, authenticated;
grant select on public.cosmetics, public.badges to authenticated;
drop policy if exists "read_cosmetics" on public.cosmetics;
create policy "read_cosmetics" on public.cosmetics for select to authenticated using (active);
drop policy if exists "read_badges" on public.badges;
create policy "read_badges" on public.badges for select to authenticated using (active);
-- perfis, cosméticos e insígnias de jogadores: só pelas funções abaixo (que aplicam a privacidade)

-- ---------------------------------------------------------------------
-- D) MONTAGEM DO PERFIL (o mesmo formato para o próprio jogador e para quem visita)
-- ---------------------------------------------------------------------
create or replace function public.profile_ensure(p_career uuid)
returns public.player_profiles language plpgsql security definer set search_path = public as $$
declare v public.player_profiles;
begin
  insert into public.player_profiles (career_id, background_id) values (p_career, 'gramado') on conflict do nothing;
  select * into v from public.player_profiles where career_id = p_career;
  return v;
end;
$$;

create or replace function public.cosmetic_json(p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', c.id, 'kind', c.kind, 'label', c.label, 'rarity', c.rarity, 'style', c.style)
    from public.cosmetics c where c.id = p_id;
$$;

-- p_full = true: o próprio jogador (vê tudo + configurações). false: visitante (respeita a privacidade).
create or replace function public.profile_build(p_career uuid, p_full boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_c   public.careers;
  v_p   public.player_profiles;
  v_m   public.mgr_coach;
  v_s   public.career_seasons;
  priv  jsonb;
  v_card public.cards;
begin
  select * into v_c from public.careers where id = p_career;
  select * into v_p from public.player_profiles where career_id = p_career;
  select * into v_m from public.mgr_coach where career_id = p_career;
  select * into v_s from public.career_seasons where career_id = p_career and mode = 'coach' order by season_no desc limit 1;
  priv := coalesce(v_p.privacy, '{}'::jsonb);
  -- carta em destaque só aparece se o jogador ainda a tem (defesa extra além do gatilho)
  select c.* into v_card from public.cards c join public.user_cards uc on uc.card_id = c.id and uc.career_id = p_career and uc.qty > 0
   where c.id = v_p.featured_card;

  return jsonb_strip_nulls(jsonb_build_object(
    'career_id', case when p_full then v_c.id end,
    'nickname', v_c.nickname, 'country', v_c.country, 'photo_id', v_c.photo_id, 'avatar', v_p.avatar_data,
    'level', v_c.level, 'xp', v_c.xp, 'joined_at', v_c.created_at,
    'club_id', case when p_full or coalesce((priv ->> 'show_career')::boolean, true) then coalesce(v_m.club_id, v_c.club_id) end,
    'coach_status', case when p_full or coalesce((priv ->> 'show_career')::boolean, true) then v_m.status end,
    'region', case when p_full or coalesce((priv ->> 'show_career')::boolean, true) then v_s.region end,
    'featured_card', case when v_card.id is not null then jsonb_build_object('id', v_card.id, 'name', v_card.name, 'tier', v_card.tier,
        'overall', v_card.overall, 'position', v_card.position, 'club_id', v_card.club_id, 'player_key', v_card.player_key,
        'image', v_card.image, 'meta', v_card.meta) end,
    'equipped', jsonb_strip_nulls(jsonb_build_object(
        'background', public.cosmetic_json(v_p.background_id), 'frame', public.cosmetic_json(v_p.frame_id),
        'effect', public.cosmetic_json(v_p.effect_id), 'emblem', public.cosmetic_json(v_p.emblem_id), 'theme', public.cosmetic_json(v_p.theme_id))),
    'badges', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'label', b.label, 'description', b.description, 'icon', b.icon,
                 'tier', b.tier, 'earned', pb.awarded_at is not null, 'awarded_at', pb.awarded_at) order by (pb.awarded_at is null), b.sort_order), '[]'::jsonb)
                 from public.badges b left join public.player_badges pb on pb.badge_id = b.id and pb.career_id = p_career
                where b.active and (p_full or pb.awarded_at is not null)),
    'titles', case when p_full or coalesce((priv ->> 'show_titles')::boolean, true) then
        (select coalesce(jsonb_agg(jsonb_build_object('competition', t ->> 'competition', 'year', (t ->> 'year')::int, 'club_id', sp.club_id)
                                   order by (t ->> 'year')::int desc), '[]'::jsonb)
           from public.mgr_spells sp cross join lateral jsonb_array_elements(coalesce(sp.titles, '[]'::jsonb)) t
          where sp.career_id = p_career) end,
    'stats', case when (p_full or coalesce((priv ->> 'show_stats')::boolean, true)) and v_m.career_id is not null then
        jsonb_build_object('matches', v_m.matches, 'wins', v_m.wins, 'draws', v_m.draws, 'losses', v_m.losses, 'gf', v_m.gf, 'ga', v_m.ga,
                           'titles', v_m.titles, 'seasons', v_m.seasons, 'reputation', round(v_m.reputation)) end,
    'collection', case when p_full or coalesce((priv ->> 'show_collection')::boolean, true) then
        jsonb_build_object(
          'total', (select count(*) from public.cards where active),
          'owned', (select count(*) from public.user_cards where career_id = p_career and qty > 0),
          'by_tier', (select coalesce(jsonb_object_agg(x.tier, x.n), '{}'::jsonb)
                        from (select c.tier, count(*) as n from public.user_cards u join public.cards c on c.id = u.card_id
                               where u.career_id = p_career and u.qty > 0 group by c.tier) x)) end,
    'privacy', case when p_full then priv end));
end;
$$;

-- ---------------------------------------------------------------------
-- E) FUNÇÕES DO APP
-- ---------------------------------------------------------------------
-- Meu perfil (concede as insígnias já cumpridas antes de montar)
create or replace function public.profile_me()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_new jsonb;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  perform public.profile_ensure(v_c.id);
  v_new := public.badges_refresh(v_c.id);
  return public.profile_build(v_c.id, true) || jsonb_build_object('new_badges', v_new,
    'migrated_local', (select migrated_local from public.player_profiles where career_id = v_c.id));
end;
$$;

-- Avatar: foto enviada (recortada 256×256 em JPEG pelo app), 'preset:<id>' (foto pronta do jogo) ou null (foto da criação)
create or replace function public.profile_set_avatar(p_data text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  if p_data is not null and p_data !~ '^preset:[a-z0-9_-]{1,20}$' and (p_data not like 'data:image/jpeg;base64,%' or length(p_data) > 90000) then
    raise exception 'Imagem inválida ou grande demais (use uma foto comum; ela é reduzida para 256×256).';
  end if;
  perform public.profile_ensure(v_c.id);
  update public.player_profiles set avatar_data = p_data, updated_at = now() where career_id = v_c.id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Carta em destaque: só uma carta que o jogador TEM agora (null = tirar o destaque)
create or replace function public.profile_set_featured(p_card text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  if p_card is not null and not exists (select 1 from public.user_cards where career_id = v_c.id and card_id = p_card and qty > 0) then
    raise exception 'Você não tem esta carta (ou ela está à venda no mercado).';
  end if;
  perform public.profile_ensure(v_c.id);
  update public.player_profiles set featured_card = p_card, updated_at = now() where career_id = v_c.id;
  return jsonb_build_object('ok', true, 'featured_card', p_card);
end;
$$;

-- Privacidade: o que OUTROS jogadores veem (avatar, nome, nível, insígnias e carta em destaque são sempre públicos)
create or replace function public.profile_set_privacy(p_privacy jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v jsonb := '{}'; k text;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  foreach k in array array['show_career', 'show_stats', 'show_collection', 'show_titles'] loop
    if p_privacy ? k then
      if jsonb_typeof(p_privacy -> k) <> 'boolean' then raise exception 'Valor inválido em %.', k; end if;
      v := v || jsonb_build_object(k, p_privacy -> k);
    end if;
  end loop;
  perform public.profile_ensure(v_c.id);
  update public.player_profiles set privacy = privacy || v, updated_at = now() where career_id = v_c.id;
  return jsonb_build_object('ok', true, 'privacy', (select privacy from public.player_profiles where career_id = v_c.id));
end;
$$;

-- Migração única das preferências que ficavam no navegador (foto enviada e banner grátis)
create or replace function public.profile_migrate_local(p_avatar text, p_background text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_p public.player_profiles;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  v_p := public.profile_ensure(v_c.id);
  if v_p.migrated_local then return jsonb_build_object('ok', true, 'skipped', true); end if;
  update public.player_profiles
     set avatar_data = case when avatar_data is null and p_avatar like 'data:image/jpeg;base64,%' and length(p_avatar) <= 90000 then p_avatar else avatar_data end,
         background_id = case when exists (select 1 from public.cosmetics where id = p_background and kind = 'background' and price_diamonds = 0)
                              then p_background else background_id end,
         migrated_local = true, updated_at = now()
   where career_id = v_c.id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Catálogo de cosméticos (com "já é seu" e "equipado")
create or replace function public.cosmetics_catalog()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_p public.player_profiles;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  v_p := public.profile_ensure(v_c.id);
  return jsonb_build_object(
    'diamonds', v_c.diamonds,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'label', c.label, 'description', c.description, 'rarity', c.rarity,
               'price', c.price_diamonds, 'style', c.style,
               'owned', c.price_diamonds = 0 or pc.cosmetic_id is not null,
               'equipped', c.id in (v_p.background_id, v_p.frame_id, v_p.effect_id, v_p.emblem_id, v_p.theme_id))
             order by c.kind, c.sort_order)
        from public.cosmetics c left join public.player_cosmetics pc on pc.cosmetic_id = c.id and pc.career_id = v_c.id
       where c.active), '[]'::jsonb));
end;
$$;

create or replace function public.cosmetic_buy(p_cosmetic text, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_prev jsonb; v_cos public.cosmetics; v_bal int;
begin
  v_c := public.sim_lock_career();
  v_prev := public.econ_request_get(v_c.id, p_request, 'cosmetic');
  if v_prev is not null then return v_prev; end if;
  select * into v_cos from public.cosmetics where id = p_cosmetic and active;
  if not found then raise exception 'Item não encontrado.'; end if;
  if v_cos.price_diamonds = 0 then raise exception 'Este item é grátis: é só equipar.'; end if;
  if exists (select 1 from public.player_cosmetics where career_id = v_c.id and cosmetic_id = p_cosmetic) then
    raise exception 'Você já tem este item.';
  end if;
  v_bal := public.econ_apply(v_c.id, 'diamonds', -v_cos.price_diamonds, 'cosmetic', p_cosmetic);
  insert into public.player_cosmetics (career_id, cosmetic_id, source, request_id) values (v_c.id, p_cosmetic, 'shop', p_request);
  return public.econ_request_save(v_c.id, p_request, 'cosmetic', jsonb_build_object(
    'ok', true, 'cosmetic', public.cosmetic_json(p_cosmetic), 'price', v_cos.price_diamonds, 'diamonds', v_bal));
end;
$$;

-- Equipar (p_cosmetic) ou desequipar (p_cosmetic = null) um tipo de item
create or replace function public.cosmetic_equip(p_kind text, p_cosmetic text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_cos public.cosmetics;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  if p_kind not in ('frame', 'background', 'effect', 'emblem', 'theme') then raise exception 'Tipo de item inválido.'; end if;
  if p_cosmetic is not null then
    select * into v_cos from public.cosmetics where id = p_cosmetic and active;
    if not found or v_cos.kind <> p_kind then raise exception 'Item inválido para este espaço.'; end if;
    if v_cos.price_diamonds > 0 and not exists (select 1 from public.player_cosmetics where career_id = v_c.id and cosmetic_id = p_cosmetic) then
      raise exception 'Você ainda não tem este item. Compre na Loja → Visual.';
    end if;
  elsif p_kind = 'background' then
    p_cosmetic := 'gramado';     -- sempre há um fundo (o padrão)
  end if;
  perform public.profile_ensure(v_c.id);
  execute format('update public.player_profiles set %I = $1, updated_at = now() where career_id = $2', p_kind || '_id') using p_cosmetic, v_c.id;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'equipped', p_cosmetic);
end;
$$;

-- ---------------------------------------------------------------------
-- F) PERMISSÕES
-- ---------------------------------------------------------------------
revoke all on function public.profile_featured_guard(), public.badge_metric(uuid, text, numeric), public.badges_refresh(uuid),
  public.profile_ensure(uuid), public.cosmetic_json(text), public.profile_build(uuid, boolean) from public, anon, authenticated;
revoke all on function public.profile_me(), public.profile_set_avatar(text), public.profile_set_featured(text), public.profile_set_privacy(jsonb),
  public.profile_migrate_local(text, text), public.cosmetics_catalog(), public.cosmetic_buy(text, uuid), public.cosmetic_equip(text, text) from public, anon;
grant execute on function public.profile_me(), public.profile_set_avatar(text), public.profile_set_featured(text), public.profile_set_privacy(jsonb),
  public.profile_migrate_local(text, text), public.cosmetics_catalog(), public.cosmetic_buy(text, uuid), public.cosmetic_equip(text, text) to authenticated;
