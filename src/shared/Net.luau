--!strict
-- Central list of remotes. The server creates them; clients wait for them.
-- Keep names here so a typo is a compile-time lookup, not a silent nil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	"State", -- server -> client: ClientState snapshot
	"Notify", -- server -> client: (text: string, kind: string)
	"ToutResult", -- server -> client: (boarded: number, hits: number)
	"SubmitTout", -- client -> server: (roundId: number, pressTimes: {number})
	"Horn", -- client -> server: ()
	"EnterVehicle", -- client -> server: () get back into your own matatu
}

local FUNCTIONS = {
	"SpawnVehicle", -- () -> (ok, message)
	"StartTout", -- () -> ToutRound?
	"BuyUpgrade", -- (slotId) -> (ok, message)
	"BuyVehicle", -- (tier) -> (ok, message)
	"EquipVehicle", -- (tier) -> (ok, message)
}

local Net = {}

local folder: Folder? = nil

local function getFolder(): Folder
	local cached = folder
	if cached then
		return cached
	end
	local resolved: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			resolved = existing
		else
			resolved = Instance.new("Folder")
			resolved.Name = FOLDER_NAME
			resolved.Parent = ReplicatedStorage
		end
	else
		resolved = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	folder = resolved
	return resolved
end

-- Server only: create every remote. Call once before anything else uses Net.
function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	local root = getFolder()
	for _, name in EVENTS do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
	for _, name in FUNCTIONS do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = root
		end
	end
end

function Net.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `Unknown RemoteEvent "{name}"`)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), `Unknown RemoteFunction "{name}"`)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

-- Simple per-player token bucket so a client can't spam a remote.
export type Limiter = { allow: (self: Limiter, player: Player) -> boolean }

function Net.rateLimiter(perSecond: number, burst: number): Limiter
	local buckets: { [Player]: { tokens: number, at: number } } = {}
	local limiter = {}
	function limiter.allow(_self, player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = burst, at = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.at) * perSecond)
		bucket.at = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
	return (limiter :: any) :: Limiter
end

return Net
