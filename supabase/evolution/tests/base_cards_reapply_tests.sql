do $$ begin
 if exists(select 1 from public._test_base_reapply_balances b join public.careers c on c.id=b.id
 where row(c.coins,c.diamonds,c.bonus_energy,c.energy,c.xp) is distinct from row(b.coins,b.diamonds,b.bonus_energy,b.energy,b.xp)) then raise exception 'Reaplicação duplicou recompensa';end if;
 if (select count(*) from public.base_card_compensations)<>(select n from public._test_base_reapply_counts) then raise exception 'Reaplicação duplicou auditoria';end if;
 raise notice 'PASS reaplicação sem compensação duplicada';
end $$;
