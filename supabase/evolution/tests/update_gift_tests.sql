-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 35 (presente da atualização e avatares). Transação com ROLLBACK.
begin;
do $test$
declare r jsonb;lvl int;xp0 int;en int;newuid uuid:=gen_random_uuid();newcar uuid:=gen_random_uuid();
begin
 perform set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
 select level,xp,bonus_energy into lvl,xp0,en from public.careers where id='31313131-0000-0000-0000-000000000011';
 r:=public.release_gift_claim();
 if not (r->>'eligible')::boolean or not (r->>'show')::boolean then raise exception 'Testador sem presente: %',r;end if;
 if (select level*1000+xp from public.careers where id='31313131-0000-0000-0000-000000000011')<>lvl*1000+xp0+1000 then raise exception 'XP do presente incorreto';end if;
 if (select level from public.careers where id='31313131-0000-0000-0000-000000000011')<>lvl+1 then raise exception 'Não subiu de nível';end if;
 if (select bonus_energy from public.careers where id='31313131-0000-0000-0000-000000000011')<>en+20 then raise exception 'Energia do presente incorreta';end if;
 if (select count(*) from public.player_avatars where career_id='31313131-0000-0000-0000-000000000011' and source='release_gift')<>1 then raise exception 'Avatar não concedido';end if;
 raise notice 'PASS testador recebe +1000 XP (nível %→%), +20 energia e o avatar %',r->>'level_before',r->>'level_after',r#>>'{avatar,label}';
 r:=public.release_gift_claim();
 if (select bonus_energy from public.careers where id='31313131-0000-0000-0000-000000000011')<>en+20 or (select count(*) from public.player_avatars where career_id='31313131-0000-0000-0000-000000000011')<>1 then raise exception 'Presente dado duas vezes';end if;
 if not (r->>'show')::boolean then raise exception 'Novidades sumiram antes de serem vistas';end if;
 perform public.release_gift_seen();
 if (public.release_gift_claim()->>'show')::boolean then raise exception 'Novidades reaparecem depois de vistas';end if;
 raise notice 'PASS presente uma única vez; novidades até o jogador fechar';
 perform public.profile_set_avatar('avatar:'||(r#>>'{avatar,id}'));
 if (select avatar_data from public.player_profiles where career_id='31313131-0000-0000-0000-000000000011')<>'avatar:'||(r#>>'{avatar,id}') then raise exception 'Avatar ganho não virou foto';end if;
 begin perform public.profile_set_avatar('avatar:'||(select id from public.avatar_catalog where id<>r#>>'{avatar,id}' limit 1));raise exception 'Usou avatar que não tem';
 exception when raise_exception then if sqlerrm not like '%não tem este avatar%' then raise;end if;end;
 if jsonb_array_length(public.profile_me()->'avatars')<>1 then raise exception 'Perfil sem a lista de avatares';end if;
 raise notice 'PASS avatar ganho pode ser foto do perfil; avatar de outro não';
 -- conta criada depois da atualização não recebe nada
 insert into auth.users(id) values(newuid);
 insert into public.careers(id,user_id,nickname,club_id,country,age) values(newcar,newuid,'Novato','palmeiras','BR',25);
 perform set_config('request.jwt.claim.sub',newuid::text,true);
 r:=public.release_gift_claim();
 if (r->>'eligible')::boolean or exists(select 1 from public.player_avatars where career_id=newcar) or (select xp from public.careers where id=newcar)<>0 then raise exception 'Conta nova recebeu o presente';end if;
 raise notice 'PASS conta nova não recebe nem vê o presente';
end $test$;
rollback;
