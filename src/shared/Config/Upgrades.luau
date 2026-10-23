--!strict
-- The five Vibe slots. Each level adds Vibe points; a fully upgraded matatu reaches 100 Vibe.

export type Level = {
	cost: number,
	vibe: number, -- cumulative vibe at this level
	label: string,
}

export type Slot = {
	id: string,
	displayName: string,
	levels: { Level },
}

local Upgrades = {}

Upgrades.Slots = {
	{
		id = "Paint",
		displayName = "Paint & graffiti",
		levels = {
			{ cost = 400, vibe = 6, label = "Two-tone stripes" },
			{ cost = 2500, vibe = 13, label = "Street graffiti" },
			{ cost = 12000, vibe = 20, label = "Full art wrap" },
		},
	},
	{
		id = "Lights",
		displayName = "Lights",
		levels = {
			{ cost = 600, vibe = 6, label = "Underglow" },
			{ cost = 3000, vibe = 13, label = "Roof neon" },
			{ cost = 14000, vibe = 20, label = "Beat-synced LEDs" },
		},
	},
	{
		id = "Sound",
		displayName = "Sound system",
		levels = {
			{ cost = 800, vibe = 6, label = "Door speakers" },
			{ cost = 3500, vibe = 13, label = "Twin subwoofers" },
			{ cost = 16000, vibe = 20, label = "Stage-shaking bass" },
		},
	},
	{
		id = "Interior",
		displayName = "Interior",
		levels = {
			{ cost = 500, vibe = 6, label = "Seat covers" },
			{ cost = 2800, vibe = 13, label = "Screens" },
			{ cost = 13000, vibe = 20, label = "Lounge interior" },
		},
	},
	{
		id = "BodyKit",
		displayName = "Body kit",
		levels = {
			{ cost = 450, vibe = 6, label = "Custom horn" },
			{ cost = 2600, vibe = 13, label = "Chrome rims" },
			{ cost = 12500, vibe = 20, label = "Spoiler & side skirts" },
		},
	},
} :: { Slot }

function Upgrades.getSlot(id: string): Slot?
	for _, slot in Upgrades.Slots do
		if slot.id == id then
			return slot
		end
	end
	return nil
end

-- Vibe (0-100) from a map of slot id -> level owned.
function Upgrades.computeVibe(levels: { [string]: number }): number
	local total = 0
	for _, slot in Upgrades.Slots do
		local owned = levels[slot.id] or 0
		if owned > 0 then
			local level = slot.levels[math.min(owned, #slot.levels)]
			total += level.vibe
		end
	end
	return math.clamp(total, 0, 100)
end

return Upgrades
