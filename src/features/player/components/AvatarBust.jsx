const TRANSITION = { transition: 'fill 0.2s ease' }

function HairShape({ style, color }) {
  switch (style) {
    case 'buzz':
      return (
        <path
          d="M18 18c0-8 6-13 14-13s14 5 14 13c-4-2-9-3-14-3s-10 1-14 3z"
          fill={color}
          style={TRANSITION}
        />
      )
    case 'curly':
      return (
        <g style={TRANSITION} fill={color}>
          <circle cx="20" cy="16" r="4" />
          <circle cx="26" cy="11.5" r="4.3" />
          <circle cx="32" cy="10.5" r="4.4" />
          <circle cx="38" cy="11.5" r="4.3" />
          <circle cx="44" cy="16" r="4" />
        </g>
      )
    case 'wavy':
      return (
        <path
          d="M18 19c0-9 6-14 14-14s14 5 14 14c0 1.5-.2 3-.6 4.3-2-4.6-6.6-7.3-13.4-7.3s-11.4 2.7-13.4 7.3c-.4-1.3-.6-2.8-.6-4.3z"
          fill={color}
          style={TRANSITION}
        />
      )
    case 'bald':
      return null
    default:
      return (
        <path
          d="M18 20c0-9 6-14 14-14s14 5 14 14v3c-3-3-8-5-14-5s-11 2-14 5z"
          fill={color}
          style={TRANSITION}
        />
      )
  }
}

export default function AvatarBust({ skin, hair, hairColor, eyeColor, beard }) {
  return (
    <svg viewBox="0 0 64 64" width="100%" height="100%">
      {/* uniforme de treino */}
      <path d="M8 64c0-16 9-22 24-22s24 6 24 22z" fill="var(--primary)" />
      <path
        d="M26 44l6 6 6-6"
        stroke="var(--primary-contrast)"
        strokeWidth="2"
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* pescoço */}
      <rect x="25" y="32" width="14" height="12" fill={skin} style={TRANSITION} />
      {/* rosto */}
      <circle cx="32" cy="24" r="13" fill={skin} style={TRANSITION} />
      {/* olhos */}
      <ellipse cx="27" cy="24.5" rx="2.1" ry="2.5" fill={eyeColor} style={TRANSITION} />
      <ellipse cx="37" cy="24.5" rx="2.1" ry="2.5" fill={eyeColor} style={TRANSITION} />
      {/* boca */}
      <path d="M27 31c2.4 1.6 7.6 1.6 10 0" stroke="rgba(0,0,0,0.35)" strokeWidth="1.4" fill="none" strokeLinecap="round" />
      {beard && (
        <path
          d="M19.5 25a12.5 12.5 0 0 0 25 0c-1 6-6.2 10.5-12.5 10.5S20.5 31 19.5 25z"
          fill={hairColor}
          opacity="0.92"
          style={TRANSITION}
        />
      )}
      <HairShape style={hair} color={hairColor} />
    </svg>
  )
}
