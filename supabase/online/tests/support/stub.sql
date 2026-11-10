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

create table public.sim_positions(code text primary key, name text not null, line text not null, sort smallint not null);
insert into public.sim_positions values('GOL','Goleiro','GK',1),('LD','Lateral-direito','DEF',2),('ZAG','Zagueiro','DEF',3),
 ('LE','Lateral-esquerdo','DEF',4),('VOL','Volante','MID',5),('MC','Meio-campista','MID',6),('MEI','Meia','MID',7),
 ('PD','Ponta-direita','ATT',8),('PE','Ponta-esquerda','ATT',9),('ATA','Atacante','ATT',10);

create table public.sim_position_fit(from_pos text, to_pos text, fit numeric(3,2), primary key(from_pos,to_pos));
insert into public.sim_position_fit
select f.code, t.code, case when f.code=t.code then 1.00 when f.code='GOL' or t.code='GOL' then 0.45 else 0.80 end
from public.sim_positions f cross join public.sim_positions t;

create table public.sim_formations(id text primary key, name text not null, sort smallint not null, slots jsonb not null);
insert into public.sim_formations values
('4-3-3','4-3-3',1,'[{"slot":"GOL","pos":"GOL"},{"slot":"LD","pos":"LD"},{"slot":"ZAG1","pos":"ZAG"},{"slot":"ZAG2","pos":"ZAG"},{"slot":"LE","pos":"LE"},
 {"slot":"VOL","pos":"VOL"},{"slot":"MC1","pos":"MC"},{"slot":"MC2","pos":"MC"},{"slot":"PD","pos":"PD"},{"slot":"ATA","pos":"ATA"},{"slot":"PE","pos":"PE"}]'),
('4-4-2','4-4-2',2,'[{"slot":"GOL","pos":"GOL"},{"slot":"LD","pos":"LD"},{"slot":"ZAG1","pos":"ZAG"},{"slot":"ZAG2","pos":"ZAG"},{"slot":"LE","pos":"LE"},
 {"slot":"MD","pos":"PD"},{"slot":"MC1","pos":"MC"},{"slot":"MC2","pos":"MC"},{"slot":"ME","pos":"PE"},{"slot":"ATA1","pos":"ATA"},{"slot":"ATA2","pos":"ATA"}]');

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

-- A função real normaliza as táticas; aqui basta devolver o que recebeu.
create function public.mgr_tactics_clean(p_t jsonb) returns jsonb language sql immutable as $$ select coalesce(p_t,'{}'::jsonb) $$;
