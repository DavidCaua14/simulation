create table public._test_base_reapply_balances as select id,coins,diamonds,bonus_energy,energy,xp from public.careers;
create table public._test_base_reapply_counts as select count(*) as n from public.base_card_compensations;
