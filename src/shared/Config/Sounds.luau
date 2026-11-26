--!strict
-- Sons de jeu (cote client, via Util/SoundFx). Ids Roblox ; "rbxasset://" = sons fournis avec Roblox.
-- Les "rbxassetid://" viennent du Creator Store (gratuits, verifies charges dans Studio le 2026-11-19).
-- Doc : docs/systems/interface.md (section Sons)

-- Volume : 1 = volume normal du son (2026-11-19, demande utilisateur : "laisse tous les sons en
-- normal", ni baisses ni hausses). Ne changer que si l'utilisateur le demande.
export type SoundDef = { id: string, volume: number, pitch: number?, pitchJitter: number? }

local Sounds: { [string]: SoundDef } = {
	-- Ramasser / deposer
	Pickup = { id = "rbxassetid://6586979979", volume = 1, pitchJitter = 0.12 }, -- "cartoon_pop" (0.19 s ; avant : "Plucked (Cork Pop)", refuse le 2026-11-19)
	-- Deposit : fruit qui tombe dans sa caisse de l'etagere (joueur et Fruit Picker)
	Deposit = { id = "rbxassetid://18145114696", volume = 1, pitchJitter = 0.1 }, -- "cartoon plop sound" (0.54 s ; avant : clickfast.wav, change le 2026-11-20)
	-- CounterDrop : boisson posee sur le comptoir (pad Drop Juices) et sur le plateau du joueur (pad Take Juices)
	CounterDrop = { id = "rbxassetid://9117471232", volume = 1, pitchJitter = 0.05 }, -- "Plastic Cup 9" gobelet pose sur du bois (0.57 s ; avant : CupPop, 2026-11-20)
	CupPop = { id = "rbxasset://sounds/clickfast.wav", volume = 1, pitch = 1.4, pitchJitter = 0.2 },
	-- Argent (refait le 2026-11-19 : une seule famille de "pops" propres, voir CashController)
	-- CashPop : un pop par billet qui arrive ; CashController monte la note a chaque billet.
	CashPop = { id = "rbxassetid://103127047792282", volume = 1, pitchJitter = 0.03 }, -- "UI bubbly_pop" (CoreKit, 0.24 s)
	-- (CashBig, "ding" de fin d'encaissement, retire le 2026-11-20 a la demande de l'utilisateur)
	-- Sale : un client achete une boisson -> caisse enregistreuse "ka-ching" (2026-11-19, demande
	-- utilisateur ; avant : le pop grave). Joue a la position du client.
	Sale = { id = "rbxassetid://120891770644830", volume = 1, pitchJitter = 0.04 }, -- "cash-register-sound-fx" (1.04 s)
	-- Paid : le joueur paie un achat (pad de machine, tuile de panneau, etage, menu Upgrades).
	-- Envoye par MoneyService.TrySpend (remote Feedback "Paid"), joue par CashController (2026-11-20).
	Paid = { id = "rbxassetid://100813529228543", volume = 1, pitchJitter = 0.04 }, -- "coins / purchasing" (Creator Store, blocky_53)
	FruitLand = { id = "rbxassetid://177172187", volume = 1, pitchJitter = 0.12 }, -- "Soft Thud" (0.28 s ; avant : clickfast.wav, change le 2026-11-20)
	NewFruit = { id = "rbxassetid://105193542038988", volume = 1 }, -- "Cute level up" (fruit jamais vu)
	-- Animations (BlenderFxController, TreeFxController, MachineFxController)
	BlenderMotor = { id = "rbxassetid://365965609", volume = 1 }, -- "Blender" (Roblox), en boucle
	BlenderPlop = { id = "rbxasset://sounds/splat.wav", volume = 0.75, pitch = 1.3, pitchJitter = 0.15 }, -- fruits dans le mixeur (-25 %, demande du 2026-11-20)
	JuiceDone = { id = "rbxassetid://342901621", volume = 1, pitch = 1.15, pitchJitter = 0.05 }, -- jus verse (fin du mixage)
	TreeBoing = { id = "rbxasset://sounds/short spring sound.wav", volume = 1, pitch = 0.85 },
	TreeChime = { id = "rbxassetid://83059242168617", volume = 1 }, -- "Bright Plucks" (arbre secoue, fruit rare)
	MachineBoing = { id = "rbxasset://sounds/short spring sound.wav", volume = 1, pitch = 1.2, pitchJitter = 0.1 },
	-- Pads d'action : "clic" quand on monte dessus (PadController)
	PadStep = { id = "rbxassetid://117649901456711", volume = 1, pitchJitter = 0.04 }, -- "ui_button_click" (0.55 s ; avant : switch.wav + boing, change le 2026-11-20)
	-- Pads verts (achat : employes, operateurs, Upgrade Tree) : son different des pads d'action
	GreenPadStep = { id = "rbxassetid://9119717523", volume = 1, pitchJitter = 0.04 }, -- "Switch Click On Or Off Toggle Button 2" (0.23 s ; "Pop Sound Effect" refuse le 2026-11-20)
	-- Interface
	TileClick = { id = "rbxassetid://10128760939", volume = 1, pitchJitter = 0.04 }, -- "RBLX UI Click" (meme son que les boutons des menus) : appui sur une tuile de panneau (BoardFxController)
	Notify = { id = "rbxassetid://3623733749", volume = 1 }, -- petit "tap" doux (message en haut de l'ecran)
	-- Cinematique d'ouverture (IntroController, 2026-11-22 ; Creator Store, ProSoundEffects, gratuits)
	IntroBirds = { id = "rbxassetid://9112831327", volume = 1 }, -- "Morning Birds 2 (SFX)", en boucle pendant l'intro
	IntroDig = { id = "rbxassetid://9114083260", volume = 1, pitchJitter = 0.06 }, -- "Dirt Dig Dirt Throws From Shovel 1" (1.0 s)
	IntroTreeFall = { id = "rbxassetid://9113466920", volume = 1 }, -- "Board Drops Wood Impacts Wobble 3" (2.2 s)
	-- Ajouts du 2026-11-23 ("plus de bruitages dans la cinematique"), verifies charges dans Studio
	-- Pas dans l'herbe : 4 variantes tirees au hasard, pas "craquants" facon jeu de blocs (2026-11-23,
	-- demande "bruits de pas de Minecraft sur l'herbe" ; pas les vrais sons de Minecraft : droits d'auteur).
	-- Serie "grass_step_01..04" (StarWithABlox), 0.55-0.64 s. Avant : walk_grass_left/right.
	IntroGrass1 = { id = "rbxassetid://108357430635661", volume = 1, pitchJitter = 0.1 },
	IntroGrass2 = { id = "rbxassetid://95318237108953", volume = 1, pitchJitter = 0.1 },
	IntroGrass3 = { id = "rbxassetid://127407887796066", volume = 1, pitchJitter = 0.1 },
	IntroGrass4 = { id = "rbxassetid://89758061708390", volume = 1, pitchJitter = 0.1 },
	IntroJump = { id = "rbxasset://sounds/action_jump.mp3", volume = 1, pitchJitter = 0.05 }, -- saut Roblox (0.34 s)
	IntroLand = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1, pitchJitter = 0.08 }, -- atterrissage Roblox (0.26 s)
	IntroWhoosh = { id = "rbxassetid://9126229267", volume = 1, pitchJitter = 0.08 }, -- "Whoosh By Fast Airy Swooshing" (0.6 s, ProSoundEffects)
	IntroRise = { id = "rbxassetid://9125807267", volume = 1 }, -- "Rising Whoosh Swooshing In" (1.3 s, ProSoundEffects)
	IntroSkid = { id = "rbxassetid://9114518395", volume = 1 }, -- "Foliage Movement 5" (2.1 s) : il freine dans l'herbe
	IntroTreeCrack = { id = "rbxassetid://9126240449", volume = 1 }, -- "Wood Crack Thick Splintering Creaking 2" (3.4 s)
	IntroLeaves = { id = "rbxassetid://9114518260", volume = 1 }, -- "Foliage Movement 2" (2.5 s) : feuillage qui s'ecrase
	-- Reactions du personnage (voix), 2026-11-23 : "plus de sons pour l'intro, les reactions".
	-- Verifies charges dans Studio ; PAS ecoutes (a valider a l'oreille, faciles a remplacer ici).
	IntroGasp = { id = "rbxassetid://9125572759", volume = 1, pitch = 1.15 }, -- "Gasps Male... 6" (1.05 s, ProSoundEffects) : il voit l'arbre
	IntroWowVoice = { id = "rbxassetid://116173584186102", volume = 1 }, -- "\"Wow\" Voice line" (0.72 s)
	IntroPant = { id = "rbxassetid://9125572450", volume = 1, pitch = 1.1 }, -- "Gasps Male... 8" (1.44 s, ProSoundEffects) : essouffle apres la course
	IntroHmm = { id = "rbxassetid://128766952075168", volume = 1 }, -- "Mmm.." (3.0 s, coupe a 1.2 s) : il reflechit
	IntroGrunt1 = { id = "rbxassetid://117404652750890", volume = 1, pitchJitter = 0.05 }, -- "effort grunt 2" (0.26 s)
	IntroGrunt2 = { id = "rbxassetid://118272408702780", volume = 1, pitchJitter = 0.05 }, -- "effort grunt 3" (0.35 s)
	IntroGrunt3 = { id = "rbxassetid://85104355106009", volume = 1, pitchJitter = 0.05 }, -- "effort grunt 5" (0.41 s)
	IntroWhoa = { id = "rbxassetid://130615718980545", volume = 1 }, -- "Haah..!" (1.04 s) : l'arbre tombe
	-- ("got it" et "woo hoo" de la fin retires le 2026-11-23 : trop de sons a la fin)
	WelcomeBack ={ id = "rbxassetid://122766504688172", volume = 1 }, -- ding de recompense (gains hors ligne)
}

return table.freeze(Sounds)
