import { useId } from 'react'

// Desenho do Apito de Ouro: apito dourado com cordão vermelho e uma estrela de brilho.
export default function GoldenWhistle({ size = 64, className = '' }) {
  const id = useId().replace(/:/g, '')
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 64 64" aria-hidden="true">
      <defs>
        <linearGradient id={`gw-g${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff3b0" />
          <stop offset=".45" stopColor="#facc15" />
          <stop offset="1" stopColor="#a16207" />
        </linearGradient>
        <linearGradient id={`gw-d${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ca8a04" />
          <stop offset="1" stopColor="#713f12" />
        </linearGradient>
      </defs>
      {/* cordão */}
      <path d="M44 22 C52 12 58 8 60 4" fill="none" stroke="#dc2626" strokeWidth="3.2" strokeLinecap="round" />
      <path d="M44 22 C50 16 54 14 58 13" fill="none" stroke="#b91c1c" strokeWidth="2.4" strokeLinecap="round" />
      {/* corpo: bocal + câmara redonda */}
      <path d="M8 26 h24 a4 4 0 0 1 4 4 v0 h0" fill="none" />
      <rect x="6" y="22" width="26" height="12" rx="4" fill={`url(#gw-g${id})`} stroke="#713f12" strokeWidth="1.5" />
      <circle cx="38" cy="38" r="15" fill={`url(#gw-g${id})`} stroke="#713f12" strokeWidth="1.8" />
      <rect x="22" y="22" width="12" height="7" rx="2" fill={`url(#gw-d${id})`} />
      <circle cx="38" cy="38" r="7.5" fill={`url(#gw-d${id})`} opacity=".85" />
      <circle cx="35" cy="35" r="2.6" fill="#fff8d6" opacity=".9" />
      {/* argola */}
      <circle cx="44" cy="23" r="3.2" fill="none" stroke="#a16207" strokeWidth="2" />
      {/* brilho */}
      <path d="M14 8 l1.8 4.4 4.4 1.8 -4.4 1.8 -1.8 4.4 -1.8 -4.4 -4.4 -1.8 4.4 -1.8z" fill="#fffbe6" />
      <path d="M54 46 l1 2.4 2.4 1 -2.4 1 -1 2.4 -1 -2.4 -2.4 -1 2.4 -1z" fill="#fffbe6" opacity=".85" />
    </svg>
  )
}
