--!strict
-- Cinematique d'ouverture (profil neuf : IntroSeen == false et Setup == 0), jouee une fois par le
-- client (IntroController) ; le serveur (IntroService) ecrit seulement IntroSeen a la fin.
-- Repere du decor ReplicatedStorage.IntroSet (tools/build-map/02m-intro-set.luau) : origine = pied
-- du grand arbre, sol a y = 0, X = sens de la marche. Le decor est clone a SetOrigin (loin de la carte).
-- Pas de bouton Skip (retire le 2026-11-22 a la demande de l'utilisateur).
-- Doc : docs/systems/cinematique.md

export type Shot = {
	t: number, -- seconde du plan
	space: "Set" | "Actor", -- Set : repere du decor ; Actor : repere de l'acteur (-Z = devant lui)
	pos: Vector3,
	look: Vector3,
	cut: boolean?, -- vrai : coupe franche (pas de glissement depuis le plan precedent)
	fov: number?,
	ease: "slow"?, -- glissement vers le plan suivant : depart et arrivee tres doux (grand mouvement de grue)
	blur: number?, -- flou du fond (0 = net, 1 = tres flou) ; le personnage reste net (Intro.Mood.FocusRadius)
}

local Intro = {}

-- Ou le decor est clone (chez le joueur seulement) : haut dans le ciel, loin de la carte.
Intro.SetOrigin = Vector3.new(0, 1200, 0)

-- Positions dans le repere du decor (y = 0 : le sol)
Intro.ActorStart = Vector3.new(-50, 0, 7) -- il marche sur le chemin (deja pendant le plan d'ouverture)...
Intro.NoticeSpot = Vector3.new(-32, 0, 7) -- ...s'arrete : il voit l'arbre DE LOIN
Intro.ActorStop = Vector3.new(-11, 0, 5) -- il a couru jusqu'au bord de la clairiere
Intro.ShovelSpot = Vector3.new(-9, 0, 8.5) -- pelle plantee dans le sol (visible des le debut)
Intro.ShovelReach = 1.7 -- distance pelle -> acteur quand il l'arrache
Intro.ShovelDepth = 1.1 -- lame enfoncee dans le sol (plantee, puis reposee apres le creusage)
Intro.ShovelRestSide = 1.8 -- pelle replantee a sa gauche apres le creusage (studs)
Intro.DigSpot = Vector3.new(-9, 0, 3.5) -- pres de l'arbre, hors des racines (il creuse en regardant le tronc)
Intro.HoleOffset = Vector3.new(2.4, 0, -0.9) -- trou (depuis DigSpot, devant lui, cote arbre)
Intro.PileOffset = Vector3.new(-0.6, 0, 2.4) -- tas de terre (depuis DigSpot, a sa droite, un peu derriere)
Intro.ShovelScale = 0.95 -- pelle a l'echelle du personnage (~4.9 studs de haut)
Intro.TreeSpot = Vector3.zero -- pied du grand arbre (niveau 10 de l'etage 1)
Intro.ItemSpot = Vector3.new(-6.3, 1.6, 2.5) -- l'arbre niveau 1 flotte au-dessus du trou avant de voler dans les mains
Intro.TreeLevel = 10
-- Fruits accroches au grand arbre (noms de ReplicatedStorage.FruitAssets ; decor, pas de jeu)
Intro.TreeFruits = table.freeze({ "Apple", "Banana", "Orange", "Pear", "Lemon", "Cherry", "Strawberry" })
Intro.SaplingLevel = 1
Intro.SaplingScale = 0.34 -- arbre niveau 1 (8.4 studs) -> ~2.9 studs dans les mains
-- Marche et course (2026-11-27) : l'animation suit la DISTANCE parcourue, pas le temps : un pied pose
-- ne glisse plus. Longueur d'un cycle complet (2 pas), en studs.
-- Les jambes d'un avatar Roblox sont courtes (1.6 stud de la hanche a la cheville) : un pas de plus
-- de ~1.7 stud ecrase le corps vers le sol. D'ou une marche plus lente qu'avant (3.75 studs / s).
Intro.WalkStride = 3.2 -- marche : ~1.2 cycle par seconde (avant 1.5 cycle / s a 4.6 studs / s, pieds qui glissaient)
Intro.RunStride = 6.4 -- course : grandes foulees avec un temps en l'air, ~2.2 cycles / s (avant 3.2, moulinet)
-- L'arbre niveau 1 tenu en main (acteur, puis vrai personnage : SaplingController), repere du
-- HumanoidRootPart : pied du pot devant les mains.
Intro.HoldOffset = CFrame.new(0, -0.9, -1.7)
Intro.HoldArmDegrees = 60 -- bras tendus devant (CarryPoseController)

-- Deroule (secondes depuis le debut). ~25 s en tout (fondu de sortie compris), refait le 2026-11-22 :
-- il voit l'arbre de loin et court, arrache la pelle plantee, creuse pour de vrai, brandit l'arbre.
-- Ralenti le 2026-11-22 ("les changements de scene sont trop rapides") : chaque plan de camera dure
-- au moins ~1.2 s (avant : certains 0.3 s ou 0.6 s). Les plans (Intro.Shots) suivent ces temps.
-- 2026-11-27 : plan d'ouverture sur le paysage (3 s) ; tout le reste est decale de 2.2 s (la marche
-- vue de cote dure 1.8 s au lieu de 2.6 s : il marche deja pendant l'ouverture). ~27 s en tout.
Intro.Times = table.freeze({
	open = 3.0, -- 0-3 : la camera descend du ciel (montagnes, volcan, foret) jusqu'a cote de lui
	notice = 4.8, -- 3-4.8 : marche tranquille vue de cote ; 4.8 : il s'arrete net, "!" (il a vu quelque chose)
	reveal = 6.0, -- derriere lui, l'arbre au loin scintille, zoom lent vers l'arbre
	wow = 7.8, -- "Wow!" bras en l'air, saut
	run = 9.3, -- il court vers l'arbre
	arrive = 10.9, -- il freine au bord de la clairiere, leve la tete (l'arbre est immense)
	think = 12.3, -- "?" : comment l'emporter ?
	idea = 13.6, -- "!" : il voit la pelle plantee a cote
	toShovel = 14.8, -- il va a la pelle
	pull = 15.5, -- il l'attrape et l'arrache du sol
	carry = 16.4, -- il va au pied de l'arbre, pelle en main
	digStart = 17.3, -- 3 coups de pelle (lever, enfoncer + pied, soulever, jeter sur le tas)
	digEnd = 20.6, -- il replante la pelle a cote de lui
	fall = 20.7, -- l'arbre tombe (1.1 s), les fruits sautent au sol
	fallEnd = 21.8,
	item = 22.6, -- l'arbre disparait en poussiere ; l'arbre niveau 1 apparait en tournant et en brillant
	grab = 23.3, -- il vole dans les mains (rebond "gelee")
	raise = 23.6, -- il le brandit au-dessus de sa tete (objet obtenu !)
	lower = 24.3, -- il le redescend devant lui (pose tenue dans l'usine)
	fade = 24.7, -- fondu au blanc (1.2 s, plus long : demande utilisateur)
	stop = 26.3, -- fin : blanc tenu un instant, puis il disparait dans l'usine (1 s)
})
local T = Intro.Times
Intro.Digs = 3
Intro.FadeInSeconds = 1.2
Intro.FadeOutSeconds = 1.0
Intro.AppearanceWaitSeconds = 1.5 -- attente max de l'avatar (vetements) avant de le copier
Intro.PoseSmoothing = 0.07 -- lissage des articulations (secondes ; 0 = aucun)
-- Camera rendue derriere le personnage a la fin (studs derriere lui, au-dessus de sa tete)
Intro.ExitCameraDistance = 12
Intro.ExitCameraHeight = 3.5
-- Arrivee dans l'usine sans a-coup (2026-11-27) : sous le blanc de la fin, la camera fait un tour
-- de l'usine (chaque cote est dessine une fois : maillages, textures, ecrans 3D), puis on attend que
-- la carte soit chargee (streaming + prechargement du Preloader) et que l'image soit fluide.
Intro.ArrivalSweepSteps = 8 -- angles du tour de camera (1 image chacun)
Intro.ArrivalMinHold = 0.5 -- blanc tenu au moins (secondes, apres le tour)
Intro.ArrivalMaxWait = 4 -- blanc tenu au plus (secondes) : le joueur n'est jamais bloque
Intro.ArrivalSmoothFrames = 10 -- images fluides de suite pour dire "pret"
Intro.ArrivalSmoothFrameSeconds = 0.05 -- une image est fluide sous cette duree (20 images/s)
-- Sons plus doux que dans le jeu (2026-11-22 : "les bruitages sont trop forts")
Intro.SoundVolume = 0.4 -- bruitages (multiplie le volume de Config/Sounds)
Intro.BirdsVolume = 0.3 -- oiseaux en boucle
-- Bruitages ajoutes le 2026-11-23 (multiplient SoundVolume) : pas, sauts, whoosh, craquement
Intro.StepVolume = 0.6 -- pas dans l'herbe (discrets, ils se repetent)
Intro.WhooshVolume = 0.7 -- whoosh (saut, terre jetee, arbre qui vole dans les mains, fondu)
Intro.CrackVolume = 0.9 -- l'arbre craque avant de tomber
-- Reactions (voix) et pas en plus, 2026-11-23 (multiplient SoundVolume)
Intro.VoiceVolume = 1.2 -- voix du personnage (surprise, wow, hmm, efforts, woohoo)
Intro.GruntVolume = 0.8 -- petits efforts (pelle arrachee, coups de pelle)
Intro.HmmSeconds = 1.2 -- le "Mmm.." (3 s) est coupe en douceur avant le "!"

-- Effets (degres de secousse de camera, duree en secondes)
Intro.DigShake = { degrees = 0.8, seconds = 0.2 }
Intro.PullShake = { degrees = 0.6, seconds = 0.2 }
Intro.LandShake = { degrees = 2.4, seconds = 0.5 }
Intro.NoticeFovKick = 6 -- "coup de zoom" quand il voit l'arbre (degres de champ de vision)
Intro.WowFovKick = 7 -- la camera "s'approche" d'un coup au Wow

-- Plans de camera (glissement doux d'un plan au suivant, sauf `cut`). Repere "Actor" : centre du
-- personnage (HumanoidRootPart, ~3 studs au-dessus du sol), sans le rebond de la marche.
-- Les temps des plans viennent de Intro.Times (T) : changer un temps deplace aussi la camera.
-- `blur` (2026-11-27) : fond flou sur les gros plans (le personnage reste net), net sur les plans larges.
Intro.Shots = table.freeze({
	-- 0. Ouverture (2026-11-27) : au-dessus de la foret, les montagnes et le volcan au fond ; la
	-- camera descend en douceur jusqu'a cote du personnage qui marche sur le chemin. Ce 1er plan
	-- (repere du decor) sert aussi a 02m-intro-set : les arbres sur sa route sont retires.
	{ t = 0, space = "Set", pos = Vector3.new(-72, 46, 62), look = Vector3.new(130, 50, -150), fov = 62, ease = "slow" },
	-- 1. De cote, suit l'acteur qui marche tranquillement
	{ t = T.open, space = "Actor", pos = Vector3.new(13, 1.8, -1), look = Vector3.new(0, 0.8, -3), fov = 60, blur = 0.2 },
	{ t = T.notice, space = "Actor", pos = Vector3.new(12, 1.8, -1.5), look = Vector3.new(0, 0.8, -3), blur = 0.2 },
	-- 2. Il s'arrete net : gros plan de profil, il leve la tete
	{ t = T.notice, space = "Actor", pos = Vector3.new(1.8, 2.4, -6.5), look = Vector3.new(0, 1.9, 0), cut = true, fov = 50, blur = 0.6 },
	{ t = T.reveal, space = "Actor", pos = Vector3.new(1.5, 2.4, -5.6), look = Vector3.new(0, 2.0, 0), fov = 50, blur = 0.6 },
	-- 3. Derriere lui : l'arbre AU LOIN au bout du chemin, zoom lent (longue focale)
	{ t = T.reveal, space = "Set", pos = Vector3.new(-46, 3.6, 13.5), look = Vector3.new(-6, 7.5, 1), cut = true, fov = 55 },
	{ t = T.wow, space = "Set", pos = Vector3.new(-44.5, 4, 13), look = Vector3.new(-4, 8.5, 0.5), fov = 46 },
	-- 4. Gros plan de face : Wow! (cadre assez haut pour les bras en l'air)
	{ t = T.wow, space = "Actor", pos = Vector3.new(1.2, 2.6, -9.5), look = Vector3.new(0, 2.5, 0), cut = true, fov = 50, blur = 0.6 },
	{ t = T.run, space = "Actor", pos = Vector3.new(1.0, 2.5, -8.8), look = Vector3.new(0, 2.4, 0), fov = 50, blur = 0.6 },
	-- 5. Il court : travelling de cote, un peu en arriere
	{ t = T.run, space = "Actor", pos = Vector3.new(10, 2.5, 1.5), look = Vector3.new(0, 1.5, -5), cut = true, fov = 62, blur = 0.25 },
	{ t = T.arrive, space = "Actor", pos = Vector3.new(10, 2.5, 1.5), look = Vector3.new(0, 1.5, -5), fov = 62, blur = 0.25 },
	-- 6. Arrivee : contre-plongee derriere lui, l'arbre immense
	{ t = T.arrive, space = "Set", pos = Vector3.new(-21, 2.2, 13), look = Vector3.new(-3, 9, 0), cut = true, fov = 62 },
	{ t = T.think, space = "Set", pos = Vector3.new(-20, 2.6, 12.2), look = Vector3.new(-1, 11, 0), fov = 60 },
	-- 7. De trois-quarts : il reflechit (le visage reste visible)
	{ t = T.think, space = "Actor", pos = Vector3.new(-4, 2.1, -6.5), look = Vector3.new(0, 1.8, 0), cut = true, fov = 50, blur = 0.6 },
	{ t = T.idea, space = "Actor", pos = Vector3.new(-3.4, 2.0, -5.8), look = Vector3.new(0, 1.8, 0), fov = 50, blur = 0.6 },
	-- 8. "!" : par-dessus son epaule, la pelle plantee
	{ t = T.idea, space = "Set", pos = Vector3.new(-3, 4.6, 12.5), look = Vector3.new(-10, 3.2, 6.5), cut = true, fov = 50, blur = 0.45 },
	{ t = T.toShovel, space = "Set", pos = Vector3.new(-3.5, 4.4, 12), look = Vector3.new(-9.8, 3, 6.8), fov = 50, blur = 0.45 },
	-- 9. Il arrache la pelle (vu de face, cote camera)
	{ t = T.toShovel, space = "Set", pos = Vector3.new(-14, 4.6, 17.5), look = Vector3.new(-9.5, 3.4, 7.6), cut = true, fov = 55, blur = 0.45 },
	{ t = T.carry, space = "Set", pos = Vector3.new(-13.2, 4.3, 16.2), look = Vector3.new(-9.5, 3.4, 7.4), fov = 55, blur = 0.45 },
	-- 10. Il creuse au pied de l'arbre : vu de cote (la pelle, le trou et le tas visibles)
	{ t = T.carry, space = "Set", pos = Vector3.new(-10, 5, 15), look = Vector3.new(-8, 2.5, 3.5), cut = true, fov = 60, blur = 0.3 },
	{ t = T.digStart, space = "Set", pos = Vector3.new(-8.6, 4.4, 13.2), look = Vector3.new(-5.5, 2.6, 2.5), fov = 58, blur = 0.3 },
	{ t = T.digEnd - 0.1, space = "Set", pos = Vector3.new(-8.2, 4.1, 12.2), look = Vector3.new(-5.5, 2.6, 2.5), fov = 58, blur = 0.3 },
	-- 11. L'arbre tombe : on recule pour tout voir (le volcan apparait derriere), et on reste pour
	-- la poussiere et les fruits
	{ t = T.fallEnd - 0.3, space = "Set", pos = Vector3.new(-20, 11, 30), look = Vector3.new(6, 5, 0), fov = 60 },
	{ t = T.item + 0.4, space = "Set", pos = Vector3.new(-19, 10, 28), look = Vector3.new(5, 4, 0), fov = 60 },
	-- 12. L'arbre niveau 1 (vu de face, la ou etait l'arbre), dans les mains, puis brandi
	{ t = T.item + 0.4, space = "Set", pos = Vector3.new(3.5, 5.5, 5.5), look = Vector3.new(-7.5, 3.2, 3), cut = true, fov = 55, blur = 0.5 },
	{ t = T.raise, space = "Set", pos = Vector3.new(3, 5.2, 5), look = Vector3.new(-8.5, 5.3, 3.3), fov = 55, blur = 0.5 },
	{ t = T.stop, space = "Set", pos = Vector3.new(2.2, 5.2, 4.6), look = Vector3.new(-9, 5.8, 3.4), fov = 55, blur = 0.5 },
} :: { Shot })

-- Lumiere de cinema (2026-11-27), seulement pendant la cinematique et seulement chez ce joueur :
-- tout est remis comme avant sous le blanc de la fin. Soleil du matin, bas, du cote de la camera et
-- devant lui (ombres longues, visages eclaires), image un peu plus chaude et plus contrastee.
-- Pas applique en Low Quality (ni flou, ni rayons). La brume (Atmosphere.Density / Haze) n'est pas
-- touchee : Low Quality la sauvegarde et la remet lui-meme.
Intro.Mood = table.freeze({
	ClockTime = 9.2, -- avec la latitude 50 : soleil a ~40 degres, vers +X +Z
	GeographicLatitude = 50,
	Brightness = 2.7,
	ColorShiftTop = Color3.fromRGB(255, 232, 200), -- lumiere du soleil un peu doree
	AtmosphereColor = Color3.fromRGB(226, 222, 214), -- brume un peu plus chaude
	AtmosphereDecay = Color3.fromRGB(204, 190, 172),
	SunRaysIntensity = 0.08,
	SunRaysSpread = 0.7,
	Contrast = 0.05,
	Saturation = 0.1,
	Tint = Color3.fromRGB(255, 247, 236),
	FocusRadius = 7, -- flou : tout ce qui est a moins de 7 studs du personnage (en profondeur) reste net
})

-- Fin (2026-11-23) : pendant le fondu au blanc, la camera s'approche peu a peu de sa tete
-- (start : seconde de depart ; distance : studs devant la tete a la fin ; fov : champ de vision final ;
-- rise : camera un peu au-dessus, pour passer au-dessus du pot tenu devant lui)
Intro.HeadZoom = table.freeze({ start = T.lower + 0.2, distance = 2.4, fov = 38, rise = 0.45 })
-- "Pop" de la pelle arrachee : elle grossit (~+30 % au plus fort avec 0.8) puis revient ; volume du pop
Intro.ShovelPop = 0.8
Intro.ShovelPopVolume = 1.6

-- Textes (vus par le joueur : anglais)
Intro.NoticeText = "!"
Intro.WowText = "Wow!"
Intro.ThinkText = "?"
Intro.IdeaText = "!"

-- Bandes noires (part de la hauteur de l'ecran, en haut et en bas)
Intro.BarHeight = 0.1

return table.freeze(Intro)
