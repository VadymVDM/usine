--!strict
-- Classements mondiaux (tous les serveurs, depuis toujours) : 2 grands murs-ecrans aux deux bouts
-- de la route (Workspace.Map.Leaderboards.WestWall / EastWall, construits par
-- tools/build-map/08-leaderboards.luau), 2 classements cote a cote sur chaque mur :
--   mur ouest (derriere le spawn)  : MONEY + JUICES SOLD
--   mur est (bout de la route)     : TIME PLAYED + ROBUX SPENT
-- Textes visibles par le joueur : en anglais.
-- Doc : docs/systems/classements.md

export type Kind = "Money" | "Count" | "Time" | "Robux"

export type Board = {
	id: string, -- nom de la colonne sur le mur ET de la statistique
	title: string,
	kind: Kind, -- facon d'afficher la valeur
	storeName: string, -- OrderedDataStore (cle "<UserId>", valeur entiere)
	wall: string, -- "WestWall" ou "EastWall"
	column: number, -- 1 = gauche de l'ecran, 2 = droite
	color: Color3, -- titre (pastille) et valeurs
}

local Leaderboards = {}

Leaderboards.Boards = table.freeze({
	table.freeze({
		id = "Money",
		title = "MONEY",
		kind = "Money",
		storeName = "Board_Money_v1",
		wall = "WestWall",
		column = 1,
		color = Color3.fromRGB(40, 220, 60),
	}),
	table.freeze({
		id = "JuicesSold",
		title = "JUICES SOLD",
		kind = "Count",
		storeName = "Board_JuicesSold_v1",
		wall = "WestWall",
		column = 2,
		color = Color3.fromRGB(255, 140, 30),
	}),
	table.freeze({
		id = "TimePlayed",
		title = "TIME PLAYED",
		kind = "Time",
		storeName = "Board_TimePlayed_v1",
		wall = "EastWall",
		column = 1,
		color = Color3.fromRGB(30, 150, 255),
	}),
	table.freeze({
		id = "RobuxSpent",
		title = "ROBUX SPENT",
		kind = "Robux",
		storeName = "Board_RobuxSpent_v1",
		wall = "EastWall",
		column = 2,
		color = Color3.fromRGB(170, 70, 255),
	}),
}) :: { Board }

Leaderboards.Rows = 10 -- lignes par panneau (= lignes construites par 08-leaderboards)
Leaderboards.RefreshSeconds = 60 -- relecture des 4 classements (quota GetSortedAsync par minute)
Leaderboards.WriteSeconds = 120 -- ecriture des stats de chaque joueur (quota SetAsync)
Leaderboards.EmptyRow = "Be the first!"

-- Robux payes (tous les achats en Robux, dons compris) : DataStore a part, cle "u<UserId>" ->
-- { Total, Receipts } (comme les dons : un meme achat n'est jamais compte deux fois).
Leaderboards.RobuxStoreName = "RobuxSpent_v1"
Leaderboards.ReceiptsKept = 50

-- 3725 s -> "1h 2m" ; 125 s -> "2m" ; 3 jours -> "3d 0h"
function Leaderboards.FormatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = s // 86400
	local hours = (s % 86400) // 3600
	local minutes = (s % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m`
end

return table.freeze(Leaderboards)
