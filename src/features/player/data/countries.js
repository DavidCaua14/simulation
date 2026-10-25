// Nacionalidade do treinador. Ela define as propostas iniciais de clube — a regra fica no banco
// (tabela sim_start_rules, ver supabase/evolution/05_career_start.sql), não aqui.
// Nova nacionalidade: uma linha em sim_start_rules + incluir aqui + a bandeira em components/flags.jsx.
// A tela de criação só mostra os países desta lista que têm regra ativa no banco.
export const COUNTRIES = [
  { id: 'BR', name: 'Brasil' },
  { id: 'EN', name: 'Inglaterra' },
]

export function getCountryById(countryId) {
  return COUNTRIES.find((c) => c.id === countryId)
}
