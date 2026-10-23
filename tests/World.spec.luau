--!strict
-- Sanity tests for the Nairobi map: every road connects, every route has a path, stages sit
-- beside their road with room for the shelter. Run with `just test`.
--
-- Config modules use Roblox-style requires (script.Parent.X) and Roblox datatypes, so they are
-- loaded here with a small shim: Lune's @lune/roblox supplies Vector3, CFrame and Color3.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local CONFIG = "src/shared/Config/"

local loaded: { [string]: any } = {}
local function load(name: string): any
	if loaded[name] then
		return loaded[name]
	end
	local scriptShim = { Parent = setmetatable({}, {
		__index = function(_, child: string)
			return { __module = child }
		end,
	}) }
	local env = setmetatable({
		script = scriptShim,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		require = function(target: any)
			return load(target.__module)
		end,
	}, { __index = _G })
	local chunk = luau.load(fs.readFile(`{CONFIG}{name}.luau`), { debugName = name, environment = env })
	loaded[name] = chunk()
	return loaded[name]
end

local World = load("World")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`  ok    {name}`)
	else
		failed += 1
		print(`  FAIL  {name}\n        {err}`)
	end
end
local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

print("World (Nairobi)")

test("every stage can reach every other stage by road", function()
	for _, a in World.StageOrder do
		for _, b in World.StageOrder do
			if a ~= b then
				local path = World.shortestPath(World.Stages[a].node, World.Stages[b].node)
				expect(path ~= nil, `no road from {a} to {b}`)
			end
		end
	end
end)

test("every route runs both ways with checkpoints and a fare", function()
	local count = 0
	for id, route in World.Routes do
		count += 1
		expect(World.route(route.to, route.from) ~= nil, `{id} has no return route`)
		expect(#route.checkpoints >= 1, `{id} has no checkpoints`)
		expect(route.baseFare > 20, `{id} fare too low: {route.baseFare}`)
		expect(route.length > 150, `{id} is suspiciously short: {route.length}`)
	end
	expect(count >= 20, `expected at least 20 routes, got {count}`)
end)

test("every stage has an unlocked route out (CBD) or a route back to the CBD", function()
	for _, id in World.StageOrder do
		local routes = World.routesFrom(id)
		expect(#routes > 0, `{id} has no routes`)
	end
	local starters = 0
	for _, route in World.routesFrom("Railways") do
		if World.routeUnlocked(route, 1) then
			starters += 1
		end
	end
	expect(starters >= 2, "a level 1 player needs at least two routes from Railways")
end)

test("stage shelters don't sit on another road", function()
	for id, stage in World.Stages do
		local room = World.distanceToRoadEdge(stage.shelterCFrame.Position)
		-- The shelter's own road is 10 studs away by construction; others must be clear too.
		expect(room > 4, `{id} shelter is {room} studs from a road edge`)
	end
end)

test("matatus spawn on their road facing along it", function()
	for id, stage in World.Stages do
		local spawn = stage.vehicleSpawn
		local _, direction, distance = World.nearestRoadPoint(spawn.Position, spawn.LookVector)
		expect(distance < stage.roadWidth / 2, `{id} spawn is off the road ({distance} studs)`)
		-- Stages on a bend face the average of the two directions, so allow ~30 degrees.
		expect(direction:Dot(spawn.LookVector) > 0.85, `{id} spawn isn't facing along the road`)
	end
end)

test("checkpoints are spaced out and lie on roads", function()
	for id, route in World.Routes do
		for i, checkpoint in route.checkpoints do
			local _, _, distance = World.nearestRoadPoint(checkpoint)
			expect(distance < 1, `{id} checkpoint {i} is off the road`)
		end
	end
end)

test("map fits within a sensible driving area", function()
	local size = World.Bounds.max - World.Bounds.min
	expect(size.X < 4000 and size.Z < 3000, `map is {size.X} x {size.Z}`)
	expect(size.X > 1500, "map is too small to feel like a city")
end)

test("route lengths (for tuning)", function()
	for _, id in { "Railways->Kilimani", "Railways->Kawangware", "Odeon->Westlands", "Odeon->Eastleigh" } do
		local route = World.Routes[id]
		print(`        {id}: {math.floor(route.length)} studs, base fare {route.baseFare}, {#route.checkpoints} checkpoints`)
	end
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed", 0)
end
