-- Partidas mais difíceis sem mexer em finanças, diretoria, mercado ou ranking:
-- só o fator de rendimento do adversário da IA nas partidas do treinador (cw_cm_match_prepare).
update public.career_difficulty_levels set ai_match_mult = case id when 'normal' then 1.25 when 'hard' then 1.32 else ai_match_mult end
 where id in ('normal','hard');
