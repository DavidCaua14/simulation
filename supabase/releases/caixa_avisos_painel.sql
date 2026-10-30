-- Gerado por scripts/build-editor-release.mjs a partir de 43_inbox_announcements_admin.sql: caixa de entrada, avisos e painel com modo Temporadas.
-- Requer o painel administrativo (supabase/releases/painel_admin.sql). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Feito para o jogo NO AR: não compara impressões digitais (os jogadores continuam jogando durante a instalação).
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('43_inbox_announcements_admin.sql'));
 if to_regprocedure('public.admin_overview()') is null then raise exception 'Requer o painel administrativo (supabase/releases/painel_admin.sql); nada foi alterado';end if;
 

-- ===================== 43_inbox_announcements_admin.sql =====================
create table if not exists public.announcements(
 id uuid primary key default gen_random_uuid(),title text not null,body text not null,
 starts_at timestamptz not null,ends_at timestamptz not null,reward jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),created_by uuid,cancelled_at timestamptz,
 check (ends_at>starts_at));
create table if not exists public.announcement_reads(
 announcement_id uuid not null references public.announcements(id) on delete cascade,career_id uuid not null references public.careers(id) on delete cascade,
 seen_at timestamptz,claimed_at timestamptz,primary key(announcement_id,career_id));
create table if not exists public.player_notices(
 id bigint generated always as identity primary key,career_id uuid not null references public.careers(id) on delete cascade,
 kind text not null check (kind in('reward','club','finance','reputation','removal','info')),
 title text not null,body text not null,reward jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),seen_at timestamptz,claimed_at timestamptz);
create index if not exists player_notices_career_idx on public.player_notices(career_id,created_at desc);
create index if not exists announcements_period_idx on public.announcements(starts_at,ends_at);
alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;
alter table public.player_notices enable row level security;
revoke all on public.announcements,public.announcement_reads,public.player_notices from public,anon,authenticated;

-- Número no formato brasileiro (1.234.567).
create or replace function public.fmt_br(n numeric)
returns text language sql immutable as $$ select replace(to_char(n,'FM999,999,999,999'),',','.') $$;

-- Premiação válida: moedas, diamantes e/ou energia bônus, inteiros positivos.
create or replace function public.inbox_reward_clean(p jsonb)
returns jsonb language sql immutable as $$
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from(
  select k,to_jsonb(least(1000000,greatest(0,(p->>k)::numeric))::int) v from unnest(array['coins','diamonds','bonus_energy']) k
  where p ? k and (p->>k) ~ '^\d+(\.\d+)?$' and (p->>k)::numeric>0) x
$$;

create or replace function public.inbox_reward_text(p jsonb)
returns text language sql immutable as $$
 select nullif(concat_ws(' · ',
  case when (p->>'coins')::int>0 then to_char((p->>'coins')::int,'FM999G999G999')||' moedas' end,
  case when (p->>'diamonds')::int>0 then (p->>'diamonds')||' diamantes' end,
  case when (p->>'bonus_energy')::int>0 then (p->>'bonus_energy')||' de energia' end),'')
$$;

-- ---------- jogador ----------
create or replace function public.inbox_list()
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();
begin
 if car is null then return jsonb_build_object('items','[]'::jsonb,'unread',0,'claimable',0);end if;
 return(with items as(
   select 'announcement' as type,a.id::text as id,'announcement' as kind,a.title,a.body,a.reward,a.starts_at as at,a.ends_at,
    r.seen_at,r.claimed_at,(a.reward<>'{}'::jsonb and r.claimed_at is null) as claimable
   from public.announcements a left join public.announcement_reads r on r.announcement_id=a.id and r.career_id=car
   where a.cancelled_at is null and a.starts_at<=now() and a.ends_at>now()
   union all
   select 'notice',n.id::text,n.kind,n.title,n.body,n.reward,n.created_at,null,n.seen_at,n.claimed_at,(n.reward<>'{}'::jsonb and n.claimed_at is null)
   from public.player_notices n where n.career_id=car and (n.created_at>now()-interval '60 days' or (n.reward<>'{}'::jsonb and n.claimed_at is null)))
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i) order by i.at desc) from items i),'[]'::jsonb),
   'unread',(select count(*) from items where seen_at is null),'claimable',(select count(*) from items where claimable)));
end $$;

-- Itens que abrem em modal na tela inicial: avisos ativos e comunicados ainda não vistos.
create or replace function public.inbox_pending()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb:=public.inbox_list();
begin
 return coalesce((select jsonb_agg(e order by e->>'at') from jsonb_array_elements(r->'items') e where e->>'seen_at' is null),'[]'::jsonb);
end $$;

create or replace function public.inbox_seen(p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();e jsonb;
begin
 if car is null then return jsonb_build_object('ok',false);end if;
 for e in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) limit 100 loop
  if e->>'type'='announcement' then
   insert into public.announcement_reads(announcement_id,career_id,seen_at) select a.id,car,now() from public.announcements a where a.id::text=e->>'id'
   on conflict(announcement_id,career_id) do update set seen_at=coalesce(announcement_reads.seen_at,now());
  elsif e->>'type'='notice' then
   update public.player_notices set seen_at=coalesce(seen_at,now()) where career_id=car and id::text=e->>'id';
  end if;
 end loop;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.inbox_claim(p_type text,p_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();rw jsonb;k text;a public.announcements;n public.player_notices;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 perform 1 from public.careers where id=car for update;
 if p_type='announcement' then
  select * into a from public.announcements where id::text=p_id and cancelled_at is null and starts_at<=now() and ends_at>now();
  if not found then raise exception 'Aviso encerrado';end if;
  if exists(select 1 from public.announcement_reads where announcement_id=a.id and career_id=car and claimed_at is not null) then
   return jsonb_build_object('ok',true,'replayed',true,'reward',a.reward);end if;
  rw:=a.reward;
  insert into public.announcement_reads(announcement_id,career_id,seen_at,claimed_at) values(a.id,car,now(),now())
  on conflict(announcement_id,career_id) do update set claimed_at=now(),seen_at=coalesce(announcement_reads.seen_at,now());
 elsif p_type='notice' then
  select * into n from public.player_notices where id::text=p_id and career_id=car for update;
  if not found then raise exception 'Mensagem não encontrada';end if;
  if n.claimed_at is not null then return jsonb_build_object('ok',true,'replayed',true,'reward',n.reward);end if;
  rw:=n.reward;
  update public.player_notices set claimed_at=now(),seen_at=coalesce(seen_at,now()) where id=n.id;
 else raise exception 'Item inválido';end if;
 if rw='{}'::jsonb then raise exception 'Este item não tem premiação';end if;
 for k in select jsonb_object_keys(rw) loop
  perform public.econ_apply(car,k,(rw->>k)::int,'inbox_reward',p_type||':'||p_id);
 end loop;
 return jsonb_build_object('ok',true,'replayed',false,'reward',rw);
end $$;

-- ---------- painel: comunicados e avisos ----------
create or replace function public.admin_notify(p_career uuid,p_kind text,p_title text,p_body text,p_reward jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare id bigint;
begin
 insert into public.player_notices(career_id,kind,title,body,reward) values(p_career,p_kind,left(p_title,120),left(p_body,2000),public.inbox_reward_clean(p_reward)) returning player_notices.id into id;
 return id;
end $$;

-- Premiação (positivo) vai para a caixa de entrada; retirada (negativo) vale na hora. Os dois geram comunicado.
create or replace function public.admin_player_grant(p_career uuid,p_currency text,p_amount int,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare label text;
begin
 perform public.admin_assert();
 if p_currency not in('coins','diamonds','bonus_energy') then raise exception 'Escolha moedas, diamantes ou energia.';end if;
 if p_amount is null or p_amount=0 or abs(p_amount)>1000000 then raise exception 'Valor inválido (até 1.000.000).';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 if not exists(select 1 from public.careers where id=p_career and status='active') then raise exception 'Jogador não encontrado.';end if;
 label:=case p_currency when 'coins' then 'moedas' when 'diamonds' then 'diamantes' else 'de energia' end;
 if p_amount>0 then
  perform public.admin_notify(p_career,'reward','Você recebeu uma premiação',trim(p_reason),jsonb_build_object(p_currency,p_amount));
 else
  perform public.econ_apply(p_career,p_currency,p_amount,'admin_grant','admin:'||gen_random_uuid());
  perform public.admin_notify(p_career,'removal','Ajuste na sua carteira',
   'Foram retirados '||public.fmt_br(abs(p_amount))||' '||label||'. Motivo: '||trim(p_reason));
 end if;
 insert into public.admin_actions(admin_id,action,career_id,detail)
 values(auth.uid(),'grant',p_career,jsonb_build_object('currency',p_currency,'amount',p_amount,'reason',left(trim(p_reason),200),'inbox',p_amount>0));
 return(select jsonb_build_object('coins',coins,'diamonds',diamonds,'bonus_energy',bonus_energy,'inbox',p_amount>0) from public.careers where id=p_career);
end $$;

create or replace function public.admin_announcement_save(p jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.announcements;rw jsonb:=public.inbox_reward_clean(coalesce(p->'reward','{}'::jsonb));s timestamptz;e timestamptz;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p->>'title','')))<3 or length(trim(coalesce(p->>'body','')))<3 then raise exception 'Preencha título e mensagem.';end if;
 s:=(p->>'starts_at')::timestamptz;e:=(p->>'ends_at')::timestamptz;
 if s is null or e is null or e<=s then raise exception 'O fim precisa ser depois do início.';end if;
 if p->>'id' is not null then
  update public.announcements set title=left(trim(p->>'title'),120),body=left(trim(p->>'body'),2000),starts_at=s,ends_at=e,reward=rw
   where id=(p->>'id')::uuid and cancelled_at is null returning * into a;
  if not found then raise exception 'Aviso não encontrado.';end if;
 else
  insert into public.announcements(title,body,starts_at,ends_at,reward,created_by) values(left(trim(p->>'title'),120),left(trim(p->>'body'),2000),s,e,rw,auth.uid()) returning * into a;
 end if;
 insert into public.admin_actions(admin_id,action,detail) values(auth.uid(),'announcement',jsonb_build_object('title',a.title,'starts_at',a.starts_at,'ends_at',a.ends_at,'reward',a.reward));
 return to_jsonb(a);
end $$;

create or replace function public.admin_announcement_cancel(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 perform public.admin_assert();
 update public.announcements set cancelled_at=now() where id=p_id and cancelled_at is null;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.admin_announcements()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.admin_assert();
 return(select coalesce(jsonb_agg(x order by x.starts_at desc),'[]') from(
  select a.*,case when a.cancelled_at is not null then 'cancelled' when a.ends_at<=now() then 'ended' when a.starts_at>now() then 'scheduled' else 'live' end as state,
   (select count(*) from public.announcement_reads r where r.announcement_id=a.id and r.seen_at is not null) as seen,
   (select count(*) from public.announcement_reads r where r.announcement_id=a.id and r.claimed_at is not null) as claimed
  from public.announcements a order by a.starts_at desc limit 100) x);
end $$;

-- Aviso imediato para todos (mantido): vira um aviso de 7 dias.
create or replace function public.admin_broadcast(p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a jsonb;
begin
 a:=public.admin_announcement_save(jsonb_build_object('title',p_title,'body',p_body,'starts_at',now(),'ends_at',now()+interval '7 days'));
 return jsonb_build_object('recipients',(select count(*) from public.careers where status='active'),'announcement',a);
end $$;

-- ---------- painel: modo Temporadas ----------
create or replace function public.admin_career(p_career uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.careers;mc public.mgr_coach;w public.cw_world;
begin
 perform public.admin_assert();
 select * into c from public.careers where id=p_career;
 if not found then raise exception 'Jogador não encontrado.';end if;
 select * into mc from public.mgr_coach where career_id=p_career;
 select * into w from public.cw_world where career_id=p_career;
 return jsonb_build_object(
  'career',jsonb_build_object('id',c.id,'nickname',c.nickname,'level',c.level,'xp',c.xp,'coins',c.coins,'diamonds',c.diamonds,'energy',c.energy,'bonus_energy',c.bonus_energy,'created_at',c.created_at),
  'email',(select email from auth.users where id=c.user_id),
  'coach',case when mc.career_id is null then null else jsonb_build_object('status',mc.status,'club_id',mc.club_id,'reputation',round(mc.reputation,1),
   'board',round(mc.board_confidence),'fans',round(mc.fan_mood),'matches',mc.matches,'wins',mc.wins,'draws',mc.draws,'losses',mc.losses,'titles',mc.titles,'fired',mc.fired_count) end,
  'world',case when w.career_id is null then null else jsonb_build_object('today',w.today,'started_on',w.started_on,'needs_sync',w.needs_sync) end,
  'club',(select jsonb_build_object('club_id',cl.club_id,'cash',cl.cash,'debt',cl.debt,'infrastructure',cl.infrastructure,'payroll',public.cw_payroll(p_career,cl.club_id),
    'squad',(select count(*) from public.mgr_players mp where mp.career_id=p_career and mp.club_id=cl.club_id))
   from public.cw_clubs cl where cl.career_id=p_career and cl.club_id=mc.club_id),
  'live_match',exists(select 1 from public.mgr_matches m where m.career_id=p_career and m.status='live' and m.user_side is not null),
  'clubs',(select coalesce(jsonb_agg(jsonb_build_object('id',sc.id,'name',sc.name,'tier',sc.tier,'region',public.cw_region(sc.id)) order by public.cw_region(sc.id),sc.tier,sc.name),'[]')
   from public.cw_clubs cl join public.sim_clubs sc on sc.id=cl.club_id where cl.career_id=p_career and sc.tier<>'foreign'),
  'notices',(select coalesce(jsonb_agg(n order by n.created_at desc),'[]') from(select kind,title,created_at,seen_at,claimed_at,reward from public.player_notices where career_id=p_career order by created_at desc limit 8) n));
end $$;

-- Leva o técnico para um clube (como se tivesse aceitado uma proposta), sem mexer em resultados já disputados.
create or replace function public.admin_career_set_club(p_career uuid,p_club text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;c public.mgr_coach;sid uuid;spell uuid;salary bigint;old text;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 perform 1 from public.careers where id=p_career for update;
 select * into w from public.cw_world where career_id=p_career;
 if not found then raise exception 'Este jogador ainda não entrou no modo Temporadas.';end if;
 if not exists(select 1 from public.cw_clubs where career_id=p_career and club_id=p_club) then raise exception 'Clube inválido.';end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'O jogador está com uma partida em andamento. Tente depois.';end if;
 if w.needs_sync then raise exception 'O calendário do jogador está atualizando resultados. Tente em instantes.';end if;
 select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id
  where ws.career_id=p_career and ws.region=public.cw_region(p_club) and s.status='active' order by ws.starts_on limit 1;
 if sid is null then raise exception 'A temporada desse país ainda não começou no mundo do jogador.';end if;
 select * into c from public.mgr_coach where career_id=p_career;
 if c.club_id=p_club and c.status='employed' then raise exception 'O jogador já treina esse clube.';end if;
 old:=c.club_id;
 if c.status='employed' then perform public.mgr_end_spell(p_career,'left');end if;
 perform public.cw_promote_season(p_career,sid,p_club);spell:=public.mgr_start_spell(p_career,p_club);
 select coalesce(monthly_salary,150) into salary from public.cw_coach where career_id=p_career;
 update public.cw_coach set contract_until=(w.today+interval '2 years')::date where career_id=p_career;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
  values(p_career,spell,p_club,w.today,(w.today+interval '2 years')::date,coalesce(salary,150));
 update public.season_offers set status='expired',responded_at=now() where career_id=p_career and kind='coach' and status='pending';
 perform public.cw_news_add(p_career,'admin-club:'||spell,'job',public.mgr_club_name(p_club)||' anuncia novo treinador','Contrato por 2 anos. A temporada e os resultados existentes continuam.',98,p_club);
 perform public.admin_notify(p_career,'club','Você é o novo treinador do '||public.mgr_club_name(p_club),
  coalesce('Você deixou o '||public.mgr_club_name(old)||'. ','')||'Contrato de 2 anos; a temporada continua de onde está. Motivo: '||trim(p_reason));
 insert into public.admin_actions(admin_id,action,career_id,detail) values(auth.uid(),'set_club',p_career,jsonb_build_object('from',old,'to',p_club,'reason',left(trim(p_reason),200)));
 return public.admin_career(p_career);
end $$;

-- Ajusta o caixa do clube atual do jogador ou a reputação do técnico.
create or replace function public.admin_career_adjust(p_career uuid,p_field text,p_amount numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare mc public.mgr_coach;cur bigint;delta bigint;rep numeric;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 if p_amount is null or p_amount=0 then raise exception 'Valor inválido.';end if;
 select * into mc from public.mgr_coach where career_id=p_career;
 if mc.career_id is null or not exists(select 1 from public.cw_world where career_id=p_career) then raise exception 'Este jogador ainda não entrou no modo Temporadas.';end if;
 if p_field='cash' then
  if mc.status<>'employed' or mc.club_id is null then raise exception 'O jogador está sem clube.';end if;
  if abs(p_amount)>100000000 then raise exception 'Valor acima do limite.';end if;
  select cash into cur from public.cw_clubs where career_id=p_career and club_id=mc.club_id;
  delta:=greatest(round(p_amount)::bigint,-cur);
  perform public.cw_cash(p_career,mc.club_id,delta,'admin_adjust','admin:'||gen_random_uuid(),'Ajuste da administração: '||left(trim(p_reason),120));
  perform public.admin_notify(p_career,'finance',case when delta>0 then 'Reforço no caixa do clube' else 'Ajuste no caixa do clube' end,
   public.mgr_club_name(mc.club_id)||(case when delta>0 then ' recebeu ' else ' teve retirado ' end)||public.fmt_br(abs(delta))||' moedas no caixa. Motivo: '||trim(p_reason));
 elsif p_field='reputation' then
  rep:=greatest(0,least(100,coalesce(mc.reputation,0)+p_amount));
  update public.mgr_coach set reputation=rep where career_id=p_career;
  perform public.admin_notify(p_career,'reputation','Sua reputação mudou',
   'Reputação de treinador: '||round(coalesce(mc.reputation,0))||' → '||round(rep)||'. Isso muda as propostas que você recebe. Motivo: '||trim(p_reason));
 else raise exception 'Campo inválido.';end if;
 insert into public.admin_actions(admin_id,action,career_id,detail) values(auth.uid(),'adjust',p_career,jsonb_build_object('field',p_field,'amount',p_amount,'reason',left(trim(p_reason),200)));
 return public.admin_career(p_career);
end $$;

-- ---------- painel: visão geral completa ----------
create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.admin_assert();
 return jsonb_build_object(
  'now',now(),
  'users',jsonb_build_object(
   'total',(select count(*) from auth.users),
   'new_7d',(select count(*) from auth.users where created_at>now()-interval '7 days'),
   'active_24h',(select count(*) from auth.users where last_sign_in_at>now()-interval '1 day'),
   'active_7d',(select count(*) from auth.users where last_sign_in_at>now()-interval '7 days'),
   'signups',(select coalesce(jsonb_agg(jsonb_build_object('day',d::date,'n',(select count(*) from auth.users u where u.created_at::date=d::date)) order by d),'[]')
     from generate_series((now()-interval '13 days')::date,now()::date,interval '1 day') d)),
  'careers',jsonb_build_object(
   'total',(select count(*) from public.careers where status='active'),
   'seasons',(select count(*) from public.cw_world),
   'employed',(select count(*) from public.mgr_coach mc join public.cw_world w using(career_id) where mc.status='employed'),
   'unemployed',(select count(*) from public.mgr_coach mc join public.cw_world w using(career_id) where mc.status<>'employed'),
   'avg_level',(select round(avg(level),1) from public.careers where status='active'),
   'coins',(select coalesce(sum(coins),0) from public.careers where status='active'),
   'diamonds',(select coalesce(sum(diamonds),0) from public.careers where status='active'),
   'top_clubs',(select coalesce(jsonb_agg(x order by x.n desc),'[]') from(select mc.club_id,count(*) n from public.mgr_coach mc join public.cw_world w using(career_id)
     where mc.status='employed' group by mc.club_id order by count(*) desc limit 5) x),
   'top_players',(select coalesce(jsonb_agg(x),'[]') from(select c.nickname,c.level,mc.club_id,mc.titles,round(mc.reputation,1) reputation from public.careers c
     left join public.mgr_coach mc on mc.career_id=c.id where c.status='active' order by c.level desc,c.xp desc limit 5) x)),
  'matches',jsonb_build_object(
   'today',(select count(*) from public.season_fixtures where player_match and played_at>now()-interval '1 day'),
   'week',(select count(*) from public.season_fixtures where player_match and played_at>now()-interval '7 days')),
  'economy',jsonb_build_object(
   'in_7d',(select coalesce(sum(delta),0) from public.wallet_ledger where currency='coins' and delta>0 and created_at>now()-interval '7 days'),
   'out_7d',(select coalesce(-sum(delta),0) from public.wallet_ledger where currency='coins' and delta<0 and created_at>now()-interval '7 days'),
   'reasons',(select coalesce(jsonb_agg(x order by x.total desc),'[]') from(select reason,sum(delta) total,count(*) n from public.wallet_ledger
     where currency='coins' and created_at>now()-interval '7 days' group by reason order by abs(sum(delta)) desc limit 6) x),
   'shop_7d',(select count(*) from public.shop_purchases where created_at>now()-interval '7 days')),
  'events',jsonb_build_object(
   'live',(select count(*) from public.events where status='published' and starts_at<=now() and (ends_at is null or ends_at>now())),
   'scheduled',(select count(*) from public.events where status='published' and starts_at>now()),
   'drafts',(select count(*) from public.events where status='draft'),
   'completions_7d',(select count(*) from public.event_completions where completed_at>now()-interval '7 days'),
   'claims_7d',(select count(*) from public.event_completions where claimed_at>now()-interval '7 days')),
  'announcements',jsonb_build_object(
   'live',(select count(*) from public.announcements where cancelled_at is null and starts_at<=now() and ends_at>now()),
   'scheduled',(select count(*) from public.announcements where cancelled_at is null and starts_at>now()),
   'unclaimed_rewards',(select count(*) from public.player_notices where reward<>'{}'::jsonb and claimed_at is null)),
  'database',jsonb_build_object(
   'size',pg_database_size(current_database()),'limit',500*1024*1024,
   'tables',(select coalesce(jsonb_agg(t order by t.bytes desc),'[]') from(
     select s.schemaname||'.'||s.relname as name,pg_total_relation_size(s.relid) as bytes,s.n_live_tup as rows
     from pg_stat_user_tables s order by pg_total_relation_size(s.relid) desc limit 8) t)),
  'recent',(select coalesce(jsonb_agg(a order by a.at desc),'[]') from(
    select x.at,x.action,x.detail,c.nickname from public.admin_actions x left join public.careers c on c.id=x.career_id order by x.at desc limit 8) a));
end $$;

revoke all on function public.fmt_br(numeric),public.inbox_reward_clean(jsonb),public.inbox_reward_text(jsonb),public.admin_notify(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.inbox_list(),public.inbox_pending(),public.inbox_seen(jsonb),public.inbox_claim(text,text),
 public.admin_player_grant(uuid,text,int,text),public.admin_announcement_save(jsonb),public.admin_announcement_cancel(uuid),public.admin_announcements(),
 public.admin_broadcast(text,text),public.admin_career(uuid),public.admin_career_set_club(uuid,text,text),public.admin_career_adjust(uuid,text,numeric,text),
 public.admin_overview() from public,anon;
grant execute on function public.inbox_list(),public.inbox_pending(),public.inbox_seen(jsonb),public.inbox_claim(text,text),
 public.admin_player_grant(uuid,text,int,text),public.admin_announcement_save(jsonb),public.admin_announcement_cancel(uuid),public.admin_announcements(),
 public.admin_broadcast(text,text),public.admin_career(uuid),public.admin_career_set_club(uuid,text,text),public.admin_career_adjust(uuid,text,numeric,text),
 public.admin_overview() to authenticated;
perform pg_notify('pgrst','reload schema');


 if to_regprocedure('public.inbox_list()') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: caixa de entrada, avisos e painel com modo Temporadas; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.inbox_list()') is not null then 'Instalação concluída: caixa de entrada, avisos e painel com modo Temporadas; dados dos usuários preservados.' else 'Não instalado' end as resultado;
