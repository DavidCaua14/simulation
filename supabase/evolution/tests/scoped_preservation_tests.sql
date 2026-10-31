do $$ declare r record;h text;n bigint;begin
 for r in select * from public._test_scoped_preservation order by name loop
 execute format('select md5(coalesce(string_agg(h,'''' order by h),'''')),count(*) from(select md5(to_jsonb(t)::text) h from public.%I t)x',r.name) into h,n;
 if h<>r.hash or n<>r.n then raise exception 'Preservation failed: %',r.name;end if;
 end loop;
 raise notice 'PASS all pre-existing table values preserved';
end $$;
