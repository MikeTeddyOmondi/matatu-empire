--!strict
-- Holds the latest server snapshot and tells listeners when it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local State = {}

local current: Types.ClientState? = nil
local listeners: { (Types.ClientState) -> () } = {}

function State.get(): Types.ClientState?
	return current
end

function State.subscribe(listener: (Types.ClientState) -> ())
	table.insert(listeners, listener)
	if current then
		task.spawn(listener, current)
	end
end

function State.start()
	Net.event("State").OnClientEvent:Connect(function(state: Types.ClientState)
		current = state
		for _, listener in listeners do
			task.spawn(listener, state)
		end
	end)
end

return State
