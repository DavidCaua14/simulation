-- Catálogo: notas por posição guardadas de forma compacta (uma linha por atleta, com vetores),
-- no lugar de uma linha por atleta e posição. sim_player_pos_ratings vira view com as mesmas colunas.
-- A tabela antiga fica como sim_player_pos_ratings_old até o reinício, para conferência; depois sai.
begin;

create table if not exists public.sim_player_ratings(
 player_id text primary key references public.sim_players(id) on delete cascade,
 pos text[] not null,
 rating numeric(5,2)[] not null,
 eff numeric(5,2)[] not null);
alter table public.sim_player_ratings enable row level security;
revoke all on public.sim_player_ratings from anon,authenticated;

insert into public.sim_player_ratings(player_id,pos,rating,eff)
select player_id,array_agg(pos order by pos),array_agg(rating order by pos),array_agg(eff order by pos)
from public.sim_player_pos_ratings group by player_id
on conflict(player_id) do nothing;

alter table public.sim_player_pos_ratings rename to sim_player_pos_ratings_old;

create view public.sim_player_pos_ratings as
 select r.player_id,x.pos,x.rating,x.eff
 from public.sim_player_ratings r
 cross join lateral unnest(r.pos,r.rating,r.eff) as x(pos,rating,eff);

create or replace function public.sim_player_pos_ratings_trg() returns trigger
language plpgsql security definer set search_path=public as $$
declare r public.sim_player_ratings;i int;
begin
 if tg_op in('DELETE','UPDATE') then
  select * into r from public.sim_player_ratings where player_id=old.player_id for update;
  i:=array_position(r.pos,old.pos);
  if i is not null then
   if cardinality(r.pos)=1 then delete from public.sim_player_ratings where player_id=old.player_id;
   else
    update public.sim_player_ratings set pos=pos[:i-1]||pos[i+1:],rating=rating[:i-1]||rating[i+1:],eff=eff[:i-1]||eff[i+1:]
    where player_id=old.player_id;
   end if;
  end if;
  if tg_op='DELETE' then return old;end if;
 end if;
 select * into r from public.sim_player_ratings where player_id=new.player_id for update;
 if not found then
  insert into public.sim_player_ratings(player_id,pos,rating,eff) values(new.player_id,array[new.pos],array[new.rating],array[new.eff]);
 else
  i:=array_position(r.pos,new.pos);
  if i is null then
   update public.sim_player_ratings set pos=pos||new.pos,rating=rating||new.rating,eff=eff||new.eff where player_id=new.player_id;
  else
   update public.sim_player_ratings set rating[i]=new.rating,eff[i]=new.eff where player_id=new.player_id;
  end if;
 end if;
 return new;
end $$;
create trigger sim_player_pos_ratings_iud instead of insert or update or delete on public.sim_player_pos_ratings
 for each row execute function public.sim_player_pos_ratings_trg();
revoke all on public.sim_player_pos_ratings from anon,authenticated;
grant select on public.sim_player_pos_ratings to authenticated;

commit;
