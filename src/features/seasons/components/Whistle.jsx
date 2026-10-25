// Apito (ícone simples do treinador), desenhado aqui para não depender de um ícone específico da biblioteca
export function Whistle({ size = 12 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="9" cy="14" r="5" />
      <path d="M12.5 10.5 21 5v5h-6" />
      <path d="M4 9 2 7" />
    </svg>
  )
}
