--!strict
-- Geography of the game's Nairobi, in real latitude/longitude (approximate, hand-placed from
-- memory of the city, then simplified for gameplay). Config/World.luau projects this onto the
-- map and builds the road graph and routes; WorldService builds the city from it.
--
-- To add a road: add any new junctions to `Nodes`, then a `Roads` entry listing node ids in
-- driving order. Roads that share a node are connected there. To add a stage: add a node on a
-- road, then a `Stages` entry pointing at it, and routes in `Routes`.

export type Node = { lat: number, lon: number, roundabout: boolean? }

export type RoadKind = "highway" | "main" | "street"

export type Road = {
	name: string,
	kind: RoadKind,
	nodes: { string },
	trees: boolean?, -- tree-lined
}

export type Style = "tower" | "glass" | "midrise" | "leafy" | "commercial" | "lowrise" | "shacks"

export type District = {
	id: string,
	displayName: string,
	lat: number,
	lon: number,
	style: Style,
	color: Color3, -- stage and sign colour
}

export type Stage = {
	id: string,
	displayName: string,
	node: string,
	district: string,
	districtMultiplier: number,
	unlockLevel: number,
}

export type Landmark = {
	id: string,
	kind: "kicc" | "park" | "stadium" | "hospital" | "mall" | "railway",
	displayName: string,
	lat: number,
	lon: number,
	size: Vector3?, -- studs; for malls and the hospital
	points: { { number } }?, -- lat/lon polyline (railway)
}

local Nairobi = {}

-- Map origin (Kencom, Moi Avenue) and scale. Real Nairobi is far too big to drive across in
-- Roblox studs, so 1 km becomes 260 studs: CBD to Kawangware is about 40 s at top speed.
Nairobi.Origin = { lat = -1.2856, lon = 36.8248 }
Nairobi.StudsPerKm = 260

Nairobi.Nodes = {
	-- Uhuru Highway and its roundabouts
	museumHill = { lat = -1.2725, lon = 36.8110, roundabout = true },
	universityWayRb = { lat = -1.2795, lon = 36.8160, roundabout = true },
	kenyattaRb = { lat = -1.2885, lon = 36.8168, roundabout = true },
	haileSelassieRb = { lat = -1.2932, lon = 36.8197, roundabout = true },
	nyayoRb = { lat = -1.3035, lon = 36.8245, roundabout = true },

	-- CBD streets
	globeRb = { lat = -1.2778, lon = 36.8262, roundabout = true },
	moiNorth = { lat = -1.2822, lon = 36.8244 },
	kencom = { lat = -1.2856, lon = 36.8248 },
	railways = { lat = -1.2903, lon = 36.8268 },
	kenyattaMid = { lat = -1.2870, lon = 36.8205 },
	railwaysStage = { lat = -1.2918, lon = 36.8236 },
	tomMboyaSouth = { lat = -1.2885, lon = 36.8292 },
	odeon = { lat = -1.2838, lon = 36.8282 },
	odeonStage = { lat = -1.2828, lon = 36.8302 },
	racecourse = { lat = -1.2815, lon = 36.8332 },

	-- Upper Hill and Valley Road
	valleyRd = { lat = -1.2915, lon = 36.8120 },
	upperHillStage = { lat = -1.2950, lon = 36.8122 },
	upperHillJn = { lat = -1.2985, lon = 36.8125 },
	hurlinghamRb = { lat = -1.2955, lon = 36.7990, roundabout = true },

	-- Ngong Road
	knh = { lat = -1.3002, lon = 36.8062 },
	mbagathiJn = { lat = -1.3008, lon = 36.8015 },
	prestige = { lat = -1.3010, lon = 36.7860 },
	adams = { lat = -1.3008, lon = 36.7800 },
	dagorettiCorner = { lat = -1.2985, lon = 36.7625, roundabout = true },
	ngongWest = { lat = -1.2998, lon = 36.7525 },

	-- Kilimani and Lavington
	yayaStage = { lat = -1.2930, lon = 36.7900 },
	yaya = { lat = -1.2925, lon = 36.7870 },
	lavingtonJn = { lat = -1.2898, lon = 36.7745 },
	valleyArcade = { lat = -1.2862, lon = 36.7688 },
	jamesGichuruMid = { lat = -1.2755, lon = 36.7760 },

	-- Kibera, Mbagathi and Lang'ata
	kiberaDrive = { lat = -1.3070, lon = 36.7820 },
	kiberaStage = { lat = -1.3115, lon = 36.7830 },
	olympic = { lat = -1.3150, lon = 36.7800 },
	mbagathiMid = { lat = -1.3085, lon = 36.8005 },
	mbagathiSouth = { lat = -1.3145, lon = 36.7995 },
	langataMid = { lat = -1.3105, lon = 36.8120 },

	-- Kawangware
	naivashaMid = { lat = -1.2925, lon = 36.7565 },
	kawangwareStage = { lat = -1.2870, lon = 36.7520 },
	kawangware = { lat = -1.2842, lon = 36.7500 },
	gitangaMid = { lat = -1.2858, lon = 36.7600 },

	-- Westlands and Parklands
	westlandsRb = { lat = -1.2662, lon = 36.8040, roundabout = true },
	westlandsStage = { lat = -1.2648, lon = 36.7995 },
	waiyakiJamesGichuru = { lat = -1.2620, lon = 36.7885 },
	waiyakiWest = { lat = -1.2592, lon = 36.7765 },
	parklandsRd = { lat = -1.2640, lon = 36.8125 },
	limuruMid = { lat = -1.2700, lon = 36.8252 },
	parklandsJn = { lat = -1.2645, lon = 36.8234 },
	parklandsStage = { lat = -1.2603, lon = 36.8212 },
	limuruNorth = { lat = -1.2565, lon = 36.8195 },

	-- Eastleigh
	jujaMid = { lat = -1.2772, lon = 36.8392 },
	eastleighStage = { lat = -1.2738, lon = 36.8442 },
	eastleighEast = { lat = -1.2712, lon = 36.8490 },
} :: { [string]: Node }

Nairobi.Roads = {
	{
		name = "Uhuru Highway",
		kind = "highway",
		nodes = { "museumHill", "universityWayRb", "kenyattaRb", "haileSelassieRb", "nyayoRb" },
		trees = true,
	},
	{ name = "Kenyatta Avenue", kind = "street", nodes = { "kenyattaRb", "kenyattaMid", "kencom" } },
	{ name = "Moi Avenue", kind = "street", nodes = { "railways", "kencom", "moiNorth", "globeRb" } },
	{ name = "Haile Selassie Avenue", kind = "street", nodes = { "haileSelassieRb", "railwaysStage", "railways", "tomMboyaSouth" } },
	{ name = "Tom Mboya Street", kind = "street", nodes = { "tomMboyaSouth", "odeon", "odeonStage", "racecourse" } },
	{ name = "Accra Road", kind = "street", nodes = { "moiNorth", "odeon" } },
	{ name = "University Way", kind = "street", nodes = { "universityWayRb", "globeRb" } },
	{ name = "Valley Road", kind = "main", nodes = { "kenyattaRb", "valleyRd", "hurlinghamRb" }, trees = true },
	{ name = "Upper Hill Road", kind = "street", nodes = { "valleyRd", "upperHillStage", "upperHillJn" } },
	{
		name = "Ngong Road",
		kind = "main",
		nodes = { "haileSelassieRb", "upperHillJn", "knh", "mbagathiJn", "prestige", "adams", "dagorettiCorner", "ngongWest" },
		trees = true,
	},
	{
		name = "Argwings Kodhek Road",
		kind = "main",
		nodes = { "hurlinghamRb", "yayaStage", "yaya", "lavingtonJn" },
		trees = true,
	},
	{ name = "Kibera Drive", kind = "street", nodes = { "adams", "kiberaDrive", "kiberaStage", "olympic" } },
	{ name = "Mbagathi Way", kind = "main", nodes = { "mbagathiJn", "mbagathiMid", "mbagathiSouth" } },
	{ name = "Lang'ata Road", kind = "main", nodes = { "nyayoRb", "langataMid", "mbagathiSouth", "olympic" } },
	{ name = "Naivasha Road", kind = "street", nodes = { "dagorettiCorner", "naivashaMid", "kawangwareStage", "kawangware" } },
	{
		name = "Gitanga Road",
		kind = "street",
		nodes = { "kawangware", "gitangaMid", "valleyArcade", "lavingtonJn" },
		trees = true,
	},
	{
		name = "James Gichuru Road",
		kind = "main",
		nodes = { "valleyArcade", "jamesGichuruMid", "waiyakiJamesGichuru" },
		trees = true,
	},
	{
		name = "Waiyaki Way",
		kind = "highway",
		nodes = { "museumHill", "westlandsRb", "westlandsStage", "waiyakiJamesGichuru", "waiyakiWest" },
	},
	{ name = "Parklands Road", kind = "street", nodes = { "westlandsRb", "parklandsRd", "parklandsJn" }, trees = true },
	{ name = "Limuru Road", kind = "main", nodes = { "globeRb", "limuruMid", "parklandsJn", "parklandsStage", "limuruNorth" } },
	{ name = "Juja Road", kind = "main", nodes = { "racecourse", "jujaMid", "eastleighStage", "eastleighEast" } },
} :: { Road }

Nairobi.Districts = {
	{ id = "CBD", displayName = "CBD", lat = -1.2860, lon = 36.8245, style = "tower", color = Color3.fromRGB(255, 196, 0) },
	{ id = "UpperHill", displayName = "Upper Hill", lat = -1.2965, lon = 36.8110, style = "tower", color = Color3.fromRGB(0, 170, 255) },
	{ id = "Westlands", displayName = "Westlands", lat = -1.2650, lon = 36.8020, style = "glass", color = Color3.fromRGB(0, 229, 255) },
	{ id = "Parklands", displayName = "Parklands", lat = -1.2630, lon = 36.8200, style = "leafy", color = Color3.fromRGB(118, 255, 3) },
	{ id = "Eastleigh", displayName = "Eastleigh", lat = -1.2750, lon = 36.8430, style = "commercial", color = Color3.fromRGB(255, 120, 0) },
	{ id = "Kilimani", displayName = "Kilimani", lat = -1.2915, lon = 36.7880, style = "midrise", color = Color3.fromRGB(213, 0, 249) },
	{ id = "Lavington", displayName = "Lavington", lat = -1.2810, lon = 36.7720, style = "leafy", color = Color3.fromRGB(100, 220, 120) },
	{ id = "NgongRoad", displayName = "Ngong Road", lat = -1.3010, lon = 36.7900, style = "commercial", color = Color3.fromRGB(255, 64, 129) },
	{ id = "Dagoretti", displayName = "Dagoretti Corner", lat = -1.2990, lon = 36.7620, style = "commercial", color = Color3.fromRGB(255, 64, 129) },
	{ id = "Kibera", displayName = "Kibera", lat = -1.3115, lon = 36.7880, style = "shacks", color = Color3.fromRGB(255, 82, 82) },
	{ id = "Kawangware", displayName = "Kawangware", lat = -1.2855, lon = 36.7525, style = "lowrise", color = Color3.fromRGB(255, 214, 0) },
} :: { District }

Nairobi.Stages = {
	{ id = "Railways", displayName = "Railways (CBD)", node = "railwaysStage", district = "CBD", districtMultiplier = 1.0, unlockLevel = 1 },
	{ id = "Odeon", displayName = "Odeon (CBD)", node = "odeonStage", district = "CBD", districtMultiplier = 1.0, unlockLevel = 1 },
	{ id = "UpperHill", displayName = "Upper Hill", node = "upperHillStage", district = "UpperHill", districtMultiplier = 1.1, unlockLevel = 1 },
	{ id = "Kilimani", displayName = "Yaya (Kilimani)", node = "yayaStage", district = "Kilimani", districtMultiplier = 1.2, unlockLevel = 1 },
	{ id = "NgongRoad", displayName = "Prestige (Ngong Rd)", node = "prestige", district = "NgongRoad", districtMultiplier = 1.2, unlockLevel = 2 },
	{ id = "Westlands", displayName = "Westlands", node = "westlandsStage", district = "Westlands", districtMultiplier = 1.4, unlockLevel = 3 },
	{ id = "Kibera", displayName = "Kibera", node = "kiberaStage", district = "Kibera", districtMultiplier = 1.1, unlockLevel = 4 },
	{ id = "Parklands", displayName = "Parklands", node = "parklandsStage", district = "Parklands", districtMultiplier = 1.3, unlockLevel = 5 },
	{ id = "Eastleigh", displayName = "Eastleigh", node = "eastleighStage", district = "Eastleigh", districtMultiplier = 1.3, unlockLevel = 6 },
	{ id = "Kawangware", displayName = "Kawangware", node = "kawangwareStage", district = "Kawangware", districtMultiplier = 1.3, unlockLevel = 8 },
} :: { Stage }

-- Routes run both ways. CBD routes leave from the terminus real matatus on that side use.
Nairobi.Routes = {
	{ "Railways", "UpperHill" },
	{ "Railways", "Kilimani" },
	{ "Railways", "NgongRoad" },
	{ "Railways", "Kibera" },
	{ "Railways", "Kawangware" },
	{ "Odeon", "Westlands" },
	{ "Odeon", "Parklands" },
	{ "Odeon", "Eastleigh" },
	{ "Westlands", "Kilimani" },
	{ "Westlands", "Kawangware" },
	{ "NgongRoad", "Kibera" },
	{ "Kilimani", "NgongRoad" },
} :: { { string } }

Nairobi.Landmarks = {
	{ id = "kicc", kind = "kicc", displayName = "KICC", lat = -1.2893, lon = 36.8226 },
	{ id = "uhuruPark", kind = "park", displayName = "Uhuru Park", lat = -1.2842, lon = 36.8122 },
	{ id = "nyayo", kind = "stadium", displayName = "Nyayo Stadium", lat = -1.3062, lon = 36.8292 },
	{ id = "knh", kind = "hospital", displayName = "Kenyatta National Hospital", lat = -1.3028, lon = 36.8075, size = Vector3.new(70, 40, 40) },
	{ id = "prestige", kind = "mall", displayName = "Prestige Plaza", lat = -1.3030, lon = 36.7862, size = Vector3.new(50, 18, 34) },
	{ id = "junction", kind = "mall", displayName = "The Junction", lat = -1.3008, lon = 36.7628, size = Vector3.new(70, 16, 44) },
	{ id = "yaya", kind = "mall", displayName = "Yaya Centre", lat = -1.2908, lon = 36.7872, size = Vector3.new(44, 26, 34) },
	{ id = "sarit", kind = "mall", displayName = "Sarit Centre", lat = -1.2630, lon = 36.8000, size = Vector3.new(60, 22, 40) },
	{ id = "valleyArcade", kind = "mall", displayName = "Valley Arcade", lat = -1.2845, lon = 36.7690, size = Vector3.new(40, 12, 28) },
	{
		id = "railway",
		kind = "railway",
		displayName = "Railway",
		lat = -1.3160,
		lon = 36.7900,
		points = { { -1.3172, 36.7740 }, { -1.3160, 36.7860 }, { -1.3135, 36.7960 }, { -1.3100, 36.8060 }, { -1.3075, 36.8160 } },
	},
} :: { Landmark }

-- A rectangle of dense mabati houses south of Ngong Road (lat/lon bounds).
Nairobi.KiberaField = { latMin = -1.3165, latMax = -1.3045, lonMin = 36.7745, lonMax = 36.7985 }

return Nairobi
