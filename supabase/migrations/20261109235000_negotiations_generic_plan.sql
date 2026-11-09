-- A tela de negociações replanejava as consultas das views nas cinco primeiras chamadas de cada conexão
-- (~700 ms cada, contra ~50 ms depois). Aqui o plano genérico é bom, então ele vale desde a primeira chamada.
-- Só muda como o PostgreSQL planeja a função; o resultado é o mesmo.
ALTER FUNCTION public.career_negotiations() SET plan_cache_mode = 'force_generic_plan';
