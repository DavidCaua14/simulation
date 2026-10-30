-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 43 (caixa de entrada, avisos com período e ações do painel no modo Temporadas). ROLLBACK.
begin;
alter table auth.users add column if not exists email text,add column if not exists created_at timestamptz default now(),add column if not exists last_sign_in_at timestamptz;
insert into auth.users(id,email) values('72727272-0000-0000-0000-000000000001','contatodavidcaua@gmail.com') on conflict (id) do update set email=excluded.email;
insert into public.admins(user_id) values('72727272-0000-0000-0000-000000000001') on conflict do nothing;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
declare car uuid:='31313131-0000-0000-0000-000000000011';r jsonb;p jsonb;item jsonb;coins0 int;own text;other text;cash0 bigint;rep0 numeric;
 as_admin jsonb:=jsonb_build_object('sub','72727272-0000-0000-0000-000000000001','email','contatodavidcaua@gmail.com','role','authenticated');
 as_player jsonb:=jsonb_build_object('sub','31313131-0000-0000-0000-000000000001','role','authenticated');
begin
 update public.cw_world set needs_sync=false where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 -- painel cria aviso ativo (com premiação), um agendado e manda premiação ao jogador
 perform set_config('request.jwt.claims',as_admin::text,true);perform set_config('request.jwt.claim.sub',as_admin->>'sub',true);
 perform public.admin_announcement_save(jsonb_build_object('title','Bem-vindo à nova temporada','body','Novidades no modo Temporadas.','starts_at',now()-interval '1 hour','ends_at',now()+interval '2 days','reward',jsonb_build_object('coins',300)));
 perform public.admin_announcement_save(jsonb_build_object('title','Aviso futuro','body','Ainda não começou.','starts_at',now()+interval '1 day','ends_at',now()+interval '3 days'));
 begin perform public.admin_announcement_save(jsonb_build_object('title','Errado','body','Fim antes do início','starts_at',now(),'ends_at',now()-interval '1 hour'));raise exception 'Aceitou fim antes do início';
 exception when raise_exception then if sqlerrm not like '%fim precisa%' then raise;end if;end;
 perform public.admin_player_grant(car,'diamonds',5,'Premiação do torneio');
 -- jogador: modal mostra o aviso ativo e a premiação; o agendado não aparece
 perform set_config('request.jwt.claims',as_player::text,true);perform set_config('request.jwt.claim.sub',as_player->>'sub',true);
 p:=public.inbox_pending();
 if jsonb_array_length(p)<>2 or exists(select 1 from jsonb_array_elements(p) e where e->>'title'='Aviso futuro') then raise exception 'Modal errado: %',p;end if;
 raise notice 'PASS modal mostra o aviso no período e a premiação; aviso futuro fica escondido';
 perform public.inbox_seen(p);
 if jsonb_array_length(public.inbox_pending())<>0 then raise exception 'Modal reaparece depois de visto';end if;
 r:=public.inbox_list();
 if (r->>'claimable')::int<>2 then raise exception 'Itens para resgatar: %',r->>'claimable';end if;
 select coins into coins0 from public.careers where id=car;
 for item in select * from jsonb_array_elements(r->'items') where (value->>'claimable')::boolean loop
  perform public.inbox_claim(item->>'type',item->>'id');perform public.inbox_claim(item->>'type',item->>'id');
 end loop;
 if (select coins from public.careers where id=car)<>coins0+300 then raise exception 'Resgate do aviso incorreto';end if;
 if (public.inbox_list()->>'claimable')::int<>0 then raise exception 'Resgate duplicado ou pendente';end if;
 raise notice 'PASS caixa de entrada: modal visto uma vez, premiações resgatadas uma única vez';

 -- painel: troca de clube, caixa e reputação geram comunicado ao jogador
 perform set_config('request.jwt.claims',as_admin::text,true);perform set_config('request.jwt.claim.sub',as_admin->>'sub',true);
 select c.club_id into other from public.cw_clubs c where c.career_id=car and c.club_id<>own and public.cw_region(c.club_id)=public.cw_region(own) order by c.club_id limit 1;
 r:=public.admin_career_set_club(car,other,'Teste de transferência');
 if r#>>'{coach,club_id}'<>other or r#>>'{coach,status}'<>'employed' then raise exception 'Troca de clube falhou: %',r->'coach';end if;
 select cash into cash0 from public.cw_clubs where career_id=car and club_id=other;
 perform public.admin_career_adjust(car,'cash',50000,'Investimento do patrocinador');
 if (select cash from public.cw_clubs where career_id=car and club_id=other)<>cash0+50000 then raise exception 'Caixa não ajustado';end if;
 select reputation into rep0 from public.mgr_coach where career_id=car;
 perform public.admin_career_adjust(car,'reputation',10,'Bônus de reputação');
 if (select reputation from public.mgr_coach where career_id=car)<>least(100,rep0+10) then raise exception 'Reputação não ajustada';end if;
 perform set_config('request.jwt.claims',as_player::text,true);perform set_config('request.jwt.claim.sub',as_player->>'sub',true);
 p:=public.inbox_pending();
 if (select count(*) from jsonb_array_elements(p) e where e->>'kind' in('club','finance','reputation'))<>3 then raise exception 'Comunicados das ações do painel: %',p;end if;
 if (public.mgr_hub()->'coach'->>'club_id')<>other then raise exception 'Hub do jogador não mostra o novo clube';end if;
 raise notice 'PASS troca de clube, caixa e reputação aparecem para o jogador em modal (%)',other;

 -- outro usuário não usa as ações do painel
 begin perform public.admin_career(car);raise exception 'Jogador acessou o painel';exception when insufficient_privilege then null;end;
 raise notice 'PASS ações do modo Temporadas só para o dono';
end $test$;
rollback;
