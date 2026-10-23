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
			Position = shelterPos + Vector3.new(0, 11, 0),
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
					Size = Vector3.new(0.8, 10.5, 0.8),
					Position = shelterPos
						+ Vector3.new(dx * (roof.Size.X / 2 - 1), 5.5, dz * (roof.Size.Z / 2 - 1)),
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

local function buildFillerBuildings()
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = mapFolder
	local rng = Random.new(254)
	local palette = {
		Color3.fromRGB(214, 196, 170),
		Color3.fromRGB(190, 120, 90),
		Color3.fromRGB(120, 150, 180),
		Color3.fromRGB(230, 230, 220),
		Color3.fromRGB(170, 190, 120),
	}
	for i = 1, #World.RoadPath - 1 do
		local a, b = World.RoadPath[i], World.RoadPath[i + 1]
		local frame = CFrame.lookAt(a, b)
		local length = (b - a).Magnitude
		for along = 0, length, 34 do
			for _, side in { -1, 1 } do
				local width = rng:NextNumber(18, 28)
				local depth = rng:NextNumber(18, 28)
				local height = rng:NextNumber(14, 60)
				local offset = World.RoadWidth / 2 + 10 + depth / 2
				local position = (frame * CFrame.new(side * offset, height / 2, -along)).Position
				local clearance = World.RoadWidth / 2 + math.max(width, depth) / 2 + 6
				if not nearRoad(position, clearance) and not nearStage(position, 70) then
					part({
						Name = "Building",
						Size = Vector3.new(width, height, depth),
						CFrame = CFrame.new(position) * frame.Rotation,
						Color = palette[rng:NextInteger(1, #palette)],
						Material = Enum.Material.Concrete,
						Parent = buildings,
					})
				end
			end
		end
	end
end

local function startDayCycle()
	Lighting.ClockTime = 6.5
	local hoursPerSecond = 24 / Economy.DayLengthSeconds
	RunService.Heartbeat:Connect(function(dt: number)
		Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
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
