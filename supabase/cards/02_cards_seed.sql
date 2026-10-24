-- GERADO por scripts/build-cards.mjs a partir de supabase/cards/cards.json — não edite à mão.
-- Rode no Supabase (SQL Editor) sempre que mudar o catálogo.
insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta) values
  ('arrascaeta-78', 'Arrascaeta', 'basica', 78, 'MEI', 'flamengo', 'arrascaeta', 'arrascaeta-78.webp', 100, true, '{}'::jsonb),
  ('arrascaeta-86', 'Arrascaeta', 'destaque', 86, 'MEI', 'flamengo', 'arrascaeta', 'arrascaeta-86.webp', 100, true, '{}'::jsonb),
  ('arrascaeta-92', 'Arrascaeta', 'lenda', 92, 'MEI', 'flamengo', 'arrascaeta', 'arrascaeta-92.webp', 100, true, '{}'::jsonb),
  ('arrascaeta-98', 'Arrascaeta', 'epica', 98, 'MEI', 'flamengo', 'arrascaeta', 'arrascaeta-98.webp', 100, true, '{}'::jsonb),
  ('gabriel-86', 'Gabriel', 'destaque', 86, 'ATA', 'flamengo', 'gabriel', 'gabriel-86.webp', 100, true, '{}'::jsonb),
  ('juninho-96', 'Juninho Pernambucano', 'lenda', 96, 'MEI', 'vasco', 'juninho-pernambucano', 'juninho-96.webp', 100, true, '{}'::jsonb),
  ('ribamar-58', 'Ribamar', 'basica', 58, null, 'vasco', 'ribamar', 'ribamar-58.webp', 100, true, '{}'::jsonb),
  ('igor-bahia-51', 'Igor Bahia', 'basica', 51, null, null, 'igor-bahia', 'igor-bahia-51.webp', 100, true, '{}'::jsonb),
  ('flavio-caca-rato-51', 'Flávio Caça-Rato', 'basica', 51, null, null, 'flavio-caca-rato', 'flavio-caca-rato-51.webp', 100, true, '{}'::jsonb)
on conflict (id) do update set
  name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image,
  weight = excluded.weight, active = excluded.active, meta = excluded.meta;
