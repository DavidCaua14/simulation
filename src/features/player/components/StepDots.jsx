export default function StepDots({ total, current }) {
  return (
    <div className="step-dots" role="progressbar" aria-valuenow={current + 1} aria-valuemax={total}>
      {Array.from({ length: total }).map((_, i) => (
        <span key={i} className={`step-dot ${i === current ? 'is-active' : ''} ${i < current ? 'is-done' : ''}`} />
      ))}
    </div>
  )
}
