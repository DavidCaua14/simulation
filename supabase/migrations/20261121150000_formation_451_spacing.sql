-- 4-5-1: meias abertos um pouco mais largos e altos e meias centrais um pouco mais baixos (cartas não se tocam no
-- campo da escalação). Só muda o desenho das vagas.
update public.sim_formations set slots='[{"x":50,"y":92,"pos":"GOL","slot":"GOL"},{"x":86,"y":72,"pos":"LD","slot":"LD"},{"x":62,"y":77,"pos":"ZAG","slot":"ZAG1"},{"x":38,"y":77,"pos":"ZAG","slot":"ZAG2"},{"x":14,"y":72,"pos":"LE","slot":"LE"},{"x":88,"y":34,"pos":"PD","slot":"MD"},{"x":70,"y":50,"pos":"MC","slot":"MC1"},{"x":50,"y":62,"pos":"VOL","slot":"VOL"},{"x":30,"y":50,"pos":"MEI","slot":"MC2"},{"x":12,"y":34,"pos":"PE","slot":"ME"},{"x":50,"y":15,"pos":"ATA","slot":"ATA"}]'::jsonb
where id='4-5-1';
