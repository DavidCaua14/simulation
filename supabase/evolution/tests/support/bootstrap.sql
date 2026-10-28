-- Apenas no PostgreSQL descartável de testes. Nunca executar em Supabase real.
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
create publication supabase_realtime;
create table public.careers (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 nickname text not null unique, photo_id text default 'photo-1', country text not null default 'BR', age int default 30,
 level int not null default 1, xp int not null default 0, skills jsonb default '{}', accessories jsonb default '[]',
 position text, jersey_number int, club_id text, status text not null default 'active', created_at timestamptz default now(),
 diamonds int not null default 0, coins int not null default 1000, energy int not null default 10
);
alter table public.careers enable row level security;
create policy own_careers on public.careers to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant usage on schema public to authenticated;
grant select, insert on public.careers to authenticated;
create function public.is_nickname_taken(check_nickname text) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.careers where nickname=check_nickname)
$$;
