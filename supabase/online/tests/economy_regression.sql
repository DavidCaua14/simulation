begin;
do $$
declare c public.on_clubs;k public.careers;j jsonb;b bigint;w int;
begin
 select x.* into c from on_clubs x join careers a on a.user_id=x.user_id and a.status='active' where a.coins>=60000 order by a.coins desc limit 1;
 if c.id is null then raise exception 'Conta de teste indisponível';end if;
 select * into k from careers where user_id=c.user_id order by (status='active') desc,created_at desc limit 1;
 b:=c.cash;w:=k.coins;
 perform set_config('request.jwt.claim.sub',c.user_id::text,true);
 begin
  j:=online_coins_convert(30000);
  j:=online_coins_convert(30000);
  if (j->>'cash')::bigint<>b+60000 or (select coins from careers where id=k.id)<>w-60000 then raise exception 'Falha aportes repetidos 1:1';end if;
  if not (j->'coins'->>'unlimited')::boolean or (j->'coins'->>'cap')::bigint-(j->'coins'->>'converted')::bigint<>w-60000 then raise exception 'Falha payload sem teto';end if;
  begin perform online_coins_convert(w);raise exception 'Falha saldo insuficiente';
  exception when others then if sqlerrm<>'Moedas insuficientes' then raise;end if;end;
  begin perform online_coins_convert(0);raise exception 'Falha quantidade inválida';
  exception when others then if sqlerrm<>'Quantidade inválida' then raise;end if;end;
  if (select coins from careers where id=k.id)<>w-60000 then raise exception 'Falha atomicidade';end if;
  raise exception 'TEST_ROLLBACK_OK';
 exception when others then if sqlerrm<>'TEST_ROLLBACK_OK' then raise;end if;
 end;
 if (select coins from careers where id=k.id)<>w or (select cash from on_clubs where id=c.id)<>b then raise exception 'Falha reversão testes';end if;
end $$;
select 'PASS: dois aportes de 30 mil, câmbio 1:1, sem teto, saldo insuficiente, validação e reversão integral' tests;
rollback;
