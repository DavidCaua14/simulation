-- =====================================================================
-- EVOLUÇÃO 05 — CLUBE INICIAL PELA NACIONALIDADE DO TREINADOR
--
-- Toda a regra fica AQUI, em duas tabelas de configuração + uma função de sorteio:
--   * sim_start_rules ............ por nacionalidade (careers.country): quais opções de clube aparecem e como são sorteadas
--   * sim_difficulty_profiles .... "experiência inicial": paciência da diretoria/torcida, metas, progressão
--   * get_initial_offers() ....... sorteia UMA vez e grava (recarregar a página não sorteia de novo)
--   * choose_initial_club(offer) . aplica o clube e o perfil de dificuldade da opção escolhida
-- Nova nacionalidade = uma linha em sim_start_rules (+ a bandeira no front). Nenhum outro código muda.
--
-- A dificuldade NÃO mexe em resultado de partida: o motor simula igual para todos. O perfil só altera
-- quanto a diretoria/torcida cobram, a meta da liga e o ganho de reputação, por um número limitado de temporadas.
--
-- Rode depois de evolution/04_manager.sql. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) PERFIS DE DIFICULDADE DA CARREIRA
-- ---------------------------------------------------------------------
create table if not exists public.sim_difficulty_profiles (
  id                    text primary key,
  label                 text not null,
  description           text not null,
  seasons               int  not null default 0 check (seasons >= 0),           -- vale nas N primeiras temporadas da carreira (0 = sempre)
  board_loss_mult       numeric(4,2) not null default 1 check (board_loss_mult between 0.1 and 2),  -- multiplica QUEDAS de confiança da diretoria
  fan_loss_mult         numeric(4,2) not null default 1 check (fan_loss_mult between 0.1 and 2),    -- multiplica QUEDAS do humor da torcida
  rep_gain_mult         numeric(4,2) not null default 1 check (rep_gain_mult between 0.5 and 2),    -- multiplica GANHOS de reputação
  fire_threshold        numeric(5,2) not null default 12 check (fire_threshold between 0 and 50),   -- confiança abaixo da qual há demissão no meio da temporada
  season_fire_threshold numeric(5,2) not null default 35 check (season_fire_threshold between 0 and 80), -- idem no fim da temporada (objetivo principal falhado)
  objective_shift       int  not null default 0 check (objective_shift between 0 and 6)              -- meta da liga N posições mais folgada
);

insert into public.sim_difficulty_profiles (id, label, description, seasons, board_loss_mult, fan_loss_mult, rep_gain_mult,
                                            fire_threshold, season_fire_threshold, objective_shift)
values
  ('standard', 'Padrão', 'Cobrança normal da diretoria e da torcida.', 0, 1, 1, 1, 12, 35, 0),
  ('accessible', 'Início acessível',
   'Nas 2 primeiras temporadas: diretoria e torcida mais pacientes (quedas de confiança 30% menores), meta da liga '
   || '1 posição mais folgada e reputação crescendo 25% mais rápido. As partidas são simuladas normalmente — nada de vitória garantida.',
   2, 0.70, 0.75, 1.25, 6, 25, 1)
on conflict (id) do update set label = excluded.label, description = excluded.description, seasons = excluded.seasons,
  board_loss_mult = excluded.board_loss_mult, fan_loss_mult = excluded.fan_loss_mult, rep_gain_mult = excluded.rep_gain_mult,
  fire_threshold = excluded.fire_threshold, season_fire_threshold = excluded.season_fire_threshold, objective_shift = excluded.objective_shift;

-- ---------------------------------------------------------------------
-- B) REGRAS POR NACIONALIDADE
-- options: lista de "fontes" de propostas. Cada uma:
--   key, label ............ identificação (aparece no card)
--   competitions .......... competições cujos participantes da temporada de referência são elegíveis
--   count ................. quantas propostas saem desta fonte
--   pick .................. 'weakest' | 'strongest' | 'random'  (ordena os elegíveis por força antes de cortar o pool)
--   pool .................. sorteia entre os N primeiros dessa ordem (null = todos)
--   min_strength / max_strength (opcionais), exclude (ids que nunca aparecem), min_squad (jogadores ativos)
--   countries ............. só clubes destes países (ex.: ["ENG"] tira o Cardiff, galês, da Championship)
--   difficulty ............ perfil aplicado se o usuário escolher esta proposta
--   bonus_min / bonus_max . luvas de assinatura (moedas), múltiplos de 50
--   pitches ............... frases do clube (uma é sorteada)
-- ---------------------------------------------------------------------
create table if not exists public.sim_start_rules (
  country    text primary key,             -- mesmo código de careers.country ('BR', 'EN')
  name       text not null,
  summary    text not null,                -- texto curto mostrado na criação do personagem
  options    jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) > 0),
  active     boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.sim_start_rules (country, name, summary, options) values
('BR', 'Brasil', 'Duas propostas: um clube da Série A e um da Série B (início mais acessível).', $j$[
  {"key": "serie_a", "label": "Série A", "competitions": ["brasileirao"], "count": 1, "pick": "weakest", "pool": 6,
   "min_squad": 18, "difficulty": "standard", "bonus_min": 200, "bonus_max": 500,
   "pitches": ["Querem apostar em você desde o primeiro dia: o elenco é humilde, mas a vaga na Série A é sua.",
               "Clube em reconstrução e uma torcida apaixonada. Fugir do Z4 já seria um feito.",
               "Projeto de longo prazo com espaço para jovens talentos brilharem na elite."]},
  {"key": "serie_b", "label": "Série B", "competitions": ["serie_b"], "count": 1, "pick": "strongest", "pool": 8,
   "min_squad": 18, "difficulty": "accessible", "bonus_min": 150, "bonus_max": 350,
   "pitches": ["A diretoria quer o acesso, mas sabe que leva tempo: terá paciência para você montar o time.",
               "Elenco competitivo para a Série B e uma cidade inteira sonhando com a volta à elite.",
               "Lugar ideal para aprender sem a pressão da Série A — e brigar pelo acesso."]}
]$j$::jsonb),
('EN', 'Inglaterra', 'Duas propostas sorteadas entre os clubes mais modestos da Championship.', $j$[
  {"key": "eng_modest", "label": "Championship", "competitions": ["championship"], "countries": ["ENG"], "count": 2, "pick": "weakest", "pool": 10,
   "min_squad": 18, "difficulty": "standard", "bonus_min": 200, "bonus_max": 450,
   "pitches": ["Clube pequeno, ambição grande: a diretoria quer um treinador para construir algo duradouro.",
               "Torcida fiel e orçamento curto. Sobreviver na Championship já é um bom começo.",
               "Clube recém-chegado à segunda divisão inglesa procura um técnico com ideias novas.",
               "Tradição, estádio antigo e muita vontade. A chance de começar a carreira na Inglaterra."]}
]$j$::jsonb)
on conflict (country) do update set name = excluded.name, summary = excluded.summary, options = excluded.options, updated_at = now();

-- ---------------------------------------------------------------------
-- C) CARREIRA: nacionalidade validada + opção/perfil escolhidos
-- ---------------------------------------------------------------------
alter table public.careers alter column country set default 'BR';
alter table public.careers add column if not exists start_option text;
alter table public.careers add column if not exists difficulty   text not null default 'standard';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'careers_country_fkey') then
    alter table public.careers add constraint careers_country_fkey foreign key (country) references public.sim_start_rules (country) not valid;
    alter table public.careers validate constraint careers_country_fkey;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'careers_difficulty_fkey') then
    alter table public.careers add constraint careers_difficulty_fkey foreign key (difficulty) references public.sim_difficulty_profiles (id);
  end if;
end $$;

alter table public.season_offers add column if not exists start_option text;
alter table public.season_offers add column if not exists difficulty   text references public.sim_difficulty_profiles (id);

-- leitura pelo app (tela de criação e propostas); escrita só por migração
alter table public.sim_start_rules         enable row level security;
alter table public.sim_difficulty_profiles enable row level security;
revoke all on public.sim_start_rules, public.sim_difficulty_profiles from anon, authenticated;
grant select on public.sim_start_rules, public.sim_difficulty_profiles to authenticated;
drop policy if exists "read_sim_start_rules" on public.sim_start_rules;
create policy "read_sim_start_rules" on public.sim_start_rules for select to authenticated using (active);
drop policy if exists "read_sim_difficulty_profiles" on public.sim_difficulty_profiles;
create policy "read_sim_difficulty_profiles" on public.sim_difficulty_profiles for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- D) PERFIL EM VIGOR para a carreira (o motor consulta isto; 'standard' quando o perfil já expirou)
-- ---------------------------------------------------------------------
create or replace function public.mgr_difficulty(p_career uuid)
returns public.sim_difficulty_profiles language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p from public.careers c
       join public.sim_difficulty_profiles p on p.id = c.difficulty
       left join public.mgr_coach m on m.career_id = c.id
      where c.id = p_career and (p.seasons = 0 or coalesce(m.seasons, 0) < p.seasons)),
    (select p from public.sim_difficulty_profiles p where p.id = 'standard'));
$$;

-- ---------------------------------------------------------------------
-- E) CLUBES ELEGÍVEIS de uma fonte (participantes oficiais da competição, com elenco cadastrado)
-- ---------------------------------------------------------------------
create or replace function public.sim_start_candidates(p_opt jsonb)
returns table (club_id text, strength int) language sql stable security definer set search_path = public as $$
  with elig as (
    select distinct cl.id, cl.strength
      from public.sim_competition_clubs cc
      join public.sim_competitions comp on comp.id = cc.competition_id and comp.active
      join public.sim_clubs cl on cl.id = cc.club_id
     where cc.competition_id in (select jsonb_array_elements_text(p_opt -> 'competitions'))
       and not (cl.id = any (coalesce(array(select jsonb_array_elements_text(p_opt -> 'exclude')), '{}')))
       and (p_opt -> 'countries' is null or cl.country in (select jsonb_array_elements_text(p_opt -> 'countries')))
       and (p_opt ->> 'min_strength' is null or cl.strength >= (p_opt ->> 'min_strength')::int)
       and (p_opt ->> 'max_strength' is null or cl.strength <= (p_opt ->> 'max_strength')::int)
       and (select count(*) from public.sim_players p where p.club_id = cl.id and p.active)
           >= coalesce((p_opt ->> 'min_squad')::int, 18)
  )
  select e.id, e.strength from elig e
   order by case coalesce(p_opt ->> 'pick', 'random')
              when 'weakest' then e.strength when 'strongest' then -e.strength else 0 end, e.id
   limit coalesce((p_opt ->> 'pool')::int, 1000);
$$;

-- ---------------------------------------------------------------------
-- F) PROPOSTAS INICIAIS — sorteadas UMA vez por carreira e gravadas
-- ---------------------------------------------------------------------
create or replace function public.get_initial_offers()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_rule  public.sim_start_rules;
  v_opt   jsonb;
  v_n     int;
  v_prev  text[];   -- 'clubeA+clubeB' de cada carreira anterior
  v_all   jsonb;
  v_set   text[];
  v_try   int := 0;
  v_pick  text[];
  v_club  text;
  v_bmin  int;
  v_bmax  int;
  v_it    jsonb;
begin
  v_c := public.sim_lock_career();               -- trava a carreira: dois pedidos simultâneos não sorteiam em dobro
  if v_c.club_id is not null then return '[]'::jsonb; end if;

  if not exists (select 1 from public.season_offers where career_id = v_c.id and season_id is null and status = 'pending') then
    select * into v_rule from public.sim_start_rules where country = v_c.country and active;
    if not found then raise exception 'Nacionalidade sem regra de início configurada: %', v_c.country; end if;

    -- conjuntos já oferecidos nas carreiras ANTERIORES do mesmo usuário: não repetir exatamente o mesmo conjunto
    select array_agg(x.k) into v_prev
      from (select string_agg(o.from_club, '+' order by o.from_club) as k
              from public.season_offers o join public.careers c2 on c2.id = o.career_id
             where c2.user_id = v_c.user_id and c2.id <> v_c.id and o.season_id is null
             group by o.career_id) x;

    loop
      v_try := v_try + 1;
      v_all := '[]'::jsonb;
      v_set := '{}';
      for v_opt in select * from jsonb_array_elements(v_rule.options) loop
        v_n := greatest(1, coalesce((v_opt ->> 'count')::int, 1));
        select array_agg(x.club_id) into v_pick
          from (select s.club_id from public.sim_start_candidates(v_opt) s
                 where not (s.club_id = any (v_set)) order by random() limit v_n) x;
        if v_pick is null or cardinality(v_pick) < v_n then
          raise exception 'Não há clubes elegíveis suficientes para a opção % (%).', v_opt ->> 'key', v_c.country;
        end if;
        foreach v_club in array v_pick loop
          v_all := v_all || jsonb_build_object('club', v_club, 'opt', v_opt);
          v_set := v_set || v_club;
        end loop;
      end loop;
      exit when v_prev is null or v_try >= 10      -- (com todas as combinações já usadas, aceita a 10ª tentativa)
             or not ((select string_agg(x, '+' order by x) from unnest(v_set) x) = any (v_prev));
    end loop;

    for v_it in select * from jsonb_array_elements(v_all) loop
      v_opt  := v_it -> 'opt';
      v_bmin := coalesce((v_opt ->> 'bonus_min')::int, 200);
      v_bmax := greatest(v_bmin, coalesce((v_opt ->> 'bonus_max')::int, 500));
      insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch, start_option, difficulty)
      values (v_c.id, null, v_it ->> 'club',
              ((v_bmin + floor(random() * (v_bmax - v_bmin + 1)))::int / 50) * 50,
              coalesce(v_opt -> 'pitches' ->> floor(random() * greatest(1, jsonb_array_length(coalesce(v_opt -> 'pitches', '[]'::jsonb))))::int,
                       'Proposta para começar a sua carreira de treinador.'),
              v_opt ->> 'key', coalesce(v_opt ->> 'difficulty', 'standard'));
    end loop;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch,
             'option', o.start_option,
             'option_label', (select e ->> 'label' from public.sim_start_rules r, jsonb_array_elements(r.options) e
                               where r.country = v_c.country and e ->> 'key' = o.start_option limit 1),
             'difficulty', coalesce(o.difficulty, 'standard'),
             'difficulty_label', d.label, 'difficulty_text', d.description,
             'strength', cl.strength)
           order by o.created_at, o.id)
      from public.season_offers o
      join public.sim_clubs cl on cl.id = o.from_club
      left join public.sim_difficulty_profiles d on d.id = coalesce(o.difficulty, 'standard')
     where o.career_id = v_c.id and o.season_id is null and o.status = 'pending'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.choose_initial_club(p_offer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_o public.season_offers;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is not null then raise exception 'Você já tem clube.'; end if;

  select * into v_o from public.season_offers
   where id = p_offer and career_id = v_c.id and season_id is null and status = 'pending' for update;
  if not found then raise exception 'Proposta inválida.'; end if;

  update public.careers
     set club_id = v_o.from_club, coins = coins + v_o.bonus_coins,
         start_option = v_o.start_option, difficulty = coalesce(v_o.difficulty, 'standard')
   where id = v_c.id;
  update public.season_offers set status = 'accepted', responded_at = now() where id = v_o.id;
  update public.season_offers set status = 'declined', responded_at = now()
   where career_id = v_c.id and season_id is null and status = 'pending' and id <> v_o.id;
end;
$$;

revoke all on function public.mgr_difficulty(uuid), public.sim_start_candidates(jsonb) from public, anon, authenticated;
revoke all on function public.get_initial_offers(), public.choose_initial_club(uuid) from public, anon;
grant execute on function public.get_initial_offers(), public.choose_initial_club(uuid) to authenticated;
