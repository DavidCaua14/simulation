-- MODO ONLINE — Fase 34: especialidades (da vida real) e perfil das lendas escrito à mão.
--
-- Especialidade é o que o jogador fazia de melhor na vida real (cobrança de falta, cabeceio, drible...). Ela:
--  • soma pontos aos atributos da ficha ligados a ela (on_traits.sheet): quem bate falta tem Chute colocado e Curva altos;
--  • soma pontos aos atributos do motor (on_traits.bump), então a ficha e a partida contam a mesma história.
-- As lendas recebem estilos e especialidades escritos à mão (on_legend_profiles, dados em 37_legend_profiles_data.sql,
-- gerados por scripts/build-legend-profiles.py). Os demais jogadores ainda não têm especialidades.

alter table public.on_players add column if not exists traits text[] not null default '{}';

create table if not exists public.on_traits(
 code text primary key,
 name text not null,
 descr text not null,
 sheet jsonb not null default '{}'::jsonb, -- pontos na ficha (chaves de on_sheet)
 bump jsonb not null default '{}'::jsonb   -- pontos nos atributos do motor (att, cre, def, ctl, gk, fin, head, pace, stam, tack, str)
);
alter table public.on_traits enable row level security;
revoke all on public.on_traits from anon,authenticated;

insert into public.on_traits(code,name,descr,sheet,bump) values
('falta','Cobrança de falta','Bate falta com precisão e efeito.','{"place":8,"curl":8}','{"fin":1,"cre":2}'),
('cabeceio','Cabeceio','Forte no jogo aéreo, no ataque e na defesa.','{"head":6,"jump":5}','{"head":4}'),
('drible','Drible','Passa pelo marcador com facilidade.','{"drib":7,"ball":4}','{"att":2,"ctl":2}'),
('chute_longe','Chute de longe','Finaliza com perigo de fora da área.','{"kick":7,"fin":2}','{"fin":2}'),
('passe','Passe preciso','Acha o companheiro livre com passes certos.','{"lpass":6,"hpass":4}','{"cre":3}'),
('lancamento','Lançamento longo','Lança e inverte o jogo com precisão.','{"hpass":8}','{"cre":2}'),
('velocidade','Velocidade','Arranca e corre mais que os marcadores.','{"speed":6,"acc":6}','{"pace":3}'),
('finalizacao','Finalização','Faz gol nas chances que aparecem.','{"fin":6,"place":3}','{"fin":3}'),
('desarme','Desarme','Rouba a bola no tempo certo.','{"tackle":7,"aggr":3}','{"tack":3}'),
('marcacao','Marcação','Lê a jogada e se posiciona bem na defesa.','{"def_aw":6,"engage":4}','{"def":3}'),
('forca','Força física','Ganha as divididas e protege a bola.','{"contact":7,"bal":4}','{"str":3}'),
('folego','Fôlego','Corre o jogo todo sem cair de rendimento.','{"stam":8}','{"stam":3}'),
('penalti','Pênalti','Bate pênalti com frieza.','{"place":4}','{"fin":1}'),
('defesa_penalti','Pegador de pênalti','Goleiro que defende pênaltis.','{"gk_refl":4,"gk_reach":3}','{"gk":1}'),
('reflexos','Reflexos','Goleiro de defesas difíceis à queima-roupa.','{"gk_refl":7,"gk_catch":4}','{"gk":3}'),
('cruzamento','Cruzamento','Cruza na medida para a área.','{"hpass":6,"curl":4}','{"cre":2}')
on conflict(code) do update set name=excluded.name,descr=excluded.descr,sheet=excluded.sheet,bump=excluded.bump;

create table if not exists public.on_legend_profiles(
 id text primary key,          -- id da lenda em on_legends (on_players.src)
 style_off text,
 style_def text,
 ai_styles text[] not null default '{}',
 traits text[] not null default '{}'
);
alter table public.on_legend_profiles enable row level security;
revoke all on public.on_legend_profiles from anon,authenticated;

-- Atributos do motor com os bônus de estilos da IA e de especialidades (sem a condição).
create or replace function public.on_comp_skill(p public.on_players) returns numeric[] language sql stable set search_path=public as $$
 select array(select round(greatest(15,least(99,c[k.i]
   +coalesce((select sum((s.bump->>(array['att','cre','def','ctl','gk','fin','head','pace','stam','tack','str'])[k.i])::numeric)
     from public.on_styles s where s.code=any(p.ai_styles)),0)
   +coalesce((select sum((t.bump->>(array['att','cre','def','ctl','gk','fin','head','pace','stam','tack','str'])[k.i])::numeric)
     from public.on_traits t where t.code=any(p.traits)),0))),2)
  from generate_series(1,11) k(i) order by k.i)
 from(select public.on_comp(p.id,p.pos,p.level,p.g) c) q $$;

-- Na partida: o mesmo com a condição (seta).
create or replace function public.on_comp_now(p public.on_players) returns numeric[] language sql stable set search_path=public as $$
 select array(select round(greatest(15,least(99,x+public.on_arrow_delta(p.arrow))),2) from unnest(public.on_comp_skill(p)) with ordinality u(x,i) order by i) $$;

-- Lenda que entra em on_players recebe o perfil escrito à mão (estilos e especialidades).
create or replace function public.on_player_profile_fill() returns trigger language plpgsql set search_path=public as $$
declare j jsonb;lp public.on_legend_profiles;
begin
 select * into lp from public.on_legend_profiles where id=new.src;
 if lp.id is not null and (tg_op='INSERT' or new.style_def is null or new.pos is distinct from old.pos) then
  new.style_off:=lp.style_off;new.style_def:=lp.style_def;new.ai_styles:=lp.ai_styles;new.traits:=lp.traits;
 elsif tg_op='INSERT' and new.style_def is null or tg_op='UPDATE' and (new.pos is distinct from old.pos or new.style_def is null) then
  j:=public.on_style_pick(new.id,new.pos,new.level,new.g,coalesce(new.legend,false));
  new.style_off:=j->>'off';new.style_def:=j->>'def';
  new.ai_styles:=array(select jsonb_array_elements_text(j->'ai'));
 end if;
 if tg_op='INSERT' then
  new.form:=case when coalesce(new.legend,false) then 'B' else 'C' end;
  new.arrow:=public.on_arrow_next(new.form,3,null,false,public.sim_hash01(new.id||':arrow0'));
 elsif new.legend is distinct from old.legend and coalesce(new.legend,false) then
  new.form:='B';
 end if;
 return new;
end $$;

-- Ficha: atributos com os bônus de estilos da IA e especialidades, mais os pontos da especialidade na ficha.
create or replace function public.on_sheet(p public.on_players) returns jsonb language sql stable set search_path=public as $$
 with b as(select public.on_comp_skill(p) x),
  tb as(select coalesce(jsonb_object_agg(e.key,e.sum),'{}'::jsonb) bonus from(
   select kv.key,sum(kv.value::numeric) sum from public.on_traits t,jsonb_each_text(t.sheet) kv where t.code=any(p.traits) group by kv.key) e),
  f(ord,k,lbl,grp) as(values
   (1,'off_aw','Talento ofensivo','atk'),(2,'ball','Controle de bola','tec'),(3,'drib','Drible','tec'),(4,'tight','Condução firme','tec'),
   (5,'lpass','Passe rasteiro','pas'),(6,'hpass','Passe pelo alto','pas'),(7,'fin','Finalização','atk'),(8,'head','Cabeceio','atk'),
   (9,'place','Chute colocado','atk'),(10,'curl','Curva','pas'),(11,'speed','Velocidade','fis'),(12,'acc','Aceleração','fis'),
   (13,'kick','Força do chute','atk'),(14,'jump','Impulsão','fis'),(15,'contact','Contato físico','fis'),(16,'bal','Equilíbrio','fis'),
   (17,'stam','Resistência','fis'),(18,'def_aw','Talento defensivo','def'),(19,'tackle','Desarme','def'),(20,'aggr','Agressividade','def'),
   (21,'engage','Empenho defensivo','def'),(22,'gk_aw','Talento do goleiro','gk'),(23,'gk_catch','Agarrar','gk'),(24,'gk_clear','Afastar','gk'),
   (25,'gk_refl','Reflexos','gk'),(26,'gk_reach','Alcance','gk')),
  calc as(select f.*,
   case f.k
     when 'off_aw' then x[1] when 'ball' then .6*x[4]+.4*x[1] when 'drib' then .5*x[1]+.3*x[4]+.2*x[8] when 'tight' then .7*x[4]+.3*x[11]
     when 'lpass' then .7*x[2]+.3*x[4] when 'hpass' then .8*x[2]+.2*x[11] when 'fin' then x[6] when 'head' then x[7]
     when 'place' then .55*x[6]+.45*x[2] when 'curl' then .6*x[2]+.4*x[6] when 'speed' then x[8] when 'acc' then .8*x[8]+.2*x[4]
     when 'kick' then .5*x[6]+.5*x[11] when 'jump' then .6*x[7]+.4*x[11] when 'contact' then x[11] when 'bal' then .5*x[4]+.5*x[11]
     when 'stam' then x[9] when 'def_aw' then x[3] when 'tackle' then x[10] when 'aggr' then .5*x[10]+.5*x[11]
     when 'engage' then .6*x[3]+.4*x[9] when 'gk_aw' then x[5] when 'gk_catch' then x[5] when 'gk_clear' then .7*x[5]+.3*x[11]
     when 'gk_refl' then x[5] when 'gk_reach' then .8*x[5]+.2*x[7] end
   +(public.sim_hash01(p.id||':sh:'||f.k)-.5)*6+coalesce((tb.bonus->>f.k)::numeric,0) v
   from f,b,tb where (f.grp='gk')=(p.pos='GOL') or f.grp='fis')
 select jsonb_build_object(
  'overall',round(p.ovr),'arrow',p.arrow,'form',p.form,
  'traits',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'name',t.name,'descr',t.descr) order by array_position(p.traits,t.code))
    from public.on_traits t where t.code=any(p.traits)),'[]'),
  'styles',jsonb_build_object(
    'off',(select jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr) from public.on_styles s where s.code=p.style_off),
    'def',(select jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr) from public.on_styles s where s.code=p.style_def),
    'ai',coalesce((select jsonb_agg(jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr)) from public.on_styles s where s.code=any(p.ai_styles)),'[]')),
  'attrs',(select jsonb_agg(jsonb_build_object('k',k,'label',lbl,'group',grp,'value',greatest(30,least(99,round(v)))::int) order by ord) from calc))
$$;

-- Elenco: especialidades de cada jogador
do $$ begin
 perform public.on_patch('public.on_squad()','''style_def'',p.style_def,','''style_def'',p.style_def,''traits'',p.traits,');
end $$;

revoke all on function public.on_comp_skill(public.on_players) from public,anon,authenticated;
