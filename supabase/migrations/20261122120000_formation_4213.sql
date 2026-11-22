-- Formação 4-2-1-3 (dois volantes, um meia e trio de ataque com pontas) para Online e Temporadas.
-- Entra logo depois da 4-2-3-1 na lista; as demais descem uma posição.
update public.sim_formations set sort = sort + 1 where sort >= 4 and id <> '4-2-1-3';
insert into public.sim_formations(id,name,sort,slots) values
 ('4-2-1-3','4-2-1-3',4,'[{"x":50,"y":92,"pos":"GOL","slot":"GOL"},{"x":86,"y":72,"pos":"LD","slot":"LD"},{"x":62,"y":77,"pos":"ZAG","slot":"ZAG1"},{"x":38,"y":77,"pos":"ZAG","slot":"ZAG2"},{"x":14,"y":72,"pos":"LE","slot":"LE"},{"x":66,"y":58,"pos":"VOL","slot":"VOL1"},{"x":34,"y":58,"pos":"MC","slot":"VOL2"},{"x":50,"y":40,"pos":"MEI","slot":"MEI"},{"x":82,"y":22,"pos":"PD","slot":"PD"},{"x":50,"y":14,"pos":"ATA","slot":"ATA"},{"x":18,"y":22,"pos":"PE","slot":"PE"}]')
on conflict(id) do update set name = excluded.name, sort = excluded.sort, slots = excluded.slots;
