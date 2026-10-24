// Últimos resultados (do mais antigo ao mais novo): V verde, E amarelo, D vermelho.
const TXT = { W: 'V', D: 'E', L: 'D' }
export default function FormDots({ form = [] }) {
  if (!form.length) return <span className="fd is-empty">sem jogos</span>
  return (
    <span className="fd" aria-label={`Últimos resultados: ${form.map((f) => TXT[f]).join(' ')}`}>
      {form.map((f, i) => (
        <i key={i} className={`f-${f}`}>
          {TXT[f]}
        </i>
      ))}
    </span>
  )
}
