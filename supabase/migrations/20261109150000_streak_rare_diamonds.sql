-- Sequência diária: diamantes são raros. Dia 5 e Dia 7 pagam só diamantes (300 e 450), sem moedas,
-- para não confundir o valor de moedas com diamantes. Demais dias seguem a escada de moedas (1k..6k).
-- Não toca em progresso de jogadores. Idempotente.
update public.streak_rewards set coins = 0, diamonds = 300 where day = 5;
update public.streak_rewards set coins = 0, diamonds = 450 where day = 7;
