// Uso: node scripts/build-kaykit-anims.mjs <pasta com os Rig_Medium_*.glb do KayKit Character Animations> public/models/kaykit/anims.glb
// (precisa de @gltf-transform/core e @gltf-transform/functions instalados; não são dependências do jogo)
// junta só as animações usadas pelo futebol num GLB (sem malha), a partir dos pacotes CC0 do KayKit
import { NodeIO } from '@gltf-transform/core'
import { prune, dedup, mergeDocuments, unpartition } from '@gltf-transform/functions'
const [src, out] = process.argv.slice(2)
const WANT = {
  'Rig_Medium_General.glb': ['Idle_A', 'Idle_B', 'Hit_A', 'Throw'],
  'Rig_Medium_MovementBasic.glb': ['Walking_A', 'Running_A', 'Running_B', 'Jump_Full_Short'],
  'Rig_Medium_MovementAdvanced.glb': ['Dodge_Left', 'Dodge_Right', 'Crouching'],
  'Rig_Medium_CombatMelee.glb': ['Melee_Unarmed_Attack_Kick'],
  'Rig_Medium_Simulation.glb': ['Cheering', 'Lie_Down', 'Lie_StandUp'],
}
const io = new NodeIO()
let base = null
for (const [file, keep] of Object.entries(WANT)) {
  const doc = await io.read(`${src}/${file}`)
  for (const a of doc.getRoot().listAnimations()) if (!keep.includes(a.getName())) a.dispose()
  await doc.transform(prune())
  if (!base) base = doc
  else {
    // só as animações: retargeta os canais para os nós (ossos) do documento base pelo nome
    const byName = new Map(base.getRoot().listNodes().map((n) => [n.getName(), n]))
    const buf = base.getRoot().listBuffers()[0]
    for (const a of doc.getRoot().listAnimations()) {
      const na = base.createAnimation(a.getName())
      for (const ch of a.listChannels()) {
        const target = byName.get(ch.getTargetNode()?.getName())
        if (!target) continue
        const s = ch.getSampler()
        const inp = base.createAccessor().setType(s.getInput().getType()).setArray(s.getInput().getArray().slice()).setBuffer(buf)
        const outp = base.createAccessor().setType(s.getOutput().getType()).setArray(s.getOutput().getArray().slice()).setBuffer(buf)
        const ns = base.createAnimationSampler().setInput(inp).setOutput(outp).setInterpolation(s.getInterpolation())
        na.addSampler(ns).addChannel(base.createAnimationChannel().setTargetNode(target).setTargetPath(ch.getTargetPath()).setSampler(ns))
      }
    }
  }
}
await base.transform(dedup(), prune(), unpartition())
await io.write(out, base)
console.log('ok', base.getRoot().listAnimations().map((a) => a.getName()).join(','))
