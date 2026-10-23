--!strict
-- Tuning numbers for money, XP, rush hours and touting.

local Economy = {}

Economy.StartingBob = 500

-- One in-game day lasts this many real seconds.
Economy.DayLengthSeconds = 12 * 60

-- Rush hours (in-game clock) double passenger spawns and add a fare bonus.
Economy.RushHours = {
	{ from = 7, to = 9 },
	{ from = 17, to = 19 },
}
Economy.RushFareBonus = 1.25

-- Passengers waiting at a stage.
Economy.MaxCrowdPerStage = 24
Economy.CrowdSpawnInterval = 3 -- seconds between new passengers (halved in rush hour)

-- Touting minigame.
Economy.ToutBeats = 5 -- prompts per round
Economy.ToutBeatGap = 0.9 -- seconds between prompts
Economy.ToutLeadIn = 1.2 -- seconds before the first prompt
Economy.ToutPerfectWindow = 0.12 -- seconds either side of a beat
Economy.ToutGoodWindow = 0.28
Economy.ToutCooldown = 4

-- XP: one XP per this many Bob earned.
Economy.BobPerXp = 10

-- XP needed to reach the next level from `level`.
function Economy.xpForLevel(level: number): number
	return math.floor(100 * level ^ 1.5)
end

function Economy.isRushHour(clockTime: number): boolean
	for _, window in Economy.RushHours do
		if clockTime >= window.from and clockTime < window.to then
			return true
		end
	end
	return false
end

-- Fare per passenger = base x district x (1 + vibe/100) x rush bonus.
function Economy.fare(baseFare: number, districtMultiplier: number, vibe: number, rush: boolean): number
	local fare = baseFare * districtMultiplier * (1 + vibe / 100)
	if rush then
		fare *= Economy.RushFareBonus
	end
	return math.floor(fare + 0.5)
end

return Economy
