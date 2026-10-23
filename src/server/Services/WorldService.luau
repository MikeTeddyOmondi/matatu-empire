--!strict
-- Builds the prototype city at runtime (ground, roads, stages, filler buildings) and runs the
-- day/night clock. Replace the generated geometry with a hand-built map later; the rest of the
-- game only depends on the stage positions in Config/World.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Economy = require(Shared.Config.Economy)

local WorldService = {}

local mapFolder: Folder

local ASPHALT = Color3.fromRGB(46, 48, 52)
local STRIPE = Color3.fromRGB(240, 200, 40)
local CONCRETE = Color3.fromRGB(170, 168, 160)
local GRASS = Color3.fromRGB(96, 140, 72)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent or mapFolder
	return p
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = flat(b - a)
	local ap = flat(point - a)
	local t = math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1)
	return (ap - ab * t).Magnitude
end

local function nearRoad(point: Vector3, clearance: number): boolean
	for i = 1, #World.RoadPath - 1 do
		if distanceToSegment(point, World.RoadPath[i], World.RoadPath[i + 1]) < clearance then
			return true
		end
	end
	return false
end

local function nearStage(point: Vector3, clearance: number): boolean
	for _, stage in World.Stages do
		if (flat(point) - flat(stage.position)).Magnitude < clearance then
			return true
		end
	end
	return false
end

local function buildGround()
	part({
		Name = "Ground",
		Size = Vector3.new(1400, 2, 1400),
		Position = Vector3.new(210, -1, -210),
		Color = GRASS,
		Material = Enum.Material.Grass,
	})
end

local function buildRoads()
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = mapFolder
	for i = 1, #World.RoadPath - 1 do
		local a, b = World.RoadPath[i], World.RoadPath[i + 1]
		local length = (b - a).Magnitude
		local mid = (a + b) / 2
		local frame = CFrame.lookAt(mid, b)
		part({
			Name = `Road{i}`,
			Size = Vector3.new(World.RoadWidth, 0.4, length + World.RoadWidth),
			CFrame = frame + Vector3.new(0, 0.2, 0),
			Color = ASPHALT,
			Material = Enum.Material.Asphalt,
			Parent = roads,
		})
		-- Dashed centre line.
		local dashes = math.floor(length / 14)
		for d = 0, dashes - 1 do
			local along = -length / 2 + 7 + d * 14
			part({
				Name = "Dash",
				Size = Vector3.new(0.6, 0.05, 6),
				CFrame = frame * CFrame.new(0, 0.43, along),
				Color = STRIPE,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = roads,
			})
		end
	end
end

local function makeSign(parent: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = parent
end

local function buildStages()
	local stages = Instance.new("Folder")
	stages.Name = "Stages"
	stages.Parent = mapFolder
	for _, stage in World.Stages do
		local model = Instance.new("Model")
		model.Name = stage.id
		model.Parent = stages

		part({
			Name = "Pad",
			Size = Vector3.new(90, 0.5, 90),
			Position = stage.position + Vector3.new(0, 0.1, 0),
			Color = CONCRETE,
			Material = Enum.Material.Concrete,
			Parent = model,
		})

		-- Zone ring so drivers can see where to stop.
		local ring = part({
			Name = "Zone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, stage.zoneRadius * 2, stage.zoneRadius * 2),
			CFrame = CFrame.new(stage.position + Vector3.new(0, 0.42, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = stage.color,
			Material = Enum.Material.Neon,
			Transparency = 0.75,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		ring:SetAttribute("StageId", stage.id)

		-- Shelter where the crowd waits.
		local shelterPos = stage.position + stage.crowdOffset
		local roof = part({
			Name = "Roof",
			Size = Vector3.new(30, 1, 14),
			Position = shelterPos + Vector3.new(0, 12.5, 0), -- clears the tallest matatu (10.4 studs)
			Color = stage.color,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		if math.abs(stage.crowdOffset.X) > math.abs(stage.crowdOffset.Z) then
			roof.Size = Vector3.new(14, 1, 30)
		end
		for _, dx in { -1, 1 } do
			for _, dz in { -1, 1 } do
				part({
					Name = "Pole",
					Size = Vector3.new(0.8, 12, 0.8),
					Position = shelterPos
						+ Vector3.new(dx * (roof.Size.X / 2 - 1), 6.25, dz * (roof.Size.Z / 2 - 1)),
					Color = Color3.fromRGB(60, 60, 64),
					Material = Enum.Material.Metal,
					Parent = model,
				})
			end
		end
		makeSign(roof, stage.displayName, stage.color)

		local crowdAnchor = part({
			Name = "CrowdAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = shelterPos + Vector3.new(0, 0.5, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		crowdAnchor:SetAttribute("StageId", stage.id)
	end

	-- Players spawn at CBD Stage, under the shelter.
	local cbd = World.Stages.CBD
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = cbd.position + cbd.crowdOffset + Vector3.new(-12, 0.5, 4)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = mapFolder
end

local WALL_COLORS = {
	Color3.fromRGB(214, 196, 170),
	Color3.fromRGB(190, 120, 90),
	Color3.fromRGB(150, 175, 200),
	Color3.fromRGB(232, 228, 214),
	Color3.fromRGB(176, 196, 128),
	Color3.fromRGB(226, 170, 110),
}
local AWNING_COLORS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(30, 110, 200),
	Color3.fromRGB(240, 180, 30),
	Color3.fromRGB(30, 150, 80),
}
local SHOP_NAMES = { "DUKA", "HOTEL", "SALON", "CHEMIST", "HARDWARE", "BUTCHERY", "CAFE", "MITUMBA", "SHOP" }
local GLASS_DAY = Color3.fromRGB(56, 74, 92)
local GLASS_NIGHT = Color3.fromRGB(255, 212, 140)
local FLOOR_HEIGHT = 4.5
local COLUMN_SPACING = 5

local windowParts: { BasePart } = {}
local windowsLit = false

-- One face of a building: glass bands per floor with wall-coloured pillars over them.
-- `axis` is the building-local axis the face points along, `sign` which way.
local function buildFace(
	model: Model,
	frame: CFrame,
	size: Vector3,
	axis: "X" | "Z",
	sign: number,
	isFront: boolean,
	wallColor: Color3
)
	local half = if axis == "X" then size.X / 2 else size.Z / 2
	local span = (if axis == "X" then size.Z else size.X) - 1.6
	local function at(u: number, y: number, out: number): CFrame
		local localY = y - size.Y / 2
		if axis == "X" then
			return frame * CFrame.new(sign * (half + out), localY, u)
		end
		return frame * CFrame.new(u, localY, sign * (half + out))
	end
	local function sized(along: number, height: number, thickness: number): Vector3
		if axis == "X" then
			return Vector3.new(thickness, height, along)
		end
		return Vector3.new(along, height, thickness)
	end

	local firstFloor = if isFront then 8.1 else 3.6
	local lastFloor = firstFloor
	for y = firstFloor, size.Y - 2.6, FLOOR_HEIGHT do
		lastFloor = y
		local glass = part({
			Name = "Windows",
			CanCollide = false, -- decoration: nothing to snag a matatu on
			CanQuery = false,
			Size = sized(span, 2.3, 0.1),
			CFrame = at(0, y, 0.05),
			Color = GLASS_DAY,
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
			CastShadow = false,
			Parent = model,
		})
		table.insert(windowParts, glass)
	end
	if lastFloor < firstFloor or size.Y < firstFloor + 2 then
		return
	end

	-- Pillars split each band into separate windows.
	local columns = math.max(1, math.floor(span / COLUMN_SPACING))
	local pillarBottom, pillarTop = firstFloor - 1.3, lastFloor + 1.3
	for i = 1, columns - 1 do
		local u = -span / 2 + i * span / columns
		part({
			Name = "Pillar",
			CanCollide = false, -- decoration: nothing to snag a matatu on
			CanQuery = false,
			Size = sized(0.8, pillarTop - pillarBottom, 0.16),
			CFrame = at(u, (pillarBottom + pillarTop) / 2, 0.08),
			Color = wallColor,
			Material = Enum.Material.Concrete,
			CastShadow = false,
			Parent = model,
		})
	end
end

local function buildShopfront(model: Model, frame: CFrame, size: Vector3, sign: number, rng: Random)
	local half = size.X / 2
	local function at(u: number, y: number, out: number): CFrame
		return frame * CFrame.new(sign * (half + out), y - size.Y / 2, u)
	end
	local width = math.min(size.Z - 8, 12)
	-- Shop window and door.
	part({
		Name = "ShopWindow",
		CanCollide = false, -- decoration: nothing to snag a matatu on
		CanQuery = false,
		Size = Vector3.new(0.1, 3.4, width),
		CFrame = at(0, 2.6, 0.05),
		Color = Color3.fromRGB(40, 52, 64),
		Material = Enum.Material.Glass,
		Reflectance = 0.2,
		Parent = model,
	})
	part({
		Name = "Door",
		CanCollide = false, -- decoration: nothing to snag a matatu on
		CanQuery = false,
		Size = Vector3.new(0.14, 4.2, 2.6),
		CFrame = at(width / 2 + 2, 2.1, 0.07),
		Color = Color3.fromRGB(70, 50, 36),
		Material = Enum.Material.Wood,
		Parent = model,
	})
	-- Awning sticking out over the pavement.
	local awningColor = AWNING_COLORS[rng:NextInteger(1, #AWNING_COLORS)]
	part({
		Name = "Awning",
		CanCollide = false, -- decoration: nothing to snag a matatu on
		CanQuery = false,
		Size = Vector3.new(2.4, 0.3, width + 2),
		CFrame = at(0, 4.9, 1.2) * CFrame.Angles(0, 0, sign * math.rad(-12)),
		Color = awningColor,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	-- Painted sign board above the awning.
	local sign_ = part({
		Name = "Sign",
		CanCollide = false, -- decoration: nothing to snag a matatu on
		CanQuery = false,
		Size = Vector3.new(0.2, 1.6, width),
		CFrame = at(0, 6.1, 0.1),
		Color = Color3.fromRGB(245, 240, 225),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = if sign > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.MaxDistance = 200
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = awningColor
	text.Text = SHOP_NAMES[rng:NextInteger(1, #SHOP_NAMES)]
	text.Parent = gui
	gui.Parent = sign_
end

local function buildBuilding(parent: Folder, cframe: CFrame, size: Vector3, roadSign: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Building"
	model.Parent = parent
	local wallColor = WALL_COLORS[rng:NextInteger(1, #WALL_COLORS)]

	part({
		Name = "Walls",
		Size = size,
		CFrame = cframe,
		Color = wallColor,
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	-- Roof parapet trim.
	part({
		Name = "Parapet",
		CanCollide = false, -- decoration: nothing to snag a matatu on
		CanQuery = false,
		Size = Vector3.new(size.X + 0.6, 0.8, size.Z + 0.6),
		CFrame = cframe * CFrame.new(0, size.Y / 2 + 0.1, 0),
		Color = wallColor:Lerp(Color3.new(0, 0, 0), 0.25),
		Material = Enum.Material.Concrete,
		Parent = model,
	})

	-- The face toward the road gets a shopfront on the ground floor.
	buildFace(model, cframe, size, "X", roadSign, true, wallColor)
	buildFace(model, cframe, size, "X", -roadSign, false, wallColor)
	buildFace(model, cframe, size, "Z", 1, false, wallColor)
	buildFace(model, cframe, size, "Z", -1, false, wallColor)
	buildShopfront(model, cframe, size, roadSign, rng)

	-- Rooftop water tank on about half the roofs.
	if rng:NextNumber() < 0.55 then
		local tankPos = cframe
			* CFrame.new(rng:NextNumber(-size.X / 4, size.X / 4), size.Y / 2 + 2.2, rng:NextNumber(-size.Z / 4, size.Z / 4))
		part({
			Name = "WaterTank",
			CanCollide = false, -- decoration: nothing to snag a matatu on
			CanQuery = false,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.4, 3.2, 3.2),
			CFrame = tankPos * CFrame.Angles(0, 0, math.pi / 2),
			Color = if rng:NextNumber() < 0.5 then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(40, 90, 170),
			Material = Enum.Material.Plastic,
			Parent = model,
		})
		part({
			Name = "TankStand",
			CanCollide = false, -- decoration: nothing to snag a matatu on
			CanQuery = false,
			Size = Vector3.new(3, 0.4, 3),
			CFrame = tankPos * CFrame.new(0, -1.9, 0),
			Color = Color3.fromRGB(90, 90, 96),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
end

local function buildFillerBuildings()
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = mapFolder
	local rng = Random.new(254)
	for i = 1, #World.RoadPath - 1 do
		local a, b = World.RoadPath[i], World.RoadPath[i + 1]
		local frame = CFrame.lookAt(a, b)
		local length = (b - a).Magnitude
		for along = 0, length, 34 do
			for _, side in { -1, 1 } do
				local width = rng:NextNumber(18, 28)
				local depth = rng:NextNumber(18, 28)
				-- Whole floors plus a little roof margin, so windows line up.
				local floors = rng:NextInteger(2, 12)
				local height = 3.6 + floors * FLOOR_HEIGHT
				local offset = World.RoadWidth / 2 + 10 + depth / 2
				local position = (frame * CFrame.new(side * offset, height / 2, -along)).Position
				local clearance = World.RoadWidth / 2 + math.max(width, depth) / 2 + 6
				if not nearRoad(position, clearance) and not nearStage(position, 70) then
					-- Building-local X points away from the road on this side, so the road is at -side.
					local cframe = CFrame.new(position) * frame.Rotation
					buildBuilding(buildings, cframe, Vector3.new(depth, height, width), -side, rng)
				end
			end
		end
	end
end

-- Windows glow after dusk; about 60% of them, like real offices and flats.
local function setWindowsLit(lit: boolean)
	if lit == windowsLit then
		return
	end
	windowsLit = lit
	local rng = Random.new(91)
	for _, window in windowParts do
		if lit and rng:NextNumber() < 0.6 then
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

local function startDayCycle()
	Lighting.ClockTime = 6.5
	local hoursPerSecond = 24 / Economy.DayLengthSeconds
	RunService.Heartbeat:Connect(function(dt: number)
		Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		local clock = Lighting.ClockTime
		setWindowsLit(clock >= 18.4 or clock < 6.2)
	end)
end

function WorldService.isRushHour(): boolean
	return Economy.isRushHour(Lighting.ClockTime)
end

-- Which stage zone (if any) contains this position, ignoring height.
function WorldService.stageAt(position: Vector3): string?
	for _, stage in World.Stages do
		if (flat(position) - flat(stage.position)).Magnitude <= stage.zoneRadius then
			return stage.id
		end
	end
	return nil
end

function WorldService.crowdPosition(stageId: string): Vector3
	local stage = World.Stages[stageId]
	return stage.position + stage.crowdOffset
end

function WorldService.init()
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace
	buildGround()
	buildRoads()
	buildStages()
	buildFillerBuildings()
end

function WorldService.start()
	startDayCycle()
end

return WorldService
