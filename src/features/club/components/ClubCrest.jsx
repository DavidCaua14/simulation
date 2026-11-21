import { useEffect, useRef, useState } from 'react'
import { getClubById } from '../data/clubs'
import { CREST_FILES } from '../data/crests'

// Escolhe preto/branco para o texto da sigla conforme o brilho da cor de fundo.
function readableOn(hex) {
  const n = parseInt(hex.slice(1), 16)
  const lum = (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255
  return lum > 0.62 ? '#111111' : '#ffffff'
}

// Escudo oficial em pixel art: a imagem real é reduzida para poucos pixels (res) e ampliada sem suavizar.
// Se a imagem não puder ser lida, fica a imagem normal.
function PixelImg({ src, size, res, alt, className, onError }) {
  const ref = useRef(null)
  const fail = useRef(onError)
  const [plain, setPlain] = useState(false)
  useEffect(() => {
    fail.current = onError
  }, [onError])
  useEffect(() => {
    let alive = true
    const img = new Image()
    img.decoding = 'async'
    img.onload = () => {
      const cv = ref.current
      if (!alive || !cv) return
      try {
        cv.width = res
        cv.height = res
        const g = cv.getContext('2d')
        g.clearRect(0, 0, res, res)
        const k = Math.min(res / img.naturalWidth, res / img.naturalHeight)
        const w = Math.max(1, Math.round(img.naturalWidth * k))
        const h = Math.max(1, Math.round(img.naturalHeight * k))
        g.imageSmoothingEnabled = true
        g.drawImage(img, Math.floor((res - w) / 2), Math.floor((res - h) / 2), w, h)
        // alfa duro: sem bordas meio transparentes (cara de pixel art)
        const d = g.getImageData(0, 0, res, res)
        for (let i = 3; i < d.data.length; i += 4) d.data[i] = d.data[i] > 110 ? 255 : 0
        g.putImageData(d, 0, 0)
      } catch {
        setPlain(true)
      }
    }
    img.onerror = () => alive && fail.current?.()
    img.src = src
    return () => {
      alive = false
    }
  }, [src, res])
  if (plain) return <img className={`crest ${className}`} style={{ width: size, height: size, objectFit: 'contain' }} src={src} alt={alt} />
  return <canvas ref={ref} className={`crest is-pixel ${className}`} style={{ width: size, height: size, imageRendering: 'pixelated' }} role="img" aria-label={alt} />
}

// Escudo do clube. Ordem: escudo baixado pelo script (public/crests) -> imagem embutida dos 3 clubes originais
// -> escudo desenhado com as cores e a sigla. Se a imagem de uma etapa falhar, cai para a próxima.
// pixel: mostra o escudo oficial em pixel art (pixel={número} define a resolução, padrão 24).
export default function ClubCrest({ clubId, size = 40, className = '', pixel = false }) {
  const club = getClubById(clubId)
  const [failedId, setFailedId] = useState(null)
  const style = { width: size, height: size }
  if (!club) return <span className={`crest ${className}`} style={style} aria-hidden="true" />

  const file = CREST_FILES[club.id]
  const src = file && failedId !== club.id ? `${import.meta.env.BASE_URL}crests/${file}` : club.shield || null

  if (src && pixel) {
    return <PixelImg key={src} src={src} size={size} res={pixel === true ? 24 : pixel} alt={club.name} className={className} onError={() => setFailedId(club.id)} />
  }

  if (src) {
    return (
      <img
        className={`crest ${className}`}
        style={{ ...style, objectFit: 'contain' }}
        src={src}
        alt={club.name}
        loading="lazy"
        decoding="async"
        onError={() => setFailedId(club.id)}
      />
    )
  }

  const [c1, c2] = club.colors || ['#444444', '#bbbbbb']
  const gid = `crest-${club.id}`
  return (
    <svg className={`crest ${className}`} style={style} viewBox="0 0 48 56" role="img" aria-label={club.name}>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={c1} />
          <stop offset="0.62" stopColor={c1} />
          <stop offset="0.62" stopColor={c2} />
          <stop offset="1" stopColor={c2} />
        </linearGradient>
      </defs>
      <path d="M24 2 L44 8 V28 C44 42 35 50 24 54 C13 50 4 42 4 28 V8 Z" fill={`url(#${gid})`} stroke="rgba(0,0,0,.45)" strokeWidth="2" />
      <path d="M24 2 L44 8 V28 C44 42 35 50 24 54 C13 50 4 42 4 28 V8 Z" fill="none" stroke="rgba(255,255,255,.35)" strokeWidth="1" transform="translate(0.5 0.5) scale(.98)" />
      <text x="24" y="31" textAnchor="middle" fontSize="15" fontWeight="800" fontFamily="Rajdhani, Inter, sans-serif"
        fill={readableOn(c1)} stroke={readableOn(c1) === '#ffffff' ? 'rgba(0,0,0,.35)' : 'rgba(255,255,255,.4)'} strokeWidth=".4">
        {club.short}
      </text>
    </svg>
  )
}
