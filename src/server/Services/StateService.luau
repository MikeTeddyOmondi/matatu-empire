--!strict
-- Builds the ClientState snapshot and sends it to its owner. Pushes are coalesced so many
-- changes in one frame cost one remote call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Economy = require(Shared.Config.Economy)
local Upgrades = require(Shared.Config.Upgrades)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local StateService = {}

local services: any
local pending: { [Player]: boolean } = {}

local function build(player: Player): Types.ClientState?
	local profile = services.PlayerDataService.get(player)
	if not profile then
		return nil
	end
	local record = services.VehicleService.get(player)
	local trip = services.PassengerService.getTrip(player)

	local nextCheckpoint: Vector3? = nil
	local destination: string? = nil
	if trip.routeId and trip.passengers > 0 then
		local route = World.Routes[trip.routeId]
		destination = World.Stages[route.to].displayName
		nextCheckpoint = route.checkpoints[trip.nextCheckpoint] or World.Stages[route.to].position
	end

	local atStage: string? = nil
	if record then
		atStage = services.WorldService.stageAt(services.VehicleService.position(record))
	end

	return {
		bob = profile.bob,
		stickers = profile.stickers,
		level = profile.level,
		xp = profile.xp,
		xpToNext = Economy.xpForLevel(profile.level),
		vibe = Upgrades.computeVibe(profile.upgrades),
		upgrades = table.clone(profile.upgrades),
		ownedTiers = table.clone(profile.ownedTiers),
		equippedTier = profile.equippedTier,
		hasVehicle = record ~= nil,
		isDriving = services.VehicleService.isDriving(player),
		passengersAboard = trip.passengers,
		seats = if record then record.tier.seats else 0,
		routeId = trip.routeId,
		destination = destination,
		nextCheckpoint = nextCheckpoint,
		atStage = atStage,
		rushHour = services.WorldService.isRushHour(),
	}
end

function StateService.push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if not player.Parent then
			return
		end
		local state = build(player)
		if state then
			Net.event("State"):FireClient(player, state)
		end
	end)
end

function StateService.init(registry: any)
	services = registry
end

function StateService.start()
	services.PlayerDataService.onLoaded(function(player: Player)
		StateService.push(player)
	end)
	-- A slow heartbeat keeps "at stage" and rush-hour flags fresh without per-frame traffic.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				StateService.push(player)
			end
		end
	end)
end

return StateService
