--!strict
-- Client-side driving. The driver's client owns the matatu's physics, so speed and steering are
-- set here every frame for instant response. The server keeps the speed check and decides every
-- fare, so nothing here can earn money.
--
-- The model is arcade-style (see VehicleService): we keep a commanded speed along the matatu's
-- heading and a yaw rate, and the chassis's LinearVelocity / AngularVelocity follow them.
--
-- Controls: W/Up accelerate, S/Down brake then reverse, A/D or Left/Right steer, R unstick.
-- Gamepad: right trigger accelerate, left trigger brake/reverse, left stick steer, D-pad up unstick.
-- Touch: the on-screen thumbstick and the Unstick button.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local DriveModel = require(ReplicatedStorage:WaitForChild("Shared").DriveModel)
local UI = require(script.Parent.UI)

local Drive = {}

local player = Players.LocalPlayer

local STUDS_TO_KMH = 0.28 * 3.6 -- 1 stud is about 28 cm
local MAX_DT = 1 / 15 -- clamp long frames (alt-tab, hitches) so nothing jumps
local GRIP_FORCE = 160 -- studs/s^2 the tyres can deliver on the ground (accelerating, braking, cornering)
local AIR_FORCE = 8 -- almost no control while airborne
local LEVEL_TORQUE = 6000 -- matches VehicleService: keeps the matatu level and sets its yaw
local MAX_VISUAL_STEER = math.rad(32)
local WHEEL_VISUAL_RANGE = 300 -- only animate wheels this close to the camera

local controls: any = nil

local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return (require(playerModule :: ModuleScript) :: any):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function keyAxis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	local value = 0
	for _, key in positive do
		if UserInputService:IsKeyDown(key) then
			value += 1
			break
		end
	end
	for _, key in negative do
		if UserInputService:IsKeyDown(key) then
			value -= 1
			break
		end
	end
	return value
end

local function strongest(...: number): number
	local best = 0
	for _, value in { ... } do
		if math.abs(value) > math.abs(best) then
			best = value
		end
	end
	return math.clamp(best, -1, 1)
end

-- Reads every input source and returns throttle (-1..1, + is forward) and steer (-1..1, + is right).
local function readInput(seat: VehicleSeat): (number, number)
	local keyThrottle, keySteer = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		keyThrottle = keyAxis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down })
		keySteer = keyAxis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })
	end

	local padThrottle, padSteer = 0, 0
	if UserInputService.GamepadEnabled then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				padThrottle += input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				padThrottle -= input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(input.Position.X) > 0.15 then
				padSteer = input.Position.X
			end
		end
	end

	-- The touch thumbstick reports a unit vector, so a diagonal gives ~0.7 on each axis. Scale it
	-- up so "up and to the side" means full throttle and full steer, like W+A on a keyboard.
	local moveThrottle, moveSteer = 0, 0
	local activeControls = getControls()
	if activeControls then
		local move: Vector3 = activeControls:GetMoveVector()
		moveThrottle = math.clamp(-move.Z * 1.42, -1, 1)
		moveSteer = math.clamp(move.X * 1.42, -1, 1)
	end

	return strongest(keyThrottle, padThrottle, moveThrottle, seat.ThrottleFloat),
		strongest(keySteer, padSteer, moveSteer, seat.SteerFloat)
end

type Vehicle = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	drive: LinearVelocity,
	turn: AngularVelocity,
}

local function myModel(): Model?
	local folder = workspace:FindFirstChild("Matatus")
	local model = folder and folder:FindFirstChild(`Matatu_{player.UserId}`)
	return if model and model:IsA("Model") then model else nil
end

-- Returns the matatu only while we are sitting in its driver's seat.
local function findMyVehicle(): Vehicle?
	local model = myModel()
	if not model then
		return nil
	end
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriverSeat")
	if not chassis or not chassis:IsA("BasePart") or not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local drive = chassis:FindFirstChild("Drive")
	local turn = chassis:FindFirstChild("Turn")
	if not drive or not drive:IsA("LinearVelocity") or not turn or not turn:IsA("AngularVelocity") then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or seat.Occupant ~= humanoid then
		return nil
	end
	return { model = model, chassis = chassis, seat = seat, drive = drive, turn = turn }
end

local function attr(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- A "Drive" prompt on your own matatu, created only on your client so nobody else sees it.
-- Press F (gamepad Y, or tap on mobile) to hop back in after getting out.
local function updateEnterPrompt(prompt: ProximityPrompt)
	local model = myModel()
	local body = model and model:FindFirstChild("Body")
	local seat = model and model:FindFirstChild("DriverSeat")
	if not body or not body:IsA("BasePart") or not seat or not seat:IsA("VehicleSeat") then
		prompt.Enabled = false
		return
	end
	local anchor = body:FindFirstChild("EnterPrompt")
	if not anchor then
		local attachment = Instance.new("Attachment")
		attachment.Name = "EnterPrompt"
		attachment.Parent = body
		anchor = attachment
	end
	if prompt.Parent ~= anchor then
		prompt.Parent = anchor
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	prompt.Enabled = humanoid ~= nil and humanoid.Health > 0 and seat.Occupant == nil and humanoid.SeatPart == nil
end

-- Wheel visuals --------------------------------------------------------------------------------

type WheelInfo = { weld: Weld, base: Vector3, front: boolean, spin: number }
type WheelSet = { wheels: { WheelInfo }, steer: number }

local wheelSets: { [Model]: WheelSet } = setmetatable({}, { __mode = "k" }) :: any
local localSteerVisual = 0 -- the local driver's steering, so their own front wheels respond instantly

local function wheelSetFor(model: Model): WheelSet?
	local set = wheelSets[model]
	if set then
		return set
	end
	local wheels = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "FrontWheel" or child.Name == "RearWheel") then
			local weld = child:FindFirstChild("Mount")
			local base = child:GetAttribute("Base")
			if weld and weld:IsA("Weld") and typeof(base) == "Vector3" then
				table.insert(wheels, { weld = weld, base = base, front = child.Name == "FrontWheel", spin = 0 })
			end
		end
	end
	if #wheels == 0 then
		return nil
	end
	set = { wheels = wheels, steer = 0 }
	wheelSets[model] = set
	return set
end

local function animateWheels(dt: number, myDrivenModel: Model?)
	local folder = workspace:FindFirstChild("Matatus")
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local chassis = model:FindFirstChild("Chassis")
		if not chassis or not chassis:IsA("BasePart") then
			continue
		end
		if (chassis.Position - cameraPosition).Magnitude > WHEEL_VISUAL_RANGE then
			continue
		end
		local set = wheelSetFor(model)
		if not set then
			continue
		end
		local radius = attr(model, "WheelRadius", 2)
		local wheelbase = attr(model, "Wheelbase", 12)
		local forward = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)

		local targetSteer: number
		if model == myDrivenModel then
			targetSteer = localSteerVisual
		else
			-- Other players' steering isn't replicated; infer it from how the matatu is turning.
			local yaw = chassis.AssemblyAngularVelocity.Y
			targetSteer = if math.abs(forward) > 1 then math.atan(yaw * wheelbase / forward) else set.steer
		end
		targetSteer = math.clamp(targetSteer, -MAX_VISUAL_STEER, MAX_VISUAL_STEER)
		set.steer += (targetSteer - set.steer) * math.min(1, dt * 12)

		local roll = -forward / radius * dt
		for _, wheel in set.wheels do
			wheel.spin = (wheel.spin + roll) % (2 * math.pi)
			local steer = if wheel.front then set.steer else 0
			wheel.weld.C0 = CFrame.new(wheel.base) * CFrame.Angles(0, steer, 0) * CFrame.Angles(wheel.spin, 0, 0)
		end
	end
end

-- Controller -----------------------------------------------------------------------------------

function Drive.start()
	local gui = UI.create("ScreenGui", {
		Name = "Gauge",
		ResetOnSpawn = false,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local gauge = UI.create("Frame", {
		Size = UDim2.fromOffset(150, 74),
		Position = UDim2.fromOffset(12, 132), -- under the wallet, clear of the touch thumbstick
		BackgroundColor3 = UI.Colors.panel,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { UI.corner(12) })
	local gearLabel = UI.label({
		Size = UDim2.fromOffset(52, 74),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.heavy,
		TextSize = 40,
		Text = "P",
		Parent = gauge,
	})
	local speedLabel = UI.label({
		Size = UDim2.new(1, -56, 0, 40),
		Position = UDim2.fromOffset(52, 8),
		Font = UI.Fonts.heavy,
		TextSize = 30,
		Text = "0",
		Parent = gauge,
	})
	UI.label({
		Size = UDim2.new(1, -56, 0, 18),
		Position = UDim2.fromOffset(52, 46),
		Font = UI.Fonts.body,
		TextSize = 14,
		TextColor3 = UI.Colors.muted,
		Text = "km/h",
		Parent = gauge,
	})
	local unstickButton = UI.button({
		Size = UDim2.fromOffset(150, 34),
		Position = UDim2.fromOffset(12, 212),
		BackgroundColor3 = UI.Colors.panelLight,
		TextColor3 = UI.Colors.text,
		TextSize = 15,
		Text = "Unstick  [R]",
		Parent = gui,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Drive"
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Your matatu"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Triggered:Connect(function()
		Net.event("EnterVehicle"):FireServer()
	end)

	local vehicle: Vehicle? = nil
	local lastVehicle: Vehicle? = nil
	local lookupTimer = 0
	local state = DriveModel.new()

	local function resetState()
		state = DriveModel.new()
		localSteerVisual = 0
	end

	local lastUnstickRequest = 0
	local function requestUnstick()
		if not vehicle or os.clock() - lastUnstickRequest < 1 then
			return
		end
		lastUnstickRequest = os.clock()
		resetState()
		Net.event("Unstick"):FireServer()
	end
	unstickButton.Activated:Connect(requestUnstick)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.DPadUp then
			requestUnstick()
		end
	end)

	-- Stop pushing as soon as we leave the seat, so the matatu doesn't roll on while the server
	-- takes physics ownership back and applies the parking brake.
	local function release(v: Vehicle)
		if v.drive.Parent then
			local mass = v.chassis.AssemblyMass
			v.drive.PlaneVelocity = Vector2.zero
			v.drive.MaxForce = mass * GRIP_FORCE
			v.turn.AngularVelocity = Vector3.zero
			v.turn.MaxTorque = mass * LEVEL_TORQUE
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	RunService.Heartbeat:Connect(function(rawDt: number)
		local dt = math.min(rawDt, MAX_DT)

		-- Re-resolve the vehicle a few times a second (it changes when you respawn, swap tiers,
		-- get out or die).
		lookupTimer -= dt
		if lookupTimer <= 0 or (vehicle and (not vehicle.model.Parent or vehicle.seat.Occupant == nil)) then
			lookupTimer = 0.2
			vehicle = findMyVehicle()
			updateEnterPrompt(prompt)
		end

		local v = vehicle
		if lastVehicle and (not v or v.model ~= lastVehicle.model) then
			release(lastVehicle)
			resetState()
		end
		lastVehicle = v
		gui.Enabled = v ~= nil

		if not v then
			animateWheels(dt, nil)
			return
		end

		local model = v.model
		local chassis = v.chassis
		local params: DriveModel.Params = {
			topSpeed = attr(model, "TopSpeed", 64),
			reverseSpeed = attr(model, "ReverseSpeed", 24),
			acceleration = attr(model, "Acceleration", 18),
			brakeDeceleration = attr(model, "BrakeDeceleration", 60),
			turnRate = attr(model, "TurnRate", 1.7),
			turnRadius = attr(model, "TurnRadius", 13),
		}

		local throttle, steer = readInput(v.seat)
		local look = chassis.CFrame.LookVector
		local velocity = chassis.AssemblyLinearVelocity
		local actualForward = velocity:Dot(look)

		-- On the ground? Cast down from the chassis past the bottom of the skids.
		rayParams.FilterDescendantsInstances = { model, player.Character :: Instance }
		local rideHeight = attr(model, "RideHeight", 2.4)
		local hit = workspace:Raycast(chassis.Position, -chassis.CFrame.UpVector * (rideHeight + 1.2), rayParams)
		local grounded = hit ~= nil

		local speed, yaw, gear = DriveModel.step(state, params, throttle, steer, actualForward, grounded, dt)

		local mass = chassis.AssemblyMass
		v.drive.PlaneVelocity = Vector2.new(0, speed)
		v.drive.MaxForce = mass * (if grounded then GRIP_FORCE else AIR_FORCE)
		v.turn.AngularVelocity = Vector3.new(0, yaw, 0)
		v.turn.MaxTorque = mass * LEVEL_TORQUE

		localSteerVisual = -steer * MAX_VISUAL_STEER
		animateWheels(dt, model)

		gearLabel.Text = gear
		gearLabel.TextColor3 = if gear == "R"
			then UI.Colors.pink
			elseif gear == "B" then UI.Colors.danger
			elseif gear == "D" then UI.Colors.green
			else UI.Colors.text
		speedLabel.Text = tostring(math.floor(math.abs(actualForward) * STUDS_TO_KMH + 0.5))
	end)
end

return Drive
