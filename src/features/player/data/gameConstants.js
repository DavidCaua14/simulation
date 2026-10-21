// Regras iniciais do personagem.
// Idade: escolhida pelo usuário, só a partir de 18 anos.
export const MIN_AGE = 18
export const MAX_AGE = 45

// O personagem sempre nasce no nível 1 e evolui com tempo, tarefas e
// partidas. O nível vale para o x1 online e para o ranqueamento.
export const STARTING_LEVEL = 1

// A cada 1000 XP o jogador sobe de nível (regra aplicada no banco, pelo gatilho
// careers_level_up). O XP que sobra continua na barra.
export const XP_PER_LEVEL = 1000
export const PLACEHOLDER_XP_TO_NEXT_LEVEL = XP_PER_LEVEL // nome antigo, mantido para não quebrar imports
