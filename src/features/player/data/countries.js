// País do jogador. Vai definir as opções iniciais de times disponíveis na
// carreira futuramente — por enquanto só a lista de seleção. Adicionar um
// novo país é só incluir aqui e desenhar a bandeira em components/flags.jsx.
export const COUNTRIES = [
  { id: 'BR', name: 'Brasil' },
  { id: 'EN', name: 'Inglaterra' },
]

export function getCountryById(countryId) {
  return COUNTRIES.find((c) => c.id === countryId)
}
