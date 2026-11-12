-- MODO ONLINE — Fase 8: preparação para o jogo.
--
-- Antes de cada partida o técnico tem quatro tarefas. Elas somam até 100% de preparação:
--   escalação revisada (30) · treino desde o último jogo (15 por sessão, até 30) · relatório do adversário (20) ·
--   preleção (20).
-- No pontapé a preparação vira bônus de forma do time (até prep_bonus, 3%) e é mostrada na partida.
-- Preparação completa em jogos seguidos forma uma sequência: cada jogo rende moedas na conta (prep_coins) e a
-- cada prep_streak_every jogos seguidos há um prêmio maior (prep_streak_coins). Jogo sem preparação completa
-- zera a sequência. Bots não têm preparação.
--
-- on_clubs.prep guarda o que foi feito para o próximo jogo: {"fx": id, "lineup": true, "scout": true, "talk": "…"}.

alter table public.on_clubs add column if not exists prep jsonb not null default '{}'::jsonb;
alter table public.on_clubs add column if not exists prep_streak smallint not null default 0;
alter table public.on_clubs add column if not exists prep_best smallint not null default 0;
alter table public.on_config add column if not exists prep_bonus numeric(4,3) not null default .03;
alter table public.on_config add column if not exists prep_coins int not null default 5;
alter table public.on_config add column if not exists prep_streak_every smallint not null default 5;
alter table public.on_config add column if not exists prep_streak_coins int not null default 30;

-- Próximo jogo do clube que ainda não terminou.
create or replace function public.on_next_fixture(p_club int) returns public.on_fixtures
language sql stable security definer set search_path=public as $$
 select f.* from public.on_fixtures f join public.on_clubs c on c.id=p_club and c.season_id=f.season_id
 where f.status<>'done' and p_club in(f.home,f.away) order by f.kickoff limit 1
$$;

-- Marca uma tarefa de preparação para o próximo jogo (as marcas de um jogo anterior são descartadas).
create or replace function public.on_prep_mark(p_club int,p_key text,p_value jsonb default 'true') returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures:=public.on_next_fixture(p_club);
begin
 if f.id is null then return;end if;
 update public.on_clubs set prep=case when (prep->>'fx')::bigint is not distinct from f.id then prep else jsonb_build_object('fx',f.id) end
  ||jsonb_build_object(p_key,p_value) where id=p_club;
end $$;

-- Preparação do clube para o jogo p_fx: tarefas, percentual, bônus e sequência.
create or replace function public.on_prep_json(c public.on_clubs,p_fx public.on_fixtures) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare cfg public.on_config;v_since timestamptz;v_cur boolean;v_line boolean;v_train int;v_scout boolean;v_talk text;v_score int;
begin
 if p_fx.id is null then return null;end if;
 select * into cfg from public.on_config;
 v_cur:=(c.prep->>'fx')::bigint is not distinct from p_fx.id;
 select coalesce(max(f.kickoff),'-infinity') into v_since from public.on_fixtures f
  where f.season_id=c.season_id and f.status='done' and c.id in(f.home,f.away);
 v_line:=v_cur and coalesce((c.prep->>'lineup')::boolean,false);
 v_scout:=v_cur and coalesce((c.prep->>'scout')::boolean,false);
 v_talk:=case when v_cur then c.prep->>'talk' end;
 select least(2,count(*)) into v_train from public.on_train t where t.club_id=c.id and t.finished_at is not null and t.score>0 and t.started_at>v_since;
 v_score:=case when v_line then 30 else 0 end+15*v_train+case when v_scout then 20 else 0 end+case when v_talk is not null then 20 else 0 end;
 return jsonb_build_object('fixture',p_fx.id,'score',v_score,'bonus',round(cfg.prep_bonus*v_score,2),
  'lineup',v_line,'train',v_train,'train_max',2,'scout',v_scout,'talk',v_talk,
  'streak',c.prep_streak,'best',c.prep_best,'coins',cfg.prep_coins,'streak_every',cfg.prep_streak_every,'streak_coins',cfg.prep_streak_coins);
end $$;

-- No pontapé: a preparação de cada técnico vira bônus de forma; sequência e moedas são atualizadas.
create or replace function public.on_prep_apply(p_fx public.on_fixtures) returns void
language plpgsql security definer set search_path=public as $$
declare cfg public.on_config;c public.on_clubs;j jsonb;i int;v_out jsonb:='[null,null]';v_score int;v_coins int;v_streak int;
begin
 select * into cfg from public.on_config;
 for i in 0..1 loop
  select * into c from public.on_clubs where id=case when i=0 then p_fx.home else p_fx.away end for update;
  continue when c.user_id is null or c.draft_step<3;
  j:=public.on_prep_json(c,p_fx);
  v_score:=(j->>'score')::int;
  v_out:=jsonb_set(v_out,array[i::text],jsonb_build_object('score',v_score,'bonus',j->'bonus'));
  update public.on_matches set state=jsonb_set(state,array['form',i::text],
   to_jsonb(round(((state->'form'->>i)::numeric*(1+cfg.prep_bonus*v_score/100.0)),3))) where fixture_id=p_fx.id;
  if v_score>=100 then
   v_streak:=c.prep_streak+1;
   v_coins:=cfg.prep_coins+case when v_streak%cfg.prep_streak_every=0 then cfg.prep_streak_coins else 0 end;
   update public.careers set coins=coins+v_coins
    where id=(select x.id from public.careers x where x.user_id=c.user_id order by (x.status='active') desc,x.created_at desc limit 1);
   insert into public.on_news(club_id,kind,text) values(c.id,'prep',format('Time 100%% preparado: +%s moedas. Sequência de %s jogo(s).',v_coins,v_streak));
  else
   v_streak:=0;
  end if;
  update public.on_clubs set prep='{}',prep_streak=v_streak,prep_best=greatest(prep_best,v_streak) where id=c.id;
 end loop;
 update public.on_matches set state=state||jsonb_build_object('prep',v_out) where fixture_id=p_fx.id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Funções chamadas pelo app
-- ─────────────────────────────────────────────────────────────────────────────

-- Relatório do adversário do próximo jogo (olheiro). Ler o relatório conta como tarefa de preparação.
create or replace function public.on_scout() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);f public.on_fixtures;o public.on_clubs;v_sec jsonb;
begin
 f:=public.on_next_fixture(c.id);
 if f.id is null then raise exception 'Sem jogo pela frente';end if;
 select * into o from public.on_clubs where id=case when f.home=c.id then f.away else f.home end;
 perform public.on_prep_mark(c.id,'scout');
 select * into c from public.on_clubs where id=c.id;
 -- força por setor dos 11 escalados de cada lado (sem escalação salva: os 11 melhores)
 select jsonb_object_agg(x.who,x.lines) into v_sec from(
  select k.who,jsonb_object_agg(z.line,z.avg) lines from(values('me',c.id),('opp',o.id)) k(who,club)
  cross join lateral(
   select sp.line,round(avg(p.ovr),1) avg from public.on_players p join public.sim_positions sp on sp.code=p.pos
   where p.club_id=k.club and p.id in(
    select e.value from public.on_lineups l,jsonb_each_text(l.slots) e where l.club_id=k.club
    union all
    select q.id from(select p2.id from public.on_players p2 where p2.club_id=k.club and not exists(select 1 from public.on_lineups l where l.club_id=k.club)
     order by p2.ovr desc limit 11) q)
   group by sp.line) z
  group by k.who) x;
 return jsonb_build_object('fixture',f.id,'kickoff',f.kickoff,'at_home',f.home=c.id,'comp',f.comp,'round',f.round,
  'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors,'bot',o.user_id is null,
   'position',(select r.pos from public.on_rank(c.season_id) r where r.club_id=o.id),
   'formation',(select l.formation from public.on_lineups l where l.club_id=o.id),
   'style',coalesce((select l.tactics->>'style' from public.on_lineups l where l.club_id=o.id),'neutral'),
   'form',coalesce((select jsonb_agg(x.r order by x.kickoff) from(
     select g.kickoff,case when g.hg=g.ag then 'D' when (g.hg>g.ag)=(g.home=o.id) then 'W' else 'L' end r
     from public.on_fixtures g where g.season_id=c.season_id and g.status='done' and o.id in(g.home,g.away) order by g.kickoff desc limit 5) x),'[]'::jsonb),
   'goals',(select jsonb_build_object('gf',t.gf,'ga',t.ga,'p',t.p) from public.on_table t where t.season_id=c.season_id and t.club_id=o.id),
   'stars',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'nat',p.nat,'ovr',p.ovr,'age',p.age,'star',p.star,
      'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.ovr desc)
    from(select * from public.on_players q where q.club_id=o.id order by q.ovr desc,q.id limit 3) p),'[]'::jsonb)),
  'sectors',v_sec,'prep',public.on_prep_json(c,f));
end $$;

-- Preleção antes do jogo: 'motivate' (motivar), 'focus' (concentrar) ou 'calm' (tranquilizar).
create or replace function public.on_team_talk(p_talk text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);
begin
 if p_talk not in('motivate','focus','calm') then raise exception 'Preleção inválida';end if;
 if public.on_next_fixture(c.id) is null then raise exception 'Sem jogo pela frente';end if;
 perform public.on_prep_mark(c.id,'talk',to_jsonb(p_talk));
 select * into c from public.on_clubs where id=c.id;
 return public.on_prep_json(c,public.on_next_fixture(c.id));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ligações com as fases anteriores (troca de texto conferida, ver on_patch na Fase 7)
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 -- salvar ou montar a escalação conta como tarefa
 perform public.on_patch('public.on_lineup_save(text,jsonb,text[],jsonb)',' return public.on_squad();',
  ' perform public.on_prep_mark(c.id,''lineup'');'||chr(10)||' return public.on_squad();');
 perform public.on_patch('public.on_lineup_auto(text)',' return public.on_squad();',
  ' perform public.on_prep_mark(c.id,''lineup'');'||chr(10)||' return public.on_squad();');
 -- pontapé: aplica o bônus
 perform public.on_patch('public.on_match_open(public.on_fixtures)','update public.on_fixtures set status=''live'' where id=p_fx.id and status=''sched'';',
  'update public.on_fixtures set status=''live'' where id=p_fx.id and status=''sched'';'||chr(10)||' perform public.on_prep_apply(p_fx);');
 -- telas: preparação no início do modo e na partida
 perform public.on_patch('public.on_status()','''train'',jsonb_build_object(',
  '''prep'',case when c.draft_step>=3 then public.on_prep_json(c,public.on_next_fixture(c.id)) end,''train'',jsonb_build_object(');
 perform public.on_patch('public.on_match_payload(bigint,int,char)','''summary'',m.summary)','''summary'',m.summary,''prep'',m.state->''prep'')');
end $$;

revoke all on function public.on_next_fixture(int),public.on_prep_mark(int,text,jsonb),public.on_prep_json(public.on_clubs,public.on_fixtures),
 public.on_prep_apply(public.on_fixtures) from public,anon,authenticated;
revoke all on function public.on_scout(),public.on_team_talk(text) from public,anon;
grant execute on function public.on_scout(),public.on_team_talk(text) to authenticated;
