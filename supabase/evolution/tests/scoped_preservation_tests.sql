do $$ declare r record;h text;n bigint;rs text[];begin
 for r in select * from public._test_scoped_preservation order by name loop
 execute format('select md5(coalesce(string_agg(h,'''' order by h),'''')),count(*),array_agg(h order by h) from(select md5((select jsonb_object_agg(k,v) from jsonb_each(to_jsonb(t)) e(k,v) where k=any($1))::text) h from public.%I t)x',r.name) into h,n,rs using r.cols;
 -- Catalog tables listed with row hashes may gain rows (e.g. a new difficulty profile); every original row must remain identical.
 if r.rows is not null then
  -- grow: catálogo pode ganhar linhas; shrink: limpeza (evolução 59) pode apagar linhas antigas. Em ambos, nenhuma linha muda.
  if r.mode='grow' and not (r.rows <@ coalesce(rs,'{}')) then raise exception 'Preservation failed: %',r.name;end if;
  if r.mode='shrink' and not (coalesce(rs,'{}') <@ r.rows) then raise exception 'Preservation failed: %',r.name;end if;
 elsif h<>r.hash or n<>r.n then raise exception 'Preservation failed: %',r.name;end if;
 end loop;
 raise notice 'PASS all pre-existing table values preserved';
end $$;
