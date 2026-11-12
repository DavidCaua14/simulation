-- Apenas no PostgreSQL descartável de testes do modo online. Nunca executar em Supabase real.
-- Cria o mínimo do resto do jogo que o modo online usa: papéis, auth.uid(), careers e as tabelas/funções reaproveitadas.
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
grant usage on schema auth to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;

create table public.careers(
 id uuid primary key default gen_random_uuid(), user_id uuid not null, nickname text not null unique,
 status text not null default 'active', created_at timestamptz default now(), coins int not null default 1000
);

-- Catálogo real (cópia de produção em 10/11/2026).
create table public.sim_positions(code text primary key, name text not null, line text not null, sort smallint not null,
 w_att numeric(4,2), w_def numeric(4,2), w_ctl numeric(4,2), drain numeric(4,2));
insert into public.sim_positions values
('GOL','Goleiro','GK',1,0.00,0.00,0.20,0.30),
('LD','Lateral-direito','DEF',2,0.35,0.75,0.50,1.10),
('ZAG','Zagueiro','DEF',3,0.10,1.00,0.35,0.85),
('LE','Lateral-esquerdo','DEF',4,0.35,0.75,0.50,1.10),
('VOL','Volante','MID',5,0.20,0.70,0.85,1.05),
('MC','Meio-campista','MID',6,0.35,0.40,1.00,1.10),
('MEI','Meia','MID',7,0.75,0.15,0.85,1.00),
('PD','Ponta-direita','ATT',8,0.90,0.15,0.45,1.10),
('PE','Ponta-esquerda','ATT',9,0.90,0.15,0.45,1.10),
('ATA','Atacante','ATT',10,1.00,0.05,0.30,0.95);

create table public.sim_position_fit(from_pos text, to_pos text, fit numeric(3,2), primary key(from_pos,to_pos));
insert into public.sim_position_fit values ('ATA','ATA',1.00),('ATA','GOL',0.45),('ATA','LD',0.65),('ATA','LE',0.65),('ATA','MC',0.78),('ATA','MEI',0.88),('ATA','PD',0.88),('ATA','PE',0.88),('ATA','VOL',0.78),('ATA','ZAG',0.65),('GOL','ATA',0.45),('GOL','GOL',1.00),('GOL','LD',0.45),('GOL','LE',0.45),('GOL','MC',0.45),('GOL','MEI',0.45),('GOL','PD',0.45),('GOL','PE',0.45),('GOL','VOL',0.45),('GOL','ZAG',0.45),('LD','ATA',0.65),('LD','GOL',0.45),('LD','LD',1.00),('LD','LE',0.93),('LD','MC',0.78),('LD','MEI',0.78),('LD','PD',0.88),('LD','PE',0.65),('LD','VOL',0.78),('LD','ZAG',0.88),('LE','ATA',0.65),('LE','GOL',0.45),('LE','LD',0.93),('LE','LE',1.00),('LE','MC',0.78),('LE','MEI',0.78),('LE','PD',0.65),('LE','PE',0.88),('LE','VOL',0.78),('LE','ZAG',0.88),('MC','ATA',0.78),('MC','GOL',0.45),('MC','LD',0.78),('MC','LE',0.78),('MC','MC',1.00),('MC','MEI',0.93),('MC','PD',0.78),('MC','PE',0.78),('MC','VOL',0.93),('MC','ZAG',0.78),('MEI','ATA',0.88),('MEI','GOL',0.45),('MEI','LD',0.78),('MEI','LE',0.78),('MEI','MC',0.93),('MEI','MEI',1.00),('MEI','PD',0.88),('MEI','PE',0.88),('MEI','VOL',0.85),('MEI','ZAG',0.78),('PD','ATA',0.88),('PD','GOL',0.45),('PD','LD',0.88),('PD','LE',0.65),('PD','MC',0.78),('PD','MEI',0.88),('PD','PD',1.00),('PD','PE',0.93),('PD','VOL',0.78),('PD','ZAG',0.65),('PE','ATA',0.88),('PE','GOL',0.45),('PE','LD',0.65),('PE','LE',0.88),('PE','MC',0.78),('PE','MEI',0.88),('PE','PD',0.93),('PE','PE',1.00),('PE','VOL',0.78),('PE','ZAG',0.65),('VOL','ATA',0.78),('VOL','GOL',0.45),('VOL','LD',0.78),('VOL','LE',0.78),('VOL','MC',0.93),('VOL','MEI',0.85),('VOL','PD',0.78),('VOL','PE',0.78),('VOL','VOL',1.00),('VOL','ZAG',0.88),('ZAG','ATA',0.65),('ZAG','GOL',0.45),('ZAG','LD',0.88),('ZAG','LE',0.88),('ZAG','MC',0.78),('ZAG','MEI',0.78),('ZAG','PD',0.65),('ZAG','PE',0.65),('ZAG','VOL',0.88),('ZAG','ZAG',1.00);

create table public.sim_formations(id text primary key, name text not null, sort smallint not null, slots jsonb not null);
insert into public.sim_formations values
('4-3-3','4-3-3',1,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 86, "y": 72, "pos": "LD", "slot": "LD"}, {"x": 62, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 38, "y": 77, "pos": "ZAG", "slot": "ZAG2"}, {"x": 14, "y": 72, "pos": "LE", "slot": "LE"}, {"x": 50, "y": 58, "pos": "VOL", "slot": "VOL"}, {"x": 70, "y": 46, "pos": "MC", "slot": "MC1"}, {"x": 30, "y": 46, "pos": "MC", "slot": "MC2"}, {"x": 82, "y": 22, "pos": "PD", "slot": "PD"}, {"x": 50, "y": 14, "pos": "ATA", "slot": "ATA"}, {"x": 18, "y": 22, "pos": "PE", "slot": "PE"}]'),
('4-4-2','4-4-2',2,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 86, "y": 72, "pos": "LD", "slot": "LD"}, {"x": 62, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 38, "y": 77, "pos": "ZAG", "slot": "ZAG2"}, {"x": 14, "y": 72, "pos": "LE", "slot": "LE"}, {"x": 84, "y": 44, "pos": "PD", "slot": "MD"}, {"x": 60, "y": 52, "pos": "VOL", "slot": "VOL"}, {"x": 40, "y": 48, "pos": "MC", "slot": "MC"}, {"x": 16, "y": 44, "pos": "PE", "slot": "ME"}, {"x": 62, "y": 17, "pos": "ATA", "slot": "ATA1"}, {"x": 38, "y": 17, "pos": "ATA", "slot": "ATA2"}]'),
('4-2-3-1','4-2-3-1',3,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 86, "y": 72, "pos": "LD", "slot": "LD"}, {"x": 62, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 38, "y": 77, "pos": "ZAG", "slot": "ZAG2"}, {"x": 14, "y": 72, "pos": "LE", "slot": "LE"}, {"x": 62, "y": 56, "pos": "VOL", "slot": "VOL1"}, {"x": 38, "y": 56, "pos": "MC", "slot": "VOL2"}, {"x": 82, "y": 32, "pos": "PD", "slot": "PD"}, {"x": 50, "y": 34, "pos": "MEI", "slot": "MEI"}, {"x": 18, "y": 32, "pos": "PE", "slot": "PE"}, {"x": 50, "y": 13, "pos": "ATA", "slot": "ATA"}]'),
('4-1-4-1','4-1-4-1',4,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 86, "y": 72, "pos": "LD", "slot": "LD"}, {"x": 62, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 38, "y": 77, "pos": "ZAG", "slot": "ZAG2"}, {"x": 14, "y": 72, "pos": "LE", "slot": "LE"}, {"x": 50, "y": 60, "pos": "VOL", "slot": "VOL"}, {"x": 85, "y": 38, "pos": "PD", "slot": "MD"}, {"x": 63, "y": 42, "pos": "MC", "slot": "MC1"}, {"x": 37, "y": 42, "pos": "MEI", "slot": "MC2"}, {"x": 15, "y": 38, "pos": "PE", "slot": "ME"}, {"x": 50, "y": 14, "pos": "ATA", "slot": "ATA"}]'),
('3-5-2','3-5-2',5,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 72, "y": 76, "pos": "ZAG", "slot": "ZAG1"}, {"x": 50, "y": 79, "pos": "ZAG", "slot": "ZAG2"}, {"x": 28, "y": 76, "pos": "ZAG", "slot": "ZAG3"}, {"x": 90, "y": 46, "pos": "LD", "slot": "ALD"}, {"x": 50, "y": 56, "pos": "VOL", "slot": "VOL"}, {"x": 67, "y": 42, "pos": "MC", "slot": "MC1"}, {"x": 33, "y": 42, "pos": "MEI", "slot": "MC2"}, {"x": 10, "y": 46, "pos": "LE", "slot": "ALE"}, {"x": 62, "y": 16, "pos": "ATA", "slot": "ATA1"}, {"x": 38, "y": 16, "pos": "ATA", "slot": "ATA2"}]'),
('3-4-3','3-4-3',6,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 72, "y": 76, "pos": "ZAG", "slot": "ZAG1"}, {"x": 50, "y": 79, "pos": "ZAG", "slot": "ZAG2"}, {"x": 28, "y": 76, "pos": "ZAG", "slot": "ZAG3"}, {"x": 88, "y": 48, "pos": "LD", "slot": "ALD"}, {"x": 60, "y": 52, "pos": "VOL", "slot": "VOL"}, {"x": 40, "y": 52, "pos": "MC", "slot": "MC"}, {"x": 12, "y": 48, "pos": "LE", "slot": "ALE"}, {"x": 80, "y": 20, "pos": "PD", "slot": "PD"}, {"x": 50, "y": 14, "pos": "ATA", "slot": "ATA"}, {"x": 20, "y": 20, "pos": "PE", "slot": "PE"}]'),
('5-3-2','5-3-2',7,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 90, "y": 64, "pos": "LD", "slot": "ALD"}, {"x": 70, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 50, "y": 80, "pos": "ZAG", "slot": "ZAG2"}, {"x": 30, "y": 77, "pos": "ZAG", "slot": "ZAG3"}, {"x": 10, "y": 64, "pos": "LE", "slot": "ALE"}, {"x": 50, "y": 54, "pos": "VOL", "slot": "VOL"}, {"x": 70, "y": 44, "pos": "MC", "slot": "MC1"}, {"x": 30, "y": 44, "pos": "MC", "slot": "MC2"}, {"x": 62, "y": 17, "pos": "ATA", "slot": "ATA1"}, {"x": 38, "y": 17, "pos": "ATA", "slot": "ATA2"}]'),
('4-3-1-2','4-3-1-2',8,'[{"x": 50, "y": 92, "pos": "GOL", "slot": "GOL"}, {"x": 86, "y": 72, "pos": "LD", "slot": "LD"}, {"x": 62, "y": 77, "pos": "ZAG", "slot": "ZAG1"}, {"x": 38, "y": 77, "pos": "ZAG", "slot": "ZAG2"}, {"x": 14, "y": 72, "pos": "LE", "slot": "LE"}, {"x": 50, "y": 58, "pos": "VOL", "slot": "VOL"}, {"x": 72, "y": 49, "pos": "MC", "slot": "MC1"}, {"x": 28, "y": 49, "pos": "MC", "slot": "MC2"}, {"x": 50, "y": 34, "pos": "MEI", "slot": "MEI"}, {"x": 63, "y": 16, "pos": "ATA", "slot": "ATA1"}, {"x": 37, "y": 16, "pos": "ATA", "slot": "ATA2"}]');

-- Cópias das funções reais (supabase/migrations/20261106090000_generated_attrs.sql e 20261104233000_club_development.sql).
create function public.sim_hash01(p text) returns double precision
language plpgsql immutable strict as $$
declare h bigint:=2166136261;i int;
begin
 for i in 1..length(p) loop
  h:=(h # ascii(substr(p,i,1)))&4294967295;
  h:=(h*16777619)&4294967295;
 end loop;
 h:=h # (h>>13);
 h:=(h*1540483477)&4294967295;
 h:=h # (h>>15);
 return h/4294967296.0;
end $$;

create function public.cw_regen_name(p_country text,p_seed text)
returns text language plpgsql immutable as $$
declare fbr text[]:=array['Gabriel','Lucas','Matheus','Pedro','Rafael','João','Gustavo','Felipe','Vinícius','Kaique','Davi','Enzo','Thiago','Bruno','Caio','Igor','Renan','Wesley','Luan','Yuri','Arthur','Nicolas','Samuel','Henrique','Ryan','Breno','Danilo','Erick','Fábio','Otávio'];
 lbr text[]:=array['Silva','Santos','Oliveira','Souza','Pereira','Lima','Carvalho','Ferreira','Rodrigues','Almeida','Costa','Gomes','Ribeiro','Martins','Rocha','Barbosa','Moraes','Teixeira','Moura','Cardoso','Nascimento','Araújo','Mendes','Freitas','Batista','Correia','Pinto','Vieira','Monteiro','Campos'];
 a int:=1+(('x'||substr(md5(p_seed||':f'),1,7))::bit(28)::int%30);b int:=1+(('x'||substr(md5(p_seed||':l'),1,7))::bit(28)::int%30);
begin
 return fbr[a]||' '||lbr[b];
end $$;



-- Motor v2 do modo Temporadas e funções puras que ele usa: cópia literal de produção (10/11/2026).
-- A migration da Fase 2 gera on_engine_run e on_ai_manage a partir de mgr_engine_run_v2 e mgr_ai_manage_v2.
-- Os corpos citam tabelas mgr_* que não existem aqui: só o texto importa.
set check_function_bodies=off;
create type public.mgr_ep as (pid text, sd smallint, slot text, pos text, aw double precision, dw double precision, cw double precision, drain double precision, att double precision, cre double precision, def double precision, ctl double precision, gk double precision, fin double precision, head double precision, pace double precision, stam double precision, tack double precision, str double precision, fit double precision, cond double precision, rhy double precision, goals integer, assists integer, shots integer, sot integer, saves integer, fouls integer, yel integer, red integer, inj boolean, on_field boolean, mins integer);
CREATE OR REPLACE FUNCTION public.mgr_tactics_clean(p_t jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare t jsonb:=coalesce(p_t,'{}'::jsonb); cm boolean; ment int; base int;
 style text; attack text; passing text; tackling text; tempo text; marking text; ls text; sp text; cr text;
begin
 cm:=t ?| array['style','attack','passing','tackling','marking','long_shots','set_pieces','crossing'];
 ment:=greatest(-2,least(2,coalesce((t->>'mentality')::int,0)));
 style:=case when t->>'style' in('defensive','neutral','attacking','counter') then t->>'style'
  when ment<0 then 'defensive' when ment>0 then 'attacking' else 'neutral' end;
 attack:=case when t->>'attack' in('left','right','both','central','mixed') then t->>'attack'
  else case t->>'width' when 'wide' then 'both' when 'center' then 'central' else 'mixed' end end;
 passing:=case when t->>'passing' in('short','mixed','long') then t->>'passing'
  else case t->>'build' when 'short' then 'short' when 'direct' then 'long' else 'mixed' end end;
 tackling:=case when t->>'tackling' in('light','balanced','heavy') then t->>'tackling'
  else case t->>'tackles' when 'cautious' then 'light' when 'aggressive' then 'heavy' else 'balanced' end end;
 tempo:=case when t->>'tempo' in('slow','normal','fast') then t->>'tempo' else 'normal' end;
 marking:=case when t->>'marking' in('low','medium','high') then t->>'marking'
  when t->>'pressing' in('low','medium','high') then t->>'pressing' else 'medium' end;
 ls:=case when t->>'long_shots' in('often','sometimes','rarely') then t->>'long_shots' else 'sometimes' end;
 sp:=case when t->>'set_pieces' in('shoot','cross','short') then t->>'set_pieces' else 'cross' end;
 cr:=case when t->>'crossing' in('byline','deep','mixed','rarely') then t->>'crossing'
  else case t->>'width' when 'wide' then 'byline' when 'center' then 'rarely' else 'mixed' end end;
 -- postura: o estilo manda; ±2 (usado pela IA no fim do jogo) é mantido quando tem o mesmo sentido do estilo
 base:=case style when 'defensive' then -1 when 'attacking' then 1 when 'counter' then -1 else 0 end;
 if style='counter' then ment:=least(0,coalesce((t->>'mentality')::int,-1));
 elsif cm and sign(ment)<>sign(base) then ment:=base;
 elsif sign(ment)<>sign(base) then ment:=base;
 end if;
 return jsonb_build_object(
  'style',style,'attack',attack,'passing',passing,'tackling',tackling,'tempo',tempo,'marking',marking,
  'long_shots',ls,'set_pieces',sp,'crossing',cr,
  'mentality',ment,
  'pressing',marking,
  'line',case when not cm and t->>'line' in('low','medium','high') then t->>'line' when marking='high' then 'high' when marking='low' or style='counter' then 'low' else 'medium' end,
  'build',case passing when 'short' then 'short' when 'long' then 'direct' else 'mixed' end,
  'width',case attack when 'central' then 'center' when 'mixed' then 'mixed' else 'wide' end,
  'tackles',case tackling when 'light' then 'cautious' when 'heavy' then 'aggressive' else 'normal' end,
  'manage',case when t->>'manage'='chase' then 'chase' when not cm and t->>'manage' in('keep','normal','push') then t->>'manage' else 'normal' end);
end $function$

;

CREATE OR REPLACE FUNCTION public.mgr_ai_tactics(p_diff numeric, p_home boolean)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
select jsonb_build_object(
'mentality', case when p_diff > 7 then 1 when p_diff < -8 then -1 when not p_home and p_diff < -3 then -1 else 0 end,
'pressing',  case when p_diff > 3 then 'high' when p_diff < -8 then 'low' else 'medium' end,
'line',      case when p_diff > 5 then 'high' when p_diff < -7 then 'low' else 'medium' end,
'tempo',     'normal',
'build',     case when p_diff > 4 then 'short' when p_diff < -6 then 'direct' else 'mixed' end,
'width',     'mixed',
'manage',    'normal')
$function$

;

CREATE OR REPLACE FUNCTION public.mgr_card_chances(p_aggression numeric, p_discipline numeric, p_tack numeric, p_cond numeric, p_fouls integer, p_booked boolean, p_tackles text, p_ref numeric, p_context numeric DEFAULT 1)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
 select jsonb_build_object(
 'yellow',least(0.42,greatest(0.06,0.16 * (0.65+p_aggression/100) * (1.30-p_discipline/200)
       * (1.25-p_tack/200) * (1+greatest(0,55-p_cond)/180) * (1+least(p_fouls,5)*0.04)
       * case p_tackles when 'aggressive' then 1.35 when 'cautious' then 0.70 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context * case when p_booked then 0.35 else 1 end)),
 'red',least(0.009,greatest(0.0003,0.0012 * (0.50+p_aggression/100) * (1.30-p_discipline/200)
       * case p_tackles when 'aggressive' then 2.0 when 'cautious' then 0.5 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context)))
$function$

;

CREATE OR REPLACE FUNCTION public.mgr_tactical_effect(p_t jsonb, p_opp jsonb, p_skill numeric, p_pace numeric, p_stamina numeric, p_head numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ctl numeric:=1; freq numeric:=1; quality numeric:=0;
begin
 if p_t->>'build'='short' then
  ctl:=ctl+greatest(-0.10,least(0.06,(p_skill-60)/250));
  if p_opp->>'pressing'='high' then ctl:=ctl+(p_skill-65)/400; quality:=quality+(p_skill-65)/700; end if;
 elsif p_t->>'build'='direct' and p_opp->>'line'='high' then
  freq:=freq+greatest(-0.04,least(0.10,(p_pace-55)/250));quality:=quality+greatest(-0.03,least(0.06,(p_pace-60)/500));
 end if;
 if p_t->>'build'='direct' and p_opp->>'pressing'='high' then freq:=freq*1.12;quality:=quality+0.025;end if;
 if p_t->>'width'='wide' then quality:=quality+greatest(-0.05,least(0.05,(p_head-60)/400)); end if;
 if p_t->>'pressing'='high' then ctl:=ctl+greatest(-0.06,least(0.04,(p_stamina-65)/350)); end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',quality);
end $function$

;

CREATE OR REPLACE FUNCTION public.mgr_pick(p_w double precision[])
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
v_t float8 := 0;
v_r float8;
v_i int;
v_n int := coalesce(array_length(p_w, 1), 0);
begin
for v_i in 1 .. v_n loop if p_w[v_i] > 0 then v_t := v_t + p_w[v_i]; end if; end loop;
if v_t <= 0 then return 0; end if;
v_r := random() * v_t;
for v_i in 1 .. v_n loop
if p_w[v_i] > 0 then
v_r := v_r - p_w[v_i];
if v_r <= 0 then return v_i; end if;
end if;
end loop;
return v_n;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mgr_pick(p_w numeric[])
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
v_t numeric := 0;
v_r numeric;
v_i int;
begin
if p_w is null then return 0; end if;
for v_i in 1 .. coalesce(array_length(p_w, 1), 0) loop v_t := v_t + greatest(coalesce(p_w[v_i], 0), 0); end loop;
if v_t <= 0 then return 0; end if;
v_r := random() * v_t;
for v_i in 1 .. array_length(p_w, 1) loop
v_r := v_r - greatest(coalesce(p_w[v_i], 0), 0);
if v_r <= 0 then return v_i; end if;
end loop;
return array_length(p_w, 1);
end;
$function$

;

CREATE OR REPLACE FUNCTION public.mgr_cond_factor(p_cond numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
select (0.70 + 0.30 * p_cond / 100) * case when p_cond < 50 then 0.88 + 0.12 * p_cond / 50 else 1 end
$function$

;

CREATE OR REPLACE FUNCTION public.mgr_engine_run_v2(p_fixture bigint, p_to integer, p_interactive character)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lsh float8[];
  v_ldist boolean;
  v_spk text[];
  v_cprev int[];
  v_fk int[];
  v_fktaker text[];
  v_cktaker text[];
  v_sp64 int;
  v_spq float8;
  v_pentaker text[];
  v_spb float8[];
  v_m      public.mgr_matches;
  v_p      public.mgr_ep[];
  v_n      int;
  v_min    int;
  v_end    int;
  v_stop   text := 'segment';
  i        int;
  j        int;
  s        int;
  d        int;
  v_e      float8;
  v_att    float8[];
  v_def    float8[];
  v_ctl    float8[];
  v_gkr    float8[];
  v_gki    int[];
  v_defav  float8[];
  v_paceav float8[];
  v_non    int[];
  v_tac    jsonb;
  v_ment   int[];
  v_amult  float8[];
  v_dmult  float8[];
  v_freq   float8[];
  v_qual   float8[];
  v_drainm float8[];
  v_foulm  float8[];
  v_offm   float8[];
  v_hdr    float8[];
  v_sc     int[];
  v_agg    int[];
  v_poss   int[];
  v_corn   int[];
  v_offs   int[];
  v_ph     float8;
  v_r      float8;
  v_pa     float8;
  v_q      float8;
  v_w      float8[];
  v_k      int;
  v_a      int;
  v_gkidx  int;
  v_head   boolean;
  v_reload boolean;
  v_neut   boolean;
  v_et     boolean;
  v_side   char;
  v_oside  char;
  v_dsec   char;
  v_inj_stop boolean;
  v_lead   int;
  v_detail text;
  v_form   float8[];
  v_tpress text[];
  v_tline  text[];
  v_ttempo text[];
  v_tbuild text[];
  v_tmanage text[];
  v_tment  int[];
  v_ctlm   float8[];
  v_dws    float8[];
  v_dirty  boolean := true;
  v_profiles jsonb;
  v_card jsonb;
  v_ref float8;
  v_tackles text[];
  v_effect jsonb;
  v_skill record;
  v_yprob float8;
  v_rprob float8;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture for update;
  if v_m.status <> 'live' then return 'ft'; end if;
  select jsonb_object_agg(a.player_id,jsonb_build_array(a.aggression,a.discipline)) into v_profiles
   from public.mgr_match_players mp join public.sim_player_attrs a on a.player_id=mp.player_id where mp.fixture_id=p_fixture;
  v_ref:=coalesce((v_m.state->>'referee')::float8,1);
  v_form := array[coalesce((v_m.state -> 'form' ->> 0)::numeric, 1), coalesce((v_m.state -> 'form' ->> 1)::numeric, 1)];
  v_min := v_m.minute;
  v_et  := coalesce((v_m.state ->> 'et')::boolean, false);
  v_end := least(p_to, case when v_et then 120 else 90 end);
  v_neut := coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_poss := array[(v_m.state -> 'poss' ->> 0)::int, (v_m.state -> 'poss' ->> 1)::int];
  v_corn := array[(v_m.state -> 'corners' ->> 0)::int, (v_m.state -> 'corners' ->> 1)::int];
  v_offs := array[(v_m.state -> 'offsides' ->> 0)::int, (v_m.state -> 'offsides' ->> 1)::int];
  v_sc   := array[(v_m.state -> 'score' ->> 0)::int, (v_m.state -> 'score' ->> 1)::int];
  v_agg  := array[(v_m.state -> 'agg' ->> 0)::int, (v_m.state -> 'agg' ->> 1)::int];
  v_cprev := array[v_corn[1], v_corn[2]]; v_fk := array[0, 0];
  v_fktaker := array[v_m.state->'fk_taker'->>'h', v_m.state->'fk_taker'->>'a'];
  v_cktaker := array[v_m.state->'ck_taker'->>'h', v_m.state->'ck_taker'->>'a'];
  v_reload := true;
  v_pentaker := array[v_m.state->'pen_taker'->>'h', v_m.state->'pen_taker'->>'a'];
  v_spb := array[coalesce((v_m.state->'sp_bonus'->>0)::float8,0), coalesce((v_m.state->'sp_bonus'->>1)::float8,0)];

  while v_min < v_end loop
    v_min := v_min + 1;

    -- a IA (e o auxiliar, no modo automático) mexe nos intervalos e marcos do jogo
    if v_min in (46, 61, 71, 81, 91, 106) then
      if v_p is not null then   -- grava antes: a IA decide olhando a condição e o placar atuais
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
        update public.mgr_matches
           set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
         where fixture_id = p_fixture;
        v_p := null;
      end if;
      if p_interactive is distinct from 'h' then perform public.mgr_ai_manage(p_fixture, 'h', v_min - 1); end if;
      if p_interactive is distinct from 'a' then perform public.mgr_ai_manage(p_fixture, 'a', v_min - 1); end if;
      v_reload := true;
    end if;

    if v_reload then
      if v_p is not null then
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
      end if;
      select * into v_m from public.mgr_matches where fixture_id = p_fixture;
      select array_agg(row(mp.player_id, case when mp.side = 'h' then 1 else 2 end, mp.slot, mp.pos,
                           sp.w_att::float8, sp.w_def::float8, sp.w_ctl::float8, sp.drain::float8,
                           mp.c_att::float8, mp.c_cre::float8, mp.c_def::float8, mp.c_ctl::float8, mp.c_gk::float8, mp.c_fin::float8,
                           mp.c_head::float8, mp.c_pace::float8, mp.c_stam::float8, mp.c_tack::float8, mp.c_str::float8,
                           mp.fit::float8, mp.cond::float8, mp.rhythm::float8, mp.goals, mp.assists, mp.shots, mp.sot, mp.saves, mp.fouls, mp.yellow, mp.red,
                           false, true, mp.minutes)::public.mgr_ep order by mp.side, mp.slot)
        into v_p
        from public.mgr_match_players mp join public.sim_positions sp on sp.code = mp.pos
       where mp.fixture_id = p_fixture and mp.status = 'on';
      v_n := coalesce(array_length(v_p, 1), 0);
      v_tac := v_m.state -> 'tactics';
      v_reload := false;
      v_dirty := true;
      -- parâmetros táticos fixos até a próxima mudança
      v_tackles:=array[coalesce(v_tac->'h'->>'tackles','normal'),coalesce(v_tac->'a'->>'tackles','normal')];
      v_tpress := array[v_tac -> 'h' ->> 'pressing', v_tac -> 'a' ->> 'pressing'];
      v_tline  := array[v_tac -> 'h' ->> 'line', v_tac -> 'a' ->> 'line'];
      v_ttempo := array[v_tac -> 'h' ->> 'tempo', v_tac -> 'a' ->> 'tempo'];
      v_tbuild := array[v_tac -> 'h' ->> 'build', v_tac -> 'a' ->> 'build'];
      v_tmanage := array[v_tac -> 'h' ->> 'manage', v_tac -> 'a' ->> 'manage'];
      v_tment  := array[coalesce((v_tac -> 'h' ->> 'mentality')::int, 0), coalesce((v_tac -> 'a' ->> 'mentality')::int, 0)];
      v_freq := array[1, 1]; v_qual := array[0, 0]; v_drainm := array[1, 1]; v_foulm := array[1, 1]; v_offm := array[1, 1];
      v_hdr := array[0.2, 0.2]; v_ctlm := array[1, 1];
      v_lsh := array[0.18, 0.18];
      v_spk := array[coalesce(v_tac->'h'->>'set_pieces','cross'), coalesce(v_tac->'a'->>'set_pieces','cross')];
      for s in 1 .. 2 loop
        d := 3 - s;
        if v_tpress[s] = 'high' then v_freq[s] := v_freq[s] * 1.06; v_drainm[s] := 1.30; v_foulm[s] := 1.25; v_ctlm[d] := v_ctlm[d] * 0.93;
        elsif v_tpress[s] = 'low' then v_drainm[s] := 0.85; v_foulm[s] := 0.85; v_ctlm[d] := v_ctlm[d] * 1.04; end if;
        if v_ttempo[s] = 'fast' then v_freq[s] := v_freq[s] * 1.10; v_drainm[s] := v_drainm[s] * 1.18; v_ctlm[s] := v_ctlm[s] * 0.97;
        elsif v_ttempo[s] = 'slow' then v_freq[s] := v_freq[s] * 0.90; v_drainm[s] := v_drainm[s] * 0.90; v_ctlm[s] := v_ctlm[s] * 1.04; end if;
        if v_tbuild[s] = 'short' then v_freq[s] := v_freq[s] * 0.95; v_qual[s] := v_qual[s] + 0.04; v_ctlm[s] := v_ctlm[s] * 1.05;
        elsif v_tbuild[s] = 'direct' then v_freq[s] := v_freq[s] * 1.08; v_qual[s] := v_qual[s] - 0.03; v_offm[s] := 1.25; v_ctlm[s] := v_ctlm[s] * 0.94; end if;
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'width' when 'wide' then 0.30 when 'center' then 0.10 else 0.20 end;
        if v_hdr[s] = 0.10 then v_qual[s] := v_qual[s] + 0.02; end if;
        -- CM17: cruzamento define a parcela de cabeceios; chutes longos trocam volume por qualidade
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'crossing' when 'byline' then 0.32 when 'deep' then 0.24 when 'rarely' then 0.06 else v_hdr[s] end;
        v_lsh[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'long_shots' when 'often' then 0.35 when 'rarely' then 0.06 else 0.18 end;
        if v_lsh[s] >= 0.35 then v_freq[s] := v_freq[s] * 1.04; elsif v_lsh[s] <= 0.06 then v_freq[s] := v_freq[s] * 0.97; v_qual[s] := v_qual[s] + 0.01; end if;
        if v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'style' = 'counter' then v_freq[s] := v_freq[s] * 1.06; v_qual[s] := v_qual[s] + 0.02; v_ctlm[s] := v_ctlm[s] * 0.95; end if;
        -- linha defensiva do ADVERSÁRIO muda a frequência de ataque e os impedimentos
        if v_tline[d] = 'high' then v_freq[s] := v_freq[s] * 0.95; v_offm[s] := v_offm[s] * 1.7;
        elsif v_tline[d] = 'low' then v_freq[s] := v_freq[s] * 1.06; v_offm[s] := v_offm[s] * 0.6; end if;
      end loop;
      for s in 1..2 loop
        select avg(c_cre) as skill,avg(c_pace) as pace,avg(c_stam * cond/100) as stamina,avg(c_head) as heading into v_skill
        from public.mgr_match_players where fixture_id=p_fixture and side=case when s=1 then 'h' else 'a' end and status='on' and pos<>'GOL';
        v_effect:=public.mgr_tactical_effect(v_tac->(case when s=1 then 'h' else 'a' end),v_tac->(case when s=1 then 'a' else 'h' end),
                  v_skill.skill,v_skill.pace,v_skill.stamina,v_skill.heading);
        v_ctlm[s]:=v_ctlm[s]*(v_effect->>'control')::float8;
        v_freq[s]:=v_freq[s]*(v_effect->>'frequency')::float8;
        v_qual[s]:=v_qual[s]+(v_effect->>'quality')::float8;
        v_foulm[s]:=v_foulm[s]*case v_tackles[s] when 'aggressive' then 1.22 when 'cautious' then 0.78 else 1 end;
      end loop;
      if not v_neut then v_ctlm[1] := v_ctlm[1] * 1.05; end if;
    end if;

    -- ---- força dos times (recalculada a cada 3 minutos ou quando alguém sai/entra) ----
    if v_dirty or v_min % 3 = 1 then
      v_dirty := false;
      v_att := array[0, 0]; v_def := array[0, 0]; v_ctl := array[0, 0]; v_gkr := array[30, 30]; v_gki := array[0, 0];
      v_defav := array[0, 0]; v_paceav := array[0, 0]; v_non := array[0, 0]; v_dws := array[0, 0];
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond) * (case when v_p[i].cond < 50 then 0.88 + 0.0024 * v_p[i].cond else 1 end)
               * (0.94 + 0.0006 * v_p[i].rhy);
        v_att[s] := v_att[s] + v_p[i].aw * (0.62 * v_p[i].att + 0.38 * v_p[i].cre) * v_e;
        v_def[s] := v_def[s] + v_p[i].dw * v_p[i].def * v_e;
        v_ctl[s] := v_ctl[s] + v_p[i].cw * v_p[i].ctl * v_e;
        v_non[s] := v_non[s] + 1;
        if v_p[i].pos = 'GOL' then v_gkr[s] := v_p[i].gk * v_e; v_gki[s] := i;
        else
          v_defav[s] := v_defav[s] + v_p[i].dw * v_p[i].def * v_e;
          v_paceav[s] := v_paceav[s] + v_p[i].dw * v_p[i].pace * v_e;
          v_dws[s] := v_dws[s] + v_p[i].dw;
        end if;
      end loop;
      for s in 1 .. 2 loop
        v_defav[s] := case when v_dws[s] > 0 then v_defav[s] / v_dws[s] else 40 end;
        v_paceav[s] := case when v_dws[s] > 0 then v_paceav[s] / v_dws[s] else 50 end;
      end loop;
    end if;

    -- ---- postura (muda com o placar conforme a "gestão do jogo") ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_ment[s] := v_tment[s];
      v_lead := (v_sc[s] + v_agg[s]) - (v_sc[d] + v_agg[d]);
      if v_tmanage[s] = 'keep' and v_lead > 0 and v_min >= 70 then v_ment[s] := greatest(-2, v_ment[s] - 1); end if;
      if v_tmanage[s] = 'push' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if; if v_tmanage[s] = 'chase' and v_lead <= 0 then v_ment[s] := least(2, v_ment[s] + case when v_lead < 0 and v_min >= 70 then 2 else 1 end); end if;
      v_amult[s] := (array[0.80, 0.90, 1.00, 1.10, 1.20])[v_ment[s] + 3];
      v_dmult[s] := (array[1.15, 1.07, 1.00, 0.94, 0.86])[v_ment[s] + 3] * case when v_tpress[s] = 'low' then 1.03 else 1 end;
    end loop;

    -- ---- posse ----
    v_r := v_ctl[1] * v_ctlm[1];
    v_q := v_ctl[2] * v_ctlm[2];
    v_ph := greatest(0.25, least(0.75, 0.5 + 1.15 * (v_r / greatest(v_r + v_q, 1) - 0.5)));
    s := case when random() < v_ph then 1 else 2 end;
    d := 3 - s;
    v_side := case when s = 1 then 'h' else 'a' end;
    v_oside := case when d = 1 then 'h' else 'a' end;
    v_poss[s] := v_poss[s] + 1;

    -- ---- jogada de ataque? ----
    v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case when v_neut then 1 when s = 1 then 1.16 else 0.96 end), 1)
                          / greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.50)
                  * v_freq[s];
    v_pa := greatest(0.05, least(0.55, v_pa));

    if random() < v_pa then
      v_r := random();
      if v_r < 0.07 * v_offm[s] then
        -- impedimento
        v_offs[s] := v_offs[s] + 1;
        if p_interactive is not null then
          v_w := '{}';
          for i in 1 .. v_n loop v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s then v_p[i].aw * v_p[i].pace else 0 end; end loop;
          v_k := public.mgr_pick(v_w);
          if v_k > 0 then perform public.mgr_event(p_fixture, v_min, v_side, 'offside', v_p[v_k].pid); end if;
        end if;
      elsif v_r < 0.07 + 0.10 then
        -- falta do defensor na jogada (pode virar pênalti ou cartão)
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = d and v_p[i].pos <> 'GOL' then v_p[i].dw * (1 + (100 - v_p[i].tack) / 100) else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].fouls := v_p[v_k].fouls + 1;
          v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
            v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[d],v_ref::numeric,1.20);
          v_r:=random();
          if v_r<(v_card->>'red')::float8 then
            v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
            perform public.mgr_event(p_fixture,v_min,v_oside,'red',v_p[v_k].pid,null,'Entrada temerária');
            update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
            if p_interactive=v_oside then v_stop:='red';end if;
          elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
            if v_p[v_k].yel>=1 then
              v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
              perform public.mgr_event(p_fixture,v_min,v_oside,'second_yellow',v_p[v_k].pid);
              update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
              if p_interactive=v_oside then v_stop:='red';end if;
            else
              v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_oside,'yellow',v_p[v_k].pid);
            end if;
          end if;
          if random() < 0.22 then v_fk[s] := v_fk[s] + 1; end if;           -- falta perigosa (bola parada)
          if random() < 0.11 then                                         -- pênalti
            v_a := 0; v_e := -1;
            for i in 1 .. v_n loop
              if v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and (v_p[i].fin + (case when v_p[i].pid = v_pentaker[s] then 500 else 0 end)) > v_e then v_e := v_p[i].fin + (case when v_p[i].pid = v_pentaker[s] then 500 else 0 end); v_a := i; end if;
            end loop;
            if v_a > 0 then
              v_p[v_a].shots := v_p[v_a].shots + 1;
              v_gkidx := v_gki[d];
              if random() < greatest(0.55, least(0.88, 0.70 + v_spb[s] + 0.004 * (v_p[v_a].fin - v_gkr[d]))) then
                v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_a].goals := v_p[v_a].goals + 1; v_sc[s] := v_sc[s] + 1;
                perform public.mgr_event(p_fixture, v_min, v_side, 'pen_goal', v_p[v_a].pid);
              else
                if random() < 0.6 and v_gkidx > 0 then
                  v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1;
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, v_p[v_gkidx].pid, 'defendido');
                else
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, null, 'para fora');
                end if;
              end if;
            end if;
          end if;
        end if;
      elsif v_r < 0.17 + 0.12 then
        if random() < 0.45 then v_corn[s] := v_corn[s] + 1; end if;  -- cruzamento cortado / jogada desarmada
      else
        -- ---- finalização ----
        v_head := random() < v_hdr[s];
        v_ldist := not v_head and random() < v_lsh[s];
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
                   case when v_head then (v_p[i].aw + 0.25) * power(v_p[i].head / 60, 3)
                        else power(v_p[i].aw + 0.05 + case when v_ldist then 0.35 * v_p[i].cw else 0 end, 1.6) * power(v_p[i].fin / 60, 2) * (0.70 + 0.003 * v_p[i].cond) end
                 else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          v_q := 0.30 + 0.0025 * ((case when v_head then v_p[v_k].head else v_p[v_k].att end) - v_defav[d])
                 + case when s = 1 and not v_neut then 0.02 else 0 end
                 + v_qual[s] + random() * 0.35
                 + case v_tline[d] when 'high' then 0.003 * (v_p[v_k].pace - v_paceav[d]) when 'low' then -0.04 else 0 end
                 - case when v_head then 0.08 else 0 end
                 - case when v_ldist then 0.13 - 0.002 * (v_p[v_k].fin - 65) else 0 end;
          v_q := greatest(0.05, least(0.95, v_q * (0.85 + 0.15*v_p[v_k].fit)));
          v_gkidx := v_gki[d];
          v_r := random();
          if v_r < (0.20 + case when v_ldist then 0.08 else 0 end) then
            -- bloqueada
            if random() < 0.60 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, 'bloqueado'); end if;
          elsif random() < greatest(0.10, least(0.75, 0.26 + 0.32 * v_q + 0.0020 * (v_p[v_k].fin - 65))) then
            v_p[v_k].sot := v_p[v_k].sot + 1;
            if random() < greatest(0.05, least(0.70, 0.11 + 0.36 * v_q + 0.0015 * (v_p[v_k].fin - v_gkr[d]))) then
              -- GOL
              v_p[v_k].goals := v_p[v_k].goals + 1;
              v_sc[s] := v_sc[s] + 1;
              v_a := 0;
              if random() < 0.78 then
                v_w := '{}';
                for i in 1 .. v_n loop
                  v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and i <> v_k and v_p[i].pos <> 'GOL'
                                     then (v_p[i].aw + 0.6 * v_p[i].cw) * power(v_p[i].cre / 60, 2) else 0 end;
                end loop;
                v_a := public.mgr_pick(v_w);
                if v_a > 0 then v_p[v_a].assists := v_p[v_a].assists + 1; end if;
              end if;
              perform public.mgr_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid,
                                       case when v_a > 0 then v_p[v_a].pid end, case when v_head then 'de cabeça' when v_ldist then 'de fora da área' end);
            else
              if v_gkidx > 0 then v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1; end if;
              if random() < 0.40 then v_corn[s] := v_corn[s] + 1; end if;
              if p_interactive is not null or v_q > 0.62 then
                perform public.mgr_event(p_fixture, v_min, v_side, 'save', v_p[v_k].pid,
                                         case when v_gkidx > 0 then v_p[v_gkidx].pid end, case when v_q > 0.62 then 'grande chance' end);
              end if;
            end if;
          else
            if random() < 0.18 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then
              perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_q > 0.62 then 'grande chance' end);
            end if;
          end if;
        end if;
      end if;
    end if;

    -- ---- bolas paradas (CM17): faltas perigosas e escanteios viram finalização conforme a tática ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_sp64 := greatest(0, v_corn[s] - v_cprev[s]) + v_fk[s];
      while v_sp64 > 0 loop
        v_sp64 := v_sp64 - 1;
        v_side := case when s = 1 then 'h' else 'a' end;
        if v_fk[s] > 0 then v_fk[s] := v_fk[s] - 1; v_head := v_spk[s] = 'cross'; v_ldist := v_spk[s] = 'shoot';
        else v_head := v_spk[s] <> 'short'; v_ldist := false; end if;
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
            case when v_ldist then power(v_p[i].fin / 60, 2) * power(v_p[i].cre / 60, 2) * case when v_p[i].pid = v_fktaker[s] then 60 else 1 end
                 when v_head then (v_p[i].aw + 0.5 * v_p[i].dw + 0.2) * power(v_p[i].head / 60, 3)
                 else power(v_p[i].aw + 0.05, 1.6) * power(v_p[i].fin / 60, 2) end else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        continue when v_k = 0;
        v_spq := case when v_ldist then 0.034 + 0.0018 * (v_p[v_k].fin - 65) + 0.0012 * (v_p[v_k].cre - 65)
                      when v_head then 0.018 + 0.0010 * (v_p[v_k].head - v_defav[d]) + case when v_cktaker[s] is not null then 0.004 else 0 end
                      else 0.012 end + 0.5 * v_spb[s];
        v_spq := greatest(0.005, least(0.15, v_spq));
        if random() < 0.55 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          if random() < v_spq / 0.55 then
            v_p[v_k].sot := v_p[v_k].sot + 1; v_p[v_k].goals := v_p[v_k].goals + 1; v_sc[s] := v_sc[s] + 1;
            perform public.mgr_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid, null, case when v_ldist then 'cobrança de falta' when v_head then 'bola parada, de cabeça' else 'bola parada' end);
          elsif p_interactive is not null and random() < 0.5 then
            perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_ldist then 'cobrança de falta' else 'bola parada' end);
          end if;
        end if;
      end loop;
    end loop;
    v_cprev := array[v_corn[1], v_corn[2]];
    v_fk := array[0, 0];

    -- ---- faltas no meio-campo e cartões (os dois times) ----
    for s in 1 .. 2 loop
      continue when random() >= 0.125 * v_foulm[s] * (case when v_min > 75 then 1.15 else 1 end);
      v_side := case when s = 1 then 'h' else 'a' end;
      v_w := '{}';
      for i in 1 .. v_n loop
        v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL'
                           then (v_p[i].dw + 0.3) * (1 + (100 - v_p[i].tack) / 100) * case when v_p[i].yel > 0 then 0.45 else 1 end else 0 end;
      end loop;
      v_k := public.mgr_pick(v_w);
      continue when v_k = 0;
      v_p[v_k].fouls := v_p[v_k].fouls + 1;
      v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
        v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[s],v_ref::numeric,case when v_min>75 and abs(v_sc[1]-v_sc[2])<=1 then 1.10 else 1.0 end);
      v_r:=random();
      if v_r<(v_card->>'red')::float8 then
        v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
        perform public.mgr_event(p_fixture,v_min,v_side,'red',v_p[v_k].pid,null,'Entrada temerária');
        update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
        if p_interactive=v_side then v_stop:='red';end if;
      elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
        if v_p[v_k].yel>=1 then
          v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
          perform public.mgr_event(p_fixture,v_min,v_side,'second_yellow',v_p[v_k].pid);
          update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
          if p_interactive=v_side then v_stop:='red';end if;
        else
          v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_side,'yellow',v_p[v_k].pid);
        end if;
      end if;
    end loop;

    -- ---- desgaste, lesões e minutos jogados ----
    v_inj_stop := false;
    if v_min % 3 = 0 then
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_side := case when s = 1 then 'h' else 'a' end;
        v_p[i].cond := greatest(0, v_p[i].cond - 3 * 0.21 * v_p[i].drain * (1.32 - v_p[i].stam / 100 * 0.62) * v_drainm[s]
                                   * case when v_et then 1.15 else 1 end);
        if random() < 3 * 0.00005 * (1 + greatest(0, 70 - v_p[i].cond) / 25) * (case when v_tpress[s] = 'high' then 1.15 else 1 end) then
          v_p[i].inj := true; v_p[i].on_field := false; v_dirty := true;
          perform public.mgr_event(p_fixture, v_min, v_side, 'injury', v_p[i].pid);
          update public.mgr_match_players set status = 'injured_off', injured = true, left_min = v_min where fixture_id = p_fixture and player_id = v_p[i].pid;
          if p_interactive = v_side then v_inj_stop := true;
          else
            -- a IA troca na hora (se ainda tiver substituição)
            v_detail := public.mgr_do_sub(p_fixture, v_side, v_p[i].pid, public.mgr_best_bench(p_fixture, v_side, v_p[i].pos), v_min, true);
            v_reload := true;
          end if;
        end if;
      end loop;
    end if;
    if v_inj_stop then v_stop := 'injury'; end if;

    if v_reload then  -- grava o estado antes de recarregar a lista de quem está em campo
      update public.mgr_matches
         set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
       where fixture_id = p_fixture;
    end if;

    exit when v_stop in ('red', 'injury');
    if v_min = 45 and not v_et then v_stop := 'ht'; exit; end if;
    if v_min = 105 and v_et then v_stop := 'et_ht'; exit; end if;
  end loop;

  -- grava tudo
  if v_p is not null then
    update public.mgr_match_players m
       set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
           fouls = x.fouls, yellow = x.yel, red = x.red,
           minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
      from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
  end if;
  update public.mgr_matches
     set minute = v_min, updated_at = now(),
         state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
   where fixture_id = p_fixture;

  if v_min >= (case when v_et then 120 else 90 end) then v_stop := 'ft'; end if;
  if v_stop = 'segment' and v_min = 45 then v_stop := 'ht'; end if;
  return v_stop;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.mgr_ai_manage_v2(p_fixture bigint, p_side character, p_minute integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_m     public.mgr_matches;
  v_my    int;
  v_opp   int;
  v_base  int;
  v_ment  int;
  r       record;
  v_in    text;
  v_n     int := 0;
  v_first boolean := true;
  v_max   int := case when p_minute >= 75 then 3 else 2 end;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_my  := (v_m.state -> 'score' ->> (case when p_side = 'h' then 0 else 1 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 0 else 1 end))::int;
  v_opp := (v_m.state -> 'score' ->> (case when p_side = 'h' then 1 else 0 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 1 else 0 end))::int;
  v_base := (v_m.state -> 'base_mentality' ->> (case when p_side = 'h' then 0 else 1 end))::int;

  -- postura
  v_ment := v_base;
  if v_my < v_opp and p_minute >= 60 then v_ment := least(2, v_base + case when v_opp - v_my >= 2 or p_minute >= 75 then 2 else 1 end);
  elsif v_my > v_opp and p_minute >= 75 then v_ment := greatest(-2, v_base - 1);
  end if;
  if v_ment <> coalesce((v_m.state -> 'tactics' -> p_side ->> 'mentality')::int, 0) then
    update public.mgr_matches set state = jsonb_set(state, array['tactics', p_side, 'mentality'], to_jsonb(v_ment)) where fixture_id = p_fixture;
  end if;

  -- Ajusta mais que a postura: pressão/ritmo conforme placar, tempo e cansaço.
  if p_minute>=60 then
   update public.mgr_matches set state=jsonb_set(state,array['tactics',p_side],
     (state->'tactics'->p_side) || case when v_my<v_opp then
       jsonb_build_object('tempo','fast','pressing',case when (select avg(cond) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on')>60 then 'high' else 'medium' end,'manage','push')
      when v_my>v_opp and p_minute>=75 then '{"tempo":"slow","pressing":"low","manage":"keep"}'::jsonb else '{}'::jsonb end
     || case when (select count(*) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on' and yellow>0)>=3
         then '{"tackles":"cautious"}'::jsonb else '{}'::jsonb end)
    where fixture_id=p_fixture;
  end if;

  -- substituições (lesionados primeiro, depois os mais cansados / pendurados)
  for r in
    select mp.player_id, mp.pos, mp.status
      from public.mgr_match_players mp
     where mp.fixture_id = p_fixture and mp.side = p_side
       and ((mp.status = 'injured_off' and mp.slot is not null)
            or (mp.status = 'on' and mp.pos <> 'GOL' and p_minute >= 45
                and (mp.cond < 66 or (mp.yellow > 0 and mp.pos in ('ZAG', 'LD', 'LE', 'VOL') and p_minute >= 55)
                     or (p_minute >= 70 and mp.cond < 74 and v_my <> v_opp))))
     order by (mp.status = 'injured_off') desc, mp.cond
  loop
    exit when v_n >= v_max and r.status <> 'injured_off';
    v_in := public.mgr_best_bench(p_fixture, p_side,
              case when v_my < v_opp and p_minute >= 70 and r.pos in ('VOL', 'ZAG') and v_ment >= 1 then 'ATA' else r.pos end);
    exit when v_in is null;
    exit when public.mgr_do_sub(p_fixture, p_side, r.player_id, v_in, p_minute, v_first) is not null;
    v_first := false;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.mgr_rate(p_fixture bigint, p_final boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_m  public.mgr_matches;
v_h  int;
v_a  int;
begin
select * into v_m from public.mgr_matches where fixture_id = p_fixture;
v_h := (v_m.state -> 'score' ->> 0)::int;
v_a := (v_m.state -> 'score' ->> 1)::int;
update public.mgr_match_players mp
set rating = round(greatest(3.0, least(10.0,
6.0 + 1.05 * mp.goals + 0.55 * mp.assists + 0.10 * mp.sot + 0.03 * mp.shots
- 0.35 * mp.yellow - 1.6 * mp.red
+ case when mp.pos = 'GOL' then 0.22 * mp.saves - 0.30 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.6 else 0 end
when mp.pos in ('ZAG', 'LD', 'LE') then -0.12 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.35 else 0 end
when mp.pos = 'VOL' then -0.06 * x.conceded + case when x.conceded = 0 and mp.minutes >= 60 then 0.15 else 0 end
else case when x.scored = 0 and mp.pos in ('ATA', 'PD', 'PE', 'MEI') then -0.25 else 0 end end
+ case when x.scored > x.conceded then 0.25 when x.scored < x.conceded then -0.25 else 0 end
+ (mp.fit - 0.92) * 2.5 + (public.mgr_cond_factor(mp.cond) - 0.9)
+ case when p_final and mp.minutes >= 20 then (random() - 0.5) * 0.7 else 0 end
))::numeric, 1)
from (select s.side,
case when s.side = 'h' then v_h else v_a end as scored,
case when s.side = 'h' then v_a else v_h end as conceded
from (values ('h'::char), ('a'::char)) s(side)) x
where mp.fixture_id = p_fixture and mp.side = x.side and mp.minutes > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mgr_do_sub(p_fixture bigint, p_side character, p_out text, p_in text, p_minute integer, p_new_window boolean, p_detail text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_m    public.mgr_matches;
v_o    public.mgr_match_players;
v_i    public.mgr_match_players;
v_used int;
v_win  int;
begin
select * into v_m from public.mgr_matches where fixture_id = p_fixture;
v_used := (v_m.state -> 'subs' -> p_side ->> 'used')::int;
v_win  := (v_m.state -> 'subs' -> p_side ->> 'windows')::int;
if v_used >= (v_m.state ->> 'max_subs')::int then return 'Limite de substituições atingido.'; end if;
if p_new_window and p_minute not in (45, 90) and v_win >= (v_m.state ->> 'max_windows')::int then
return 'Você já usou todas as paradas para substituição.';
end if;
select * into v_o from public.mgr_match_players where fixture_id = p_fixture and player_id = p_out and side = p_side;
select * into v_i from public.mgr_match_players where fixture_id = p_fixture and player_id = p_in and side = p_side;
if v_o.player_id is null or v_o.status not in ('on', 'injured_off') then return 'Quem sai precisa estar em campo.'; end if;
if v_o.status = 'injured_off' and v_o.slot is null then return 'Esse jogador já foi substituído.'; end if;
if v_i.player_id is null or v_i.status <> 'bench' then return 'Quem entra precisa estar no banco (e não pode ter jogado).'; end if;
update public.mgr_match_players
set status = case when status = 'injured_off' then 'injured_off' else 'off' end, left_min = coalesce(left_min, p_minute), slot = null
where fixture_id = p_fixture and player_id = p_out;
update public.mgr_match_players
set status = 'on', slot = v_o.slot, pos = v_o.pos, fit = public.mgr_fit(p_in, v_o.pos), entered_min = p_minute
where fixture_id = p_fixture and player_id = p_in;
update public.mgr_matches
set state = jsonb_set(jsonb_set(state, array['subs', p_side, 'used'], to_jsonb(v_used + 1)),
array['subs', p_side, 'windows'], to_jsonb(v_win + case when p_new_window and p_minute not in (45, 90) then 1 else 0 end))
where fixture_id = p_fixture;
perform public.mgr_event(p_fixture, p_minute, p_side, 'sub', p_in, p_out, p_detail);
return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mgr_event(p_fixture bigint, p_minute integer, p_side character, p_kind text, p_player text DEFAULT NULL::text, p_player2 text DEFAULT NULL::text, p_detail text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_seq int;
begin
update public.mgr_matches set state = jsonb_set(state, '{seq}', to_jsonb(coalesce((state ->> 'seq')::int, 0) + 1))
where fixture_id = p_fixture returning (state ->> 'seq')::int into v_seq;
insert into public.mgr_match_events (fixture_id, seq, minute, side, kind, player_id, player2_id, detail)
values (p_fixture, coalesce(v_seq, 1), p_minute, p_side, p_kind, p_player, p_player2, p_detail);
end;
$function$;

CREATE OR REPLACE FUNCTION public.mgr_set_positions(p_fixture bigint, p_side character, p_slots jsonb, p_minute integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_form  jsonb;
v_m     public.mgr_matches;
r       record;
v_pos   text;
v_n     int := 0;
begin
if p_slots is null or jsonb_typeof(p_slots) <> 'object' then return null; end if;
select * into v_m from public.mgr_matches where fixture_id = p_fixture;
select f.slots into v_form from public.sim_formations f where f.id = v_m.state -> 'formation' ->> (case when p_side = 'h' then 0 else 1 end);
if (select count(*) from jsonb_each_text(p_slots)) <> (select count(distinct value) from jsonb_each_text(p_slots)) then
return 'O mesmo jogador está em duas posições.';
end if;
for r in select key as slot, value as pid from jsonb_each_text(p_slots) loop
select s ->> 'pos' into v_pos from jsonb_array_elements(v_form) s where s ->> 'slot' = r.slot;
if v_pos is null then return format('A vaga %s não existe na formação atual.', r.slot); end if;
if not exists (select 1 from public.mgr_match_players where fixture_id = p_fixture and side = p_side and player_id = r.pid and status = 'on') then
continue;   -- quem já saiu (lesão/expulsão) é ignorado
end if;
if exists (select 1 from public.mgr_match_players where fixture_id = p_fixture and player_id = r.pid and slot is distinct from r.slot) then
v_n := v_n + 1;
end if;
update public.mgr_match_players set slot = '__' || r.slot, pos = v_pos, fit = public.mgr_fit(r.pid, v_pos)
where fixture_id = p_fixture and player_id = r.pid;
end loop;
update public.mgr_match_players set slot = substr(slot, 3) where fixture_id = p_fixture and side = p_side and slot like '\_\_%';
if exists (select 1 from public.mgr_match_players where fixture_id = p_fixture and side = p_side and status = 'on' and slot is not null
group by slot having count(*) > 1) then
return 'Dois jogadores na mesma posição.';
end if;
if v_n > 0 then perform public.mgr_event(p_fixture, p_minute, p_side, 'tactic', null, null, 'Jogadores trocam de posição'); end if;
return null;
end;
$function$;

set check_function_bodies=on;

-- Catálogo de jogadores reais (só o que o modo online lê): 3.000 jogadores fictícios, notas de 50 a 90.
create table public.sim_players(id text primary key, full_name text, short_name text, position text, secondary_positions text[],
 nationality text, age smallint, active boolean not null default true, career_id uuid);
create table public.sim_player_base(player_id text primary key, rating numeric(5,2), age0 smallint, potential smallint);
insert into public.sim_players(id,full_name,short_name,position,secondary_positions,nationality,age)
select 'real-'||i,'Jogador Real '||i,'Real '||i,(array['GOL','LD','ZAG','LE','VOL','MC','MEI','PD','PE','ATA'])[1+i%10],
 case when i%4=0 then array['MC'] else '{}'::text[] end,(array['BRA','ARG','URU'])[1+i%3],18+i%17
from generate_series(1,3000) i;
insert into public.sim_player_base(player_id,rating,age0,potential)
select 'real-'||i,50+((i*37)%401)/10.0,18+i%17,least(99,55+((i*37)%401)/10.0+i%9)::smallint from generate_series(1,3000) i;
