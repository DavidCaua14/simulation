-- Local validation only. Capture existing tables, excluding volatile ctid ordering changes from VACUUM.
create table public._test_scoped_preservation(name text primary key,hash text not null,n bigint not null);
do $$ declare r record;h text;n bigint;begin
 for r in select tablename from pg_tables where schemaname='public' and tablename<>'_test_scoped_preservation' order by tablename loop
 execute format('select md5(coalesce(string_agg(h,'''' order by h),'''')),count(*) from(select md5(to_jsonb(t)::text) h from public.%I t)x',r.tablename) into h,n;
 insert into public._test_scoped_preservation values(r.tablename,h,n);
 end loop;
end $$;
