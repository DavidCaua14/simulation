-- A tela de negociações lê o histórico de cada negociação. Sem índice, cada leitura varria a tabela inteira
-- (45 mil varreduras completas registradas). Só cria índice; nenhuma linha muda.
CREATE INDEX IF NOT EXISTS cw_offer_history_negotiation_idx ON public.cw_offer_history (negotiation_id, id);
