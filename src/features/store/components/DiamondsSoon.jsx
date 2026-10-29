import { Gem, Lock } from 'lucide-react'

// Compra de diamantes com dinheiro real: AINDA NÃO EXISTE (não há provedor de pagamento configurado).
// O cartão aparece desabilitado, sem preço e sem simular pagamento.
export default function DiamondsSoon() {
  return (
    <section className="sh-diamonds" aria-label="Comprar diamantes (em breve)">
      <div className="sh-dia-card" aria-disabled="true">
        <span className="sh-dia-icon"><Gem size={30} /></span>
        <div>
          <h4>Comprar diamantes</h4>
          <p>Pacotes de diamantes com pagamento seguro.</p>
        </div>
        <span className="gx-tag is-soon"><Lock size={11} /> EM BREVE</span>
      </div>
      <p className="cx-hint">
        Ainda não há compra com dinheiro real no jogo — nenhum pagamento é feito aqui. Os diamantes conquistados nos eventos continuam disponíveis para energia e itens visuais.
      </p>
    </section>
  )
}
