// Textos e arte da gestão do clube. Os números (custos, prazos, efeitos) vêm do banco.
const art = import.meta.glob('./assets/*.webp', { eager: true, query: '?url', import: 'default' })
export const ART = Object.fromEntries(Object.entries(art).map(([k, v]) => [k.replace('./assets/', '').replace('.webp', ''), v]))

export const FOCUS = [
  { id: 'balanced', label: 'Equilibrado', text: 'Evolução distribuída por todos os atributos.' },
  { id: 'physical', label: 'Físico', text: 'Velocidade, resistência e força crescem mais. Bom para elencos jovens.' },
  { id: 'attack', label: 'Ataque', text: 'Finalização, movimentação, drible e técnica.' },
  { id: 'defense', label: 'Defesa', text: 'Marcação, desarme, posicionamento e jogo aéreo.' },
  { id: 'tactical', label: 'Tático', text: 'Passe e visão; o entrosamento com a formação cresce mais rápido e posições novas são aprendidas antes.' },
  { id: 'set_pieces', label: 'Bola parada', text: 'Técnica e finalização; pênaltis cobrados com mais precisão nas partidas.' },
]
export const INTENSITY = [
  { id: 'light', label: 'Leve', text: '−15% de evolução. Mais seguro para elencos cansados.' },
  { id: 'normal', label: 'Normal', text: 'Carga padrão.' },
  { id: 'hard', label: 'Forte', text: '+15% de evolução.' },
]

export const FACILITIES = {
  training: { label: 'Centro de treinamento', art: (lvl) => ART[`centro_treinamento_nivel_${Math.min(3, Math.max(1, Math.ceil(lvl / 2)))}`], effect: 'Acelera a evolução de todos os atletas.' },
  youth: { label: 'Categorias de base', art: () => ART.categorias_base, effect: 'Revela mais jovens, e de melhor potencial, no início de cada temporada.' },
  medical: { label: 'Departamento médico', art: () => ART.departamento_medico, effect: 'Encurta o tempo de recuperação das lesões.' },
  stadium: { label: 'Estádio', art: () => ART.vestiario, effect: 'Aumenta a bilheteria. Durante a obra, a arrecadação cai 15%.' },
}

export const STAFF = {
  assistant: { label: 'Auxiliar técnico', effect: 'Evolução +2% por nível e bola parada mais eficiente.', art: () => ART.sala_tatica },
  fitness: { label: 'Preparador físico', effect: 'Físico evolui mais e veteranos perdem menos.', art: () => ART.academia },
  physio: { label: 'Fisioterapeuta', effect: 'Recuperação de lesões mais rápida.', art: () => ART.departamento_medico },
  psychologist: { label: 'Psicólogo', effect: 'A moral do elenco sobe aos poucos todo mês.', art: () => ART.vestiario },
  scout: { label: 'Olheiro-chefe', effect: 'Relatórios mais rápidos, mais relatórios ao mesmo tempo e faixa de potencial mais estreita.', art: () => ART.olheiros },
  youth: { label: 'Técnico da base', effect: 'Jovens revelados com mais potencial.', art: () => ART.categorias_base },
}

export const POS_SHORT = { GOL: 'GOL', LD: 'LD', ZAG: 'ZAG', LE: 'LE', VOL: 'VOL', MC: 'MC', MEI: 'MEI', PD: 'PD', PE: 'PE', ATA: 'ATA' }

// Faixas de reputação → clubes que costumam procurar o treinador (20A: mostrar com clareza).
export const REPUTATION_STEPS = [
  { at: 0, label: 'Clubes pequenos e da Série B' },
  { at: 35, label: 'Clubes médios das ligas principais' },
  { at: 50, label: 'Clubes tradicionais' },
  { at: 65, label: 'Grandes clubes e disputa continental' },
  { at: 80, label: 'Gigantes do Brasil e da Europa' },
]
