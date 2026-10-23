--!strict
-- Layout of the prototype city. Everything here is generated at runtime by WorldService,
-- so the place file can stay empty while you iterate.

export type Stage = {
	id: string,
	displayName: string,
	position: Vector3,
	zoneRadius: number,
	districtMultiplier: number,
	color: Color3,
	crowdOffset: Vector3, -- where waiting passengers stand, relative to `position`
	vehicleSpawn: CFrame, -- where a matatu appears when spawned at this stage
}

export type Route = {
	id: string,
	from: string,
	to: string,
	baseFare: number, -- Bob per passenger before multipliers
	checkpoints: { Vector3 }, -- must be passed in order
	minTripSeconds: number, -- anything faster is rejected as an exploit
}

local World = {}

World.RoadWidth = 40
World.CheckpointRadius = 28

World.Stages = {
	CBD = {
		id = "CBD",
		displayName = "CBD Stage",
		position = Vector3.new(0, 0, 0),
		zoneRadius = 34,
		districtMultiplier = 1.0,
		color = Color3.fromRGB(255, 196, 0),
		crowdOffset = Vector3.new(0, 0, 30),
		-- Facing +X, along the road toward Estates.
		vehicleSpawn = CFrame.new(-24, 4, -8) * CFrame.Angles(0, -math.pi / 2, 0),
	},
	Estates = {
		id = "Estates",
		displayName = "Estates Stage",
		position = Vector3.new(420, 0, -420),
		zoneRadius = 34,
		districtMultiplier = 1.3,
		color = Color3.fromRGB(0, 200, 140),
		crowdOffset = Vector3.new(30, 0, 0),
		-- Facing +Z, back down the road toward CBD.
		vehicleSpawn = CFrame.new(412, 4, -444) * CFrame.Angles(0, math.pi, 0),
	},
} :: { [string]: Stage }

-- Road path from CBD to Estates (an L-shape). Reverse it for the return trip.
local cbdToEstates = {
	Vector3.new(140, 0, 0),
	Vector3.new(280, 0, 0),
	Vector3.new(420, 0, 0),
	Vector3.new(420, 0, -140),
	Vector3.new(420, 0, -280),
}

local function reversed(list: { Vector3 }): { Vector3 }
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

World.Routes = {
	["CBD->Estates"] = {
		id = "CBD->Estates",
		from = "CBD",
		to = "Estates",
		baseFare = 30,
		checkpoints = cbdToEstates,
		minTripSeconds = 12,
	},
	["Estates->CBD"] = {
		id = "Estates->CBD",
		from = "Estates",
		to = "CBD",
		baseFare = 30,
		checkpoints = reversed(cbdToEstates),
		minTripSeconds = 12,
	},
} :: { [string]: Route }

-- The road is drawn as straight segments through these points.
World.RoadPath = { World.Stages.CBD.position, Vector3.new(420, 0, 0), World.Stages.Estates.position }

function World.routeFrom(stageId: string): Route?
	for _, route in World.Routes do
		if route.from == stageId then
			return route
		end
	end
	return nil
end

return World
