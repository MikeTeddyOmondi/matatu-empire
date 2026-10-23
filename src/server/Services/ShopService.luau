--!strict
-- Buying Vibe upgrades and new matatu tiers with Bob. Prices come from config, never the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Vehicles = require(Shared.Config.Vehicles)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local ShopService = {}

local services: any
local limiter = Net.rateLimiter(3, 5)

local function buyUpgrade(player: Player, slotId: unknown): (boolean, string)
	if type(slotId) ~= "string" then
		return false, "Invalid upgrade"
	end
	local slot = Upgrades.getSlot(slotId)
	local profile = services.PlayerDataService.get(player)
	if not slot or not profile then
		return false, "Invalid upgrade"
	end
	local owned = profile.upgrades[slot.id] or 0
	local nextLevel = slot.levels[owned + 1]
	if not nextLevel then
		return false, `{slot.displayName} is maxed out`
	end
	if not services.EconomyService.spend(player, nextLevel.cost) then
		return false, `You need {nextLevel.cost} Bob`
	end
	services.PlayerDataService.update(player, function(p: Types.Profile)
		p.upgrades[slot.id] = owned + 1
	end)
	services.VehicleService.refreshCosmetics(player)
	services.StateService.push(player)
	return true, `Installed: {nextLevel.label}`
end

local function buyVehicle(player: Player, tierNumber: unknown): (boolean, string)
	if type(tierNumber) ~= "number" then
		return false, "Invalid vehicle"
	end
	local tier = Vehicles[tierNumber]
	local profile = services.PlayerDataService.get(player)
	if not tier or not profile then
		return false, "Invalid vehicle"
	end
	if table.find(profile.ownedTiers, tier.tier) then
		return false, "You already own this one"
	end
	if profile.level < tier.unlockLevel then
		return false, `Unlocks at level {tier.unlockLevel}`
	end
	if not services.EconomyService.spend(player, tier.cost) then
		return false, `You need {tier.cost} Bob`
	end
	services.PlayerDataService.update(player, function(p: Types.Profile)
		table.insert(p.ownedTiers, tier.tier)
		p.equippedTier = tier.tier
	end)
	services.VehicleService.spawn(player)
	return true, `New ride: {tier.displayName}!`
end

local function equipVehicle(player: Player, tierNumber: unknown): (boolean, string)
	if type(tierNumber) ~= "number" then
		return false, "Invalid vehicle"
	end
	local profile = services.PlayerDataService.get(player)
	if not profile or not table.find(profile.ownedTiers, tierNumber) then
		return false, "You don't own that matatu"
	end
	services.PlayerDataService.update(player, function(p: Types.Profile)
		p.equippedTier = tierNumber
	end)
	services.VehicleService.spawn(player)
	return true, `Switched to {Vehicles[tierNumber].displayName}`
end

local function guarded(handler: (Player, unknown) -> (boolean, string))
	return function(player: Player, arg: unknown)
		if not limiter:allow(player) then
			return false, "Slow down"
		end
		return handler(player, arg)
	end
end

function ShopService.init(registry: any)
	services = registry
end

function ShopService.start()
	Net.func("BuyUpgrade").OnServerInvoke = guarded(buyUpgrade)
	Net.func("BuyVehicle").OnServerInvoke = guarded(buyVehicle)
	Net.func("EquipVehicle").OnServerInvoke = guarded(equipVehicle)
end

return ShopService
