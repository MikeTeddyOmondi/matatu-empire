--!strict
-- Server entry point. Every service gets init(registry) first (no cross-calls yet), then
-- start() once all of them exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

Net.setup()

local ServicesFolder = script:WaitForChild("Services")

local ORDER = {
	"PlayerDataService",
	"WorldService",
	"StateService",
	"EconomyService",
	"VehicleService",
	"PassengerService",
	"ShopService",
}

local registry: { [string]: any } = {}
for _, name in ORDER do
	registry[name] = require(ServicesFolder:WaitForChild(name) :: ModuleScript) :: any
end

for _, name in ORDER do
	local service = registry[name]
	if service.init then
		service.init(registry)
	end
end

for _, name in ORDER do
	local service = registry[name]
	if service.start then
		service.start()
	end
end

print("[Matatu Empire] server ready")
