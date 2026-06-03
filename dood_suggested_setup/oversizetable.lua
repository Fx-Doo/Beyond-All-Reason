-- CATEGORIES:
-- size = 1 : a very light passenger that can be carried by any transport, 
-- a light transport can hold two without any speed loss

-- size = 1.5 : a light passenger that can be carried by any transport, 
-- a light transport can hold two but with a small speed loss (20%)

-- size = 2 : a medium passenger that can be carried by any transport,
-- a light transport can hold one without any speed loss

-- size = 3 : a medium passenger that can be carried by any transport,
-- a light transport can hold one but with a small speed loss (20%)

-- size = 4 : a heavy passenger that can only be carried by heavy transports or t2 transports,
-- they can only be carried one at a time, without any speed loss

-- size = 6 : a very heavy passenger that can only be carried by heavy transports or t2 transports,
-- they can only be carried one at a time, with a speed loss ranging from 15 to 30% depending on the transport

-- Special case: Commanders are considered size 5; 
-- but regardless of their overweight tag, they will always slow their transporter
-- to their respective maximal speedNerf value.

return {
-- ARM Commanders
  armcom = { passengersize = 6 },
  armcomcon = { passengersize = 6 },
  armcomlvl2 = { passengersize = 6 },
  armcomlvl3 = { passengersize = 6 },
  armcomlvl4 = { passengersize = 6 },
  armcomlvl5 = { passengersize = 6 },
  armcomlvl6 = { passengersize = 6 },
  armcomlvl7 = { passengersize = 6 },
  armcomlvl8 = { passengersize = 6 },
  armcomlvl9 = { passengersize = 6 },
  armcomlvl10 = { passengersize = 6 },
  armcomnew = { passengersize = 6 },
  -- ARM Bots T1
  armck = { passengersize = 2 },
  armflea = { passengersize = 1 },
  armham = { passengersize = 1.5 },
  armjeth = { passengersize = 1.5 },
  armpw = { passengersize = 1 },
  armrectr = { passengersize = 1 },
  armrock = { passengersize = 1.5 },
  armwar = { passengersize = 2 },
  -- ARM Bots T2
  armaak = { passengersize = 3 }, -- t2 aa bot
  armack = { passengersize = 2 }, -- t2 con
  armamph = { passengersize = 2 }, -- platy
  armaser = { passengersize = 2 }, -- jammer?
  armdecom = { passengersize = 6 }, -- decoy com
  armdecomlvl3 = { passengersize = 6 }, -- decoy com
  armdecomlvl6 = { passengersize = 6 }, -- decoy com
  armdecomlvl10 = { passengersize = 6 }, -- decoy com
  armfark = { passengersize = 1 }, -- butler
  armfast = { passengersize = 2 }, -- sprinter
  armfboy = { passengersize = 6 }, -- fattie
  armfido = { passengersize = 3 }, -- hound
  armhack = { passengersize = 1 }, -- ?
  armmark = { passengersize = 2 }, -- radar bot
  armmav = { passengersize = 3 }, -- maverick
  armsack = { passengersize = 1 }, -- ?
  armscab = { passengersize = 6 }, -- mob anti
  armsnipe = { passengersize = 3 }, -- sniper
  armspid = { passengersize = 1.5 }, -- emp spider
  armsptk = { passengersize = 4 }, -- rocker spider (ex recluse)
  armspy = { passengersize = 2 }, -- ghost
  armvader = { passengersize = 1 }, -- crawling bomb
  armzeus = { passengersize = 3 }, -- welder
  -- ARM Vehicles T1
  armart = { passengersize = 2 }, -- artillery
  armbeaver = { passengersize = 2 }, -- amphib con
  armcv = { passengersize = 2 }, -- con
  armfav = { passengersize = 1 }, -- fav
  armflash = { passengersize = 1.5 }, -- blitz
  armjanus = { passengersize = 2 }, -- janus OP <3
  armmlv = { passengersize = 1 }, -- minelayer
  armpincer = { passengersize = 2 }, -- amphib
  armsam = { passengersize = 2 }, -- missile
  armstump = { passengersize = 2 }, -- stout
  -- ARM Vehicles T2
  armacv = { passengersize = 3 }, -- a con veh
  armbull = { passengersize = 4 }, -- bull
  armconsul = { passengersize = 2 }, -- consul
  armcroc = { passengersize = 4 }, -- turtle
  armgremlin = { passengersize = 2 }, -- gremlin
  armhacv = { passengersize = 4 }, -- ?
  armjam = { passengersize = 2 }, --jammer veh
  armlatnk = { passengersize = 2 }, -- jaguar
  armmanni = { passengersize = 6 }, -- starlight
  armmart = { passengersize = 4 }, -- luger/mauser
  armmerl = { passengersize = 6 }, -- missile
  armsacv = { passengersize = 4 }, -- ?
  armseer = { passengersize = 2 }, -- radar veh
  armyork = { passengersize = 3 }, -- flak veh
  -- ARM Hovercraft
  armah = { passengersize = 3 }, -- aa hover
  armanac = { passengersize = 3 }, -- hovertank
  armch = { passengersize = 2 }, -- con hover
  armmh = { passengersize = 3 }, -- missile hover
  armsh = { passengersize = 1.5 }, -- scout hover
  -- ARM Buildings
  armbeamer = { passengersize = 4 },
  armllt = { passengersize = 4 },
  armnanotc = { passengersize = 2 },
  armnanotc2plat = { passengersize = 6 },
  armnanotct2 = { passengersize = 6 },
  armrad = { passengersize = 4 },
  armrl = { passengersize = 4 },
  -- ARM Assist Drone
  armassistdrone_land = { passengersize = 1 },
  -- COR Commanders
  corcom = { passengersize = 6 },
  corcomcon = { passengersize = 6 },
  corcomlvl2 = { passengersize = 6 },
  corcomlvl3 = { passengersize = 6 },
  corcomlvl4 = { passengersize = 6 },
  corcomlvl5 = { passengersize = 6 },
  corcomlvl6 = { passengersize = 6 },
  corcomlvl7 = { passengersize = 6 },
  corcomlvl8 = { passengersize = 6 },
  corcomlvl9 = { passengersize = 6 },
  corcomlvl10 = { passengersize = 6 },
  -- COR Bots T1
  corak = { passengersize = 1 }, -- grunt
  corck = { passengersize = 2 }, -- con bot
  corcrash = { passengersize = 1.5 }, -- aa bot
  cornecro = { passengersize = 1 }, -- rez
  corstorm = { passengersize = 1.5 }, -- rocket bot
  corthud = { passengersize = 1.5 }, -- plasma bot
  -- COR Bots T2
  coraak = { passengersize = 3 }, -- aa bot
  corack = { passengersize = 2 }, -- t2 con
  coramph = { passengersize = 3 }, -- duck
  corcan = { passengersize = 3 }, -- sumo
  cordecom = { passengersize = 6 }, -- decoy com
  cordecomlvl3 = { passengersize = 6 },
  cordecomlvl6 = { passengersize = 6 },
  cordecomlvl10 = { passengersize = 6 },
  corfast = { passengersize = 1 }, -- freaker
  corhack = { passengersize = 1 }, -- ?
  corhrk = { passengersize = 3 }, -- rocket bot
  cormando = { passengersize = 2 }, -- commando (prolly a 2+, but since it's a paratrooper, let's downgrade it to 2 ?)
  cormort = { passengersize = 3 }, -- sheldon
  corpyro = { passengersize = 2 }, -- FIENDDDDD OP
  corroach = { passengersize = 1 }, -- crawling
  corsack = { passengersize = 1 }, -- ?
  corsktl = { passengersize = 1.5 }, -- skuttle
  corspec = { passengersize = 2 }, -- jammer?
  corspy = { passengersize = 2 }, -- spectre
  corsumo = { passengersize = 6 }, -- mammoth
  cortermite = { passengersize = 4 }, -- termite
  corvoyr = { passengersize = 2 }, -- radar
  -- COR Vehicles T1
  corcv = { passengersize = 2 }, -- con veh
  corfav = { passengersize = 1 }, -- scout veh
  corgarp = { passengersize = 2 }, -- amphib veh
  corgator = { passengersize = 1.5 }, -- incisor
  corlevlr = { passengersize = 2 }, -- pounder
  cormist = { passengersize = 2 }, -- missile truck
  cormlv = { passengersize = 2 }, -- minelayer
  cormuskrat = { passengersize = 2 }, -- amphib con veh
  corraid = { passengersize = 2 }, -- brute
  corwolv = { passengersize = 2 }, -- arti
  -- COR Vehicles T2
  coracv = { passengersize = 2 }, -- adv con
  corban = { passengersize = 4 }, -- banisher
  coreter = { passengersize = 2 }, -- jammer
  corgol = { passengersize = 6 }, -- tzar
  corhacv = { passengersize = 4 }, -- ?
  cormabm = { passengersize = 6 }, -- mobile anti
  cormart = { passengersize = 4 }, -- art
  corparrow = { passengersize = 4 }, -- poison arrow
  corphantom = { passengersize = 2 }, -- amphib stealth scout
  corprinter = { passengersize = 4 }, -- ?
  correap = { passengersize = 4 }, -- reaper
  corsacv = { passengersize = 4 }, -- ?
  corsala = { passengersize = 4 }, -- salamander
  corseal = { passengersize = 4 }, -- alligator
  corsent = { passengersize = 4 }, -- aa veh
  corsiegebreaker = { passengersize = 16 }, --?
  cortrem = { passengersize = 6 }, -- tremor
  corvac = { passengersize = 3 }, -- field engineer?
  corvacct = { passengersize = 3 }, -- ?
  corvrad = { passengersize = 2 }, -- mob vveh rad ?
  corvroc = { passengersize = 6 }, -- vroc?
  -- COR Hovercraft
  corah = { passengersize = 3 },
  corch = { passengersize = 2 },
  corhal = { passengersize = 4 },
  cormh = { passengersize = 3 },
  corsh = { passengersize = 1.5 },
  corsnap = { passengersize = 3 },
  -- COR Buildings
  corhllt = { passengersize = 4 },
  corllt = { passengersize = 4 },
  cornanotc = { passengersize = 2 },
  cornanotc2plat = { passengersize = 6 },
  cornanotct2 = { passengersize = 6 },
  corrad = { passengersize = 4 },
  corrl = { passengersize = 4 },
  -- COR Assist Drone
  corassistdrone_land = { passengersize = 1 },
  -- HATs
  cor_hat_fightnight = { passengersize = 1 },
  cor_hat_hornet = { passengersize = 1 },
  cor_hat_hw = { passengersize = 1 },
  cor_hat_legfn = { passengersize = 1 },
  cor_hat_ptaq = { passengersize = 1 },
  cor_hat_viking = { passengersize = 1 },
  -- Legion Commanders
  legcom = { passengersize = 6 },
  legcomecon = { passengersize = 1 },
  legcomoff = { passengersize = 6 },
  legcomt2com = { passengersize = 6 },
  legcomt2def = { passengersize = 6 },
  legcomt2off = { passengersize = 6 },
  legcomlvl2 = { passengersize = 6 },
  legcomlvl3 = { passengersize = 6 },
  legcomlvl4 = { passengersize = 6 },
  legcomlvl5 = { passengersize = 6 },
  legcomlvl6 = { passengersize = 6 },
  legcomlvl7 = { passengersize = 6 },
  legcomlvl8 = { passengersize = 6 },
  legcomlvl9 = { passengersize = 6 },
  legcomlvl10 = { passengersize = 6 },
  -- Legion Bots T1
  legaabot = { passengersize = 1 },
  legbal = { passengersize = 1 },
  legcen = { passengersize = 1 },
  leggob = { passengersize = 1 },
  legkark = { passengersize = 1 },
  leglob = { passengersize = 1 },
  legrezbot = { passengersize = 1 },
  -- Legion Bots T2
  legadvaabot = { passengersize = 1 },
  legajamk = { passengersize = 1 },
  legamph = { passengersize = 4 },
  legaradk = { passengersize = 1 },
  legaspy = { passengersize = 1 },
  legbart = { passengersize = 4 },
  legdecom = { passengersize = 6 },
  legdecomlvl3 = { passengersize = 6 },
  legdecomlvl6 = { passengersize = 6 },
  legdecomlvl10 = { passengersize = 6 },
  leghrk = { passengersize = 4 },
  leginc = { passengersize = 4 },
  leginfestor = { passengersize = 4 },
  legshot = { passengersize = 1 },
  legsnapper = { passengersize = 1 },
  legsrail = { passengersize = 4 },
  legstr = { passengersize = 4 },
  -- Legion Vehicles T1
  legamphtank = { passengersize = 4 },
  legbar = { passengersize = 4 },
  leggat = { passengersize = 4 },
  leghades = { passengersize = 1 },
  leghelios = { passengersize = 1 },
  legmlv = { passengersize = 1 },
  legrail = { passengersize = 4 },
  legscout = { passengersize = 1 },
  -- Legion Vehicles T2
  legaheattank = { passengersize = 4 },
  legamcluster = { passengersize = 4 },
  legaskirmtank = { passengersize = 4 },
  legavantinuke = { passengersize = 4 },
  legavjam = { passengersize = 4 },
  legavrad = { passengersize = 4 },
  legavroc = { passengersize = 4 },
  legfloat = { passengersize = 4 },
  legfmg = { passengersize = 4 },
  leginf = { passengersize = 4 },
  legmed = { passengersize = 4 },
  legmrv = { passengersize = 1 },
  legvcarry = { passengersize = 4 },
  legvflak = { passengersize = 4 },
  -- Legion Hovercraft
  legah = { passengersize = 4 },
  legcar = { passengersize = 4 },
  legmh = { passengersize = 4 },
  legner = { passengersize = 4 },
  legsh = { passengersize = 4 },
  -- Legion Ships
  leganavybattleship = { passengersize = 16 },
  -- Legion Constructors
  legack = { passengersize = 1 },
  legaceb = { passengersize = 1 },
  legacv = { passengersize = 4 },
  legafcv = { passengersize = 4 },
  legch = { passengersize = 4 },
  legck = { passengersize = 1 },
  legcv = { passengersize = 4 },
  leghack = { passengersize = 1 },
  leghacv = { passengersize = 4 },
  legotter = { passengersize = 4 },
  -- Legion Buildings
  leglht = { passengersize = 1 },
  legmg = { passengersize = 4 },
  legnanotc = { passengersize = 4 },
  legnanotct2 = { passengersize = 4 },
  legnanotct2plat = { passengersize = 4 },
  legrad = { passengersize = 1 },
  legrl = { passengersize = 4 },
  -- Legion T3
  leegmech = { passengersize = 4 },
  legerailtank = { passengersize = 16 },
  legeshotgunmech = { passengersize = 4 },
  -- Legion Assist Drone
  legassistdrone_land = { passengersize = 1 },
  -- Baby Units
  babyleggob = { passengersize = 1 },
  babyleglob = { passengersize = 1 },
  babylegshot = { passengersize = 1 },
  -- Debug
  dbg_sphere = { passengersize = 1 },
  dbg_sphere_fullmetal = { passengersize = 1 },
  -- Dummy
  dummycom = { passengersize = 6 },
}