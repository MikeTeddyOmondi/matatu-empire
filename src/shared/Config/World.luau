--!strict
-- The game world, derived from Config/Nairobi: projects real coordinates onto the map, builds
-- the road graph, finds each route's path with Dijkstra, and places stages beside their road.
-- Pure math with no services, so the server, the client and the unit tests all share it.
--
-- Map axes: +X is east, -Z is north, Y is up. Roads sit on the ground at Y = 0.

local Nairobi = require(script.Parent.Nairobi)

export type Node = {
	id: string,
	position: Vector3,
	roundabout: boolean,
	roads: { string }, -- names of the roads through this node
}

export type Road = {
	name: string,
	kind: Nairobi.RoadKind,
	width: number,
	trees: boolean,
	nodeIds: { string },
	points: { Vector3 },
}

export type Segment = {
	a: Vector3,
	b: Vector3,
	width: number,
	road: Road,
}

export type District = {
	id: string,
	displayName: string,
	position: Vector3,
	style: Nairobi.Style,
	color: Color3,
}

export type Stage = {
	id: string,
	displayName: string,
	district: string,
	districtMultiplier: number,
	unlockLevel: number,
	color: Color3,
	node: string,
	position: Vector3, -- centre of the road at the stage
	roadWidth: number,
	roadDirection: Vector3, -- along the road, pointing so the shelter is on the left (Kenya drives on the left)
	side: Vector3, -- unit vector from the road towards the shelter
	zoneRadius: number,
	shelterCFrame: CFrame, -- shelter centre, facing the road
	vehicleSpawn: CFrame, -- left lane beside the shelter
}

export type Route = {
	id: string,
	from: string,
	to: string,
	nodePath: { string },
	path: { Vector3 }, -- every node on the way, start and end included
	checkpoints: { Vector3 }, -- the stretch to drive through, destination excluded
	length: number, -- studs
	baseFare: number, -- Bob per passenger before multipliers
	minTripSeconds: number, -- anything faster is rejected as an exploit
}

export type Landmark = {
	id: string,
	kind: string,
	displayName: string,
	position: Vector3,
	size: Vector3?,
	points: { Vector3 }?,
}

local World = {}

World.CheckpointRadius = 32
World.CheckpointShare = 0.6 -- share of a route's checkpoints you must pass for the fare
World.RoadWidths = { highway = 52, main = 44, street = 36 }
World.RoadTop = 0.4 -- road surface height

local KM_PER_DEG_LAT = 110.574
local KM_PER_DEG_LON = 111.320 * math.cos(math.rad(Nairobi.Origin.lat))

function World.toStuds(lat: number, lon: number): Vector3
	local east = (lon - Nairobi.Origin.lon) * KM_PER_DEG_LON * Nairobi.StudsPerKm
	local north = (lat - Nairobi.Origin.lat) * KM_PER_DEG_LAT * Nairobi.StudsPerKm
	return Vector3.new(east, 0, -north)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Nodes and roads --------------------------------------------------------------------------------

World.Nodes = {} :: { [string]: Node }
for id, node in Nairobi.Nodes do
	World.Nodes[id] = {
		id = id,
		position = World.toStuds(node.lat, node.lon),
		roundabout = node.roundabout == true,
		roads = {},
	}
end

World.Roads = {} :: { Road }
World.Segments = {} :: { Segment }
for _, road in Nairobi.Roads do
	local points = {}
	for _, nodeId in road.nodes do
		local node = World.Nodes[nodeId]
		assert(node, `Road "{road.name}" uses unknown node "{nodeId}"`)
		table.insert(points, node.position)
		table.insert(node.roads, road.name)
	end
	local built: Road = {
		name = road.name,
		kind = road.kind,
		width = World.RoadWidths[road.kind],
		trees = road.trees == true,
		nodeIds = road.nodes,
		points = points,
	}
	table.insert(World.Roads, built)
	for i = 1, #points - 1 do
		table.insert(World.Segments, { a = points[i], b = points[i + 1], width = built.width, road = built })
	end
end

-- Closest point on a segment (flat), and how far along it is (0..1).
local function closestOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = flat(b - a)
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return a, 0
	end
	local t = math.clamp(flat(p - a):Dot(ab) / lengthSq, 0, 1)
	return a + ab * t, t
end

-- Nearest point on any road centre line, the road direction there (pointing the way `facing`
-- points, if given), the flat distance to it, and its segment.
function World.nearestRoadPoint(position: Vector3, facing: Vector3?): (Vector3, Vector3, number, Segment)
	local best: Segment = World.Segments[1]
	local bestPoint, bestDistance = best.a, math.huge
	for _, segment in World.Segments do
		local point = closestOnSegment(position, segment.a, segment.b)
		local distance = flat(position - point).Magnitude
		if distance < bestDistance then
			best, bestPoint, bestDistance = segment, point, distance
		end
	end
	local direction = flat(best.b - best.a).Unit
	if facing and flat(facing):Dot(direction) < 0 then
		direction = -direction
	end
	return bestPoint, direction, bestDistance, best
end

-- Distance from a point to the nearest road edge (negative when on a road).
function World.distanceToRoadEdge(position: Vector3, ignoreRoad: Road?): number
	local best = math.huge
	for _, segment in World.Segments do
		if segment.road ~= ignoreRoad then
			local point = closestOnSegment(position, segment.a, segment.b)
			best = math.min(best, flat(position - point).Magnitude - segment.width / 2)
		end
	end
	for _, node in World.Nodes do
		if node.roundabout then
			best = math.min(best, flat(position - node.position).Magnitude - World.roundaboutRadius(node))
		end
	end
	return best
end

function World.widestRoadAt(node: Node): number
	local widest = 0
	for _, road in World.Roads do
		if table.find(road.nodeIds, node.id) then
			widest = math.max(widest, road.width)
		end
	end
	return widest
end

function World.roundaboutRadius(node: Node): number
	return World.widestRoadAt(node) * 0.85
end

-- Districts and landmarks -------------------------------------------------------------------------

World.Districts = {} :: { District }
for _, district in Nairobi.Districts do
	table.insert(World.Districts, {
		id = district.id,
		displayName = district.displayName,
		position = World.toStuds(district.lat, district.lon),
		style = district.style,
		color = district.color,
	})
end

function World.districtAt(position: Vector3): District
	local best, bestDistance = World.Districts[1], math.huge
	for _, district in World.Districts do
		local distance = flat(position - district.position).Magnitude
		if distance < bestDistance then
			best, bestDistance = district, distance
		end
	end
	return best
end

function World.district(id: string): District?
	for _, district in World.Districts do
		if district.id == id then
			return district
		end
	end
	return nil
end

World.Landmarks = {} :: { Landmark }
for _, landmark in Nairobi.Landmarks do
	local points: { Vector3 }? = nil
	if landmark.points then
		local projected = {}
		for _, point in landmark.points do
			table.insert(projected, World.toStuds(point[1], point[2]))
		end
		points = projected
	end
	table.insert(World.Landmarks, {
		id = landmark.id,
		kind = landmark.kind :: string,
		displayName = landmark.displayName,
		position = World.toStuds(landmark.lat, landmark.lon),
		size = landmark.size,
		points = points,
	})
end

do
	local field = Nairobi.KiberaField
	local a = World.toStuds(field.latMin, field.lonMin)
	local b = World.toStuds(field.latMax, field.lonMax)
	World.KiberaField = {
		min = Vector3.new(math.min(a.X, b.X), 0, math.min(a.Z, b.Z)),
		max = Vector3.new(math.max(a.X, b.X), 0, math.max(a.Z, b.Z)),
	}
end

-- Overall extent of the roads, with a margin, for the ground and the minimap.
do
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, node in World.Nodes do
		minX, maxX = math.min(minX, node.position.X), math.max(maxX, node.position.X)
		minZ, maxZ = math.min(minZ, node.position.Z), math.max(maxZ, node.position.Z)
	end
	local margin = 240
	World.Bounds = {
		min = Vector3.new(minX - margin, 0, minZ - margin),
		max = Vector3.new(maxX + margin, 0, maxZ + margin),
	}
end

-- Stages ----------------------------------------------------------------------------------------

local function roadThrough(nodeId: string): Road
	for _, road in World.Roads do
		if table.find(road.nodeIds, nodeId) then
			return road
		end
	end
	error(`No road passes through stage node "{nodeId}"`)
end

World.Stages = {} :: { [string]: Stage }
World.StageOrder = {} :: { string }
for _, stage in Nairobi.Stages do
	local node = World.Nodes[stage.node]
	assert(node, `Stage "{stage.id}" uses unknown node "{stage.node}"`)
	local road = roadThrough(stage.node)
	local index = table.find(road.nodeIds, stage.node) :: number
	local before = road.points[math.max(1, index - 1)]
	local after = road.points[math.min(#road.points, index + 1)]
	local along = flat(after - before).Unit

	-- Put the shelter on whichever side has more room (away from other roads).
	local leftOf = Vector3.new(along.Z, 0, -along.X)
	local probe = road.width / 2 + 16
	local leftRoom = World.distanceToRoadEdge(node.position + leftOf * probe, road)
	local rightRoom = World.distanceToRoadEdge(node.position - leftOf * probe, road)
	local side = if leftRoom >= rightRoom then leftOf else -leftOf
	-- Drive with the kerb (and the shelter) on your left.
	local direction = if Vector3.new(along.Z, 0, -along.X):Dot(side) > 0 then along else -along

	local shelterAt = node.position + side * (road.width / 2 + 10)
	local spawnAt = node.position + side * (road.width / 4) + Vector3.new(0, World.RoadTop + 3.2, 0)
	local district = World.district(stage.district)

	World.Stages[stage.id] = {
		id = stage.id,
		displayName = stage.displayName,
		district = stage.district,
		districtMultiplier = stage.districtMultiplier,
		unlockLevel = stage.unlockLevel,
		color = if district then district.color else Color3.new(1, 1, 1),
		node = stage.node,
		position = node.position,
		roadWidth = road.width,
		roadDirection = direction,
		side = side,
		zoneRadius = math.max(34, road.width * 0.8),
		shelterCFrame = CFrame.lookAt(shelterAt, node.position),
		vehicleSpawn = CFrame.lookAt(spawnAt, spawnAt + direction),
	}
	table.insert(World.StageOrder, stage.id)
end

-- Routes ----------------------------------------------------------------------------------------

local adjacency: { [string]: { { to: string, length: number } } } = {}
for _, road in World.Roads do
	for i = 1, #road.nodeIds - 1 do
		local a, b = road.nodeIds[i], road.nodeIds[i + 1]
		local length = flat(road.points[i + 1] - road.points[i]).Magnitude
		adjacency[a] = adjacency[a] or {}
		adjacency[b] = adjacency[b] or {}
		table.insert(adjacency[a], { to = b, length = length })
		table.insert(adjacency[b], { to = a, length = length })
	end
end

-- Shortest path between two nodes along the roads (Dijkstra; the graph is small).
function World.shortestPath(fromId: string, toId: string): ({ string }?, number)
	local distance: { [string]: number } = { [fromId] = 0 }
	local previous: { [string]: string } = {}
	local done: { [string]: boolean } = {}
	while true do
		local current, currentDistance = nil, math.huge
		for id, d in distance do
			if not done[id] and d < currentDistance then
				current, currentDistance = id, d
			end
		end
		if not current then
			return nil, math.huge
		end
		if current == toId then
			break
		end
		done[current] = true
		local edges = adjacency[current]
		if edges then
			for _, edge in edges do
				local candidate = currentDistance + edge.length
				if candidate < (distance[edge.to] or math.huge) then
					distance[edge.to] = candidate
					previous[edge.to] = current
				end
			end
		end
	end
	local path = { toId }
	while path[1] ~= fromId do
		table.insert(path, 1, previous[path[1]])
	end
	return path, distance[toId]
end

local MIN_CHECKPOINT_GAP = 50

local function buildRoute(fromId: string, toId: string): Route
	local from, to = World.Stages[fromId], World.Stages[toId]
	local nodePath, length = World.shortestPath(from.node, to.node)
	assert(nodePath, `No road connects {fromId} and {toId}`)
	local path, checkpoints = {}, {}
	local last = from.position
	for i, nodeId in nodePath do
		local position = World.Nodes[nodeId].position
		table.insert(path, position)
		local isEnd = i == 1 or i == #nodePath
		if not isEnd and flat(position - last).Magnitude >= MIN_CHECKPOINT_GAP then
			table.insert(checkpoints, position)
			last = position
		end
	end
	return {
		id = `{fromId}->{toId}`,
		from = fromId,
		to = toId,
		nodePath = nodePath,
		path = path,
		checkpoints = checkpoints,
		length = length,
		baseFare = math.floor(20 + length / 25),
		minTripSeconds = length / 110, -- faster than any matatu can go
	}
end

World.Routes = {} :: { [string]: Route }
for _, pair in Nairobi.Routes do
	local there = buildRoute(pair[1], pair[2])
	local back = buildRoute(pair[2], pair[1])
	World.Routes[there.id] = there
	World.Routes[back.id] = back
end

function World.route(fromId: string, toId: string): Route?
	return World.Routes[`{fromId}->{toId}`]
end

-- Routes leaving a stage, cheapest unlock first, then nearest first.
function World.routesFrom(stageId: string): { Route }
	local list = {}
	for _, route in World.Routes do
		if route.from == stageId then
			table.insert(list, route)
		end
	end
	table.sort(list, function(a, b)
		local la, lb = World.Stages[a.to].unlockLevel, World.Stages[b.to].unlockLevel
		if la ~= lb then
			return la < lb
		end
		return a.length < b.length
	end)
	return list
end

-- Whether a player of this level may run a route (both ends unlocked).
function World.routeUnlocked(route: Route, level: number): boolean
	return level >= World.Stages[route.from].unlockLevel and level >= World.Stages[route.to].unlockLevel
end

return World
