import { createContext } from 'react'

// Outro modo de jogo pode trocar a ficha do campo (camisa) por um desenho próprio: o valor é uma função que
// recebe as mesmas props de PlayerToken e devolve o elemento (o modo online desenha a carta). Sem provider, nada muda.
export const PitchTokenContext = createContext(null)
