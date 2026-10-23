--!strict
-- Unit tests for the arcade driving model, run outside Studio with Lune:
--   just test      (or: lune run tests/DriveModel.spec.luau)
--
-- A tiny 2D physics stand-in plays the part of Roblox: the matatu's velocity follows the
-- commanded speed with at most GRIP acceleration (like the LinearVelocity's MaxForce), its heading
-- follows the commanded yaw, and walls stop motion into them.

local DriveModel = require("../src/shared/DriveModel")

local GRIP = 160 -- matches GRIP_FORCE in Controllers/Drive.luau

local TIER1: DriveModel.Params = {
	topSpeed = 64,
	reverseSpeed = 24,
	acceleration = 18,
	brakeDeceleration = 60,
	turnRate = 1.7,
	turnRadius = 13,
}

type Wall = { normal: { x: number, z: number }, offset: number } -- inside when pos . normal <= offset

type Sim = {
	state: DriveModel.State,
	params: DriveModel.Params,
	x: number,
	z: number,
	heading: number, -- radians, forward = (cos, sin); + yaw turns left (counter-clockwise)
	vx: number,
	vz: number,
	walls: { Wall },
	grounded: boolean,
	gear: DriveModel.Gear,
	commanded: number,
	yaw: number,
}

local function newSim(params: DriveModel.Params?): Sim
	return {
		state = DriveModel.new(),
		params = params or TIER1,
		x = 0,
		z = 0,
		heading = 0,
		vx = 0,
		vz = 0,
		walls = {},
		grounded = true,
		gear = "P",
		commanded = 0,
		yaw = 0,
	}
end

local function forward(sim: Sim): (number, number)
	return math.cos(sim.heading), math.sin(sim.heading)
end

local function actualForward(sim: Sim): number
	local fx, fz = forward(sim)
	return sim.vx * fx + sim.vz * fz
end

local function speedOf(sim: Sim): number
	return math.sqrt(sim.vx * sim.vx + sim.vz * sim.vz)
end

local function step(sim: Sim, throttle: number, steer: number, dt: number)
	local speed, yaw, gear =
		DriveModel.step(sim.state, sim.params, throttle, steer, actualForward(sim), sim.grounded, dt)
	sim.gear, sim.commanded, sim.yaw = gear, speed, yaw

	sim.heading += yaw * dt
	if sim.grounded then
		local fx, fz = forward(sim)
		local dx, dz = speed * fx - sim.vx, speed * fz - sim.vz
		local gap = math.sqrt(dx * dx + dz * dz)
		local maxDelta = GRIP * dt
		if gap > maxDelta then
			dx, dz = dx / gap * maxDelta, dz / gap * maxDelta
		end
		sim.vx += dx
		sim.vz += dz
	end
	sim.x += sim.vx * dt
	sim.z += sim.vz * dt

	for _, wall in sim.walls do
		local depth = sim.x * wall.normal.x + sim.z * wall.normal.z - wall.offset
		if depth > 0 then
			sim.x -= wall.normal.x * depth
			sim.z -= wall.normal.z * depth
			local into = sim.vx * wall.normal.x + sim.vz * wall.normal.z
			if into > 0 then
				sim.vx -= wall.normal.x * into
				sim.vz -= wall.normal.z * into
			end
		end
	end
end

local function run(sim: Sim, seconds: number, throttle: number, steer: number, dt: number?)
	local h = dt or 1 / 60
	for _ = 1, math.floor(seconds / h + 0.5) do
		step(sim, throttle, steer, h)
	end
end

-- Tiny test runner ------------------------------------------------------------------------------

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

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

print("DriveModel")

test("accelerates to top speed and holds it", function()
	local sim = newSim()
	run(sim, 2, 1, 0)
	expect(near(actualForward(sim), 36, 2), `expected ~36 studs/s after 2 s, got {actualForward(sim)}`)
	run(sim, 4, 1, 0)
	expect(near(actualForward(sim), 64, 0.5), `expected top speed 64, got {actualForward(sim)}`)
	expect(sim.gear == "D", `expected gear D, got {sim.gear}`)
end)

test("W + A turns smoothly without losing speed (the stalling bug)", function()
	local sim = newSim()
	run(sim, 1.5, 1, 0)
	local before = actualForward(sim)
	run(sim, 3, 1, -1)
	expect(actualForward(sim) >= before, `speed dropped while turning: {before} -> {actualForward(sim)}`)
	expect(sim.yaw > 0.5, `expected a left turn, yaw = {sim.yaw}`)
	expect(speedOf(sim) > 20, `matatu stalled in the turn: {speedOf(sim)}`)
end)

test("W + D at full speed turns right and keeps going", function()
	local sim = newSim()
	run(sim, 6, 1, 0)
	run(sim, 2, 1, 1)
	expect(sim.yaw < -1, `expected a right turn, yaw = {sim.yaw}`)
	expect(speedOf(sim) > 55, `lost too much speed: {speedOf(sim)}`)
end)

test("turning circle is never tighter than turnRadius", function()
	for _, cruise in { 5, 10, 20, 40, 64 } do
		local sim = newSim()
		sim.state.speed = cruise
		sim.vx = cruise
		run(sim, 1, cruise / 64, -1)
		local radius = math.abs(actualForward(sim) / sim.yaw)
		expect(radius >= TIER1.turnRadius - 0.5, `radius {radius} at {cruise} studs/s is tighter than allowed`)
	end
end)

test("can't spin on the spot when stopped (steer alone)", function()
	local sim = newSim()
	run(sim, 1, 0, 1)
	expect(near(sim.yaw, 0, 1e-6), `expected no yaw, got {sim.yaw}`)
	expect(sim.gear == "P", `expected park, got {sim.gear}`)
end)

test("S brakes first, then reverses", function()
	local sim = newSim()
	run(sim, 6, 1, 0)
	step(sim, -1, 0, 1 / 60)
	expect(sim.gear == "B", `expected brake, got {sim.gear}`)
	run(sim, 1.2, -1, 0)
	expect(actualForward(sim) < 0, `expected to be reversing after braking, got {actualForward(sim)}`)
	run(sim, 3, -1, 0)
	expect(near(actualForward(sim), -24, 0.5), `expected reverse top speed -24, got {actualForward(sim)}`)
	expect(sim.gear == "R", `expected gear R, got {sim.gear}`)
end)

test("reversing while steering left swings the nose right", function()
	local sim = newSim()
	run(sim, 2, -1, -1)
	expect(actualForward(sim) < -5, "expected to be reversing")
	expect(sim.yaw < 0, `expected nose to swing right (negative yaw), got {sim.yaw}`)
end)

test("W from reverse brakes, then drives forward", function()
	local sim = newSim()
	run(sim, 3, -1, 0)
	step(sim, 1, 0, 1 / 60)
	expect(sim.gear == "B", `expected brake, got {sim.gear}`)
	run(sim, 2, 1, 0)
	expect(actualForward(sim) > 5, `expected forward motion, got {actualForward(sim)}`)
end)

test("letting go coasts to a stop and parks", function()
	local sim = newSim()
	run(sim, 3, 1, 0)
	run(sim, 8, 0, 0)
	expect(speedOf(sim) < 0.01, `expected to stop, still at {speedOf(sim)}`)
	expect(sim.gear == "P", `expected park, got {sim.gear}`)
end)

test("hitting a wall: reverse responds immediately (no stored speed)", function()
	local sim = newSim()
	sim.walls = { { normal = { x = 1, z = 0 }, offset = 60 } }
	run(sim, 6, 1, 0) -- slam into the wall and keep holding W
	expect(near(sim.x, 60, 0.01), `expected to be at the wall, x = {sim.x}`)
	expect(sim.commanded < DriveModel.BLOCKED_SLACK + 1, `command kept growing against the wall: {sim.commanded}`)
	run(sim, 0.5, -1, 0)
	expect(actualForward(sim) < -2, `expected to be backing away within 0.5 s, got {actualForward(sim)}`)
	expect(sim.x < 59.5, `expected to have left the wall, x = {sim.x}`)
end)

test("nose against a wall, W + D pivots to wriggle free", function()
	local sim = newSim()
	sim.walls = { { normal = { x = 1, z = 0 }, offset = 20 } }
	run(sim, 4, 1, 0)
	local headingBefore = sim.heading
	run(sim, 1.5, 1, 1)
	expect(sim.heading < headingBefore - 0.3, `expected to pivot right, heading change {sim.heading - headingBefore}`)
	-- Once angled, W slides along the wall and gets moving again.
	run(sim, 2, 1, 1)
	expect(speedOf(sim) > 5, `still stuck: {speedOf(sim)}`)
end)

test("scraping along a wall at an angle keeps moving", function()
	local sim = newSim()
	sim.walls = { { normal = { x = 0, z = 1 }, offset = 3 } }
	sim.heading = math.rad(10) -- drifting into the wall on the left
	run(sim, 4, 1, 0)
	expect(sim.x > 40, `expected to slide along the wall, x = {sim.x}`)
end)

test("airborne: no steering, speed follows real motion, smooth landing", function()
	local sim = newSim()
	run(sim, 3, 1, 0)
	local launch = actualForward(sim)
	sim.grounded = false
	run(sim, 0.5, 1, 1)
	expect(near(sim.state.speed, launch, 0.01), "command should match real motion in the air")
	expect(near(sim.yaw, 0, 1e-6), `expected no yaw in the air, got {sim.yaw}`)
	sim.grounded = true
	step(sim, 1, 0, 1 / 60)
	expect(near(sim.commanded, launch, 1), `landing jolt: {launch} -> {sim.commanded}`)
end)

test("results don't depend on frame rate", function()
	local fast, slow = newSim(), newSim()
	run(fast, 3, 1, -1, 1 / 240)
	run(slow, 3, 1, -1, 1 / 15)
	expect(near(speedOf(fast), speedOf(slow), 1), `speed differs: {speedOf(fast)} vs {speedOf(slow)}`)
	expect(near(fast.heading, slow.heading, 0.15), `heading differs: {fast.heading} vs {slow.heading}`)
end)

test("half throttle (thumbstick) settles at half speed", function()
	local sim = newSim()
	run(sim, 6, 0.5, 0)
	expect(near(actualForward(sim), 32, 0.5), `expected 32, got {actualForward(sim)}`)
	run(sim, 3, 0.25, 0)
	expect(near(actualForward(sim), 16, 0.5), `expected to ease down to 16, got {actualForward(sim)}`)
end)

test("out-of-range input is clamped", function()
	local sim = newSim()
	run(sim, 8, 5, 0)
	expect(actualForward(sim) <= 64.01, `exceeded top speed: {actualForward(sim)}`)
end)

test("never commands more than the server's speed check allows", function()
	for _, params in { TIER1, { topSpeed = 84, reverseSpeed = 26, acceleration = 20, brakeDeceleration = 60, turnRate = 1.5, turnRadius = 17 } } do
		local sim = newSim(params)
		local worst = 0
		for i = 1, 600 do
			step(sim, if i % 97 < 60 then 1 else -1, math.sin(i / 20), 1 / 60)
			worst = math.max(worst, math.abs(sim.commanded))
		end
		expect(worst <= params.topSpeed * 1.5, `commanded {worst} > server limit`)
	end
end)

-- Drives the real route shape: east along a 40-stud road, a 90 degree corner, then north. A simple
-- bot brakes before the corner like a player would, and must stay on the road the whole way.
test("can take the 90 degree corner on the CBD-Estates road", function()
	local sim = newSim()
	local halfRoad, halfWidth = 20, 4
	local corner = { x = 420, z = 0 }
	local maxOff = 0
	local reached = false
	for _ = 1, 60 * 40 do
		local turning = sim.x > corner.x - 30
		local targetX, targetZ = if turning then corner.x else sim.x + 40, if turning then sim.z + 40 else 0
		local desired = math.atan2(targetZ - sim.z, targetX - sim.x)
		local err = (desired - sim.heading + math.pi) % (2 * math.pi) - math.pi
		local steer = math.clamp(-err * 3, -1, 1)
		local distance = corner.x - sim.x
		local throttle = if not turning and distance < 70 and actualForward(sim) > 22 then -1 else 1
		step(sim, throttle, steer, 1 / 60)
		-- Distance from the nearer leg's centre line (the corner square belongs to both legs).
		local offFirst = if sim.x <= corner.x + halfRoad then math.abs(sim.z) else math.huge
		local offSecond = if sim.z >= -halfRoad then math.abs(sim.x - corner.x) else math.huge
		local off = math.min(offFirst, offSecond)
		maxOff = math.max(maxOff, off)
		if sim.z > 300 then
			reached = true
			break
		end
	end
	expect(reached, `never got up the second leg (x={sim.x}, z={sim.z})`)
	expect(maxOff <= halfRoad - halfWidth, `left the road: {maxOff} studs off the centre line`)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed", 0)
end
