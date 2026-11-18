-- MODO ONLINE — Fase 33: condição (setas), estilos de jogo e ficha completa de atributos.
--
-- Inspirado no PES 2014 / eFootball (só no modo online):
--  • CONDIÇÃO: cada jogador entra em campo com uma seta (1 vermelha ↓, 2 laranja ↘, 3 amarela →, 4 verde ↗, 5 azul ↑)
--    que soma ou tira pontos de todos os atributos naquela partida (on_arrow_delta).
--    A seta muda ao fim de cada partida do clube, para o jogo seguinte (on_arrow_next). Depende da "regularidade":
--      B — lendas: só amarela, verde ou azul;
--      C — os demais: qualquer seta (sorteio), puxada para cima por boa nota e vitória, para baixo por nota ruim.
--    Quem estava muito bem (azul) ou muito mal (vermelha) tende a voltar ao meio, como no PES.
--  • ESTILOS DE JOGO: estilo ofensivo + estilo defensivo + até dois estilos da IA, escolhidos pela posição e pelos
--    atributos do próprio jogador (on_style_pick). No motor mudam o peso do jogador no ataque, na defesa e na criação
--    (on_styles.aw/dw/cw/drain) e somam aderência ao plano de jogo quando combinam com ele (on_styles.plans).
--  • FICHA: 26 atributos derivados dos 11 do motor (on_sheet), um valor por atributo (nível com o treino feito).
--    Coerência: Chute colocado e Curva saem de finalização e criação; Salto de cabeceio e força; e assim por diante.

alter table public.on_players add column if not exists form char(1) not null default 'C' check (form in('A','B','C','D','E'));
alter table public.on_players add column if not exists arrow smallint not null default 3 check (arrow between 1 and 5);
alter table public.on_players add column if not exists style_off text;
alter table public.on_players add column if not exists style_def text;
alter table public.on_players add column if not exists ai_styles text[] not null default '{}';
alter table public.on_match_players add column if not exists arrow smallint not null default 3;
alter table public.on_match_players add column if not exists s_aw numeric(4,2) not null default 1;
alter table public.on_match_players add column if not exists s_dw numeric(4,2) not null default 1;
alter table public.on_match_players add column if not exists s_cw numeric(4,2) not null default 1;
alter table public.on_match_players add column if not exists s_dr numeric(4,2) not null default 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- Catálogo de estilos (nome em português na tela; en guarda o original do eFootball, só para referência)
-- kind: off (com a bola), def (sem a bola), ai (tendência da IA). pos: posições em que o estilo existe.
-- aw/dw/cw/drain: multiplicam o peso do jogador no ataque, na defesa, na criação e o desgaste.
-- plans: planos de jogo que o estilo ajuda a executar (aderência).
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.on_styles(
 code text primary key,
 kind text not null check (kind in('off','def','ai')),
 name text not null,
 en text not null,
 descr text not null,
 pos text[] not null,
 aw numeric(4,2) not null default 1,
 dw numeric(4,2) not null default 1,
 cw numeric(4,2) not null default 1,
 drain numeric(4,2) not null default 1,
 plans text[] not null default '{}',
 bump jsonb not null default '{}'::jsonb -- estilos da IA: pontos somados a atributos do motor (ex.: {"pace":3})
);
alter table public.on_styles enable row level security;
revoke all on public.on_styles from anon,authenticated;

insert into public.on_styles(code,kind,name,en,descr,pos,aw,dw,cw,drain,plans,bump) values
-- goleiros
('gk_build','off','Goleiro construtor','Build-Up Goalkeeper','Participa da saída de bola com passes curtos.','{GOL}',1,1,1.15,1,'{posse}','{}'),
('gk_off','def','Goleiro ofensivo','Offensive Goalkeeper','Sai do gol para cortar lançamentos e antecipar atacantes.','{GOL}',1,1,1,1,'{pressao,total}','{}'),
('gk_def','def','Goleiro defensivo','Defensive Goalkeeper','Fica perto da linha do gol e prioriza defesas e posicionamento.','{GOL}',1,1,1,1,'{retranca}','{}'),
('gk_sweeper','def','Goleiro-líbero','Sweeper GK','Joga adiantado para cortar bolas nas costas da defesa.','{GOL}',1,1,1,1,'{pressao,contra}','{}'),
-- zagueiros e laterais (com a bola)
('build_up','off','Zagueiro construtor','Build Up','Participa da saída de bola com passes e movimentação.','{ZAG}',1,1,1.18,1,'{posse}','{}'),
('extra_frontman','off','Zagueiro elemento-surpresa','Extra Frontman','Avança ao ataque de vez em quando e vira mais uma opção.','{ZAG}',1.6,0.95,1,1.04,'{total,direto}','{}'),
('off_fullback','off','Lateral ofensivo','Offensive Full-back','Sobe o tempo todo pelo corredor para apoiar o ataque.','{LD,LE}',1.25,0.92,1.05,1.05,'{pontas,total}','{}'),
('fb_finisher','off','Lateral finalizador','Full-back Finisher','Corta para o meio e participa das jogadas por dentro.','{LD,LE}',1.3,0.93,1,1.04,'{total}','{}'),
-- meio-campo (com a bola)
('orchestrator','off','Organizador','Orchestrator','Controla o ritmo do jogo com passes e distribuição.','{VOL,MC}',0.95,1,1.18,1,'{posse}','{}'),
('box_to_box','off','Meia de área a área','Box-to-Box','Percorre o campo todo, ajudando no ataque e na defesa.','{VOL,MC}',1.12,1.08,1,1.1,'{pressao,total}','{}'),
('hole_player','off','Infiltração','Hole Player','Infiltra nos espaços vazios e chega à área para finalizar.','{MC,MEI,PD,PE,ATA}',1.18,0.9,1,1.02,'{contra,total}','{}'),
('creative','off','Armador criativo','Creative Playmaker','Se movimenta para receber e cria chances para os companheiros.','{MEI,PD,PE}',1.05,1,1.12,1,'{posse}','{}'),
('classic10','off','Camisa 10 clássico','Classic No. 10','Organiza o ataque com visão de jogo e passe, e corre pouco sem a bola.','{MEI}',1,0.88,1.18,0.95,'{posse}','{}'),
('dummy_runner','off','Abre-espaços','Dummy Runner','Corre sem a bola para arrastar marcadores e abrir espaço para os outros.','{MEI,ATA}',1,1,1.08,1.03,'{total,contra}','{}'),
-- pontas e ataque (com a bola)
('prolific_winger','off','Ponta veloz','Prolific Winger','Usa a largura do campo para atacar a defesa em velocidade.','{PD,PE}',1.12,1,1,1.03,'{pontas,contra}','{}'),
('roaming_flank','off','Ponta que corta para dentro','Roaming Flank','Sai da lateral e procura espaço por dentro para criar ou finalizar.','{PD,PE}',1.14,1,1.03,1,'{total}','{}'),
('cross_specialist','off','Especialista em cruzamentos','Cross Specialist','Mantém a amplitude e cruza na área.','{PD,PE}',0.95,1,1.12,1,'{pontas}','{}'),
('goal_poacher','off','Artilheiro','Goal Poacher','Corre nas costas da defesa para receber em profundidade.','{ATA}',1.14,0.85,1,1,'{contra,direto}','{}'),
('fox_in_box','off','Matador da área','Fox in the Box','Se posiciona na área para aproveitar cruzamentos, rebotes e passes curtos.','{ATA}',1.12,0.85,1,0.95,'{pontas}','{}'),
('target_man','off','Pivô','Target Man','Centroavante de referência: protege a bola, disputa o lançamento e serve os companheiros.','{ATA}',1.04,1,1.08,1,'{direto}','{}'),
('deep_lying','off','Atacante recuado','Deep-Lying Forward','Recua para receber e ligar o meio-campo ao ataque.','{ATA}',0.92,1,1.15,1,'{posse}','{}'),
-- sem a bola
('destroyer','def','Destruidor','The Destroyer','Marca forte e busca o desarme o tempo todo.','{ZAG,LD,LE,VOL,MC}',1,1.1,1,1.04,'{pressao,retranca}','{}'),
('high_line','def','Mestre da linha alta','High Line Master','Organiza a linha defensiva e controla a profundidade.','{ZAG,LD,LE}',1,1.04,1,1,'{pressao}','{}'),
('covering','def','Cobertura','Covering Role','Cobre os espaços deixados pelos companheiros.','{ZAG,LD,LE,VOL,MC}',0.95,1.06,1,1,'{retranca}','{}'),
('def_fullback','def','Lateral defensivo','Defensive Full-back','Evita subir demais e protege a defesa.','{LD,LE}',0.8,1.12,1,0.97,'{retranca}','{}'),
('anchor','def','Volante âncora','Anchor Man','Fica à frente da zaga e protege os zagueiros.','{VOL}',0.8,1.15,1,0.97,'{retranca}','{}'),
('all_action','def','Defensor incansável','All Action Defender','Volta rápido e cobre várias regiões do campo.','{VOL,MC}',1,1.08,1,1.08,'{retranca,pressao}','{}'),
('pass_disruptor','def','Interceptador','Pass Disruptor','Antecipa passes e fecha as linhas de passe do rival.','{VOL,MC,MEI}',1,1.05,1.04,1,'{pressao}','{}'),
('shadow_marker','def','Marcador sombra','Shadow Marker','Acompanha de perto um adversário.','{ZAG,LD,LE,VOL,MC}',1,1.08,1,1.03,'{retranca}','{}'),
('front_pressure','def','Pressão no ataque','Front Line Pressure','Pressiona zagueiros e goleiro rivais para forçar o erro na saída.','{PD,PE,MEI,ATA}',1,1.3,1,1.08,'{pressao}','{}'),
('front_poacher','def','Interceptador avançado','Front Line Poacher','Antecipa passes na primeira linha de marcação.','{PD,PE,ATA}',1,1.25,1,1.04,'{pressao,contra}','{}'),
('deep_press','def','Atacante que volta para marcar','Deep-Pressing Forward','Recua para ajudar na pressão do time.','{MEI,PD,PE,ATA}',0.97,1.22,1,1.06,'{pressao,retranca}','{}'),
('attack_outlet','def','Referência no contra-ataque','Attack Outlet','Economiza energia na defesa e fica pronto para o contra-ataque.','{MEI,PD,PE,ATA}',1.05,0.7,1,0.9,'{contra}','{}'),
-- tendências da IA (pequenos bônus nos atributos do motor)
('ai_trickster','ai','Driblador','Trickster','Usa dribles, fintas e movimentos técnicos.','{MEI,PD,PE,ATA}',1,1,1,1,'{}','{"att":2,"ctl":2}'),
('ai_mazing','ai','Drible em velocidade','Mazing Run','Conduz a bola por espaços apertados para passar pelos marcadores.','{MC,MEI,PD,PE,ATA,LD,LE}',1,1,1,1,'{}','{"ctl":2,"att":1}'),
('ai_speed','ai','Drible veloz','Speeding Bullet','Usa a velocidade e a aceleração para avançar.','{LD,LE,PD,PE,ATA}',1,1,1,1,'{contra}','{"pace":3}'),
('ai_incisive','ai','Infiltração em diagonal','Incisive Run','Faz diagonais para dentro em busca da finalização.','{PD,PE,MEI,ATA}',1,1,1,1,'{}','{"att":2}'),
('ai_longball','ai','Especialista em lançamento','Long Ball Expert','Prefere lançamentos longos e inversões de jogo.','{ZAG,VOL,MC,MEI}',1,1,1,1,'{direto}','{"cre":2}'),
('ai_earlycross','ai','Cruzamento antecipado','Early Crosser','Cruza cedo, antes de a defesa se arrumar.','{LD,LE,PD,PE,MC}',1,1,1,1,'{pontas}','{"cre":2}'),
('ai_longranger','ai','Chute de longe','Long Ranger','Procura o chute de fora da área.','{VOL,MC,MEI,PD,PE,ATA}',1,1,1,1,'{}','{"fin":2}')
on conflict(code) do update set kind=excluded.kind,name=excluded.name,en=excluded.en,descr=excluded.descr,pos=excluded.pos,
 aw=excluded.aw,dw=excluded.dw,cw=excluded.cw,drain=excluded.drain,plans=excluded.plans,bump=excluded.bump;

-- ─────────────────────────────────────────────────────────────────────────────
-- Condição
-- ─────────────────────────────────────────────────────────────────────────────
-- Pontos somados a cada atributo do motor pela seta (vermelha −5 … azul +5).
create or replace function public.on_arrow_delta(p_arrow int) returns numeric language sql immutable as $$
 select (array[-5,-2.5,0,2.5,5]::numeric[])[greatest(1,least(5,coalesce(p_arrow,3)))] $$;

-- Próxima seta. p_rating: nota na partida (nulo = não jogou); p_won: o clube venceu.
-- Regularidade B (lendas): amarela, verde ou azul. C (demais): qualquer uma.
create or replace function public.on_arrow_next(p_form char,p_prev int,p_rating numeric,p_won boolean,p_r float8 default random())
returns int language plpgsql immutable as $$
declare w numeric[];v numeric:=0;tot numeric;i int;r numeric;
begin
 w:=case p_form when 'A' then array[0,0,.25,.45,.30] when 'B' then array[0,0,.45,.40,.15]
  when 'D' then array[.15,.30,.40,.15,0] when 'E' then array[.30,.40,.30,0,0] else array[.08,.17,.40,.22,.13] end;
 -- nota e resultado puxam a seta
 if p_rating is not null and p_rating>=7.5 then w[4]:=w[4]*1.5;w[5]:=w[5]*1.6;w[1]:=w[1]*.5;w[2]:=w[2]*.6;
 elsif p_rating is not null and p_rating<5.8 then w[1]:=w[1]*1.6;w[2]:=w[2]*1.4;w[5]:=w[5]*.5;end if;
 if p_won then w[4]:=w[4]*1.2;w[5]:=w[5]*1.2;end if;
 -- extremos voltam ao meio (ciclo do PES)
 if p_prev=5 then w[5]:=w[5]*.5;elsif p_prev=1 then w[1]:=w[1]*.4;end if;
 tot:=w[1]+w[2]+w[3]+w[4]+w[5];r:=p_r*tot;
 for i in 1..5 loop v:=v+w[i];if r<v then return i;end if;end loop;
 return 3;
end $$;

-- Atributos do motor com a condição e os bônus dos estilos da IA (ordem de on_comp:
-- att, cre, def, ctl, gk, fin, head, pace, stam, tack, str).
create or replace function public.on_comp_now(p public.on_players) returns numeric[] language sql stable set search_path=public as $$
 select array(select round(greatest(15,least(99,c[k.i]+public.on_arrow_delta(p.arrow)
   +coalesce((select sum((s.bump->>(array['att','cre','def','ctl','gk','fin','head','pace','stam','tack','str'])[k.i])::numeric)
     from public.on_styles s where s.code=any(p.ai_styles)),0))),2)
  from generate_series(1,11) k(i) order by k.i)
 from(select public.on_comp(p.id,p.pos,p.level,p.g) c) q $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Estilos: escolha coerente com a posição e os atributos (determinística por jogador)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_style_pick(p_id text,p_pos text,p_level numeric,p_g smallint[],p_legend boolean default false) returns jsonb
language plpgsql stable set search_path=public as $$
declare c numeric[];v_off text;v_def text;v_ai text[];n int;
 -- grupo de treino de cada atributo (mesma tabela de on_comp)
 grp constant int[]:=array[3,2,1,2,0,3,1,4,4,1,4];
 -- quão comum é o estilo no futebol (somado à pontuação): raros negativos, comuns positivos
 pri constant jsonb:='{"extra_frontman":-2.5,"fb_finisher":-2,"classic10":-1,"anchor":2,"def_fullback":1.5,"prolific_winger":2,
  "cross_specialist":1,"goal_poacher":1,"target_man":0.5,"hole_player":-0.5,"gk_build":-1,"gk_off":-0.5,"build_up":0.5,
  "dummy_runner":-1,"attack_outlet":0.5,"front_pressure":0.5}';
 -- pontuação de cada estilo: soma de dois atributos do motor (índices de on_comp) + variação do jogador
 sc constant jsonb:='{"gk_build":[2,4],"gk_off":[8,5],"gk_def":[5,7],"gk_sweeper":[8,3],
  "build_up":[2,4],"extra_frontman":[6,7],"off_fullback":[8,2],"fb_finisher":[1,6],"orchestrator":[2,4],"box_to_box":[9,1],
  "hole_player":[1,6],"creative":[2,4],"classic10":[2,6],"dummy_runner":[8,1],"prolific_winger":[8,1],"roaming_flank":[1,6],
  "cross_specialist":[2,8],"goal_poacher":[8,6],"fox_in_box":[6,7],"target_man":[7,11],"deep_lying":[2,4],
  "destroyer":[10,11],"high_line":[8,3],"covering":[3,9],"def_fullback":[3,10],"anchor":[3,11],"all_action":[9,3],
  "pass_disruptor":[3,8],"shadow_marker":[10,8],"front_pressure":[9,8],"front_poacher":[3,8],"deep_press":[9,10],"attack_outlet":[8,6],
  "ai_trickster":[1,4],"ai_mazing":[4,8],"ai_speed":[8,8],"ai_incisive":[1,8],"ai_longball":[2,11],"ai_earlycross":[2,2],"ai_longranger":[6,2]}';
begin
 -- ponto forte próprio do jogador em cada atributo: a variação individual (±3) e o ganho de treino do grupo.
 -- O nível e o perfil da posição são iguais para todos da posição, por isso ficam de fora da escolha.
 c:=array(select (public.sim_hash01(p_id||':a'||k.i)-.5)*6+coalesce(p_g[grp[k.i]],0) from generate_series(1,11) k(i) order by k.i);
 select s.code into v_off from public.on_styles s where s.kind='off' and p_pos=any(s.pos)
  order by c[(sc->s.code->>0)::int]+c[(sc->s.code->>1)::int]+(public.sim_hash01(p_id||':so:'||s.code)-.5)*3+coalesce((pri->>s.code)::numeric,0) desc limit 1;
 select s.code into v_def from public.on_styles s where s.kind='def' and p_pos=any(s.pos)
  order by c[(sc->s.code->>0)::int]+c[(sc->s.code->>1)::int]+(public.sim_hash01(p_id||':sd:'||s.code)-.5)*3+coalesce((pri->>s.code)::numeric,0) desc limit 1;
 -- goleiro: estilo com a bola só se tiver bom passe
 if p_pos='GOL' and c[2]<1 then v_off:=null;end if;
 -- estilos da IA: lendas têm 1 ou 2; os demais 0, 1 ou 2
 n:=case when p_legend then 1+floor(public.sim_hash01(p_id||':ain')*2)::int
  else (array[0,0,1,1,1,2])[1+floor(public.sim_hash01(p_id||':ain')*6)::int] end;
 v_ai:=array(select s.code from public.on_styles s where s.kind='ai' and p_pos=any(s.pos)
  order by c[(sc->s.code->>0)::int]+c[(sc->s.code->>1)::int]+(public.sim_hash01(p_id||':sa:'||s.code)-.5)*3+coalesce((pri->>s.code)::numeric,0) desc limit n);
 return jsonb_build_object('off',v_off,'def',v_def,'ai',to_jsonb(v_ai));
end $$;

-- Preenche estilos, regularidade e seta de quem ainda não tem (jogadores novos entram pelo gatilho abaixo).
create or replace function public.on_player_profile_fill() returns trigger language plpgsql set search_path=public as $$
declare j jsonb;
begin
 if tg_op='INSERT' and new.style_def is null or tg_op='UPDATE' and (new.pos is distinct from old.pos or new.style_def is null) then
  j:=public.on_style_pick(new.id,new.pos,new.level,new.g,coalesce(new.legend,false));
  new.style_off:=j->>'off';new.style_def:=j->>'def';
  new.ai_styles:=array(select jsonb_array_elements_text(j->'ai'));
 end if;
 if tg_op='INSERT' then
  new.form:=case when coalesce(new.legend,false) then 'B' else 'C' end;
  new.arrow:=public.on_arrow_next(new.form,3,null,false,public.sim_hash01(new.id||':arrow0'));
 elsif new.legend is distinct from old.legend and coalesce(new.legend,false) then
  new.form:='B';
 end if;
 return new;
end $$;
drop trigger if exists on_players_profile on public.on_players;
create trigger on_players_profile before insert or update of pos,legend on public.on_players
 for each row execute function public.on_player_profile_fill();

-- jogadores que já existem: estilos, regularidade (lendas B) e uma seta inicial
do $$
declare p public.on_players;j jsonb;
begin
 for p in select * from public.on_players where style_def is null loop
  j:=public.on_style_pick(p.id,p.pos,p.level,p.g,coalesce(p.legend,false));
  update public.on_players set style_off=j->>'off',style_def=j->>'def',ai_styles=array(select jsonb_array_elements_text(j->'ai')),
   form=case when coalesce(p.legend,false) then 'B' else 'C' end,
   arrow=public.on_arrow_next(case when coalesce(p.legend,false) then 'B' else 'C' end,3,null,false,public.sim_hash01(p.id||':arrow0'))
  where id=p.id;
 end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ficha completa (tela do jogador): um valor por atributo, o de hoje (nível com o treino feito, igual à nota da carta).
-- A condição (seta) não entra aqui: ela vale só na partida e aparece à parte.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_sheet(p public.on_players) returns jsonb language sql stable set search_path=public as $$
 with b as(select public.on_comp(p.id,p.pos,p.level,p.g) x),
  -- [chave, rótulo, grupo]; fórmulas sobre os atributos do motor (att1 cre2 def3 ctl4 gk5 fin6 head7 pace8 stam9 tack10 str11)
  f(ord,k,lbl,grp) as(values
   (1,'off_aw','Talento ofensivo','atk'),(2,'ball','Controle de bola','tec'),(3,'drib','Drible','tec'),(4,'tight','Condução firme','tec'),
   (5,'lpass','Passe rasteiro','pas'),(6,'hpass','Passe pelo alto','pas'),(7,'fin','Finalização','atk'),(8,'head','Cabeceio','atk'),
   (9,'place','Chute colocado','atk'),(10,'curl','Curva','pas'),(11,'speed','Velocidade','fis'),(12,'acc','Aceleração','fis'),
   (13,'kick','Força do chute','atk'),(14,'jump','Impulsão','fis'),(15,'contact','Contato físico','fis'),(16,'bal','Equilíbrio','fis'),
   (17,'stam','Resistência','fis'),(18,'def_aw','Talento defensivo','def'),(19,'tackle','Desarme','def'),(20,'aggr','Agressividade','def'),
   (21,'engage','Empenho defensivo','def'),(22,'gk_aw','Talento do goleiro','gk'),(23,'gk_catch','Agarrar','gk'),(24,'gk_clear','Afastar','gk'),
   (25,'gk_refl','Reflexos','gk'),(26,'gk_reach','Alcance','gk')),
  calc as(select f.*,
   case f.k
     when 'off_aw' then x[1] when 'ball' then .6*x[4]+.4*x[1] when 'drib' then .5*x[1]+.3*x[4]+.2*x[8] when 'tight' then .7*x[4]+.3*x[11]
     when 'lpass' then .7*x[2]+.3*x[4] when 'hpass' then .8*x[2]+.2*x[11] when 'fin' then x[6] when 'head' then x[7]
     when 'place' then .55*x[6]+.45*x[2] when 'curl' then .6*x[2]+.4*x[6] when 'speed' then x[8] when 'acc' then .8*x[8]+.2*x[4]
     when 'kick' then .5*x[6]+.5*x[11] when 'jump' then .6*x[7]+.4*x[11] when 'contact' then x[11] when 'bal' then .5*x[4]+.5*x[11]
     when 'stam' then x[9] when 'def_aw' then x[3] when 'tackle' then x[10] when 'aggr' then .5*x[10]+.5*x[11]
     when 'engage' then .6*x[3]+.4*x[9] when 'gk_aw' then x[5] when 'gk_catch' then x[5] when 'gk_clear' then .7*x[5]+.3*x[11]
     when 'gk_refl' then x[5] when 'gk_reach' then .8*x[5]+.2*x[7] end
   +(public.sim_hash01(p.id||':sh:'||f.k)-.5)*6 v
   from f,b where (f.grp='gk')=(p.pos='GOL') or f.grp='fis')
 select jsonb_build_object(
  'overall',round(p.ovr),'arrow',p.arrow,'form',p.form,
  'styles',jsonb_build_object(
    'off',(select jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr) from public.on_styles s where s.code=p.style_off),
    'def',(select jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr) from public.on_styles s where s.code=p.style_def),
    'ai',coalesce((select jsonb_agg(jsonb_build_object('code',s.code,'name',s.name,'descr',s.descr)) from public.on_styles s where s.code=any(p.ai_styles)),'[]')),
  'attrs',(select jsonb_agg(jsonb_build_object('k',k,'label',lbl,'group',grp,'value',greatest(30,least(99,round(v)))::int) order by ord) from calc))
$$;

-- RPC da tela: ficha de um jogador do meu clube ou do adversário (qualquer jogador da temporada ao vivo)
create or replace function public.on_player_sheet(p_player text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();p public.on_players;
begin
 select x.* into p from public.on_players x join public.on_clubs k on k.id=x.club_id where x.id=p_player and k.season_id=c.season_id;
 if p.id is null then raise exception 'Jogador não encontrado';end if;
 return public.on_sheet(p)||jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'legend',coalesce(p.legend,false),'mine',p.club_id=c.id);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ligações com a partida
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 -- as duas trocas de on_build_side (colunas e valores) só fecham juntas: valida o corpo depois
 perform set_config('check_function_bodies','off',true);
 -- escalação: atributos com condição e estilos da IA; seta e pesos dos estilos gravados na linha da partida
 perform public.on_patch('public.on_build_side(bigint,character,integer,jsonb)',
  'cross join lateral(select public.on_comp(p.id,p.pos,p.level,p.g) c) k',
  'cross join lateral(select public.on_comp_now(p) c) k');
 perform public.on_patch('public.on_build_side(bigint,character,integer,jsonb)',
  'c_att,c_cre,c_def,c_ctl,c_gk,c_fin,c_head,c_pace,c_stam,c_tack,c_str,entered_min)',
  'c_att,c_cre,c_def,c_ctl,c_gk,c_fin,c_head,c_pace,c_stam,c_tack,c_str,entered_min,arrow,s_aw,s_dw,s_cw,s_dr)');
 perform public.on_patch('public.on_build_side(bigint,character,integer,jsonb)',
  'c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],case when x.slot is null then null else 0 end',
  'c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],case when x.slot is null then null else 0 end,p.arrow,
  coalesce((select exp(sum(ln(s.aw))) from public.on_styles s where s.code in(p.style_off,p.style_def)),1),
  coalesce((select exp(sum(ln(s.dw))) from public.on_styles s where s.code in(p.style_off,p.style_def)),1),
  coalesce((select exp(sum(ln(s.cw))) from public.on_styles s where s.code in(p.style_off,p.style_def)),1),
  coalesce((select exp(sum(ln(s.drain))) from public.on_styles s where s.code in(p.style_off,p.style_def)),1)');
 -- motor: o estilo muda o peso do jogador no ataque, na defesa, na criação e o desgaste
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  'sp.w_att::float8, sp.w_def::float8, sp.w_ctl::float8, sp.drain::float8,',
  '(sp.w_att * mp.s_aw)::float8, (sp.w_def * mp.s_dw)::float8, (sp.w_ctl * mp.s_cw)::float8, (sp.drain * mp.s_dr)::float8,');
 -- fim da partida: nova seta para todo o elenco dos dois clubes (vale para o próximo jogo)
 perform public.on_patch('public.on_match_finish(bigint)',
  ' -- fases seguintes (bilheteria, copa...)',
  ' -- condição para o próximo jogo (fase 33)
 update public.on_players p set arrow=public.on_arrow_next(p.form,p.arrow,
   (select mp.rating from public.on_match_players mp where mp.fixture_id=p_fixture and mp.player_id=p.id and mp.minutes>0),
   p.club_id=v_w)
 where p.club_id in(f.home,f.away);
 -- fases seguintes (bilheteria, copa...)');
 perform set_config('check_function_bodies','on',true);
end $$;

-- Estilos que combinam com o plano: fração de 0 a 1 (5 titulares com estilo compatível = 1).
-- Vale tanto quanto ter vantagem no confronto de planos: até +9% de chances criadas e +0,05 na qualidade.
create or replace function public.on_style_synergy(p_fixture bigint,p_side char,p_plan text) returns numeric
language sql stable set search_path=public as $$
 select least(1,count(*)/5.0)::numeric from public.on_match_players mp join public.on_players p on p.id=mp.player_id
 where mp.fixture_id=p_fixture and mp.side=p_side and mp.status='on'
  and exists(select 1 from public.on_styles s where s.code=any(array[p.style_off,p.style_def]||p.ai_styles) and p_plan=any(s.plans))
$$;
create or replace function public.on_club_synergy(p_club int,p_plan text) returns numeric language sql stable set search_path=public as $$
 select least(1,count(*)/5.0)::numeric from public.on_lineups l,jsonb_each_text(l.slots) e join public.on_players p on p.id=e.value
 where l.club_id=p_club and exists(select 1 from public.on_styles s where s.code=any(array[p.style_off,p.style_def]||p.ai_styles) and p_plan=any(s.plans))
$$;
do $$ begin
 perform public.on_patch('public.on_plan_effect(bigint,integer,jsonb,jsonb,numeric,numeric,numeric,numeric)',
  ' freq:=freq*(1+0.14*vs);qual:=qual+0.05*vs;',
  ' freq:=freq*(1+0.14*vs);qual:=qual+0.05*vs;
 -- estilos dos titulares que combinam com o plano (fase 33)
 if me<>''equilibrado'' then
  e:=public.on_style_synergy(p_fixture,case when p_s=1 then ''h'' else ''a'' end,me);
  freq:=freq*(1+0.09*e);qual:=qual+0.05*e;
  if me=''retranca'' then ofreq:=ofreq*(1-0.08*e);oqual:=oqual-0.03*e;end if;
  if me=''direto'' then qual:=qual+0.03*e;end if;
  e:=public.on_plan_edge(me,pm,po);
 end if;');
end $$;

-- Estilos e setas aumentam o ataque em média (gols subiram de 2,8 para 3,0 por jogo no laboratório):
-- a chance base de cada jogada virar ataque cai um pouco para manter a média.
do $$ begin
 perform public.on_patch('public.on_engine_run(bigint,integer,text)','v_pa := 0.335 * (v_form[s] / v_form[d])','v_pa := 0.285 * (v_form[s] / v_form[d])');
end $$;

-- Elenco: seta, regularidade e estilos de cada jogador (as cartas do campo mostram a seta)
do $$ begin
 perform public.on_patch('public.on_squad()','''legend'',p.legend,','''legend'',p.legend,''arrow'',p.arrow,''form'',p.form,''style_off'',p.style_off,''style_def'',p.style_def,');
end $$;

revoke all on function public.on_arrow_delta(int),public.on_arrow_next(char,int,numeric,boolean,float8),public.on_comp_now(public.on_players),
 public.on_style_pick(text,text,numeric,smallint[],boolean),public.on_player_profile_fill(),public.on_sheet(public.on_players),
 public.on_style_synergy(bigint,char,text),public.on_club_synergy(int,text) from public,anon,authenticated;
revoke all on function public.on_player_sheet(text) from public,anon;
grant execute on function public.on_player_sheet(text) to authenticated;
