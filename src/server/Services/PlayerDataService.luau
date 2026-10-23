--!strict
-- Loads, caches and saves player profiles.
--
-- Uses DataStoreService directly with a simple session lock so two servers never write the
-- same profile at once. When DataStores are unavailable (Studio without "Enable Studio Access
-- to API Services"), it falls back to in-memory profiles and warns once.
--
-- For production you may swap this for ProfileStore (https://github.com/MadStudioRoblox/ProfileStore);
-- the public API below (get / onLoaded / update) is all the other services use.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)

type Profile = Types.Profile

local STORE_NAME = "MatatuEmpire_Profiles_v1"
local PROFILE_VERSION = 1
local AUTOSAVE_SECONDS = 60
local LOCK_TIMEOUT_SECONDS = 15 * 60 -- a lock older than this is treated as stale (crashed server)
local MAX_RETRIES = 4

local PlayerDataService = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local releasing: { [Player]: boolean } = {}

local store: DataStore? = nil
local storeAvailable = true

local function defaultProfile(): Profile
	return {
		version = PROFILE_VERSION,
		bob = Economy.StartingBob,
		stickers = 0,
		level = 1,
		xp = 0,
		ownedTiers = { 1 },
		equippedTier = 1,
		upgrades = {},
		stats = { trips = 0, passengersCarried = 0, lifetimeBob = 0 },
	}
end

-- Fill any fields missing from older saves so new code never sees nil.
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if type(data) ~= "table" then
		return base
	end
	for key, value in base :: any do
		if data[key] == nil then
			data[key] = value
		end
	end
	if type(data.stats) ~= "table" then
		data.stats = base.stats
	end
	for key, value in base.stats :: any do
		if data.stats[key] == nil then
			data.stats[key] = value
		end
	end
	data.version = PROFILE_VERSION
	return data :: Profile
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local lastError: any
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(2 ^ attempt * 0.5)
	end
	warn(`[PlayerData] {label} failed after {MAX_RETRIES} attempts: {lastError}`)
	return false, nil
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function loadProfile(player: Player): Profile?
	if not storeAvailable or not store then
		return defaultProfile()
	end
	local activeStore = store :: DataStore
	local sessionId = game.JobId ~= "" and game.JobId or "studio"

	local ok, result = withRetries("load", function()
		local loaded: any = nil
		activeStore:UpdateAsync(keyFor(player), function(old: any)
			old = old or {}
			local lock = old.lock
			local now = os.time()
			if lock and lock.session ~= sessionId and now - (lock.at or 0) < LOCK_TIMEOUT_SECONDS then
				-- Another server still owns this profile. Abort the write.
				loaded = false
				return nil
			end
			old.lock = { session = sessionId, at = now }
			old.data = reconcile(old.data)
			loaded = old.data
			return old
		end)
		return loaded
	end)

	if not ok then
		return nil
	end
	if result == false then
		player:Kick("Your data is still saving on another server. Please rejoin in a minute.")
		return nil
	end
	return result :: Profile
end

local function saveProfile(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not storeAvailable or not store then
		return
	end
	local activeStore = store :: DataStore
	local sessionId = game.JobId ~= "" and game.JobId or "studio"
	withRetries("save", function()
		activeStore:UpdateAsync(keyFor(player), function(old: any)
			old = old or {}
			if old.lock and old.lock.session ~= sessionId then
				-- We lost the lock (should not happen); never overwrite another server's data.
				return nil
			end
			old.data = profile
			old.lock = if release then nil else { session = sessionId, at = os.time() }
			return old
		end)
		return true
	end)
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

-- Runs `callback` for every profile already loaded and every profile loaded later.
function PlayerDataService.onLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Apply a mutation and return whether a profile existed.
function PlayerDataService.update(player: Player, mutate: (Profile) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	mutate(profile)
	return true
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not profile then
		if player.Parent then
			player:Kick("Could not load your data. Please rejoin.")
		end
		return
	end
	if not player.Parent then
		-- Left while loading: release the lock we just took.
		profiles[player] = profile
		saveProfile(player, true)
		profiles[player] = nil
		return
	end
	profiles[player] = profile
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function onPlayerRemoving(player: Player)
	if releasing[player] then
		return
	end
	releasing[player] = true
	saveProfile(player, true)
	profiles[player] = nil
	releasing[player] = nil
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeAvailable = false
	end
	if RunService:IsStudio() and storeAvailable then
		-- A probe read tells us whether Studio API access is enabled.
		local probeOk = pcall(function()
			(store :: DataStore):GetAsync("__probe")
		end)
		storeAvailable = probeOk
	end
	if not storeAvailable then
		warn("[PlayerData] DataStores unavailable; using in-memory profiles (progress will not save).")
	end
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				onPlayerRemoving(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
