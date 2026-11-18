#!/usr/bin/env python3
"""Gera supabase/online/36_legend_profiles.sql: estilos e especialidades das lendas, escritos à mão.

Formato de cada linha: id-sem-lg: estilo_com_bola, estilo_sem_bola, ias (+), especialidades (+)
Use '-' para vazio. Os códigos curtos estão nos dicionários abaixo. A posição vem de on_legends; o script recusa
estilo que não exista na posição da lenda (mesma regra de on_styles.pos).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OFF = {'gb': 'gk_build', 'bu': 'build_up', 'ef': 'extra_frontman', 'of': 'off_fullback', 'ff': 'fb_finisher', 'or': 'orchestrator',
       'bb': 'box_to_box', 'hp': 'hole_player', 'cp': 'creative', 'c10': 'classic10', 'dr': 'dummy_runner', 'pw': 'prolific_winger',
       'rf': 'roaming_flank', 'cs': 'cross_specialist', 'gp': 'goal_poacher', 'fb': 'fox_in_box', 'tm': 'target_man', 'dl': 'deep_lying'}
DEF = {'go': 'gk_off', 'gd': 'gk_def', 'gs': 'gk_sweeper', 'de': 'destroyer', 'hl': 'high_line', 'co': 'covering', 'df': 'def_fullback',
       'an': 'anchor', 'aa': 'all_action', 'pd': 'pass_disruptor', 'sm': 'shadow_marker', 'fp': 'front_pressure', 'fpo': 'front_poacher',
       'dp': 'deep_press', 'ao': 'attack_outlet'}
AI = {'tr': 'ai_trickster', 'mz': 'ai_mazing', 'sp': 'ai_speed', 'in': 'ai_incisive', 'lb': 'ai_longball', 'ec': 'ai_earlycross', 'lr': 'ai_longranger'}
TR = {'fk': 'falta', 'hd': 'cabeceio', 'dr': 'drible', 'ls': 'chute_longe', 'ps': 'passe', 'lg': 'lancamento', 'vel': 'velocidade',
      'fin': 'finalizacao', 'ds': 'desarme', 'mk': 'marcacao', 'fo': 'forca', 'st': 'folego', 'pk': 'penalti', 'pks': 'defesa_penalti',
      'rx': 'reflexos', 'cr': 'cruzamento'}
POS = {
    'gk_build': 'GOL', 'build_up': 'ZAG', 'extra_frontman': 'ZAG', 'off_fullback': 'LD LE', 'fb_finisher': 'LD LE', 'orchestrator': 'VOL MC',
    'box_to_box': 'VOL MC', 'hole_player': 'MC MEI PD PE ATA', 'creative': 'MEI PD PE', 'classic10': 'MEI', 'dummy_runner': 'MEI ATA',
    'prolific_winger': 'PD PE', 'roaming_flank': 'PD PE', 'cross_specialist': 'PD PE', 'goal_poacher': 'ATA', 'fox_in_box': 'ATA',
    'target_man': 'ATA', 'deep_lying': 'ATA', 'gk_off': 'GOL', 'gk_def': 'GOL', 'gk_sweeper': 'GOL', 'destroyer': 'ZAG LD LE VOL MC',
    'high_line': 'ZAG LD LE', 'covering': 'ZAG LD LE VOL MC', 'def_fullback': 'LD LE', 'anchor': 'VOL', 'all_action': 'VOL MC',
    'pass_disruptor': 'VOL MC MEI', 'shadow_marker': 'ZAG LD LE VOL MC', 'front_pressure': 'PD PE MEI ATA', 'front_poacher': 'PD PE ATA',
    'deep_press': 'MEI PD PE ATA', 'attack_outlet': 'MEI PD PE ATA', 'ai_trickster': 'MEI PD PE ATA', 'ai_mazing': 'MC MEI PD PE ATA LD LE',
    'ai_speed': 'LD LE PD PE ATA', 'ai_incisive': 'PD PE MEI ATA', 'ai_longball': 'ZAG VOL MC MEI', 'ai_earlycross': 'LD LE PD PE MC',
    'ai_longranger': 'VOL MC MEI PD PE ATA'}

DATA = """
pele: hp, fpo, tr+in, fin+dr+hd
diego-maradona: c10, ao, tr+mz, dr+fk+ps
johan-cruyff: dl, fp, tr+mz, dr+ps+vel
franz-beckenbauer: bu, co, lb, ps+mk+lg
zinedine-zidane: c10, ao, tr+mz, dr+ps+fo
ronaldo-nazario: gp, ao, mz+sp, fin+vel+dr
ronaldinho-gaucho: cp, ao, tr+mz, dr+fk+ps
alfredo-di-stefano: hp, fp, in, fin+st+ps
ferenc-puskas: fb, ao, lr, fin+ls
michel-platini: c10, ao, lr, fk+ps+fin
garrincha: pw, ao, tr+mz, dr+vel+cr
zico: c10, ao, lr, fk+ps+fin
romario: fb, ao, tr, fin+dr
rivaldo: hp, ao, lr+in, fk+ls+dr
kaka: hp, ao, mz+in, vel+dr+fin
roberto-carlos: of, df, sp+ec, fk+ls+vel
cafu: of, df, sp+ec, st+vel+cr
socrates: bb, pd, lr, ps+fin+hd
falcao: or, pd, lb, ps+lg+ls
carlos-alberto-torres: of, co, ec, mk+ls+cr
rivellino: c10, ao, lr+tr, fk+ls+dr
tostao: dl, fp, in, fin+ps
jairzinho: pw, ao, sp+in, vel+fo+fin
didi: or, pd, lb, fk+ps+lg
nilton-santos: of, co, ec, mk+cr
djalma-santos: of, df, -, mk+ds
gerson: or, pd, lb, lg+ps+ls
bebeto: fb, ao, in, fin+dr
careca: gp, fp, sp, fin+vel+hd
junior: of, co, ec, cr+ps
leandro: of, df, ec, cr+mk
claudio-taffarel: -, gd, -, pks+rx
dida: -, gd, -, pks+rx
gilmar: -, gd, -, rx
lucio: ef, de, -, ds+fo+vel
aldair: bu, co, -, mk+hd
dunga: or, an, lb, ds+lg+mk
mauro-silva: or, an, -, ds+mk+st
juninho-pernambucano: or, pd, lr+lb, fk+ls+lg
adriano-imperador: tm, ao, lr, ls+fo+fin
robinho: rf, ao, tr+mz, dr+vel
djalminha: c10, ao, tr, dr+ps+fk
alex: c10, ao, lr, fk+ps
marcos: -, gd, -, rx+pks
rogerio-ceni: gb, gd, -, fk+pk
edmundo: hp, ao, tr, dr+fin
rai: hp, ao, -, pk+ps+hd
zagallo: cs, dp, ec, cr+st
ademir-da-guia: c10, ao, -, ps+lg
reinaldo: fb, ao, -, fin+hd
roberto-dinamite: fb, ao, lr, fin+ls+fk
leonidas-da-silva: gp, ao, tr+sp, fin+vel+dr
zizinho: c10, ao, tr, dr+ps
vava: fb, fp, -, fin+fo
gilberto-silva: or, an, -, mk+ds+hd
juan: bu, co, -, mk+hd
ze-roberto: bb, aa, mz, st+dr+ps
elano: bb, pd, lr+ec, fk+cr
diego-ribas: c10, ao, lr, ps+fk
fred: fb, ao, -, fin+hd
luis-fabiano: gp, ao, -, fin+fo
maicon: of, df, sp+ec, fo+cr+ls
julio-cesar: -, gd, -, rx
gabriel-batistuta: gp, ao, lr, fin+ls+fo
daniel-passarella: ef, de, -, hd+ds+fk
mario-kempes: hp, ao, sp, fin+vel+dr
juan-roman-riquelme: c10, ao, lb, ps+fk+lg
javier-zanetti: of, df, mz, st+mk
fernando-redondo: or, pd, lb, ps+ds
hernan-crespo: fb, ao, -, fin+hd
carlos-tevez: hp, fp, lr, st+fo+fin
javier-mascherano: or, de, -, ds+mk+st
diego-simeone: bb, de, -, ds+st+hd
roberto-ayala: bu, co, -, hd+mk
juan-sebastian-veron: or, pd, lb+lr, lg+ps+ls
pablo-aimar: cp, ao, tr+mz, dr+ps
ariel-ortega: hp, ao, tr+mz, dr
claudio-caniggia: gp, ao, sp, vel+fin
jorge-burruchaga: hp, pd, -, ps+fin
ubaldo-fillol: -, gd, -, rx+pks
oscar-ruggeri: ef, de, -, hd+ds
ricardo-bochini: c10, ao, tr, ps+dr
omar-sivori: hp, ao, tr+mz, dr+fin
esteban-cambiasso: or, aa, lr, mk+ps+st
walter-samuel: bu, de, -, ds+fo+hd
diego-milito: fb, ao, -, fin
sergio-aguero: gp, ao, mz+in, fin+dr+vel
gonzalo-higuain: fb, ao, -, fin
javier-saviola: gp, ao, mz, vel+dr+fin
martin-palermo: tm, ao, -, hd+fin
enzo-francescoli: c10, ao, -, ps+dr+fin
diego-forlan: hp, ao, lr, fk+ls+fin
obdulio-varela: or, an, lb, mk+ds+lg
juan-alberto-schiaffino: c10, ao, -, ps+fin
jose-nasazzi: bu, co, -, mk+hd
alvaro-recoba: hp, ao, lr+tr, fk+ls
diego-lugano: ef, de, -, hd+ds+fo
diego-godin: ef, co, -, hd+mk
paolo-montero: bu, de, -, ds+mk
carlos-valderrama: c10, ao, lb, ps+lg
faustino-asprilla: hp, ao, tr+sp, vel+dr
rene-higuita: gb, gs, -, fk+pks
freddy-rincon: bb, aa, lr, fo+st
ivan-cordoba: bu, co, -, vel+mk
elias-figueroa: bu, co, lb, mk+hd+lg
ivan-zamorano: tm, ao, -, hd+fin
marcelo-salas: fb, ao, lr, fin+hd
jose-luis-chilavert: gb, gd, -, fk+pk+pks
roque-santa-cruz: tm, ao, -, hd
carlos-gamarra: bu, co, -, mk+ds
teofilo-cubillas: c10, ao, lr, fk+ls+dr
claudio-pizarro: tm, ao, -, hd+fin
hugo-sanchez: fb, ao, -, fin+hd
rafael-marquez: bu, co, lb, lg+fk+mk
cuauhtemoc-blanco: c10, ao, tr, fk+dr
jorge-campos: gb, gs, -, rx
marco-van-basten: fb, ao, -, fin+hd+dr
ruud-gullit: hp, fp, -, fo+hd+st
frank-rijkaard: bb, an, -, ds+fo+hd
dennis-bergkamp: dl, ao, tr, ps+fin+dr
ronald-koeman: bu, co, lb, fk+lg+ls
clarence-seedorf: bb, aa, lr, st+ps+ls
edgar-davids: bb, de, -, ds+st
patrick-kluivert: tm, ao, -, fin+hd
ruud-van-nistelrooy: fb, ao, -, fin
arjen-robben: rf, ao, in+lr, dr+ls+vel
wesley-sneijder: c10, ao, lr, fk+ps+ls
robin-van-persie: hp, ao, lr, fin+fk
edwin-van-der-sar: gb, gd, -, rx
johan-neeskens: bb, aa, -, st+pk+ds
ruud-krol: bu, hl, lb, lg+mk
marc-overmars: pw, ao, sp, vel+cr
frank-de-boer: bu, hl, lb, lg+mk
jaap-stam: bu, de, -, fo+ds+hd
gerd-muller: fb, ao, -, fin+hd
lothar-matthaus: bb, aa, lr, st+ls+ps
karl-heinz-rummenigge: hp, ao, sp, fin+vel
paul-breitner: of, de, -, pk+ls+st
sepp-maier: -, gd, -, rx
oliver-kahn: -, gd, -, rx+pks
philipp-lahm: of, df, ec, mk+ps+st
bastian-schweinsteiger: or, aa, lr, ps+st
miroslav-klose: fb, ao, -, hd+fin
michael-ballack: bb, aa, lr, hd+ls+fo
jurgen-klinsmann: gp, fp, -, fin+hd+vel
rudi-voller: fb, fp, -, fin+hd
andreas-brehme: of, df, ec, fk+cr+pk
matthias-sammer: bu, co, -, mk+st
uwe-seeler: fb, fp, -, hd+fin
gunter-netzer: c10, ao, lb, lg+fk
fritz-walter: c10, ao, -, ps+fin
mesut-ozil: c10, ao, tr, ps
per-mertesacker: bu, hl, -, hd+mk
paolo-maldini: of, hl, -, mk+ds
franco-baresi: bu, hl, -, mk+ds
roberto-baggio: c10, ao, tr+lr, fk+dr+pk
alessandro-del-piero: hp, ao, tr, fk+fin+dr
francesco-totti: c10, ao, lr, ps+fk+ls
andrea-pirlo: or, pd, lb, fk+lg+ps
gianluigi-buffon: -, gd, -, rx+pks
fabio-cannavaro: bu, de, -, ds+mk+vel
alessandro-nesta: bu, co, -, ds+mk
dino-zoff: -, gd, -, rx
gaetano-scirea: bu, co, -, mk+ps
giuseppe-meazza: hp, ao, tr, fin+dr
gianni-rivera: c10, ao, -, ps+lg
luigi-riva: gp, ao, lr, ls+fin+fo
paolo-rossi: fb, ao, -, fin
giacinto-facchetti: of, co, -, hd+st
marco-tardelli: bb, de, lr, ds+st
gennaro-gattuso: bb, de, -, ds+st
christian-vieri: tm, ao, -, fo+fin+hd
filippo-inzaghi: fb, ao, -, fin
gianfranco-zola: hp, ao, tr, fk+dr
daniele-de-rossi: or, de, lb+lr, ds+lg+ls
giorgio-chiellini: bu, de, -, ds+fo+hd
andrea-barzagli: bu, co, -, mk
gianluca-zambrotta: of, df, sp+ec, st+cr
luca-toni: tm, ao, -, hd+fin
bobby-charlton: hp, ao, lr, ls+ps+st
bobby-moore: bu, co, lb, mk+lg
gordon-banks: -, gd, -, rx
gary-lineker: fb, ao, -, fin
alan-shearer: tm, ao, lr, fin+hd+ls
david-beckham: cs, dp, ec+lr, fk+cr+lg
steven-gerrard: bb, aa, lr, ls+lg+st
frank-lampard: hp, aa, lr, ls+fin+pk
paul-scholes: or, pd, lr+lb, ls+ps+lg
wayne-rooney: hp, fp, lr, fin+ls+st
rio-ferdinand: bu, co, -, vel+mk
john-terry: bu, de, -, hd+ds
ashley-cole: of, df, sp, vel+mk
michael-owen: gp, ao, sp, vel+fin
paul-gascoigne: c10, ao, tr+mz, dr+fk
kevin-keegan: hp, fp, -, st+hd+fin
stanley-matthews: pw, ao, tr+mz, dr+cr
jimmy-greaves: fb, ao, -, fin
peter-shilton: -, gd, -, rx
david-seaman: -, gd, -, rx+pks
tony-adams: bu, de, -, hd+ds
sol-campbell: bu, de, -, fo+hd
george-best: pw, ao, tr+mz, dr+vel
kenny-dalglish: dl, ao, -, ps+fin
denis-law: fb, ao, -, fin+hd
ryan-giggs: pw, dp, mz+ec, dr+vel+cr
ian-rush: gp, fp, -, fin
gareth-bale: pw, ao, sp+lr, vel+ls+fk
roy-keane: bb, de, -, ds+st
thierry-henry: gp, ao, sp+in, vel+fin+dr
just-fontaine: fb, ao, -, fin
raymond-kopa: c10, ao, tr, dr+ps
patrick-vieira: bb, an, -, ds+fo+st
lilian-thuram: of, df, -, mk+fo
marcel-desailly: bu, de, -, fo+ds
laurent-blanc: bu, co, lb, hd+lg
didier-deschamps: or, an, -, mk+ps
claude-makelele: or, an, -, ds+mk
franck-ribery: rf, ao, tr+mz, dr+vel
david-trezeguet: fb, ao, -, fin+hd
eric-cantona: dl, ao, -, ps+fin+fo
jean-pierre-papin: fb, ao, -, fin
fabien-barthez: gb, gs, -, rx
bixente-lizarazu: of, df, ec, mk+st
robert-pires: rf, ao, -, ps+dr
alain-giresse: c10, ao, -, ps+dr
jean-tigana: bb, aa, -, st+dr
xavi-hernandez: or, pd, -, ps+lg
andres-iniesta: hp, pd, mz, dr+ps
iker-casillas: -, gd, -, rx+pks
carles-puyol: bu, de, -, ds+hd+st
raul-gonzalez: hp, ao, -, fin
fernando-hierro: bu, co, lb, hd+fk+pk
david-villa: gp, ao, -, fin+fk
fernando-torres: gp, ao, sp, vel+fin
xabi-alonso: or, pd, lb+lr, lg+ps+ls
gerard-pique: bu, co, -, hd+ps
david-silva: cp, ao, tr, ps
cesc-fabregas: or, pd, -, ps+lg
luis-suarez-miramontes: c10, ao, lb, ps+lg
emilio-butragueno: hp, ao, tr, dr+fin
pep-guardiola: or, pd, -, ps+lg
luis-enrique: bb, aa, -, st+fin
fernando-morientes: tm, ao, -, hd
paco-gento: pw, ao, sp, vel+cr
eusebio: gp, ao, sp+lr, ls+fin+vel
luis-figo: cp, ao, tr+ec, dr+cr+ps
rui-costa: c10, ao, -, ps+lg
deco: c10, pd, -, ps+dr
ricardo-carvalho: bu, co, -, mk+ds
paulo-futre: pw, ao, tr+mz, dr+vel
nani: rf, ao, tr+lr, dr+ls
lev-yashin: gb, gs, -, rx+pks
oleg-blokhin: gp, ao, sp, vel+fin
andriy-shevchenko: gp, ao, sp+lr, fin+vel
rinat-dasayev: -, gd, -, rx
andrey-arshavin: hp, ao, tr+mz, dr
pavel-nedved: hp, dp, lr, ls+st
josef-masopust: bb, aa, -, dr+st
petr-cech: -, gd, -, rx+pks
tomas-rosicky: cp, ao, -, ps+dr
jan-koller: tm, ao, -, hd+fo
hristo-stoichkov: hp, ao, lr, fk+ls+fin
dimitar-berbatov: dl, ao, tr, fin+ps
gheorghe-hagi: c10, ao, lr+tr, fk+ls+ps
dragan-stojkovic: c10, ao, tr, dr+fk
nemanja-vidic: bu, de, -, hd+ds
dejan-stankovic: bb, aa, lr, ls+st
davor-suker: fb, ao, -, fin+fk
zvonimir-boban: c10, ao, -, ps
robert-prosinecki: c10, ao, tr, dr+fk
ivan-rakitic: bb, aa, lr, ls+ps
mario-mandzukic: tm, fp, -, hd+st
darijo-srna: of, df, ec, cr+fk
zlatan-ibrahimovic: tm, ao, tr+lr, fo+fin+dr
henrik-larsson: fb, fp, -, fin+hd
freddie-ljungberg: hp, fp, -, fin+st
michael-laudrup: c10, ao, tr, ps+dr
peter-schmeichel: gb, go, -, rx
brian-laudrup: pw, ao, tr, dr+vel
ole-gunnar-solskjr: fb, ao, -, fin
jari-litmanen: c10, ao, -, ps+fin
sami-hyypia: bu, co, -, hd+mk
zbigniew-boniek: hp, ao, in, vel+fin
grzegorz-lato: pw, ao, sp, vel+fin
kazimierz-deyna: c10, ao, lr, ps+fk
sandor-kocsis: fb, ao, -, hd+fin
nandor-hidegkuti: dl, ao, -, ps+fin
hans-krankl: fb, ao, -, fin+hd
matthias-sindelar: dl, ao, tr, dr+ps
stephane-chapuisat: gp, ao, sp, vel+fin
jean-marie-pfaff: gb, gs, -, rx+pks
enzo-scifo: c10, ao, lr, ps+fk
vincent-kompany: bu, de, -, hd+ds
eden-hazard: rf, ao, tr+mz, dr
paul-van-himst: hp, ao, -, fin+dr
hakan-sukur: tm, ao, -, hd+fin
rustu-recber: -, gs, -, rx
theodoros-zagorakis: bb, aa, -, st+ds
george-weah: gp, ao, sp+mz, vel+fo+fin
samuel-eto-o: gp, fp, sp, vel+fin
roger-milla: fb, ao, -, fin
didier-drogba: tm, ao, lr, fo+hd+fk
yaya-toure: bb, aa, mz+lr, fo+ls+st
kolo-toure: bu, co, -, vel+fo
jay-jay-okocha: cp, ao, tr+mz, dr+fk
nwankwo-kanu: dl, ao, tr, dr+fin
michael-essien: bb, de, lr, fo+st+ds
abedi-pele: c10, ao, tr, dr+ps
rabah-madjer: hp, ao, tr, fin+dr
mustapha-hadji: cp, ao, lr, ls+dr
el-hadji-diouf: hp, fp, sp, vel+dr
frederic-kanoute: tm, ao, -, fo+fin
mohamed-aboutrika: c10, ao, -, ps+fin
hidetoshi-nakata: cp, pd, -, ps+st
shunsuke-nakamura: c10, ao, lb, fk+ps
park-ji-sung: bb, aa, -, st+mk
cha-bum-kun: gp, ao, sp, vel+fin
ali-daei: tm, ao, -, hd+fin
tim-cahill: hp, fp, -, hd+fin
harry-kewell: rf, ao, tr, dr+ls
mark-viduka: tm, ao, -, fo+fin
landon-donovan: hp, ao, in, vel+pk
clint-dempsey: hp, ao, -, fin+st
tim-howard: -, gd, -, rx
dwight-yorke: hp, ao, -, fin+ps
alberto-spencer: fb, ao, -, hd+fin
alex-aguinaga: c10, ao, -, ps+fk
antonio-valencia: pw, ao, sp+ec, vel+cr
juan-arango: c10, ao, lr, fk+ls
marco-etcheverry: c10, ao, tr, dr+ps
arsenio-erico: fb, ao, tr, fin+hd
hector-chumpitaz: bu, co, -, mk+fk
nolberto-solano: cs, dp, ec, cr+fk
leonel-sanchez: pw, ao, lr, ls+fin
mario-yepes: bu, de, -, hd+ds
marcelo: of, df, mz+ec, dr+cr
fernandinho: or, an, -, ds+ps+st
toni-kroos: or, pd, lb+lr, ps+lg+ls
"""

DATA2 = """
lionel-messi: rf, ao, tr+mz, dr+fk+ps
cristiano-ronaldo: gp, ao, sp+lr, fin+hd+ls
neymar-jr: rf, ao, tr+mz, dr+fk+vel
karim-benzema: dl, ao, -, fin+ps
robert-lewandowski: fb, fp, -, fin+hd
sergio-ramos: ef, de, -, hd+ds+pk
mohamed-salah: rf, ao, sp+in, vel+fin
arthur-friedenreich: gp, ao, tr, fin+dr
dani-alves: of, df, ec, cr+st
coutinho: hp, ao, lr+tr, ls+dr
domingos-da-guia: bu, co, -, mk+dr
ademir-de-menezes: gp, ao, sp, fin+vel
jose-manuel-moreno: hp, ao, tr, dr+fin
valentino-mazzola: hp, ao, lr, ls+st
gunnar-nordahl: fb, ao, -, fin+fo
antoine-griezmann: hp, fp, lr, fin+fk
sadio-mane: pw, fp, sp, vel+fin
son-heung-min: rf, ao, sp+lr, vel+fin+ls
casemiro: or, an, lr, ds+hd+ls
sergio-busquets: or, pd, -, ps+mk
edinson-cavani: fb, fp, -, fin+hd+st
radamel-falcao: fb, ao, -, fin+hd
adolfo-pedernera: dl, ao, -, ps+dr
angel-labruna: fb, ao, -, fin
jose-leandro-andrade: bb, aa, mz, dr+st
willem-van-hanegem: or, pd, lb, lg+ps
rob-rensenbrink: pw, ao, tr, dr+fin
bernd-schuster: or, pd, lb+lr, lg+ls
wolfgang-overath: c10, ao, -, ps+lg
sandro-mazzola: hp, ao, -, fin+dr
silvio-piola: fb, ao, -, fin+hd
tom-finney: pw, ao, tr, dr+cr
duncan-edwards: bb, aa, lr, fo+ls+st
john-charles: tm, ao, -, hd+fo
dragan-dzajic: pw, ao, tr+ec, dr+cr+fk
florian-albert: hp, ao, tr, dr+fin
jozsef-bozsik: or, pd, -, ps+lg
eduard-streltsov: dl, ao, -, fin+ps
nils-liedholm: or, pd, lb, ps+lg
thomas-muller: dr, fp, -, fin+st
mats-hummels: bu, co, lb, lg+mk
keylor-navas: -, gd, -, rx
hugo-lloris: gb, gs, -, rx
leonardo-bonucci: bu, co, lb, lg+mk
paul-pogba: bb, aa, lr+mz, ls+lg+fo
mario-coluna: bb, aa, lr, ls+ps
toninho-cerezo: bb, aa, -, ps+st
pepe-macia: pw, ao, lr, fin+ls
zito: or, an, -, ds+ps
heleno-de-freitas: fb, ao, -, fin+hd
julinho-botelho: pw, ao, tr, dr+cr
amadeo-carrizo: gb, gs, -, rx
ladislao-mazurkiewicz: -, gs, -, rx
alcides-ghiggia: pw, ao, sp, vel+fin
hector-scarone: hp, ao, -, fin+ps
faas-wilkes: hp, ao, tr+mz, dr
helmut-rahn: pw, ao, lr, ls+fin
gianluca-vialli: tm, fp, -, hd+fin+st
walter-zenga: -, gd, -, rx
bryan-robson: bb, aa, -, st+hd+fin
dixie-dean: tm, ao, -, hd+fin
graeme-souness: bb, de, lr, ds+ps
telmo-zarra: fb, ao, -, hd+fin
dejan-savicevic: c10, ao, tr, dr+ps
zoltan-czibor: pw, ao, sp, vel+ls
gunnar-gren: c10, ao, -, ps
kurt-hamrin: pw, ao, sp, vel+fin
allan-simonsen: hp, ao, sp, vel+fin
riyad-mahrez: rf, ao, tr+in, dr+fk
jordi-alba: of, df, sp+ec, vel+cr
marco-reus: hp, ao, lr, fin+fk
jerome-boateng: bu, de, lb, lg+fo
alexis-sanchez: rf, fp, tr, dr+st
marco-verratti: or, pd, -, ps+dr
ciro-immobile: gp, ao, -, fin
raphael-varane: bu, co, -, vel+hd
thiago-alcantara: or, pd, -, ps+dr
roberto-firmino: dl, fp, -, ps+st
eder-aleixo: pw, ao, lr, ls+fk
clodoaldo: or, pd, -, ps+dr
jair-da-rosa-pinto: c10, ao, lr, ls+ps
fernando-morena: fb, ao, -, fin+hd
abe-lenstra: hp, ao, tr, dr+fin
pierre-littbarski: pw, ao, tr, dr+cr
jurgen-kohler: bu, sm, -, mk+ds
berti-vogts: of, sm, -, mk+st
toni-schumacher: -, go, -, rx
stefan-effenberg: or, pd, lb+lr, lg+ls
roberto-mancini: dl, ao, tr, ps+dr
bruno-conti: pw, ao, tr, dr+cr
giuseppe-bergomi: bu, sm, -, mk+ds
antonio-cabrini: of, co, ec, cr+ls
claudio-gentile: bu, sm, -, ds+mk
giancarlo-antognoni: c10, ao, -, ps+lg
angelo-peruzzi: -, gd, -, rx
alessandro-costacurta: bu, hl, -, mk
glenn-hoddle: c10, ao, lb+lr, lg+ls+ps
john-barnes: pw, ao, tr, dr+cr
ray-clemence: -, gd, -, rx
geoff-hurst: tm, ao, -, hd+fin
billy-wright: bu, co, -, hd+mk
billy-bremner: bb, de, -, ds+st
neville-southall: -, gd, -, rx
pat-jennings: -, gd, -, rx
youri-djorkaeff: hp, ao, lr, ls+fk
andoni-zubizarreta: -, gd, -, rx
luis-arconada: -, gd, -, rx
amancio-amaro: pw, ao, tr, dr+vel
jose-angel-iribar: -, gd, -, rx
jan-ceulemans: hp, ao, -, hd+fo
michel-preudhomme: -, gd, -, rx
predrag-mijatovic: hp, ao, tr, dr+fin
safet-susic: c10, ao, tr, dr+ps
gyula-grosics: gb, gs, -, rx
georgi-asparuhov: gp, ao, -, fin+hd
igor-belanov: gp, ao, sp+lr, vel+ls
preben-elkjr: gp, ao, sp, vel+fo
herbert-prohaska: or, pd, -, ps
kalidou-koulibaly: bu, de, -, fo+ds
salif-keita: gp, ao, sp, vel+fin
lorenzo-insigne: rf, ao, in+lr, ls+dr
diego-costa: tm, fp, -, fo+fin
santi-cazorla: or, pd, lr, ps+fk
victor-valdes: gb, gs, -, rx
vitor-baia: -, gd, -, rx
david-luiz: bu, de, lb, fk+lg
filipe-luis: of, df, -, mk+st
branco: of, df, ec, fk+ls
muller: gp, ao, sp, vel+fin
emerson-leao: -, gd, -, rx
paulo-cesar-caju: pw, ao, tr, dr+ps
mauro-ramos: bu, co, -, mk+ps
bellini: bu, de, -, hd+ds
dirceu-lopes: c10, ao, tr, dr+ps
evaristo-de-macedo: fb, ao, -, fin+hd
danilo-alvim: or, pd, -, ps+lg
dejan-petkovic: c10, ao, lr, fk+ps
marcelinho-carioca: c10, ao, lr, fk+ls
renato-gaucho: pw, ao, tr+mz, dr+vel
mario-jardel: fb, ao, -, hd+fin
antonio-rattin: or, an, -, ds+mk
norberto-alonso: c10, ao, -, ps+fk
osvaldo-ardiles: bb, aa, mz, dr+ps
jorge-valdano: tm, ao, -, fin+hd
ramon-diaz: fb, ao, -, fin
luis-cubilla: pw, ao, tr, dr+fin
carlos-caszely: fb, ao, -, fin
julio-cesar-romero: c10, ao, -, ps+fk
johnny-rep: pw, ao, sp, vel+fin
arie-haan: bb, pd, lr, ls+ps
phillip-cocu: or, pd, -, ps+mk
rafael-van-der-vaart: c10, ao, lr, ls+ps+fk
sami-khedira: bb, aa, -, st+mk
thomas-haler: c10, ao, lr, fk+dr
andreas-kopke: -, gd, -, rx+pks
jens-lehmann: -, gd, -, rx+pks
uli-hoene: bb, aa, mz, vel+ps
franco-causio: pw, ao, tr+ec, dr+cr
gianluca-pagliuca: -, gd, -, rx+pks
francesco-toldo: -, gd, -, rx+pks
demetrio-albertini: or, pd, lb, ps+lg
roberto-donadoni: cs, dp, ec, cr+dr
pietro-vierchowod: bu, sm, -, ds+vel
ciro-ferrara: bu, co, -, mk+ds
mauro-tassotti: of, df, -, mk+cr
antonio-di-natale: gp, ao, lr, fin+ls
peter-beardsley: hp, ao, tr, dr+ps
martin-peters: bb, aa, -, fin+st
ian-wright: gp, ao, sp, vel+fin
robbie-fowler: fb, ao, -, fin
paul-mcgrath: bu, co, -, hd+mk
liam-brady: or, pd, lb, lg+ps
danny-blanchflower: or, pd, -, ps
nicolas-anelka: gp, ao, sp, vel+fin
patrice-evra: of, df, -, mk+st
manuel-amoros: of, df, -, mk+st
maxime-bossis: bu, co, -, mk
marius-tresor: bu, co, -, mk+hd
luis-fernandez: or, an, -, ds+st
jose-antonio-camacho: of, df, -, ds+st
rafael-gordillo: of, df, ec, cr+st
michel-gonzalez: cs, dp, ec, cr+ps
carlos-santillana: fb, ao, -, hd+fin
juanito: pw, ao, tr, dr+fin
eric-gerets: of, df, -, mk+st
sinisa-mihajlovic: bu, de, lb, fk+lg+ls
miralem-pjanic: or, pd, lr, fk+ps
wodzimierz-lubanski: gp, ao, -, fin+vel
antonin-panenka: c10, ao, -, pk+ps+fk
ivo-viktor: -, gd, -, rx
krasimir-balakov: c10, ao, lr, fk+ps
valentin-ivanov: hp, ao, -, fin+dr
albert-shesternyov: bu, co, -, mk+vel
morten-olsen: bu, co, -, mk+ps
bruno-pezzey: ef, co, -, hd+mk
lefter-kucukandonyadis: hp, ao, -, fin+dr
thomas-nkono: -, gs, -, rx
laurent-pokou: gp, ao, tr, fin+dr
lakhdar-belloumi: c10, ao, -, ps+fk
mahmoud-el-khatib: hp, ao, -, fin+dr
kunishige-kamamoto: fb, ao, -, fin+hd
dimitri-payet: c10, ao, lr, fk+cr
juan-mata: cp, ao, -, ps+fk
fernando-couto: bu, de, -, hd+ds
pauleta: fb, ao, -, fin+hd
jose-aguas: fb, ao, -, hd+fin
fernando-chalana: pw, ao, tr+mz, dr
humberto-coelho: bu, co, -, mk+hd
joao-pinto: hp, ao, tr, dr+fin
willian: pw, fp, tr, dr+st
douglas-costa: pw, ao, sp+lr, vel+dr
alexandre-pato: gp, ao, sp, vel+fin
jorginho-putinatti: of, df, ec, cr+st
zinho: cp, pd, -, ps+st
ricardo-rocha: bu, de, -, ds+hd
wilson-piazza: bu, co, -, mk+ps
castilho: -, gd, -, rx
canhoteiro: pw, ao, tr, dr
moacir-barbosa: -, gd, -, rx
bauer: or, an, -, ds+ps
emerson-ferreira: or, an, -, ds+st
edilson: hp, ao, tr, dr+fin
dario-conca: c10, ao, -, ps+fk
andres-dalessandro: c10, ao, tr, dr+ps
evair: fb, ao, -, fin+pk
ricardo-gomes: bu, co, -, hd+mk
carlos-mozer: bu, de, -, ds+hd
juan-pablo-sorin: of, df, -, st+hd
daniel-bertoni: pw, ao, -, fin+vel
leopoldo-luque: tm, ao, -, fin+hd
sergio-goycochea: -, gd, -, pks+rx
ruben-sosa: hp, ao, lr, fk+ls
ruben-paz: c10, ao, -, ps+fk
hector-castro: fb, ao, -, fin
willington-ortiz: pw, ao, tr, dr
andres-escobar: bu, co, -, mk+ps
hugo-sotil: hp, ao, tr, dr+fin
cesar-cueto: c10, ao, -, ps+dr
wim-suurbier: of, df, -, vel+st
ronald-de-boer: hp, ao, -, ps+fin
giovanni-van-bronckhorst: of, df, -, ls+ps
mark-van-bommel: or, de, -, ds+ps
horst-hrubesch: tm, ao, -, hd+fo
klaus-allofs: fb, ao, -, fin
oliver-bierhoff: tm, ao, -, hd+fin
mehmet-scholl: c10, ao, -, ps+fk
torsten-frings: or, an, lr, ds+ls
lukas-podolski: pw, ao, lr, ls+fin
antonio-cassano: dl, ao, tr, ps+dr
raheem-sterling: pw, ao, sp+mz, vel+dr
jamie-carragher: bu, co, -, mk+ds
gary-neville: of, df, ec, cr+mk
chris-waddle: pw, ao, tr, dr+cr
teddy-sheringham: dl, ao, -, ps+hd
stuart-pearce: of, df, -, fk+ds
nobby-stiles: or, sm, -, ds+st
jack-charlton: bu, de, -, hd+mk
trevor-francis: gp, ao, sp, vel+fin
michael-carrick: or, pd, lb, ps+lg
matt-le-tissier: c10, ao, lr, fk+pk+ls
jim-baxter: or, pd, -, ps+dr
mark-hughes: tm, ao, -, fo+fin
emmanuel-petit: or, aa, lb+lr, lg+ls
william-gallas: bu, co, -, mk
samir-nasri: cp, ao, tr, dr+ps
dominique-rocheteau: pw, ao, tr, dr+fin
gaizka-mendieta: bb, aa, lr, ls+fk
quini: fb, ao, -, fin
guti: c10, ao, -, ps+lg
dries-mertens: hp, ao, lr, ls+fk
jan-vertonghen: bu, co, lb, lg+mk
toby-alderweireld: bu, co, lb, lg+mk
alen-boksic: tm, ao, -, fo+fin
branislav-ivanovic: of, df, -, hd+fo
jan-tomaszewski: -, gd, -, pks+rx
karel-poborsky: pw, ao, ec, cr+st
lajos-detari: c10, ao, lr, fk+ls
gheorghe-popescu: bu, co, lb, lg+mk
adrian-mutu: hp, ao, tr, fin+fk
cristian-chivu: bu, co, lb, lg+fk
serhiy-rebrov: hp, ao, -, fin+ls
aleksandr-mostovoi: c10, ao, -, ps+dr
igor-akinfeev: -, gd, -, rx
tomas-brolin: hp, ao, -, fin+ps
toni-polster: fb, ao, -, fin+fk
andreas-herzog: c10, ao, -, fk+ps
arda-turan: cp, ao, tr, dr+ps
emmanuel-adebayor: tm, ao, -, hd+fo
rashidi-yekini: tm, ao, -, fo+fin
mohamed-timoumi: c10, ao, tr, dr+ps
noureddine-naybet: bu, co, -, mk+hd
badou-zaki: -, gd, -, rx
tony-yeboah: gp, ao, lr, ls+fo
kalusha-bwalya: c10, ao, -, fk+ps
hong-myung-bo: bu, co, lb, lg+mk
shinji-kagawa: cp, ao, -, ps+dr
majed-abdullah: fb, ao, -, fin
blaise-matuidi: bb, aa, -, st+ds
javier-hernandez: fb, ao, -, fin
carlos-vela: rf, ao, tr, dr+fin
"""


def main():
    data_src = (ROOT / 'supabase/online/10_legends_data.sql').read_text() + (ROOT / 'supabase/online/23_catalog_data.sql').read_text()
    pos = {m[0]: m[2] for m in re.findall(r"\('lg-([^']+)','((?:[^']|'')*)','([A-Z]+)'", data_src)}
    rows, errors = [], []
    for line in (DATA + DATA2).strip().splitlines():
        if not line.strip():
            continue
        key, rest = line.split(':', 1)
        key = key.strip()
        off, df, ai, tr = [x.strip() for x in rest.split(',')]
        if key not in pos:
            errors.append(f'{key}: lenda inexistente')
            continue
        p = pos[key]
        off_c = None if off == '-' else OFF[off]
        def_c = DEF[df]
        ai_c = [] if ai == '-' else [AI[a] for a in ai.split('+')]
        tr_c = [] if tr == '-' else [TR[t] for t in tr.split('+')]
        for code in [off_c, def_c, *ai_c]:
            if code and p not in POS[code].split():
                errors.append(f'{key} ({p}): estilo {code} não existe na posição')
        if len(tr_c) > 3:
            errors.append(f'{key}: mais de 3 especialidades')
        rows.append((f'lg-{key}', off_c, def_c, ai_c, tr_c))
    missing = sorted(set(pos) - {r[0][3:] for r in rows})
    if missing:
        errors.append('sem perfil: ' + ', '.join(missing))
    if errors:
        print('\n'.join(errors))
        sys.exit(1)
    q = lambda v: 'null' if v is None else "'" + v + "'"
    arr = lambda xs: "'{" + ','.join(xs) + "}'"
    values = ',\n'.join(f"({q(i)},{q(o)},{q(d)},{arr(a)},{arr(t)})" for i, o, d, a, t in rows)
    out = f"""-- MODO ONLINE — Fase 34 (dados): estilos e especialidades das lendas, escritos à mão.
-- Gerado por scripts/build-legend-profiles.py (edite lá e rode de novo). Uma linha por lenda de on_legends:
-- estilo com a bola, estilo sem a bola, estilos da IA e até 3 especialidades da vida real (on_traits).
insert into public.on_legend_profiles(id,style_off,style_def,ai_styles,traits) values
{values}
on conflict(id) do update set style_off=excluded.style_off,style_def=excluded.style_def,ai_styles=excluded.ai_styles,traits=excluded.traits;

-- lendas que já estão em algum clube recebem o perfil
update public.on_players p set style_off=l.style_off,style_def=l.style_def,ai_styles=l.ai_styles,traits=l.traits
 from public.on_legend_profiles l where p.src=l.id;
"""
    (ROOT / 'supabase/online/37_legend_profiles_data.sql').write_text(out)
    print(f'{len(rows)} lendas')


if __name__ == '__main__':
    main()
