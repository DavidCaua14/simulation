// Últimos resultados: V (verde), E (amarelo), D (vermelho). Ex.: ● ● ● ● ●
const TXT = { W: 'V', D: 'E', L: 'D' }
export default function FormDots({ form = [] }) {
  if (!form.length) return <span className="sn-form empty">sem jogos</span>
  return (
    <span className="sn-form" aria-label={`Últimos resultados: ${form.map((f) => TXT[f]).join(' ')}`}>
      {form.map((f, i) => (
        <i key={i} className={`f-${f}`}>
          {TXT[f]}
        </i>
      ))}
    </span>
  )
}
