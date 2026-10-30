-- Gerado por scripts/build-editor-release.mjs a partir de 42_admin_dashboard.sql: painel administrativo.
-- Requer os eventos (evolução 13). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Feito para o jogo NO AR: não compara impressões digitais (os jogadores continuam jogando durante a instalação).
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('42_admin_dashboard.sql'));
 if to_regprocedure('public.admin_assert()') is null then raise exception 'Requer os eventos (evolução 13); nada foi alterado';end if;
 

-- ===================== 42_admin_dashboard.sql =====================
insert into public.admins(user_id) select u.id from auth.users u where lower(u.email)='contatodavidcaua@gmail.com' on conflict do nothing;

-- Só o e-mail do dono do jogo, mesmo que alguém mais esteja na tabela `admins`.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admins where user_id=auth.uid())
  and lower(coalesce(auth.jwt()->>'email',''))='contatodavidcaua@gmail.com'
$$;

create table if not exists public.admin_actions(
 id bigint generated always as identity primary key,at timestamptz not null default now(),admin_id uuid not null,
 action text not null,career_id uuid,detail jsonb not null default '{}'::jsonb);
create index if not exists admin_actions_at_idx on public.admin_actions(at desc);
alter table public.admin_actions enable row level security;
revoke all on public.admin_actions from public,anon,authenticated;

create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.admin_assert();
 return jsonb_build_object(
  'now',now(),
  'users',jsonb_build_object(
   'total',(select count(*) from auth.users),
   'new_7d',(select count(*) from auth.users where created_at>now()-interval '7 days'),
   'active_24h',(select count(*) from auth.users where last_sign_in_at>now()-interval '1 day'),
   'active_7d',(select count(*) from auth.users where last_sign_in_at>now()-interval '7 days')),
  'careers',jsonb_build_object(
   'total',(select count(*) from public.careers where status='active'),
   'seasons',(select count(*) from public.cw_world),
   'coins',(select coalesce(sum(coins),0) from public.careers where status='active'),
   'diamonds',(select coalesce(sum(diamonds),0) from public.careers where status='active')),
  'events',jsonb_build_object(
   'live',(select count(*) from public.events where status='published' and starts_at<=now() and (ends_at is null or ends_at>now())),
   'scheduled',(select count(*) from public.events where status='published' and starts_at>now()),
   'drafts',(select count(*) from public.events where status='draft')),
  'database',jsonb_build_object(
   'size',pg_database_size(current_database()),'limit',500*1024*1024,
   'tables',(select coalesce(jsonb_agg(t order by t.bytes desc),'[]') from(
     select s.schemaname||'.'||s.relname as name,pg_total_relation_size(s.relid) as bytes,s.n_live_tup as rows
     from pg_stat_user_tables s order by pg_total_relation_size(s.relid) desc limit 8) t)),
  'recent',(select coalesce(jsonb_agg(a order by a.at desc),'[]') from(
    select x.at,x.action,x.detail,c.nickname from public.admin_actions x left join public.careers c on c.id=x.career_id order by x.at desc limit 6) a));
end $$;

create or replace function public.admin_players(p_query text default '',p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare q text:=nullif(trim(coalesce(p_query,'')),'');
begin
 perform public.admin_assert();
 return(select coalesce(jsonb_agg(p order by p.last_sign_in_at desc nulls last,p.created_at desc),'[]') from(
  select c.id,c.nickname,u.email,c.level,c.xp,c.coins,c.diamonds,c.energy,c.bonus_energy,c.created_at,u.last_sign_in_at,
   mc.club_id,mc.status as coach_status,exists(select 1 from public.cw_world w where w.career_id=c.id) as in_seasons
  from public.careers c join auth.users u on u.id=c.user_id left join public.mgr_coach mc on mc.career_id=c.id
  where c.status='active' and (q is null or c.nickname ilike '%'||left(q,60)||'%' or u.email ilike '%'||left(q,60)||'%')
  order by u.last_sign_in_at desc nulls last,c.created_at desc limit least(greatest(coalesce(p_limit,50),1),200)) p);
end $$;

-- Envia (ou retira, com valor negativo) moedas, diamantes ou energia bônus de um jogador. Fica registrado.
create or replace function public.admin_player_grant(p_career uuid,p_currency text,p_amount int,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ref text:='admin:'||gen_random_uuid();
begin
 perform public.admin_assert();
 if p_currency not in('coins','diamonds','bonus_energy') then raise exception 'Escolha moedas, diamantes ou energia.';end if;
 if p_amount is null or p_amount=0 or abs(p_amount)>1000000 then raise exception 'Valor inválido (até 1.000.000).';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 if not exists(select 1 from public.careers where id=p_career and status='active') then raise exception 'Jogador não encontrado.';end if;
 perform public.econ_apply(p_career,p_currency,p_amount,'admin_grant',ref);
 insert into public.admin_actions(admin_id,action,career_id,detail)
 values(auth.uid(),'grant',p_career,jsonb_build_object('currency',p_currency,'amount',p_amount,'reason',left(trim(p_reason),200)));
 return(select jsonb_build_object('coins',coins,'diamonds',diamonds,'bonus_energy',bonus_energy) from public.careers where id=p_career);
end $$;

-- Aviso para todos: chega na caixa de mensagens (Clube) de cada carreira ativa.
create or replace function public.admin_broadcast(p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n int;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p_title,'')))<3 or length(trim(coalesce(p_body,'')))<3 then raise exception 'Preencha título e mensagem.';end if;
 insert into public.mgr_messages(career_id,season_id,day_no,kind,title,body)
 select c.id,(select s.id from public.career_seasons s where s.career_id=c.id and s.status='active' order by s.season_no desc limit 1),
  coalesce((select s.day_no from public.career_seasons s where s.career_id=c.id and s.status='active' order by s.season_no desc limit 1),0),
  'system',left(trim(p_title),120),left(trim(p_body),2000)
 from public.careers c where c.status='active';
 get diagnostics n=row_count;
 insert into public.admin_actions(admin_id,action,detail) values(auth.uid(),'broadcast',jsonb_build_object('title',left(trim(p_title),120),'recipients',n));
 return jsonb_build_object('recipients',n);
end $$;

create or replace function public.admin_actions_list(p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.admin_assert();
 return(select coalesce(jsonb_agg(a order by a.at desc),'[]') from(
  select x.id,x.at,x.action,x.detail,x.career_id,c.nickname from public.admin_actions x left join public.careers c on c.id=x.career_id
  order by x.at desc limit least(greatest(coalesce(p_limit,100),1),500)) a);
end $$;

revoke all on function public.is_admin(),public.admin_overview(),public.admin_players(text,int),public.admin_player_grant(uuid,text,int,text),
 public.admin_broadcast(text,text),public.admin_actions_list(int) from public,anon;
grant execute on function public.is_admin(),public.admin_overview(),public.admin_players(text,int),public.admin_player_grant(uuid,text,int,text),
 public.admin_broadcast(text,text),public.admin_actions_list(int) to authenticated;
perform pg_notify('pgrst','reload schema');


 if to_regprocedure('public.admin_overview()') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: painel administrativo; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.admin_overview()') is not null then 'Instalação concluída: painel administrativo; dados dos usuários preservados.' else 'Não instalado' end as resultado;
