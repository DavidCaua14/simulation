begin;
-- Fix only unset search paths; leave intentional privileges and existing RLS semantics intact.
do $$ declare r record;begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
 where n.nspname='public' and l.lanname in('sql','plpgsql') and not coalesce(p.proconfig,'{}') && array['search_path=public','search_path=public, pg_temp']
 and not exists(select 1 from unnest(coalesce(p.proconfig,'{}')) cfg where cfg like 'search_path=%') loop
 execute format('alter function %s set search_path=public,pg_temp',r.signature);
 end loop;
end $$;
do $$ declare r record;qual text;chk text;begin
 for r in select p.polname,c.relname,pg_get_expr(p.polqual,p.polrelid) q,pg_get_expr(p.polwithcheck,p.polrelid) ck
 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' loop
 qual:=r.q;chk:=r.ck;
 if qual like '%auth.uid()%' and qual not ilike '%select auth.uid()%' then qual:=replace(qual,'auth.uid()','(select auth.uid())');end if;
 if chk like '%auth.uid()%' and chk not ilike '%select auth.uid()%' then chk:=replace(chk,'auth.uid()','(select auth.uid())');end if;
 if qual is distinct from r.q or chk is distinct from r.ck then
 execute format('alter policy %I on public.%I %s %s',r.polname,r.relname,case when qual is null then '' else 'using ('||qual||')' end,case when chk is null then '' else 'with check ('||chk||')' end);
 end if;
 end loop;
end $$;
-- No blanket SECURITY INVOKER conversion, GRANT, policy creation or index deletion.
commit;
