--!strict
-- Every change to Bob, Stickers and XP goes through here. Clients never send amounts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local EconomyService = {}

local services: any

local function setLeaderstat(player: Player, name: string, value: number)
	local stats = player:FindFirstChild("leaderstats")
	local stat = stats and stats:FindFirstChild(name)
	if stat and stat:IsA("IntValue") then
		stat.Value = value
	end
end

local function createLeaderstats(player: Player, bob: number, level: number)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local bobValue = Instance.new("IntValue")
	bobValue.Name = "Bob"
	bobValue.Value = bob
	bobValue.Parent = folder
	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = level
	levelValue.Parent = folder
	folder.Parent = player
end

function EconomyService.getBob(player: Player): number
	local profile = services.PlayerDataService.get(player)
	return if profile then profile.bob else 0
end

-- Adds Bob earned from gameplay. Also grants XP and handles level-ups.
function EconomyService.earn(player: Player, amount: number, reason: string)
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local leveledTo: number? = nil
	local ok = services.PlayerDataService.update(player, function(profile: Types.Profile)
		profile.bob += amount
		profile.stats.lifetimeBob += amount
		profile.xp += math.max(1, math.floor(amount / Economy.BobPerXp))
		while profile.xp >= Economy.xpForLevel(profile.level) do
			profile.xp -= Economy.xpForLevel(profile.level)
			profile.level += 1
			leveledTo = profile.level
		end
	end)
	if not ok then
		return
	end
	local profile = services.PlayerDataService.get(player)
	setLeaderstat(player, "Bob", profile.bob)
	setLeaderstat(player, "Level", profile.level)
	Net.event("Notify"):FireClient(player, `+{amount} Bob · {reason}`, "money")
	if leveledTo then
		Net.event("Notify"):FireClient(player, `Level up! You are now level {leveledTo}`, "level")
	end
	services.StateService.push(player)
end

-- Spends Bob if the player has enough. Returns whether the spend happened.
function EconomyService.spend(player: Player, amount: number): boolean
	amount = math.floor(amount)
	if amount < 0 then
		return false
	end
	local spent = false
	services.PlayerDataService.update(player, function(profile: Types.Profile)
		if profile.bob >= amount then
			profile.bob -= amount
			spent = true
		end
	end)
	if spent then
		setLeaderstat(player, "Bob", EconomyService.getBob(player))
		services.StateService.push(player)
	end
	return spent
end

function EconomyService.init(registry: any)
	services = registry
end

function EconomyService.start()
	services.PlayerDataService.onLoaded(function(player: Player, profile)
		createLeaderstats(player, profile.bob, profile.level)
	end)
end

return EconomyService
