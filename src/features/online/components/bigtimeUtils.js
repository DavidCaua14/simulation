// Textos das cartas Big Time: data curta e o jogo da atuação.
const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
export function btDate(d) {
  if (!d) return ''
  const [y, m, day] = String(d).slice(0, 10).split('-').map(Number)
  return `${day} ${MONTHS[m - 1]} ${y}`
}
// "Barcelona × Real Madrid · 3 x 0"
export function btMatch(bt) {
  if (!bt) return ''
  const vs = bt.team ? `${bt.team} × ${bt.opponent}` : `contra ${bt.opponent}`
  return bt.score ? `${vs} · ${bt.score}` : vs
}

