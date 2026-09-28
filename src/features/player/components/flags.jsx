export function BrazilFlag(props) {
  return (
    <svg viewBox="0 0 32 22" width="22" height="16" {...props}>
      <rect width="32" height="22" rx="2" fill="#0a8a3d" />
      <polygon points="16,3 29,11 16,19 3,11" fill="#f7cf1e" />
      <circle cx="16" cy="11" r="5.2" fill="#1a4e9e" />
    </svg>
  )
}

export function EnglandFlag(props) {
  return (
    <svg viewBox="0 0 32 22" width="22" height="16" {...props}>
      <rect width="32" height="22" rx="2" fill="#ffffff" />
      <rect x="13" width="6" height="22" fill="#ce1124" />
      <rect y="8" width="32" height="6" fill="#ce1124" />
    </svg>
  )
}

export const FLAGS = {
  BR: BrazilFlag,
  EN: EnglandFlag,
}

export function CountryFlag({ countryId, ...props }) {
  const Flag = FLAGS[countryId]
  return Flag ? <Flag {...props} /> : null
}
