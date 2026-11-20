-- MODO ONLINE — Fase 45: cada clube escolhe o modelo do seu estádio (modo pixel da partida). Fica em
-- on_clubs.colors.arena (junto com o nome do estádio em colors.stadium) e chega à partida pelo mesmo caminho das
-- cores. Modelos: os mesmos ids de src/features/match3d/stadiums.js. Sem escolha, o app sorteia um fixo pelo clube.
create or replace function public.on_arenas() returns text[] language sql immutable as $$
 select array['arena','concreto','interior','praia','neon','circulos'] $$;

do $$ begin
 perform public.on_patch('public.on_club_identity(jsonb)',
  ' update public.on_clubs set name=v_name,short=v_short,colors=v_col where id=c.id;',
  ' if p ? ''arena'' then
  if not (p->>''arena'' = any(public.on_arenas())) then raise exception ''Estádio inválido'';end if;
  v_col:=v_col||jsonb_build_object(''arena'',p->>''arena'');
 end if;
 update public.on_clubs set name=v_name,short=v_short,colors=v_col where id=c.id;');
end $$;
