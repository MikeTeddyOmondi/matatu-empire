--!strict
-- Matatu stages: a lay-by, a glowing stop zone on the road, a shelter with the stage name, and
-- the spot where the waiting crowd stands. Positions come from Config/World.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local Kit = require(script.Parent.Kit)

local Stages = {}

local TOP = World.RoadTop

local function buildStage(parent: Folder, stage: World.Stage)
	local model = Instance.new("Model")
	model.Name = stage.id
	model.Parent = parent

	local along = stage.roadDirection
	local shelter = stage.shelterCFrame
	local layBy = stage.position + stage.side * (stage.roadWidth / 2 + 7)

	-- Concrete lay-by between the road edge and the shelter.
	Kit.part({
		Name = "LayBy",
		Size = Vector3.new(14, 1, 56),
		CFrame = CFrame.lookAt(layBy, layBy + along) * CFrame.new(0, TOP + 0.08 - 0.5, 0),
		Color = Kit.Colors.concrete,
		Material = Enum.Material.Concrete,
		Parent = model,
	})

	-- The stop zone drivers aim for.
	local ring = Kit.decor({
		Name = "Zone",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, stage.zoneRadius * 2, stage.zoneRadius * 2),
		CFrame = CFrame.new(stage.position + Vector3.new(0, TOP + 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = stage.color,
		Material = Enum.Material.Neon,
		Transparency = 0.78,
		Parent = model,
	})
	ring:SetAttribute("StageId", stage.id)

	-- Shelter: a roof on four poles, the name board and a bench.
	local roof = Kit.part({
		Name = "Roof",
		Size = Vector3.new(30, 1, 12),
		CFrame = shelter * CFrame.new(0, 12.5, 0),
		Color = stage.color,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, dx in { -14, 14 } do
		for _, dz in { -5, 5 } do
			Kit.part({
				Name = "Pole",
				Size = Vector3.new(0.8, 12, 0.8),
				CFrame = shelter * CFrame.new(dx, 6.25, dz),
				Color = Color3.fromRGB(60, 60, 64),
				Material = Enum.Material.Metal,
				Parent = model,
			})
		end
	end
	Kit.decor({
		Name = "Bench",
		Size = Vector3.new(22, 1, 2.5),
		CFrame = shelter * CFrame.new(0, 2, 4),
		Color = Color3.fromRGB(110, 80, 56),
		Material = Enum.Material.Wood,
		Parent = model,
	})
	Kit.billboard(roof, stage.displayName, stage.color, UDim2.fromOffset(280, 60), Vector3.new(0, 6, 0), 500)

	local anchor = Kit.decor({
		Name = "CrowdAnchor",
		Size = Vector3.one,
		CFrame = shelter * CFrame.new(0, 0.5, 0),
		Transparency = 1,
		Parent = model,
	})
	anchor:SetAttribute("StageId", stage.id)

	Kit.claim(shelter.Position, 24)
	Kit.claim(layBy, 30)
end

function Stages.build()
	local folder = Kit.folder("Stages")
	for _, id in World.StageOrder do
		buildStage(folder, World.Stages[id])
	end

	-- Players spawn under the first stage's shelter (Railways).
	local first = World.Stages[World.StageOrder[1]]
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = first.shelterCFrame * CFrame.new(-8, TOP + 0.5, -2)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = Kit.root
end

return Stages
