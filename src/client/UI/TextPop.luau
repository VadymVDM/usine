--!strict
-- Faire apparaitre un texte SANS changer sa taille (fondu, chute avec rebond, balancement).
--
-- Pourquoi (bug telephone du 2026-11-27 : "Pick up the fruits", "NEW FRUIT!" saccades, lettres qui
-- apparaissent / disparaissent ou clignotent en noir) : Roblox range toutes les lettres affichees
-- dans une seule image partagee par tout le jeu (atlas de glyphes). Chaque taille de texte et chaque
-- epaisseur de contour y prend sa propre place, et un telephone les dessine environ 3 fois plus
-- grandes qu'un PC (ecran plus dense). Un texte qu'on fait grossir (UIScale, TextSize) cree une
-- nouvelle taille a chaque image : l'atlas deborde, Roblox jette des lettres pour faire de la place
-- et elles clignotent (le contour fonce reste parfois seul : lettres noires). Sources : DevForum
-- "All About Text - Best Practices" (equipe texte de Roblox), "UI Flickering - Unable to fix".
--
-- Regle du jeu : un texte apparait a sa taille finale. On anime sa position, sa transparence, sa
-- rotation (le dessin des lettres ne change pas). Les petits rebonds autour de 1 (boutons, montant
-- du HUD) restent tolerés : peu de tailles, toujours les memes, deja en memoire.
-- Doc : docs/systems/interface.md (section "Textes animes : jamais de changement de taille")

local TweenService = game:GetService("TweenService")

local Jelly = require(script.Parent.Parent:WaitForChild("Fx"):WaitForChild("Jelly"))

local TextPop = {}

-- Transparence de repos de chaque texte et contour d'un groupe
export type Fade = { [Instance]: number }

local function isText(item: Instance): boolean
	return item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")
end

-- Textes et contours sous `root` (root compris), avec leur transparence actuelle (= de repos).
function TextPop.Collect(root: Instance): Fade
	local fade: Fade = {}
	local function add(item: Instance)
		if isText(item) then
			fade[item] = (item :: any).TextTransparency
		elseif item:IsA("UIStroke") then
			fade[item] = item.Transparency
		end
	end
	add(root)
	for _, item in root:GetDescendants() do
		add(item)
	end
	return fade
end

-- hidden : 0 = comme au repos, 1 = invisible.
function TextPop.SetHidden(fade: Fade, hidden: number)
	for item, rest in fade do
		local value = rest + (1 - rest) * hidden
		if item:IsA("UIStroke") then
			item.Transparency = value
		else
			(item :: any).TextTransparency = value
		end
	end
end

-- Animation en cours par objet : ses tweens, et (pour In) sa position et ses transparences de
-- repos, reprises si une nouvelle apparition arrive pendant la precedente (sinon on noterait des
-- valeurs a moitie animees). Retiree a la fin de l'animation : rien ne garde un texte detruit.
type Run = { tweens: { Tween }, home: UDim2?, fade: Fade? }
local running: { [Instance]: Run } = {}

local function stop(target: Instance): Run?
	local run = running[target]
	if run then
		running[target] = nil
		for _, tween in run.tweens do
			tween:Cancel()
		end
	end
	return run
end

local function fadeTweens(fade: Fade, info: TweenInfo, list: { Tween })
	for item, rest in fade do
		local goal = if item:IsA("UIStroke") then { Transparency = rest } else { TextTransparency = rest }
		table.insert(list, TweenService:Create(item, info, goal))
	end
end

-- Lance les tweens ; `last` = le plus long : a sa fin, l'objet sort de `running`.
local function launch(target: Instance, run: Run, last: Tween)
	running[target] = run
	last.Completed:Once(function()
		if running[target] == run then
			running[target] = nil
		end
	end)
	for _, tween in run.tweens do
		tween:Play()
	end
end

export type InOptions = {
	drop: number?, -- pixels de chute (> 0 : arrive d'au-dessus, < 0 : d'en dessous). Defaut : 45 % de sa hauteur
	duration: number?, -- secondes (defaut 0.35)
	delay: number?, -- secondes avant de commencer
}

-- Apparition : le texte (ou un cadre plein de textes) tombe a sa place avec un petit depassement
-- (Back) et apparait en fondu. Pour un objet que personne d'autre ne deplace.
function TextPop.In(target: GuiObject, options: InOptions?)
	local opts: InOptions = options or {}
	local previous = stop(target)
	local home: UDim2 = if previous and previous.home then previous.home else target.Position
	local fade: Fade = if previous and previous.fade then previous.fade else TextPop.Collect(target)
	local drop = opts.drop or math.max(10, target.AbsoluteSize.Y * 0.45)
	local duration = opts.duration or 0.35
	local delay = opts.delay or 0
	target.Position = home - UDim2.fromOffset(0, drop)
	TextPop.SetHidden(fade, 1)
	local move = TweenService:Create(
		target,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay),
		{ Position = home }
	)
	local tweens: { Tween } = { move }
	fadeTweens(fade, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), tweens)
	launch(target, { tweens = tweens, home = home, fade = fade }, move)
end

-- Apparition en fondu seulement : pour un texte dont la position est deja animee ailleurs
-- (texte qui monte, compteur qui suit le montant du HUD).
function TextPop.FadeIn(target: GuiObject, duration: number?)
	local previous = stop(target)
	local fade: Fade = if previous and previous.fade then previous.fade else TextPop.Collect(target)
	TextPop.SetHidden(fade, 1)
	local tweens: { Tween } = {}
	fadeTweens(fade, TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), tweens)
	if #tweens > 0 then
		launch(target, { tweens = tweens, fade = fade }, tweens[1])
	end
end

---------------------------------------------------------------------------------------------
-- Chute "gelee" pilotee image par image (bandeaux NEW FLOOR!, REBIRTH, carte NEW FRUIT!) : un
-- ressort Jelly deplace le groupe (au lieu de le faire grossir) et le fait apparaitre.

export type Drop = {
	target: GuiObject,
	home: UDim2,
	fade: Fade,
	spring: Jelly.Spring,
	start: number, -- valeur de depart du ressort (< 0)
	distance: number, -- chute, en fraction de la hauteur du parent (> 0 : d'au-dessus)
	hidden: number, -- 1 -> 0, ne remonte jamais (le texte ne repalit pas pendant les rebonds)
}

local function placeDrop(d: Drop, writeFade: boolean)
	d.target.Position = d.home + UDim2.fromScale(0, d.spring.x * d.distance)
	if writeFade then
		d.hidden = math.min(d.hidden, math.clamp(d.spring.x / d.start, 0, 1))
		TextPop.SetHidden(d.fade, d.hidden)
	end
end

-- `spring` : ressort deja regle, avec sa valeur de depart (spring.x < 0). Place le groupe tout de
-- suite (cache, decale) : rien ne s'affiche a sa place avant le 1er pas.
function TextPop.NewDrop(target: GuiObject, spring: Jelly.Spring, distance: number): Drop
	local start = if spring.x < 0 then spring.x else -1
	spring.x = start
	local d: Drop = {
		target = target,
		home = target.Position,
		fade = TextPop.Collect(target),
		spring = spring,
		start = start,
		distance = distance,
		hidden = 1,
	}
	placeDrop(d, true)
	return d
end

-- Un pas du ressort. writeFade = false des que l'appelant fait disparaitre les textes lui-meme.
function TextPop.StepDrop(d: Drop, dt: number, writeFade: boolean?)
	Jelly.Step(d.spring, dt)
	placeDrop(d, writeFade ~= false)
end

return TextPop
