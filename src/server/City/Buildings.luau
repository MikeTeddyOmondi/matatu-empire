--!strict
-- Buildings along every road, styled by district: CBD and Upper Hill towers, Westlands glass,
-- Kilimani apartments, leafy Parklands/Lavington compounds, busy Eastleigh and Ngong Road shop
-- blocks, low-rise Kawangware, and the mabati houses of Kibera.
--
-- Part counts are kept modest (window bands, not individual windows) so the city streams
-- smoothly on phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local Kit = require(script.Parent.Kit)
local Roads = require(script.Parent.Roads)

local Buildings = {}

local FLOOR = 4.5
local SETBACK = 8 -- pavement plus a little forecourt

local GLASS_DAY = Color3.fromRGB(56, 74, 92)
local GLASS_NIGHT = Color3.fromRGB(255, 212, 140)

-- Window bands that light up at night.
Buildings.windows = {} :: { BasePart }

type StyleSpec = {
	floors: NumberRange,
	width: NumberRange,
	depth: NumberRange,
	spacing: number,
	walls: { Color3 },
	material: Enum.Material,
	glassBuilding: boolean?,
	shopfront: number, -- chance of a ground-floor shop
	tank: number, -- chance of a rooftop water tank
	balconies: boolean?,
	compound: boolean?, -- set back behind a wall with trees
	mabatiRoof: number?, -- chance of a corrugated iron roof
	secondRow: boolean?,
}

local STYLES: { [string]: StyleSpec } = {
	tower = {
		floors = NumberRange.new(8, 22),
		width = NumberRange.new(20, 30),
		depth = NumberRange.new(20, 28),
		spacing = 30,
		walls = { Color3.fromRGB(214, 206, 190), Color3.fromRGB(180, 186, 192), Color3.fromRGB(200, 170, 140), Color3.fromRGB(150, 160, 175) },
		material = Enum.Material.Concrete,
		shopfront = 0.7,
		tank = 0.2,
		secondRow = true,
	},
	glass = {
		floors = NumberRange.new(6, 18),
		width = NumberRange.new(22, 32),
		depth = NumberRange.new(20, 30),
		spacing = 36,
		walls = { Color3.fromRGB(70, 120, 150), Color3.fromRGB(60, 140, 140), Color3.fromRGB(90, 110, 130) },
		material = Enum.Material.Glass,
		glassBuilding = true,
		shopfront = 0.3,
		tank = 0,
		secondRow = true,
	},
	midrise = {
		floors = NumberRange.new(5, 10),
		width = NumberRange.new(18, 26),
		depth = NumberRange.new(18, 24),
		spacing = 32,
		walls = { Color3.fromRGB(236, 228, 210), Color3.fromRGB(210, 196, 170), Color3.fromRGB(230, 214, 196), Color3.fromRGB(190, 200, 205) },
		material = Enum.Material.SmoothPlastic,
		shopfront = 0.2,
		tank = 0.5,
		balconies = true,
		secondRow = true,
	},
	leafy = {
		floors = NumberRange.new(2, 5),
		width = NumberRange.new(16, 22),
		depth = NumberRange.new(16, 22),
		spacing = 44,
		walls = { Color3.fromRGB(240, 236, 226), Color3.fromRGB(225, 205, 175), Color3.fromRGB(205, 215, 200) },
		material = Enum.Material.SmoothPlastic,
		shopfront = 0,
		tank = 0.4,
		balconies = true,
		compound = true,
	},
	commercial = {
		floors = NumberRange.new(3, 8),
		width = NumberRange.new(16, 24),
		depth = NumberRange.new(16, 22),
		spacing = 26,
		walls = {
			Color3.fromRGB(226, 170, 110),
			Color3.fromRGB(150, 175, 200),
			Color3.fromRGB(230, 200, 90),
			Color3.fromRGB(200, 110, 100),
			Color3.fromRGB(176, 196, 128),
			Color3.fromRGB(240, 240, 230),
		},
		material = Enum.Material.Concrete,
		shopfront = 0.95,
		tank = 0.6,
		secondRow = true,
	},
	lowrise = {
		floors = NumberRange.new(1, 3),
		width = NumberRange.new(12, 18),
		depth = NumberRange.new(12, 18),
		spacing = 20,
		walls = {
			Color3.fromRGB(220, 200, 160),
			Color3.fromRGB(190, 120, 90),
			Color3.fromRGB(120, 160, 190),
			Color3.fromRGB(230, 220, 120),
			Color3.fromRGB(160, 200, 150),
		},
		material = Enum.Material.Plaster,
		shopfront = 0.8,
		tank = 0.5,
		mabatiRoof = 0.6,
		secondRow = true,
	},
	shacks = {
		floors = NumberRange.new(1, 1),
		width = NumberRange.new(8, 12),
		depth = NumberRange.new(8, 12),
		spacing = 13,
		walls = { Color3.fromRGB(120, 110, 100), Color3.fromRGB(150, 120, 90), Color3.fromRGB(110, 120, 130) },
		material = Enum.Material.CorrodedMetal,
		shopfront = 0.35,
		tank = 0,
		mabatiRoof = 1,
	},
}

local AWNINGS = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(30, 110, 200), Color3.fromRGB(240, 180, 30), Color3.fromRGB(30, 150, 80) }
local SHOPS = {
	"DUKA", "HOTEL", "SALON", "CHEMIST", "HARDWARE", "BUTCHERY", "CAFE", "MITUMBA", "M-PESA", "BAR",
	"KIBANDA", "SUPERMARKET", "BOUTIQUE", "PHONE REPAIRS", "CHAPATI & BEANS", "BARBER", "BANK", "SACCO",
}

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

local function between(range: NumberRange, rng: Random): number
	return rng:NextNumber(range.Min, range.Max)
end

-- Window bands on one face, plus pillars on the road-facing face.
local function windowsOnFace(model: Model, cframe: CFrame, size: Vector3, face: Vector3, firstFloor: number, wallColor: Color3, pillars: boolean)
	local alongX = face.Z ~= 0
	local half = if alongX then size.Z / 2 else size.X / 2
	local span = (if alongX then size.X else size.Z) - 2
	local function at(u: number, y: number, out: number): CFrame
		local localY = y - size.Y / 2
		if alongX then
			return cframe * CFrame.new(u, localY, face.Z * (half + out))
		end
		return cframe * CFrame.new(face.X * (half + out), localY, u)
	end
	local function sized(along: number, height: number, thickness: number): Vector3
		return if alongX then Vector3.new(along, height, thickness) else Vector3.new(thickness, height, along)
	end
	local last = firstFloor
	for y = firstFloor, size.Y - 2.6, FLOOR do
		last = y
		local band = Kit.decor({
			Name = "Windows",
			Size = sized(span, 2.2, 0.12),
			CFrame = at(0, y, 0.06),
			Color = GLASS_DAY,
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
			CastShadow = false,
			Parent = model,
		})
		table.insert(Buildings.windows, band)
	end
	if pillars and last > firstFloor then
		local columns = math.max(1, math.floor(span / 5))
		for i = 1, columns - 1 do
			Kit.decor({
				Name = "Pillar",
				Size = sized(0.8, last - firstFloor + 2.6, 0.18),
				CFrame = at(-span / 2 + i * span / columns, (firstFloor + last) / 2, 0.09),
				Color = wallColor,
				Material = Enum.Material.Concrete,
				CastShadow = false,
				Parent = model,
			})
		end
	end
end

local function shopfront(model: Model, cframe: CFrame, size: Vector3, face: Vector3, rng: Random)
	local half = size.X / 2
	local width = math.min(size.Z - 4, 12)
	local function at(u: number, y: number, out: number): CFrame
		return cframe * CFrame.new(face.X * (half + out), y - size.Y / 2, u)
	end
	Kit.decor({ Name = "ShopWindow", Size = Vector3.new(0.1, 3.2, width), CFrame = at(0, 2.6, 0.05), Color = Color3.fromRGB(40, 52, 64), Material = Enum.Material.Glass, Reflectance = 0.2, Parent = model })
	local awningColor = pick(AWNINGS, rng)
	Kit.decor({
		Name = "Awning",
		Size = Vector3.new(2.4, 0.3, width + 2),
		CFrame = at(0, 4.7, 1.2) * CFrame.Angles(0, 0, face.X * math.rad(-12)),
		Color = awningColor,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	local board = Kit.decor({ Name = "Sign", Size = Vector3.new(0.2, 1.6, width), CFrame = at(0, 6, 0.1), Color = Color3.fromRGB(245, 240, 225), Material = Enum.Material.SmoothPlastic, Parent = model })
	Kit.paint(board, if face.X > 0 then Enum.NormalId.Right else Enum.NormalId.Left, pick(SHOPS, rng), awningColor)
end

local function waterTank(model: Model, cframe: CFrame, size: Vector3, rng: Random)
	local tank = cframe * CFrame.new(rng:NextNumber(-size.X / 4, size.X / 4), size.Y / 2 + 2.2, rng:NextNumber(-size.Z / 4, size.Z / 4))
	Kit.decor({
		Name = "WaterTank",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.4, 3.2, 3.2),
		CFrame = tank * CFrame.Angles(0, 0, math.pi / 2),
		Color = if rng:NextNumber() < 0.5 then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(40, 90, 170),
		Material = Enum.Material.Plastic,
		Parent = model,
	})
end

-- One building. `cframe` is the ground-level centre; its -X side faces the road when roadSide
-- is -1, +X when it is 1.
local function build(parent: Instance, spec: StyleSpec, cframe: CFrame, size: Vector3, roadSide: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Building"
	model.Parent = parent
	local centre = cframe * CFrame.new(0, size.Y / 2, 0)
	local wall = pick(spec.walls, rng)

	local body = Kit.part({
		Name = "Walls",
		Size = size,
		CFrame = centre,
		Color = wall,
		Material = spec.material,
		Reflectance = if spec.glassBuilding then 0.25 else 0,
		Parent = model,
	})

	local roadFace = Vector3.new(roadSide, 0, 0)
	if spec.glassBuilding then
		-- Curtain-wall towers: floor slabs every two floors instead of window bands.
		for y = FLOOR * 2, size.Y - 2, FLOOR * 2 do
			Kit.decor({
				Name = "Slab",
				Size = Vector3.new(size.X + 0.4, 0.5, size.Z + 0.4),
				CFrame = centre * CFrame.new(0, y - size.Y / 2, 0),
				Color = Color3.fromRGB(220, 225, 230),
				Material = Enum.Material.Concrete,
				CastShadow = false,
				Parent = model,
			})
		end
	elseif spec.floors.Max > 1 then
		local hasShop = rng:NextNumber() < spec.shopfront
		local firstFloor = if hasShop then 8.1 else 3.6
		-- A band per floor on the face drivers see; side walls get one tall glass panel each,
		-- which reads fine at a glance and keeps the part count phone-friendly.
		windowsOnFace(model, centre, size, roadFace, firstFloor, wall, true)
		if size.Y > firstFloor + 4 then
			for _, sign in { -1, 1 } do
				local panel = Kit.decor({
					Name = "Windows",
					Size = Vector3.new(size.X * 0.5, size.Y - firstFloor - 2, 0.12),
					CFrame = centre * CFrame.new(0, (firstFloor - 1.2) / 2 - 1.2 + 0.6, sign * (size.Z / 2 + 0.06)),
					Color = GLASS_DAY,
					Material = Enum.Material.Glass,
					Reflectance = 0.15,
					CastShadow = false,
					Parent = model,
				})
				table.insert(Buildings.windows, panel)
			end
		end
		if hasShop then
			shopfront(model, centre, size, roadFace, rng)
		end
		if spec.balconies and size.Y > 10 then
			for y = firstFloor + 1.6, size.Y - 3, FLOOR do
				Kit.decor({
					Name = "Balcony",
					Size = Vector3.new(1.6, 0.4, size.Z * 0.6),
					CFrame = centre * CFrame.new(roadSide * (size.X / 2 + 0.8), y - size.Y / 2, 0),
					Color = Color3.fromRGB(240, 240, 235),
					Material = Enum.Material.Concrete,
					CastShadow = false,
					Parent = model,
				})
			end
		end
	elseif rng:NextNumber() < spec.shopfront then
		shopfront(model, centre, size, roadFace, rng)
	end

	if spec.mabatiRoof and rng:NextNumber() < spec.mabatiRoof then
		Kit.decor({
			Name = "Mabati",
			Size = Vector3.new(size.X + 1.2, 0.4, size.Z + 1.2),
			CFrame = centre * CFrame.new(0, size.Y / 2 + 0.4, 0) * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-5, 5))),
			Color = if rng:NextNumber() < 0.6 then Color3.fromRGB(150, 90, 60) else Color3.fromRGB(150, 155, 160),
			Material = Enum.Material.CorrodedMetal,
			Parent = model,
		})
	else
		Kit.decor({
			Name = "Parapet",
			Size = Vector3.new(size.X + 0.6, 0.8, size.Z + 0.6),
			CFrame = centre * CFrame.new(0, size.Y / 2 + 0.1, 0),
			Color = wall:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.Concrete,
			Parent = model,
		})
		if rng:NextNumber() < spec.tank then
			waterTank(model, centre, size, rng)
		end
	end
	return body
end

-- A perimeter wall with a gate gap, for leafy compounds.
local function compoundWall(model: Instance, cframe: CFrame, plot: Vector3, roadSide: number)
	local front = cframe * CFrame.new(roadSide * plot.X / 2, 1.5, 0)
	for _, side in { -1, 1 } do
		Kit.part({
			Name = "Wall",
			Size = Vector3.new(0.8, 3, plot.Z / 2 - 4),
			CFrame = front * CFrame.new(0, 0, side * (plot.Z / 4 + 2)),
			Color = Color3.fromRGB(200, 190, 175),
			Material = Enum.Material.Brick,
			Parent = model,
		})
	end
end

local function alongRoads(parent: Folder, rng: Random)
	for _, road in World.Roads do
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local frame = CFrame.lookAt(Kit.flat(a), Kit.flat(b))
			local length = Kit.flat(b - a).Magnitude
			local along = 10
			while along < length - 10 do
				local probe = frame * CFrame.new(0, 0, -along)
				local district = World.districtAt(probe.Position)
				local spec = STYLES[district.style]
				for _, side in { -1, 1 } do
					local rows = if spec.secondRow then 2 else 1
					local offset = road.width / 2 + SETBACK
					for _ = 1, rows do
						local floors = math.floor(between(spec.floors, rng) + 0.5)
						local height = if spec.floors.Max <= 1 then rng:NextNumber(5, 7) else 3.6 + floors * FLOOR
						local width = between(spec.width, rng)
						local depth = between(spec.depth, rng)
						local extra = if spec.compound then 10 else 0
						local distance = offset + extra + depth / 2
						local spot = frame * CFrame.new(side * distance, 0, -along - rng:NextNumber(-3, 3))
						local position = spot.Position
						local cframe = CFrame.new(position) * frame.Rotation
						-- Footprint check: every corner clear of every road (by the pavement), and
						-- nothing else already standing there.
						local radius = math.max(width, depth) / 2 * 0.85
						local inKibera = position.X > World.KiberaField.min.X and position.X < World.KiberaField.max.X
							and position.Z > World.KiberaField.min.Z and position.Z < World.KiberaField.max.Z
						local clear = not (spec ~= STYLES.shacks and inKibera) and Kit.isFree(position, radius)
						if clear then
							for _, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
								local point = (cframe * CFrame.new(corner.X * depth / 2, 0, corner.Z * width / 2)).Position
								if World.distanceToRoadEdge(point) < SETBACK - 2 then
									clear = false
									break
								end
							end
						end
						if not clear then
							break
						end
						build(parent, spec, cframe, Vector3.new(depth, height, width), -side, rng)
						Kit.claim(position, radius)
						if spec.compound then
							local plot = Vector3.new(depth + extra * 2, 0, width + 12)
							compoundWall(parent, CFrame.new(position) * frame.Rotation, plot, -side)
							Roads.tree(parent, (CFrame.new(position) * frame.Rotation * CFrame.new(-side * (depth / 2 + 5), 0, width / 2)).Position, rng)
						end
						offset = distance + depth / 2 + 6
					end
				end
				along += spec.spacing + rng:NextNumber(-3, 3)
			end
		end
	end
end

-- Dense mabati houses filling the Kibera field, with lanes between them.
local function kibera(parent: Folder, rng: Random)
	local spec = STYLES.shacks
	local field = World.KiberaField
	local step = 12
	for x = field.min.X, field.max.X, step do
		for z = field.min.Z, field.max.Z, step do
			-- Narrow footpaths every few rows.
			local column = math.floor((x - field.min.X) / step)
			local row = math.floor((z - field.min.Z) / step)
			if column % 5 ~= 2 and row % 6 ~= 3 then
				local position = Vector3.new(x + rng:NextNumber(-1.5, 1.5), 0, z + rng:NextNumber(-1.5, 1.5))
				local width, depth = rng:NextNumber(7, 10), rng:NextNumber(7, 10)
				local radius = math.max(width, depth) / 2
				if Kit.canPlace(position, radius, 4) then
					local cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0)
					build(parent, spec, cframe, Vector3.new(depth, rng:NextNumber(5, 6.5), width), 1, rng)
					Kit.claim(position, radius * 0.9)
				end
			end
		end
	end
end

-- Back-lot buildings filling the blocks between roads, so the skyline reads as a dense city.
-- Simple boxes (walls, roof, one window panel) because they're seen from a distance.
local function infill(parent: Folder, rng: Random)
	local min, max = World.Bounds.min, World.Bounds.max
	local step = 34
	for x = min.X, max.X, step do
		for z = min.Z, max.Z, step do
			local position = Vector3.new(x + rng:NextNumber(-6, 6), 0, z + rng:NextNumber(-6, 6))
			local edge = World.distanceToRoadEdge(position)
			local inKibera = position.X > World.KiberaField.min.X - 20 and position.X < World.KiberaField.max.X + 20
				and position.Z > World.KiberaField.min.Z - 20 and position.Z < World.KiberaField.max.Z + 20
			if edge > 36 and edge < 220 and not inKibera then
				local district = World.districtAt(position)
				local spec = STYLES[district.style]
				if spec ~= STYLES.shacks then
					local width, depth = between(spec.width, rng), between(spec.depth, rng)
					local radius = math.max(width, depth) / 2 * 0.9
					-- Taller near the roads, lower further back.
					local falloff = 1 - math.clamp((edge - 36) / 200, 0, 0.6)
					local floors = math.max(1, math.floor(between(spec.floors, rng) * falloff + 0.5))
					local height = 3.6 + floors * FLOOR
					if Kit.isFree(position, radius) then
						local model = Instance.new("Model")
						model.Name = "Infill"
						model.Parent = parent
						local cframe = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90 + rng:NextNumber(-4, 4)), 0)
						local wall = pick(spec.walls, rng)
						Kit.part({ Name = "Walls", Size = Vector3.new(depth, height, width), CFrame = cframe, Color = wall, Material = spec.material, Parent = model })
						if height > 8 and not spec.glassBuilding then
							local panel = Kit.decor({
								Name = "Windows",
								Size = Vector3.new(depth * 0.7, height - 5, 0.12),
								CFrame = cframe * CFrame.new(0, 0.5, -width / 2 - 0.06),
								Color = GLASS_DAY,
								Material = Enum.Material.Glass,
								CastShadow = false,
								Parent = model,
							})
							table.insert(Buildings.windows, panel)
						end
						if spec.mabatiRoof and rng:NextNumber() < spec.mabatiRoof then
							Kit.decor({ Name = "Mabati", Size = Vector3.new(depth + 1, 0.4, width + 1), CFrame = cframe * CFrame.new(0, height / 2 + 0.3, 0), Color = Color3.fromRGB(150, 90, 60), Material = Enum.Material.CorrodedMetal, Parent = model })
						end
						Kit.claim(position, radius)
					end
				end
			end
		end
	end
end

local function districtSigns(parent: Folder)
	for _, district in World.Districts do
		local anchor = Kit.decor({
			Name = district.displayName,
			Size = Vector3.one,
			Position = district.position + Vector3.new(0, 70, 0),
			Transparency = 1,
			Parent = parent,
		})
		Kit.billboard(anchor, string.upper(district.displayName), district.color, UDim2.fromOffset(300, 56), Vector3.zero, 900)
	end
end

function Buildings.build()
	local folder = Kit.folder("Buildings")
	local rng = Random.new(254)
	kibera(Kit.folder("Kibera"), rng)
	alongRoads(folder, rng)
	infill(Kit.folder("Infill"), rng)
	districtSigns(Kit.folder("DistrictSigns"))
end

local lit = false
-- Windows glow after dusk; about 60% of them, like real offices and flats.
function Buildings.setLit(on: boolean)
	if on == lit then
		return
	end
	lit = on
	local rng = Random.new(91)
	for _, window in Buildings.windows do
		if on and rng:NextNumber() < 0.6 then
			window.Material = Enum.Material.Neon
			window.Color = GLASS_NIGHT
			window.Reflectance = 0
		else
			window.Material = Enum.Material.Glass
			window.Color = GLASS_DAY
			window.Reflectance = 0.15
		end
	end
end

return Buildings
