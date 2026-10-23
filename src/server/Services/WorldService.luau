--!strict
-- Builds Nairobi at server start from Config/Nairobi + Config/World (see src/server/City), and
-- runs the day/night clock. The rest of the game only depends on Config/World.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Economy = require(Shared.Config.Economy)

local City = script.Parent.Parent.City
local Kit = require(City.Kit)
local Roads = require(City.Roads)
local Stages = require(City.Stages)
local Landmarks = require(City.Landmarks)
local Buildings = require(City.Buildings)

local WorldService = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function WorldService.isRushHour(): boolean
	return Economy.isRushHour(Lighting.ClockTime)
end

-- Which stage zone (if any) contains this position, ignoring height.
function WorldService.stageAt(position: Vector3): string?
	for id, stage in World.Stages do
		if (flat(position) - flat(stage.position)).Magnitude <= stage.zoneRadius then
			return id
		end
	end
	return nil
end

function WorldService.crowdPosition(stageId: string): Vector3
	return World.Stages[stageId].shelterCFrame.Position
end

local function startDayCycle()
	Lighting.ClockTime = 6.5
	local hoursPerSecond = 24 / Economy.DayLengthSeconds
	RunService.Heartbeat:Connect(function(dt: number)
		Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		local clock = Lighting.ClockTime
		Buildings.setLit(clock >= 18.4 or clock < 6.2)
	end)
end

function WorldService.init()
	local map = Instance.new("Folder")
	map.Name = "Map"
	Kit.root = map
	Kit.reset()

	local started = os.clock()
	-- Order matters: roads first, then things that claim space before buildings fill the rest.
	Roads.build()
	Stages.build()
	Landmarks.build()
	Roads.buildTrees()
	Buildings.build()
	map.Parent = workspace

	local parts = 0
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[World] built Nairobi: %d parts in %.2f s", parts, os.clock() - started))
end

function WorldService.start()
	startDayCycle()
end

return WorldService
