export default function SoccerBallIcon({ size = 22, ...props }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" {...props}>
      <circle cx="12" cy="12" r="9.25" stroke="currentColor" strokeWidth="1.6" />
      <path
        d="M12 7.3 15.6 9.9l-1.4 4.2H9.8l-1.4-4.2L12 7.3Z"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
      <path
        d="M12 7.3V4.2M15.6 9.9l2.9-1.9M14.2 14.1l1.1 3.6M9.8 14.1l-1.1 3.6M8.6 9.9 5.7 8"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
    </svg>
  )
}
