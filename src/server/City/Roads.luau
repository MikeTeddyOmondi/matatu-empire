--!strict
-- Ground, roads, roundabouts, pavements, lane markings, street-name signs and roadside trees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local Kit = require(script.Parent.Kit)

local Roads = {}

local C = Kit.Colors
local TOP = World.RoadTop
local PAVEMENT = 6 -- pavement width each side
local MAX_PART = 2000 -- Roblox caps part sizes at 2048

local function buildGround(parent: Folder)
	local min, max = World.Bounds.min, World.Bounds.max
	local tilesX = math.ceil((max.X - min.X) / MAX_PART)
	local tilesZ = math.ceil((max.Z - min.Z) / MAX_PART)
	local sizeX = (max.X - min.X) / tilesX
	local sizeZ = (max.Z - min.Z) / tilesZ
	for i = 0, tilesX - 1 do
		for j = 0, tilesZ - 1 do
			Kit.part({
				Name = "Ground",
				Size = Vector3.new(sizeX, 4, sizeZ),
				Position = Vector3.new(min.X + (i + 0.5) * sizeX, -2, min.Z + (j + 0.5) * sizeZ),
				Color = C.grass,
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
	end
	-- Bare earth under Kibera.
	local field = World.KiberaField
	local centre = (field.min + field.max) / 2
	local size = field.max - field.min
	Kit.part({
		Name = "KiberaGround",
		Size = Vector3.new(size.X + 30, 0.2, size.Z + 30),
		Position = Vector3.new(centre.X, 0.05, centre.Z),
		Color = C.dirt,
		Material = Enum.Material.Ground,
		CanCollide = false,
		Parent = parent,
	})
end

-- How much of a road end to leave clear at a junction or roundabout (for pavements and lines).
local function junctionClearance(nodeId: string): number
	local node = World.Nodes[nodeId]
	if node.roundabout then
		return World.roundaboutRadius(node) + 2
	end
	if #node.roads > 1 then
		return World.widestRoadAt(node) / 2 + 2
	end
	return 0
end

local function strip(parent: Folder, name: string, a: Vector3, b: Vector3, offset: number, width: number, top: number, thickness: number, color: Color3, material: Enum.Material, collide: boolean)
	local length = Kit.flat(b - a).Magnitude
	if length < 1 then
		return
	end
	local frame = CFrame.lookAt(Kit.flat(a), Kit.flat(b)) * CFrame.new(offset, top - thickness / 2, -length / 2)
	local props = {
		Name = name,
		Size = Vector3.new(width, thickness, length),
		CFrame = frame,
		Color = color,
		Material = material,
		Parent = parent,
	}
	if collide then
		Kit.part(props)
	else
		Kit.decor(props)
	end
end

local function buildRoad(parent: Folder, road: World.Road)
	local folder = Kit.folder(road.name, parent)
	local width = road.width
	for i = 1, #road.points - 1 do
		local a, b = road.points[i], road.points[i + 1]
		local direction = Kit.flat(b - a).Unit
		strip(folder, "Asphalt", a, b, 0, width, TOP, 1, C.asphalt, Enum.Material.Asphalt, true)

		-- Trim the ends at junctions so pavements and lines don't run across other roads.
		local trimA = junctionClearance(road.nodeIds[i])
		local trimB = junctionClearance(road.nodeIds[i + 1])
		local length = Kit.flat(b - a).Magnitude
		if trimA + trimB < length - 4 then
			local a2, b2 = a + direction * trimA, b - direction * trimB
			for _, side in { -1, 1 } do
				strip(folder, "Pavement", a2, b2, side * (width / 2 + PAVEMENT / 2), PAVEMENT, TOP + 0.05, 1, C.sidewalk, Enum.Material.Concrete, true)
			end
			if road.kind == "highway" then
				-- Double yellow line down the middle of a dual carriageway.
				for _, offset in { -0.5, 0.5 } do
					strip(folder, "Median", a2, b2, offset, 0.4, TOP + 0.02, 0.05, C.median, Enum.Material.SmoothPlastic, false)
				end
				-- Dashed lane lines on each side.
				local dashes = math.floor((length - trimA - trimB) / 16)
				for d = 0, dashes - 1 do
					local s = trimA + 4 + d * 16
					for _, offset in { -width / 4, width / 4 } do
						strip(folder, "Lane", a + direction * s, a + direction * (s + 7), offset, 0.5, TOP + 0.02, 0.05, C.lane, Enum.Material.SmoothPlastic, false)
					end
				end
			else
				local dashes = math.floor((length - trimA - trimB) / 16)
				for d = 0, dashes - 1 do
					local s = trimA + 4 + d * 16
					strip(folder, "Lane", a + direction * s, a + direction * (s + 7), 0, 0.5, TOP + 0.02, 0.05, C.lane, Enum.Material.SmoothPlastic, false)
				end
			end
		end
	end
	-- Round off every bend and end so segments join without gaps.
	for _, point in road.points do
		Kit.disc({ Name = "Joint", Color = C.asphalt, Material = Enum.Material.Asphalt, Parent = folder }, point, width / 2, 1, TOP)
	end
end

local function buildRoundabout(parent: Folder, node: World.Node)
	local radius = World.roundaboutRadius(node)
	local folder = Kit.folder("Roundabout", parent)
	Kit.disc({ Name = "Ring", Color = C.asphalt, Material = Enum.Material.Asphalt, Parent = folder }, node.position, radius, 1, TOP)
	-- A raised island you drive around. Checkpoints sit at the centre with a radius that
	-- reaches the ring, so going around counts.
	local island = radius * 0.42
	Kit.disc({ Name = "Kerb", Color = Color3.fromRGB(230, 230, 225), Material = Enum.Material.Concrete, Parent = folder }, node.position, island + 0.8, 1.2, TOP + 1)
	Kit.disc({ Name = "Island", Color = C.grass, Material = Enum.Material.Grass, Parent = folder }, node.position, island, 1.2, TOP + 1.1)
	Kit.decor({
		Name = "Flowers",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(island * 0.9, 3, island * 0.9),
		Position = node.position + Vector3.new(0, TOP + 1.5, 0),
		Color = Color3.fromRGB(250, 180, 40),
		Material = Enum.Material.Grass,
		Parent = folder,
	})
	Kit.claim(node.position, radius)
end

local function streetSign(parent: Folder, road: World.Road, i: number)
	local a, b = road.points[i], road.points[i + 1]
	local direction = Kit.flat(b - a).Unit
	local left = Vector3.new(direction.Z, 0, -direction.X)
	local length = Kit.flat(b - a).Magnitude
	local at = a + direction * math.min(length / 2, 60) + left * (road.width / 2 + PAVEMENT - 1)
	local pole = Kit.decor({
		Name = "StreetSign",
		Size = Vector3.new(0.5, 9, 0.5),
		Position = at + Vector3.new(0, TOP + 4.5, 0),
		Color = Color3.fromRGB(70, 70, 74),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	Kit.billboard(pole, road.name, Color3.new(1, 1, 1), UDim2.fromOffset(200, 34), Vector3.new(0, 5.5, 0), 220)
	local label = (pole:FindFirstChildOfClass("BillboardGui") :: BillboardGui):FindFirstChildOfClass("TextLabel") :: TextLabel
	label.BackgroundColor3 = C.signGreen
	label.BackgroundTransparency = 0
end

local JACARANDA = Color3.fromRGB(150, 110, 210)
local LEAVES = { Color3.fromRGB(60, 120, 50), Color3.fromRGB(80, 140, 60), Color3.fromRGB(50, 105, 55) }

function Roads.tree(parent: Instance, position: Vector3, rng: Random, scale: number?)
	local s = scale or rng:NextNumber(0.8, 1.3)
	local height = 9 * s
	Kit.decor({
		Name = "Trunk",
		Size = Vector3.new(1.2 * s, height, 1.2 * s),
		Position = position + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(92, 68, 48),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local canopy = if rng:NextNumber() < 0.18 then JACARANDA else LEAVES[rng:NextInteger(1, #LEAVES)]
	Kit.decor({
		Name = "Canopy",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(10, 7, 10) * s,
		Position = position + Vector3.new(0, height + 1.5 * s, 0),
		Color = canopy,
		Material = Enum.Material.Grass,
		CastShadow = true,
		Parent = parent,
	})
	Kit.claim(position, 3 * s)
end

local function roadsideTrees(parent: Folder, road: World.Road, rng: Random)
	for i = 1, #road.points - 1 do
		local a, b = road.points[i], road.points[i + 1]
		local direction = Kit.flat(b - a).Unit
		local right = Vector3.new(-direction.Z, 0, direction.X)
		local length = Kit.flat(b - a).Magnitude
		for s = 30, length - 30, 46 do
			for _, side in { -1, 1 } do
				local at = a + direction * (s + rng:NextNumber(-6, 6)) + right * side * (road.width / 2 + PAVEMENT + 4)
				if Kit.canPlace(at, 3, PAVEMENT + 1) then
					Roads.tree(parent, at, rng)
				end
			end
		end
	end
end

function Roads.build()
	local folder = Kit.folder("Roads")
	buildGround(Kit.folder("Ground"))
	for _, road in World.Roads do
		buildRoad(folder, road)
	end
	local roundabouts = Kit.folder("Roundabouts")
	for _, node in World.Nodes do
		if node.roundabout then
			buildRoundabout(roundabouts, node)
		end
	end
	local signs = Kit.folder("StreetSigns")
	for _, road in World.Roads do
		streetSign(signs, road, 1)
		if #road.points > 3 then
			streetSign(signs, road, math.floor(#road.points / 2))
		end
	end
end

-- Trees go in after stages and landmarks have claimed their space, before buildings.
function Roads.buildTrees()
	local folder = Kit.folder("Trees")
	local rng = Random.new(1963)
	for _, road in World.Roads do
		if road.trees then
			roadsideTrees(folder, road, rng)
		end
	end
end

return Roads
