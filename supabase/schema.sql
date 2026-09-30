-- Rode este arquivo inteiro uma vez em: Supabase → SQL Editor → New query.
-- Ele cria a tabela de carreiras/personagens, protege os dados por usuário
-- (Row Level Security) e cria uma função para checar nickname disponível
-- sem expor os dados de outros usuários.

create table if not exists public.careers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'retired')),
  nickname text not null,
  photo_id text not null,
  country text not null,
  age int not null check (age between 18 and 45),
  position text,
  jersey_number int,
  level int not null default 1,
  xp int not null default 0,
  skills jsonb not null default '{
    "finalizacao": 20, "passe": 20, "drible": 20,
    "defesa": 20, "fisico": 20, "velocidade": 20
  }'::jsonb,
  accessories jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

-- Nickname único (sem diferenciar maiúsculas/minúsculas), em toda a tabela.
create unique index if not exists careers_nickname_unique_idx
  on public.careers (lower(nickname));

-- Regra de negócio: só 1 carreira ATIVA por usuário ao mesmo tempo
-- (pode ter várias no total, encerradas/"retired").
create unique index if not exists careers_one_active_per_user_idx
  on public.careers (user_id)
  where (status = 'active');

alter table public.careers enable row level security;

-- Cada usuário só vê, cria e edita as PRÓPRIAS carreiras.
create policy "select_own_careers" on public.careers
  for select using (auth.uid() = user_id);

create policy "insert_own_careers" on public.careers
  for insert with check (auth.uid() = user_id);

create policy "update_own_careers" on public.careers
  for update using (auth.uid() = user_id);

-- Checagem de nickname disponível: precisa rodar "por fora" do RLS acima
-- (SECURITY DEFINER), porque o usuário logado não tem permissão de leitura
-- sobre as carreiras de outros usuários — só retorna true/false, nunca os
-- dados de quem já usa o nickname.
create or replace function public.is_nickname_taken(check_nickname text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.careers
    where lower(nickname) = lower(check_nickname)
  );
$$;

grant execute on function public.is_nickname_taken(text) to authenticated, anon;
