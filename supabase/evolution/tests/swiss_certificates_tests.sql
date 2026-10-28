begin;
do $$
declare certificates jsonb;cert jsonb;templates jsonb;tpl jsonb;countries jsonb;slots text[];signature jsonb;n int:=0;r record;
begin
 select rules->'swiss_templates',rules->'swiss_certificates' into templates,certificates from public.sim_competitions where id='ucl';
 assert jsonb_array_length(certificates)>0,'Sem certificados de sorteio';
 select array_agg(x::text order by x) into slots from generate_series(1,36) x;
 for cert in select * from jsonb_array_elements(certificates) loop
  tpl:=templates->(cert->>'template')::int;
  select jsonb_object_agg(o::text,x) into countries from jsonb_array_elements_text(cert->'assignment') with ordinality t(x,o);
  assert public.sim_swiss_cost(slots,tpl,countries)=0,'Certificado com confronto nacional ou mais de dois adversários do mesmo país';
  with entries as(select (o-1)/9 as pot,x as country,count(*) as n from jsonb_array_elements_text(cert->'assignment') with ordinality t(x,o) group by 1,2),
  pots as(select pot,jsonb_object_agg(entries.country,entries.n) as counts from entries group by pot)
   select jsonb_agg(counts order by pot) into signature from pots;
  assert signature=cert->'signature','Certificado com distribuição incorreta de associações nos potes';
  for r in
   with edges as(select (m->>0)::int as round_no,(m->>1)::int as h,(m->>2)::int as a from jsonb_array_elements(tpl) m),
   sides as(select h as club,a as opponent,true as home,round_no from edges union all select a,h,false,round_no from edges)
   select club,count(*) as games,count(*) filter(where home) as homes,count(distinct round_no) as rounds,count(distinct opponent) as rivals from sides group by club
  loop
   assert r.games=8 and r.homes=4 and r.rounds=8 and r.rivals=8,'Modelo com repetição, sobreposição ou mando desequilibrado';
  end loop;
  n:=n+1;
 end loop;
 raise notice 'PASS todos os % sorteios certificados respeitam associações, rodadas e mandos',n;
end $$;
rollback;
