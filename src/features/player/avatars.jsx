const PRESETS = [
  { id: 'a1', skin: '#f0c8a0', hair: '#3b2a1e', hairStyle: 'short' },
  { id: 'a2', skin: '#c98a5e', hair: '#1a1a1a', hairStyle: 'buzz' },
  { id: 'a3', skin: '#8d5a3b', hair: '#0d0d0d', hairStyle: 'curly' },
  { id: 'a4', skin: '#f3d6b8', hair: '#8a5a2e', hairStyle: 'long' },
  { id: 'a5', skin: '#e0a878', hair: '#4a2f1a', hairStyle: 'mohawk' },
  { id: 'a6', skin: '#5c3a24', hair: '#161616', hairStyle: 'short' },
  { id: 'a7', skin: '#f5e0c8', hair: '#c98a3a', hairStyle: 'buzz' },
  { id: 'a8', skin: '#a86a45', hair: '#2b1c10', hairStyle: 'curly' },
]

function HairPath({ style, color }) {
  switch (style) {
    case 'buzz':
      return <path d="M14 32c0-14 8-22 18-22s18 8 18 22" fill={color} />
    case 'curly':
      return <circle cx="32" cy="20" r="17" fill={color} />
    case 'long':
      return (
        <path
          d="M12 34c0-16 9-25 20-25s20 9 20 25v10h-6V34c0-3-2-5-4-5s-3 2-3 5v10h-4V32c0-2-1-4-3-4s-3 2-3 4v12h-4V30c0-2-1-3-3-3s-3 1-3 3v14h-6V34z"
          fill={color}
        />
      )
    case 'mohawk':
      return (
        <path
          d="M28 6c1 8 2 14 4 14s3-6 4-14c2 6 3 12 3 16H25c0-4 1-10 3-16z"
          fill={color}
        />
      )
    default:
      return <path d="M13 30c0-13 8-21 19-21s19 8 19 21v4H13z" fill={color} />
  }
}

function AvatarFace({ skin, hair, hairStyle }) {
  return (
    <svg viewBox="0 0 64 64" width="100%" height="100%">
      <circle cx="32" cy="34" r="22" fill={skin} />
      <HairPath style={hairStyle} color={hair} />
      <circle cx="24" cy="34" r="2.4" fill="#26211c" />
      <circle cx="40" cy="34" r="2.4" fill="#26211c" />
      <path d="M25 43c3 3 11 3 14 0" stroke="#26211c" strokeWidth="2" fill="none" strokeLinecap="round" />
    </svg>
  )
}

export const AVATARS = PRESETS.map((p) => ({
  id: p.id,
  render: () => <AvatarFace skin={p.skin} hair={p.hair} hairStyle={p.hairStyle} />,
}))
