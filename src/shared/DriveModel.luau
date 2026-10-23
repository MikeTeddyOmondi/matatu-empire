--!strict
-- The arcade driving model, kept free of Roblox APIs so it can be unit-tested outside Studio
-- (tests/DriveModel.spec.luau). Controllers/Drive.luau feeds it input and the measured motion
-- every frame and applies the speed and yaw it returns to the matatu's movers.
--
-- Conventions: speed is studs/s along the matatu's heading (+ forward, - reverse). Yaw is rad/s
-- about world +Y, so a positive yaw turns the nose left. Steer +1 means "turn right".

local DriveModel = {}

export type Params = {
	topSpeed: number,
	reverseSpeed: number,
	acceleration: number,
	brakeDeceleration: number,
	turnRate: number,
	turnRadius: number,
}

export type State = {
	speed: number, -- commanded speed
	yaw: number, -- commanded yaw rate
}

export type Gear = "D" | "R" | "B" | "N" | "P"

DriveModel.INPUT_DEADZONE = 0.05
DriveModel.COAST_DECELERATION = 10 -- studs/s^2 with no pedal pressed
DriveModel.STOP_SPEED = 0.5 -- below this the matatu counts as stopped
DriveModel.BLOCKED_SLACK = 4 -- studs/s: command running ahead of reality by more than this = blocked
DriveModel.RECONCILE_RATE = 90 -- studs/s^2 at which a blocked command falls back to the real speed
DriveModel.BLOCKED_SPEED = 2 -- studs/s: below this while pressing a pedal we count as stuck
DriveModel.PIVOT_FACTOR = 0.35 -- share of turnRate allowed when stuck, to wriggle off a wall
DriveModel.HIGH_SPEED_STEER_LOSS = 0.2 -- steering gets this much lighter at top speed
DriveModel.STEER_RESPONSE = 8 -- yaw ramps to full lock in 1/8 s

function DriveModel.new(): State
	return { speed = 0, yaw = 0 }
end

local function moveToward(value: number, target: number, maxDelta: number): number
	if value < target then
		return math.min(value + maxDelta, target)
	end
	return math.max(value - maxDelta, target)
end
DriveModel.moveToward = moveToward

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

-- Advances the model by dt. Returns the speed and yaw to command, and the gear to display.
function DriveModel.step(
	state: State,
	p: Params,
	throttle: number,
	steer: number,
	actualForward: number,
	grounded: boolean,
	dt: number
): (number, number, Gear)
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	local deadzone = DriveModel.INPUT_DEADZONE
	local speed = state.speed
	local gear: Gear

	if not grounded then
		-- No traction in the air: follow what the matatu is actually doing so landing is smooth.
		speed = actualForward
		gear = if speed > DriveModel.STOP_SPEED
			then "D"
			elseif speed < -DriveModel.STOP_SPEED then "R"
			else "N"
	else
		-- Hit something (wall, kerb, another matatu)? Then the matatu isn't moving the way we
		-- command. Let the stored speed fall back to reality so the next input responds at once
		-- instead of first "using up" speed we never actually had.
		if math.abs(speed - actualForward) > DriveModel.BLOCKED_SLACK then
			speed = moveToward(speed, actualForward, DriveModel.RECONCILE_RATE * dt)
		end

		if throttle > deadzone then
			if speed < -DriveModel.STOP_SPEED then
				speed = moveToward(speed, 0, p.brakeDeceleration * dt)
				gear = "B"
			else
				local target = p.topSpeed * throttle
				speed = if speed < target
					then math.min(target, speed + p.acceleration * dt)
					else moveToward(speed, target, DriveModel.COAST_DECELERATION * dt)
				gear = "D"
			end
		elseif throttle < -deadzone then
			if speed > DriveModel.STOP_SPEED then
				speed = moveToward(speed, 0, p.brakeDeceleration * dt)
				gear = "B"
			else
				local target = -p.reverseSpeed * -throttle
				speed = if speed > target
					then math.max(target, speed - p.acceleration * dt)
					else moveToward(speed, target, DriveModel.COAST_DECELERATION * dt)
				gear = "R"
			end
		else
			speed = moveToward(speed, 0, DriveModel.COAST_DECELERATION * dt)
			if math.abs(speed) < DriveModel.STOP_SPEED then
				speed = 0
				gear = "P"
			else
				gear = "N"
			end
		end
	end

	-- Steering: yaw is limited by the tightest turning circle at low speed (no spinning on the
	-- spot), by turnRate at high speed, and reverses direction when reversing, like a real car.
	local targetYaw = 0
	if grounded then
		local absSpeed = math.abs(speed)
		local speedShare = math.clamp(absSpeed / p.topSpeed, 0, 1)
		local cap = math.min(p.turnRate, absSpeed / p.turnRadius)
			* (1 - DriveModel.HIGH_SPEED_STEER_LOSS * speedShare)
		local direction = sign(speed)
		-- Stuck against something while pressing a pedal: allow a slow pivot in the direction
		-- you're trying to go, so W+A / S+A wriggles you free.
		if math.abs(throttle) > deadzone and math.abs(actualForward) < DriveModel.BLOCKED_SPEED then
			cap = math.max(cap, p.turnRate * DriveModel.PIVOT_FACTOR)
			direction = sign(throttle)
		end
		targetYaw = -steer * cap * direction
	end
	local yaw = moveToward(state.yaw, targetYaw, p.turnRate * DriveModel.STEER_RESPONSE * dt)

	state.speed = speed
	state.yaw = yaw
	return speed, yaw, gear
end

return DriveModel
