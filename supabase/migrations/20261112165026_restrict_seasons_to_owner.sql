-- Restrição temporária de Temporadas. Progresso e demais modos preservados.
create or replace function public.seasons_require_access() returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from auth.users where id=auth.uid() and lower(email)='contatodavidcaua@gmail.com') then
  raise exception using errcode='42501',message='O modo Temporadas está indisponível no momento.';
 end if;
end $$;
revoke all on function public.seasons_require_access() from public,anon;
grant execute on function public.seasons_require_access() to authenticated;

-- Protege as entradas públicas do modo, inclusive chamadas diretas à API.
-- Mantém assinaturas, permissões e corpos originais; helpers compartilhados não mudam.
do $$
declare r record;patched text;
begin
 for r in
  select p.oid,p.prosrc,pg_get_functiondef(p.oid) definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_language l on l.oid=p.prolang
  where n.nspname='public' and l.lanname='plpgsql' and p.prorettype<>'trigger'::regtype
   and (p.proname like 'career\_%' escape '\' or p.proname like 'mgr\_%' escape '\' or p.proname like 'season\_%' escape '\')
   and has_function_privilege('authenticated',p.oid,'execute')
 loop
  if position('perform public.seasons_require_access();' in r.prosrc)>0 then continue;end if;
  patched:=regexp_replace(r.prosrc,'(^|;)([ \t\r\n]*begin)\M',E'\\1\\2\n perform public.seasons_require_access();','im');
  if patched=r.prosrc then raise exception 'Não foi possível proteger %',r.oid::regprocedure;end if;
  execute replace(r.definition,r.prosrc,patched);
 end loop;
end $$;
