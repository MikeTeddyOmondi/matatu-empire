--!strict
-- Matatu tiers available in the MVP (tiers 4 and 5 come in a later update).
--
-- Handling is arcade-style (see Controllers/Drive.luau): the numbers below are what the driver
-- feels directly, not motor settings. Speeds are in studs per second (1 stud is about 28 cm, so
-- 64 studs/s is roughly 65 km/h).

export type VehicleTier = {
	tier: number,
	displayName: string,
	seats: number,
	cost: number, -- Bob
	unlockLevel: number,
	length: number, -- studs
	width: number,
	height: number,
	topSpeed: number, -- studs/s going forward
	reverseSpeed: number, -- studs/s going backward
	acceleration: number, -- studs/s^2 under full throttle
	brakeDeceleration: number, -- studs/s^2 when pressing the opposite pedal
	turnRate: number, -- max yaw in rad/s
	turnRadius: number, -- tightest turning circle radius in studs (limits yaw at low speed)
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
		topSpeed = 64,
		reverseSpeed = 24,
		acceleration = 18,
		brakeDeceleration = 60,
		turnRate = 1.7,
		turnRadius = 13,
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
		topSpeed = 80,
		reverseSpeed = 28,
		acceleration = 24,
		brakeDeceleration = 70,
		turnRate = 1.8,
		turnRadius = 13,
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
		topSpeed = 84,
		reverseSpeed = 26,
		acceleration = 20,
		brakeDeceleration = 60,
		turnRate = 1.5,
		turnRadius = 17,
		bodyColor = Color3.fromRGB(250, 250, 250),
	},
}

return Vehicles
