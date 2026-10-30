-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 42 (painel administrativo). Transação com ROLLBACK.
begin;
-- O auth.users local é simplificado; no Supabase estas colunas já existem.
alter table auth.users add column if not exists email text,add column if not exists created_at timestamptz default now(),add column if not exists last_sign_in_at timestamptz;
insert into auth.users(id,email) values('72727272-0000-0000-0000-000000000001','contatodavidcaua@gmail.com') on conflict (id) do update set email=excluded.email;
insert into public.admins(user_id) values('72727272-0000-0000-0000-000000000001') on conflict do nothing;
insert into public.admins(user_id) values('31313131-0000-0000-0000-000000000001') on conflict do nothing;
update auth.users set email='outro@example.com' where id='31313131-0000-0000-0000-000000000001';
do $test$
declare r jsonb;car uuid:='31313131-0000-0000-0000-000000000011';coins0 int;n int;
begin
 -- 1) outro usuário, mesmo estando em `admins`, é bloqueado
 perform set_config('request.jwt.claims',jsonb_build_object('sub','31313131-0000-0000-0000-000000000001','email','outro@example.com','role','authenticated')::text,true);
 perform set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
 begin perform public.admin_overview();raise exception 'Outro usuário acessou o painel';
 exception when insufficient_privilege then null;end;
 begin perform public.admin_player_grant(car,'coins',100,'teste');raise exception 'Outro usuário enviou moedas';
 exception when insufficient_privilege then null;end;
 if public.is_admin() then raise exception 'is_admin verdadeiro para outro e-mail';end if;
 raise notice 'PASS só o e-mail do dono acessa o painel (outro usuário bloqueado)';

 -- 2) dono: visão geral, busca, envio e aviso
 perform set_config('request.jwt.claims',jsonb_build_object('sub','72727272-0000-0000-0000-000000000001','email','contatodavidcaua@gmail.com','role','authenticated')::text,true);
 perform set_config('request.jwt.claim.sub','72727272-0000-0000-0000-000000000001',true);
 r:=public.admin_overview();
 if (r#>>'{users,total}')::int<1 or (r#>>'{database,size}')::bigint<=0 then raise exception 'Visão geral incompleta: %',r;end if;
 if jsonb_array_length(public.admin_players('',10))=0 then raise exception 'Busca de jogadores vazia';end if;
 select coins into coins0 from public.careers where id=car;
 r:=public.admin_player_grant(car,'coins',250,'Compensação de teste');
 if not exists(select 1 from public.player_notices where career_id=car and kind='reward' and (reward->>'coins')::int=250 and claimed_at is null) then raise exception 'Premiação não foi para a caixa de entrada: %',r;end if;
 begin perform public.admin_player_grant(car,'coins',10,'');raise exception 'Envio sem motivo aceito';
 exception when raise_exception then if sqlerrm not like '%motivo%' then raise;end if;end;
 r:=public.admin_broadcast('Manutenção amanhã','O jogo fica fora do ar das 3h às 4h.');
 select count(*) into n from public.announcements where title='Manutenção amanhã' and starts_at<=now() and ends_at>now();
 if n<>1 or (r->>'recipients')::int<1 then raise exception 'Aviso não chegou';end if;
 if jsonb_array_length(public.admin_actions_list(10))<2 then raise exception 'Registro de ações vazio';end if;
 raise notice 'PASS dono vê a visão geral, busca jogadores, envia premiação (com motivo) e avisa todos (% carreiras)',r->>'recipients';
end $test$;
rollback;
