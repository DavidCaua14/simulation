-- Evolução 63 — uma só dificuldade escolhida pelo treinador.
-- Antes havia dois sistemas: o PERFIL (sim_difficulty_profiles: Padrão / Início acessível / Difícil da evolução 58) e o
-- NÍVEL (career_difficulty_levels: Fácil / Normal / Difícil, criado direto em produção, com receitas, mercado e ranking).
-- Agora:
--  * O NÍVEL é a dificuldade escolhida (Fácil, Normal, Difícil). Ele também carrega os multiplicadores das evoluções
--    58/62: evolução dos atletas, verba e teto salarial da diretoria e força da IA no mercado.
--  * O PERFIL fica só para o "Início acessível", bônus temporário concedido por algumas propostas iniciais.
--  * O "Difícil" do perfil (evolução 58) deixa de existir; carreiras nele passam ao nível Difícil.
--  * mgr_difficulty preserva a versão instalada e soma o nível por cima. Se ela já aplica o nível na cobrança da
--    diretoria (produção), isso não é repetido.
--  * A troca de dificuldade vale uma vez por temporada (o nível pesa no ranking).
begin;

-- Tabela de níveis: em produção já existe; em instalações novas é criada com os mesmos valores.
do $$ begin
 if to_regclass('public.career_difficulty_levels') is null then
  create table public.career_difficulty_levels(
   id text primary key,label text not null,description text not null,sort_order int not null default 2,
   board_loss_mult numeric not null default 1,fan_loss_mult numeric not null default 1,fire_delta numeric not null default 0,
   season_fire_delta numeric not null default 0,objective_shift int not null default 0,income_mult numeric not null default 1,
   seller_fee_mult numeric not null default 1,listed_offer_mult numeric not null default 1,ranking_mult numeric not null default 1);
  alter table public.career_difficulty_levels enable row level security;
  revoke all on public.career_difficulty_levels from public,anon,authenticated;
 end if;
end $$;
insert into public.career_difficulty_levels(id,label,description,sort_order,board_loss_mult,fan_loss_mult,fire_delta,season_fire_delta,objective_shift,income_mult,seller_fee_mult,listed_offer_mult,ranking_mult)
values('easy','Fácil','Diretoria e torcida mais pacientes, receitas 10% maiores e mercado mais favorável. Vale 15% menos no ranking.',1,0.80,0.85,-3,-5,1,1.10,0.90,1.25,0.85),
 ('normal','Normal','A experiência padrão do jogo.',2,1,1,0,0,0,1,1,1,1),
 ('hard','Difícil','Cobrança maior, receitas 10% menores e mercado mais duro. Vale 20% mais no ranking.',3,1.25,1.20,3,5,0,0.90,1.15,0.75,1.20)
on conflict(id) do nothing;
alter table public.career_difficulty_levels add column if not exists dev_mult numeric not null default 1;
alter table public.career_difficulty_levels add column if not exists budget_mult numeric not null default 1;
alter table public.career_difficulty_levels add column if not exists wage_mult numeric not null default 1;
alter table public.career_difficulty_levels add column if not exists ai_market_mult numeric not null default 1;
update public.career_difficulty_levels set
 dev_mult=case id when 'easy' then 1.10 when 'hard' then 0.85 else 1 end,
 budget_mult=case id when 'easy' then 1.15 when 'hard' then 0.85 else 1 end,
 wage_mult=case id when 'easy' then 1.10 when 'hard' then 0.95 else 1 end,
 ai_market_mult=case id when 'easy' then 0.85 when 'hard' then 1.25 else 1 end,
 description=case id when 'easy' then 'Diretoria e torcida mais pacientes, receitas 10% maiores, mercado mais favorável, verba 15% maior e atletas evoluindo 10% mais rápido. Vale 15% menos no ranking.'
  when 'hard' then 'Cobrança maior, receitas 10% menores, mercado mais duro, verba 15% menor e atletas evoluindo 15% mais devagar. Vale 20% mais no ranking.'
  else description end
where id in('easy','normal','hard');

alter table public.careers add column if not exists difficulty_level text not null default 'normal';
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.careers'::regclass and contype='f' and pg_get_constraintdef(oid) ilike '%(difficulty_level)%') then
  alter table public.careers add constraint careers_difficulty_level_fkey foreign key(difficulty_level) references public.career_difficulty_levels(id);
 end if;
end $$;
alter table public.careers add column if not exists difficulty_season uuid;

-- O "Difícil" do perfil (evolução 58) vira o nível Difícil; o perfil volta ao Padrão.
update public.careers set difficulty_level='hard',difficulty='standard' where difficulty='hard';
update public.season_offers set difficulty='standard' where difficulty='hard';
delete from public.sim_difficulty_profiles p where p.id='hard'
 and not exists(select 1 from public.careers where difficulty='hard') and not exists(select 1 from public.season_offers where difficulty='hard');
-- Perfis não carregam mais multiplicadores de dificuldade escolhida: só o bônus do Início acessível.
update public.sim_difficulty_profiles set dev_mult=1,ai_market_mult=1,budget_mult=case id when 'accessible' then 1.15 else 1 end,
 wage_mult=case id when 'accessible' then 1.10 else 1 end;

-- mgr_difficulty = perfil (versão instalada) + nível.
do $$ declare src text;board text;begin
 if to_regprocedure('public.mgr_difficulty_before_v63(uuid)') is null then
  alter function public.mgr_difficulty(uuid) rename to mgr_difficulty_before_v63;
 end if;
 select prosrc into src from pg_proc where oid='public.mgr_difficulty_before_v63(uuid)'::regprocedure;
 board:=case when src ilike '%difficulty_level%' then '' else
  ' p.board_loss_mult:=p.board_loss_mult*l.board_loss_mult;p.fan_loss_mult:=p.fan_loss_mult*l.fan_loss_mult;'
  ||'p.fire_threshold:=p.fire_threshold+l.fire_delta;p.season_fire_threshold:=p.season_fire_threshold+l.season_fire_delta;'
  ||'p.objective_shift:=p.objective_shift+l.objective_shift;' end;
 execute format($f$create or replace function public.mgr_difficulty(p_career uuid)
returns public.sim_difficulty_profiles language plpgsql stable security definer set search_path=public as $b$
declare p public.sim_difficulty_profiles;l public.career_difficulty_levels;
begin
 p:=public.mgr_difficulty_before_v63(p_career);
 select lv.* into l from public.careers c join public.career_difficulty_levels lv on lv.id=coalesce(c.difficulty_level,'normal') where c.id=p_career;
 if l.id is null then return p;end if;
 p.dev_mult:=coalesce(p.dev_mult,1)*l.dev_mult;p.budget_mult:=coalesce(p.budget_mult,1)*l.budget_mult;
 p.wage_mult:=coalesce(p.wage_mult,1)*l.wage_mult;p.ai_market_mult:=coalesce(p.ai_market_mult,1)*l.ai_market_mult;%s
 return p;
end $b$;$f$,board);
end $$;

-- Escolha da dificuldade (uma vez por temporada).
create or replace function public.career_difficulty_set(p_difficulty text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car public.careers;lvl text;season uuid;
begin
 car:=public.mgr_lock();
 lvl:=case p_difficulty when 'standard' then 'normal' else p_difficulty end;
 if not exists(select 1 from public.career_difficulty_levels where id=lvl) then raise exception 'Dificuldade inválida';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 select primary_season into season from public.cw_world where career_id=car.id;
 if lvl=coalesce(car.difficulty_level,'normal') then return jsonb_build_object('ok',true,'difficulty',lvl);end if;
 if season is not null and car.difficulty_season is not distinct from season then
  raise exception 'A dificuldade só pode ser trocada uma vez por temporada.';
 end if;
 update public.careers set difficulty_level=lvl,difficulty_season=season,
  difficulty=case when difficulty='hard' then 'standard' else difficulty end where id=car.id;
 return jsonb_build_object('ok',true,'difficulty',lvl);
end $$;

-- Leitura do painel Clube: nível escolhido, opções e o perfil temporário.
do $$ declare src text;o text;n text;begin
 select pg_get_functiondef('public.career_club_dev_read()'::regprocedure) into src;
 if src like '%difficulty_levels%' then return;end if;
 o:=$q$'difficulty',(select jsonb_build_object('id',p.id,'label',p.label,'dev_mult',p.dev_mult) from public.sim_difficulty_profiles p where p.id=(public.mgr_difficulty(car.id)).id),$q$;
 n:=$q$'difficulty',(select jsonb_build_object('id',lv.id,'label',lv.label,'description',lv.description,'profile',c.difficulty,
    'profile_label',(select label from public.sim_difficulty_profiles where id=c.difficulty),'can_change',c.difficulty_season is distinct from w.primary_season)
   from public.careers c join public.career_difficulty_levels lv on lv.id=coalesce(c.difficulty_level,'normal') where c.id=car.id),
  'difficulty_levels',(select jsonb_agg(jsonb_build_object('id',id,'label',label,'description',description) order by sort_order) from public.career_difficulty_levels),$q$;
 if position(o in src)=0 then raise exception 'career_club_dev_read diferente do esperado';end if;
 execute replace(src,o,n);
end $$;

revoke all on function public.mgr_difficulty(uuid),public.mgr_difficulty_before_v63(uuid) from public,anon,authenticated;
revoke all on function public.career_difficulty_set(text) from public,anon;
grant execute on function public.career_difficulty_set(text) to authenticated;
revoke all on function public.career_club_dev_read() from public,anon;
grant execute on function public.career_club_dev_read() to authenticated;

notify pgrst,'reload schema';
commit;
