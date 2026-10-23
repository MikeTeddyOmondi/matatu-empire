--!strict

-- Persisted per-player data. Bump `version` and migrate in PlayerDataService when this changes.
export type Profile = {
	version: number,
	bob: number,
	stickers: number,
	level: number,
	xp: number,
	ownedTiers: { number },
	equippedTier: number,
	upgrades: { [string]: number }, -- slot id -> level owned (0-3), shared across the fleet in the MVP
	stats: {
		trips: number,
		passengersCarried: number,
		lifetimeBob: number,
	},
}

-- Snapshot sent to the owning client so the HUD can render.
export type ClientState = {
	bob: number,
	stickers: number,
	level: number,
	xp: number,
	xpToNext: number,
	vibe: number,
	upgrades: { [string]: number },
	ownedTiers: { number },
	equippedTier: number,
	hasVehicle: boolean,
	isDriving: boolean,
	passengersAboard: number,
	seats: number,
	routeId: string?,
	destination: string?,
	nextCheckpoint: Vector3?, -- where to drive next; nil when no trip is running
	atStage: string?,
	rushHour: boolean,
}

export type ToutRound = {
	roundId: number,
	beats: { number }, -- server times (workspace:GetServerTimeNow()) of each prompt
	goodWindow: number,
	perfectWindow: number,
}

-- A ModuleScript must return exactly one value.
return {}
