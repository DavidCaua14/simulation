-- Fase 1 (lacuna): contar as chamadas que batem no limite de 8 s.
-- A API de logs do Supabase não expõe mais os logs do Postgres, e um cancelamento por
-- statement_timeout não aparece em pg_stat_statements. O app informa cada erro 57014 aqui.
-- Consulta: select fn,count(*),max(at) from public.rpc_timeouts group by 1 order by 2 desc;

create table if not exists public.rpc_timeouts(
 id bigserial primary key,
 at timestamptz not null default now(),
 user_id uuid,
 fn text not null);
create index if not exists rpc_timeouts_fn_at on public.rpc_timeouts(fn,at);
alter table public.rpc_timeouts enable row level security;
revoke all on public.rpc_timeouts from anon,authenticated;

create or replace function public.report_rpc_timeout(p_fn text) returns void
language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid();
begin
 if u is null or p_fn is null or p_fn !~ '^[a-z0-9_]{1,80}$' then return; end if;
 -- Um registro por usuário e função a cada 30 s: um erro repetido não enche a tabela.
 if exists(select 1 from public.rpc_timeouts where user_id=u and fn=p_fn and at>now()-interval '30 seconds') then return; end if;
 insert into public.rpc_timeouts(user_id,fn) values(u,p_fn);
 delete from public.rpc_timeouts where at<now()-interval '90 days';
end $$;
revoke all on function public.report_rpc_timeout(text) from public,anon;
grant execute on function public.report_rpc_timeout(text) to authenticated;
