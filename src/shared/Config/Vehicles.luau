--!strict
-- Matatu tiers available in the MVP (tiers 4 and 5 come in a later update).

export type VehicleTier = {
	tier: number,
	displayName: string,
	seats: number,
	cost: number, -- Bob
	unlockLevel: number,
	length: number, -- studs
	width: number,
	height: number,
	maxSpeed: number, -- wheel angular speed, rad/s
	torque: number,
	bodyColor: Color3,
}

local Vehicles: { VehicleTier } = {
	{
		tier = 1,
		displayName = "Old 14-seater",
		seats = 14,
		cost = 0,
		unlockLevel = 1,
		length = 18,
		width = 8,
		height = 7,
		maxSpeed = 32,
		torque = 9000,
		bodyColor = Color3.fromRGB(235, 235, 225),
	},
	{
		tier = 2,
		displayName = "Upgraded 14-seater",
		seats = 14,
		cost = 5000,
		unlockLevel = 3,
		length = 18,
		width = 8,
		height = 7,
		maxSpeed = 40,
		torque = 12000,
		bodyColor = Color3.fromRGB(245, 245, 245),
	},
	{
		tier = 3,
		displayName = "25-seater minibus",
		seats = 25,
		cost = 40000,
		unlockLevel = 10,
		length = 24,
		width = 9,
		height = 8,
		maxSpeed = 42,
		torque = 18000,
		bodyColor = Color3.fromRGB(250, 250, 250),
	},
}

return Vehicles
