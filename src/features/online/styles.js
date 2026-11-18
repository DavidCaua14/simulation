// Nomes dos estilos de jogo e especialidades do modo online (mesmos códigos de on_styles e on_traits no banco).
export const STYLE_NAME = {
  gk_build: 'Goleiro construtor', gk_off: 'Goleiro ofensivo', gk_def: 'Goleiro defensivo', gk_sweeper: 'Goleiro-líbero',
  build_up: 'Zagueiro construtor', extra_frontman: 'Zagueiro elemento-surpresa', off_fullback: 'Lateral ofensivo', fb_finisher: 'Lateral finalizador',
  orchestrator: 'Organizador', box_to_box: 'Meia de área a área', hole_player: 'Infiltração', creative: 'Armador criativo',
  classic10: 'Camisa 10 clássico', dummy_runner: 'Abre-espaços', prolific_winger: 'Ponta veloz', roaming_flank: 'Ponta que corta para dentro',
  cross_specialist: 'Especialista em cruzamentos', goal_poacher: 'Artilheiro', fox_in_box: 'Matador da área', target_man: 'Pivô',
  deep_lying: 'Atacante recuado', destroyer: 'Destruidor', high_line: 'Mestre da linha alta', covering: 'Cobertura',
  def_fullback: 'Lateral defensivo', anchor: 'Volante âncora', all_action: 'Defensor incansável', pass_disruptor: 'Interceptador',
  shadow_marker: 'Marcador sombra', front_pressure: 'Pressão no ataque', front_poacher: 'Interceptador avançado',
  deep_press: 'Atacante que volta para marcar', attack_outlet: 'Referência no contra-ataque',
}
export const styleName = (code) => STYLE_NAME[code] || null
