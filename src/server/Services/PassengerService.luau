--!strict
-- Waiting crowds, the touting minigame, trips and fares.
--
-- A trip starts when passengers board at a stage, bound for the destination the driver picked
-- (or the first unlocked route from that stage). It pays when the matatu stops inside the
-- destination's zone, having passed enough of the route's checkpoints in order
-- (World.CheckpointShare; skipping ahead is fine), no faster than the route's minimum time, and
-- without failing the speed check. All of this is decided on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Economy = require(Shared.Config.Economy)
local Upgrades = require(Shared.Config.Upgrades)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

type Trip = {
	routeId: string?,
	passengers: number,
	nextCheckpoint: number,
	visited: number,
	startedAt: number,
}

type ActiveRound = {
	id: number,
	beats: { number },
	stageId: string,
	expiresAt: number,
}

local PassengerService = {}

local services: any
local trips: { [Player]: Trip } = {}
local rounds: { [Player]: ActiveRound } = {}
local lastToutAt: { [Player]: number } = {}
local chosenDestination: { [Player]: string } = {}
local nextRoundId = 0

local crowdCounts: { [string]: number } = {}
local crowdFigures: { [string]: { Model } } = {}
local crowdFolder: Folder

local STOP_SPEED = 5 -- studs/s: below this a matatu counts as stopped
local SHIRTS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(40, 90, 200),
	Color3.fromRGB(240, 180, 30),
	Color3.fromRGB(30, 150, 80),
	Color3.fromRGB(120, 60, 160),
	Color3.fromRGB(240, 240, 240),
}
local SKIN = {
	Color3.fromRGB(92, 58, 38),
	Color3.fromRGB(120, 78, 50),
	Color3.fromRGB(70, 44, 30),
	Color3.fromRGB(150, 104, 70),
}

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function getTrip(player: Player): Trip
	local trip = trips[player]
	if not trip then
		trip = { routeId = nil, passengers = 0, nextCheckpoint = 1, visited = 0, startedAt = 0 }
		trips[player] = trip
	end
	return trip
end

local function resetTrip(trip: Trip)
	trip.routeId = nil
	trip.passengers = 0
	trip.nextCheckpoint = 1
	trip.visited = 0
	trip.startedAt = 0
end

-- Crowd -----------------------------------------------------------------------------------------

local function makeFigure(stageId: string, rng: Random): Model
	local stage = World.Stages[stageId]
	-- Spread along the shelter, everyone facing the road.
	local spot = stage.shelterCFrame * CFrame.new(rng:NextNumber(-12, 12), World.RoadTop, rng:NextNumber(-4, 2))
	local base = spot.Position
	local facing = stage.position

	local model = Instance.new("Model")
	model.Name = "Passenger"
	local frame = CFrame.lookAt(base, Vector3.new(facing.X, base.Y, facing.Z))

	local function piece(name: string, size: Vector3, offsetY: number, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CFrame = frame * CFrame.new(0, offsetY, 0)
		p.Parent = model
	end

	local height = rng:NextNumber(0.9, 1.1)
	piece("Legs", Vector3.new(1.6, 2.2, 0.9) * height, 1.4 * height, Color3.fromRGB(40, 40, 60))
	piece("Torso", Vector3.new(2, 2, 1) * height, 3.5 * height, SHIRTS[rng:NextInteger(1, #SHIRTS)])
	piece(
		"Head",
		Vector3.new(1.3, 1.3, 1.3) * height,
		5.2 * height,
		SKIN[rng:NextInteger(1, #SKIN)],
		Enum.PartType.Ball
	)
	model.Parent = crowdFolder
	return model
end

local function setCrowd(stageId: string, count: number)
	count = math.clamp(count, 0, Economy.MaxCrowdPerStage)
	crowdCounts[stageId] = count
	local figures = crowdFigures[stageId]
	local rng = Random.new()
	while #figures < count do
		table.insert(figures, makeFigure(stageId, rng))
	end
	while #figures > count do
		local figure = table.remove(figures)
		if figure then
			figure:Destroy()
		end
	end
end

local function crowdLoop()
	local elapsed: { [string]: number } = {}
	for id in World.Stages do
		elapsed[id] = 0
	end
	while true do
		local dt = task.wait(0.5)
		local interval = Economy.CrowdSpawnInterval
		if services.WorldService.isRushHour() then
			interval /= 2
		end
		for id in World.Stages do
			elapsed[id] += dt
			if elapsed[id] >= interval then
				elapsed[id] = 0
				if crowdCounts[id] < Economy.MaxCrowdPerStage then
					setCrowd(id, crowdCounts[id] + 1)
				end
			end
		end
	end
end

-- Trips -----------------------------------------------------------------------------------------

local function seatsFor(player: Player): number
	local record = services.VehicleService.get(player)
	return if record then record.tier.seats else 0
end

local function vibeFor(player: Player): number
	local profile = services.PlayerDataService.get(player)
	return if profile then Upgrades.computeVibe(profile.upgrades) else 0
end

local function updateLabel(player: Player)
	local trip = getTrip(player)
	local seats = seatsFor(player)
	local text = `{player.DisplayName} · {trip.passengers}/{seats}`
	if trip.routeId and trip.passengers > 0 then
		local route = World.Routes[trip.routeId]
		text ..= ` · to {World.Stages[route.to].displayName}`
	end
	services.VehicleService.setLabel(player, text)
end

local function unloadUnpaid(player: Player, reason: string)
	local trip = getTrip(player)
	if trip.passengers > 0 then
		Net.event("Notify"):FireClient(player, reason, "warn")
	end
	resetTrip(trip)
	updateLabel(player)
	services.StateService.push(player)
end

local function completeTrip(player: Player, route: World.Route)
	local trip = getTrip(player)
	local from, to = World.Stages[route.from], World.Stages[route.to]
	local multiplier = math.max(from.districtMultiplier, to.districtMultiplier)
	local rush = services.WorldService.isRushHour()
	local vibe = vibeFor(player)
	local perPassenger = Economy.fare(route.baseFare, multiplier, vibe, rush)
	local profile = services.PlayerDataService.get(player)
	local interiorLevel = if profile then profile.upgrades.Interior or 0 else 0
	local tips = interiorLevel * 2 * trip.passengers
	local total = perPassenger * trip.passengers + tips
	local carried = trip.passengers

	services.PlayerDataService.update(player, function(p: Types.Profile)
		p.stats.trips += 1
		p.stats.passengersCarried += carried
	end)

	-- Some riders hang around at the destination and become its crowd.
	setCrowd(route.to, crowdCounts[route.to] + math.floor(carried / 3))

	resetTrip(trip)
	updateLabel(player)
	local reason = `{carried} passengers to {to.displayName}`
	if rush then
		reason ..= " (rush hour!)"
	end
	services.EconomyService.earn(player, total, reason)
end

local function tripLoop()
	while true do
		task.wait(0.25)
		for player, trip in trips do
			local record = services.VehicleService.get(player)
			if not record or not trip.routeId or trip.passengers <= 0 then
				continue
			end
			local route = World.Routes[trip.routeId]
			local position = services.VehicleService.position(record)

			-- Count the next checkpoint reached in order; skipping ahead to a later one is fine
			-- (you took a different lane, or went round a roundabout wide).
			local checkpoints = route.checkpoints
			for j = trip.nextCheckpoint, #checkpoints do
				if flatDistance(position, checkpoints[j]) <= World.CheckpointRadius then
					trip.visited += 1
					trip.nextCheckpoint = j + 1
					services.StateService.push(player)
					break
				end
			end

			local stageId = services.WorldService.stageAt(position)
			if stageId == route.to and services.VehicleService.speed(record) < STOP_SPEED then
				if record.flagged then
					record.flagged = false
					unloadUnpaid(player, "Passengers got off: this trip failed the speed check.")
				elseif trip.visited < math.ceil(#checkpoints * World.CheckpointShare) then
					unloadUnpaid(player, "Passengers got off unpaid: you didn't follow the route.")
				elseif os.clock() - trip.startedAt < route.minTripSeconds then
					unloadUnpaid(player, "That trip was impossibly fast. No fare.")
				else
					completeTrip(player, route)
				end
			end
		end
	end
end

-- Touting ---------------------------------------------------------------------------------------

local function startTout(player: Player): (Types.ToutRound?, string?)
	local record = services.VehicleService.get(player)
	if not record or not services.VehicleService.isDriving(player) then
		return nil, "Get in your matatu first"
	end
	local now = os.clock()
	if now - (lastToutAt[player] or 0) < Economy.ToutCooldown then
		return nil, "Catch your breath..."
	end
	if services.VehicleService.speed(record) > STOP_SPEED then
		return nil, "Stop at the stage to tout"
	end
	local stageId = services.WorldService.stageAt(services.VehicleService.position(record))
	if not stageId then
		return nil, "Drive into a stage zone to tout"
	end

	local trip = getTrip(player)
	if trip.passengers > 0 and trip.routeId then
		local route = World.Routes[trip.routeId]
		if route.from ~= stageId then
			unloadUnpaid(player, "Your passengers got off: they were going somewhere else.")
		end
	end
	if trip.passengers >= record.tier.seats then
		return nil, "You're full! Drive to your destination"
	end
	if trip.passengers == 0 and not PassengerService.routeFor(player, stageId) then
		local level = (services.PlayerDataService.get(player) or { level = 1 }).level
		local nextLevel = math.huge
		for _, route in World.routesFrom(stageId) do
			nextLevel = math.min(nextLevel, math.max(World.Stages[route.from].unlockLevel, World.Stages[route.to].unlockLevel))
		end
		return nil, if nextLevel < math.huge and nextLevel > level
			then `Routes from here unlock at level {nextLevel}`
			else "No routes from this stage"
	end
	if crowdCounts[stageId] <= 0 then
		return nil, "Nobody waiting. Give the crowd a few seconds"
	end

	lastToutAt[player] = now
	nextRoundId += 1
	local serverNow = workspace:GetServerTimeNow()
	local beats = {}
	for i = 0, Economy.ToutBeats - 1 do
		table.insert(beats, serverNow + Economy.ToutLeadIn + i * Economy.ToutBeatGap)
	end
	rounds[player] = {
		id = nextRoundId,
		beats = beats,
		stageId = stageId,
		expiresAt = beats[#beats] + 3,
	}
	return {
		roundId = nextRoundId,
		beats = beats,
		goodWindow = Economy.ToutGoodWindow,
		perfectWindow = Economy.ToutPerfectWindow,
	},
		nil
end

local function scoreRound(round: ActiveRound, presses: { number }): (number, number)
	local used: { [number]: boolean } = {}
	local perfect, good = 0, 0
	for _, beat in round.beats do
		local bestIndex, bestDiff = nil, math.huge
		for i, press in presses do
			if not used[i] then
				local diff = math.abs(press - beat)
				if diff < bestDiff then
					bestIndex, bestDiff = i, diff
				end
			end
		end
		if bestIndex and bestDiff <= Economy.ToutGoodWindow then
			used[bestIndex] = true
			if bestDiff <= Economy.ToutPerfectWindow then
				perfect += 1
			else
				good += 1
			end
		end
	end
	return perfect, good
end

local function submitTout(player: Player, roundId: unknown, presses: unknown)
	local round = rounds[player]
	if not round or type(roundId) ~= "number" or roundId ~= round.id or type(presses) ~= "table" then
		return
	end
	rounds[player] = nil
	local serverNow = workspace:GetServerTimeNow()
	if serverNow > round.expiresAt then
		return
	end

	-- Sanitize: numbers only, bounded count, and no presses from the future.
	local clean: { number } = {}
	for _, value in presses :: { any } do
		if type(value) == "number" and value == value and value <= serverNow + 0.05 then
			table.insert(clean, value)
		end
		if #clean >= Economy.ToutBeats * 3 then
			break
		end
	end
	-- Mashing is punished: every extra press beyond the beats costs a hit.
	local perfect, good = scoreRound(round, clean)
	local spam = math.max(0, #clean - Economy.ToutBeats)
	good = math.max(0, good - spam)

	local record = services.VehicleService.get(player)
	if not record then
		return
	end
	if services.WorldService.stageAt(services.VehicleService.position(record)) ~= round.stageId then
		Net.event("ToutResult"):FireClient(player, 0, perfect, good)
		return
	end

	local trip = getTrip(player)
	local vibe = vibeFor(player)
	local pull = math.floor((2 + perfect * 2 + good) * (1 + vibe / 100))
	local free = record.tier.seats - trip.passengers
	local boarded = math.max(0, math.min(pull, free, crowdCounts[round.stageId]))

	if boarded > 0 then
		setCrowd(round.stageId, crowdCounts[round.stageId] - boarded)
		if trip.passengers == 0 then
			local route = PassengerService.routeFor(player, round.stageId)
			if route then
				trip.routeId = route.id
				trip.nextCheckpoint = 1
				trip.visited = 0
				trip.startedAt = os.clock()
				record.flagged = false
			end
		end
		trip.passengers += boarded
		updateLabel(player)
		services.StateService.push(player)
	end
	Net.event("ToutResult"):FireClient(player, boarded, perfect, good)
end

-- Public ----------------------------------------------------------------------------------------

function PassengerService.getTrip(player: Player): Trip
	return getTrip(player)
end

function PassengerService.chosenDestination(player: Player): string?
	return chosenDestination[player]
end

-- The route passengers boarding at `stageId` will take: the driver's chosen destination if
-- there is an unlocked route to it from here, otherwise the first unlocked route.
function PassengerService.routeFor(player: Player, stageId: string): World.Route?
	local profile = services.PlayerDataService.get(player)
	local level = if profile then profile.level else 1
	local chosen = chosenDestination[player]
	if chosen then
		local route = World.route(stageId, chosen)
		if route and World.routeUnlocked(route, level) then
			return route
		end
	end
	for _, route in World.routesFrom(stageId) do
		if World.routeUnlocked(route, level) then
			return route
		end
	end
	return nil
end

function PassengerService.init(registry: any)
	services = registry
	crowdFolder = Instance.new("Folder")
	crowdFolder.Name = "Crowds"
	crowdFolder.Parent = workspace
	for id in World.Stages do
		crowdCounts[id] = 0
		crowdFigures[id] = {}
	end
end

function PassengerService.start()
	for id in World.Stages do
		setCrowd(id, 8)
	end

	Net.func("StartTout").OnServerInvoke = function(player: Player)
		local round, message = startTout(player)
		if not round and message then
			Net.event("Notify"):FireClient(player, message, "info")
		end
		return round
	end
	Net.event("SubmitTout").OnServerEvent:Connect(submitTout)

	local selectLimiter = Net.rateLimiter(4, 6)
	Net.func("SelectRoute").OnServerInvoke = function(player: Player, destination: unknown)
		if not selectLimiter:allow(player) then
			return false, "Slow down"
		end
		if type(destination) ~= "string" or not World.Stages[destination] then
			return false, "Unknown destination"
		end
		if getTrip(player).passengers > 0 then
			return false, "Drop off your passengers first"
		end
		chosenDestination[player] = destination
		services.StateService.push(player)
		return true, `Route: to {World.Stages[destination].displayName}`
	end

	services.VehicleService.onDespawn(function(player: Player)
		trips[player] = nil
		rounds[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		trips[player] = nil
		rounds[player] = nil
		lastToutAt[player] = nil
		chosenDestination[player] = nil
	end)

	task.spawn(crowdLoop)
	task.spawn(tripLoop)
end

return PassengerService
