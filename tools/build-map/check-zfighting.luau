--!strict
-- Detecteur de z-fighting (lecture seule, ne modifie rien). A lancer dans Studio (mode Edit, MCP
-- execute_luau ou barre de commande) apres une reconstruction de la carte (01 ... 05).
-- Cherche deux faces de pieces (Part bloc, non invisibles) :
--   * avec la meme direction, a moins de TOL stud l'une de l'autre (regle docs/style.md : 0.05) ;
--   * qui se recouvrent sur plus de MIN_AREA stud2 ;
--   * de couleur ou de matiere differente (meme couleur = invisible a l'ecran) ;
--   * visibles : le point juste devant la face n'est pas dans une autre piece.
-- Les faces tournees vers le bas sont ignorees (posees sur le sol, jamais vues).
-- Ne voit pas les MeshPart / Union / cylindres : regarder ceux-la a l'oeil.
-- Doc : docs/systems/carte-bases.md (section Z-fighting)

local TOL = 0.045 -- un ecart de 0.05 (la regle) passe, malgre les arrondis
local MIN_AREA = 0.05

type Face = { p: BasePart, n: Vector3, c: Vector3, d: number, u: Vector3, hu: number, v: Vector3, hv: number }

local function facesOf(p: BasePart): { Face }
	local cf, s = p.CFrame, p.Size / 2
	local axes = {
		{ cf.RightVector, s.X, cf.UpVector, s.Y, cf.LookVector, s.Z },
		{ cf.UpVector, s.Y, cf.RightVector, s.X, cf.LookVector, s.Z },
		{ cf.LookVector, s.Z, cf.RightVector, s.X, cf.UpVector, s.Y },
	}
	local r: { Face } = {}
	for _, a: { any } in axes do
		for _, sg in { 1, -1 } do
			local n: Vector3 = a[1] * sg
			if n.Y > -0.9 then
				local c = cf.Position + n * a[2]
				table.insert(r, { p = p, n = n, c = c, d = n:Dot(c), u = a[3], hu = a[4], v = a[5], hv = a[6] })
			end
		end
	end
	return r
end

local function key(n: Vector3): string
	return string.format("%.2f,%.2f,%.2f", n.X, n.Y, n.Z)
end

-- Surface commune de deux rectangles dans le meme plan (axes separateurs) + son centre
local function overlap(f: Face, g: Face): (number, Vector3)
	local area, mid = 1, Vector3.zero
	for i, ax in { f.u, f.v, g.u, g.v } do
		local function proj(h: Face): (number, number)
			local c = ax:Dot(h.c)
			local e = math.abs(ax:Dot(h.u)) * h.hu + math.abs(ax:Dot(h.v)) * h.hv
			return c - e, c + e
		end
		local a0, a1 = proj(f)
		local b0, b1 = proj(g)
		local lo, hi = math.max(a0, b0), math.min(a1, b1)
		if hi - lo <= 0.02 then
			return 0, Vector3.zero
		end
		if i <= 2 then
			area *= hi - lo
			mid += ax * ((lo + hi) / 2 - ax:Dot(f.c))
		end
	end
	return area, f.c + mid
end

local function inside(p: BasePart, pt: Vector3): boolean
	local l = p.CFrame:PointToObjectSpace(pt)
	local s = p.Size / 2
	return math.abs(l.X) < s.X and math.abs(l.Y) < s.Y and math.abs(l.Z) < s.Z
end

-- Deux pieces de decor par niveau (LookId / LookLevel / LookMaxLevel) qui ne sont jamais visibles
-- en meme temps (variantes d'une meme piece : rail jaune / bleu / dore...) : pas de z-fighting.
local function neverTogether(a: BasePart, b: BasePart): boolean
	local idA, idB = a:GetAttribute("LookId"), b:GetAttribute("LookId")
	if idA == nil or idA ~= idB then
		return false
	end
	local minA = a:GetAttribute("LookLevel") :: number? or 0
	local minB = b:GetAttribute("LookLevel") :: number? or 0
	local maxA = a:GetAttribute("LookMaxLevel") :: number? or math.huge
	local maxB = b:GetAttribute("LookMaxLevel") :: number? or math.huge
	return maxA < minB or maxB < minA
end

local function scan(root: Instance): { string }
	local parts: { BasePart } = {}
	local groups: { [string]: { Face } } = {}
	for _, p in root:GetDescendants() do
		if p:IsA("Part") and p.Shape == Enum.PartType.Block and p.Transparency < 1 then
			table.insert(parts, p)
			for _, f in facesOf(p) do
				local k = key(f.n)
				groups[k] = groups[k] or {}
				table.insert(groups[k], f)
			end
		end
	end
	local hits: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, list in groups do
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		for i = 1, #list do
			local f = list[i]
			local j = i + 1
			while j <= #list and list[j].d - f.d < TOL do
				local g = list[j]
				if g.p ~= f.p and (f.p.Color ~= g.p.Color or f.p.Material ~= g.p.Material) and not neverTogether(f.p, g.p) then
					local area, mid = overlap(f, g)
					if area > MIN_AREA then
						local probe = mid + f.n * 0.08
						local hidden = false
						for _, q in parts do
							if q ~= f.p and q ~= g.p and inside(q, probe) then
								hidden = true
								break
							end
						end
						local line = f.p:GetFullName() .. "  |  " .. g.p:GetFullName()
						if not hidden and not seen[line] then
							seen[line] = true
							table.insert(hits, line .. string.format("  ecart=%.3f surface=%.1f", g.d - f.d, area))
						end
					end
				end
				j += 1
			end
		end
		task.wait()
	end
	return hits
end

local out = {}
local roots: { Instance? } = {
	game:GetService("ServerStorage"):FindFirstChild("BaseTemplate"),
	game:GetService("ServerStorage"):FindFirstChild("FloorTemplate"),
	-- Tour assemblee (tools/build-map/preview-tower.luau) : les faces ENTRE deux etages ne se voient
	-- que la (dalle, piliers, cage d'ascenseur, escalier qui arrive dans le trou)
	workspace:FindFirstChild("_PreviewBase"),
	workspace:FindFirstChild("Map"),
	game:GetService("ServerStorage"):FindFirstChild("TreeStages"),
}
for _, root in roots do
	if root then
		local hits = scan(root)
		table.insert(out, "== " .. root.Name .. " : " .. #hits)
		for _, h in hits do
			table.insert(out, h)
		end
	end
end
return table.concat(out, "\n")
