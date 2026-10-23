--!strict
-- Client-side driving. The driver's client owns the matatu's physics, so the motors and steering
-- are run here for instant response. The server keeps the anti-exploit speed check and decides
-- every fare, so nothing here can earn money.
--
-- Controls: W/Up accelerate, S/Down brake then reverse, A/D or Left/Right steer.
-- Gamepad: right trigger accelerate, left trigger brake/reverse, left stick steer.
-- Touch: the on-screen thumbstick.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local UI = require(script.Parent.UI)

local Drive = {}

local player = Players.LocalPlayer

local REVERSE_SPEED_FACTOR = 0.45 -- reverse top speed as a share of forward top speed
local BRAKE_THRESHOLD = 3 -- studs/s: above this, the opposite pedal brakes instead of switching gear
local STUDS_TO_KMH = 0.28 * 3.6 -- 1 stud is about 28 cm

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
	local keyThrottle = 0
	local keySteer = 0
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

	local moveThrottle, moveSteer = 0, 0
	local activeControls = getControls()
	if activeControls then
		local move: Vector3 = activeControls:GetMoveVector()
		moveThrottle, moveSteer = -move.Z, move.X
	end

	return strongest(keyThrottle, padThrottle, moveThrottle, seat.ThrottleFloat),
		strongest(keySteer, padSteer, moveSteer, seat.SteerFloat)
end

type Vehicle = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	motors: { HingeConstraint },
	servos: { HingeConstraint },
}

local function findMyVehicle(): Vehicle?
	local folder = workspace:FindFirstChild("Matatus")
	local model = folder and folder:FindFirstChild(`Matatu_{player.UserId}`)
	if not model or not model:IsA("Model") then
		return nil
	end
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriverSeat")
	if not chassis or not chassis:IsA("BasePart") or not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or seat.Occupant ~= humanoid then
		return nil
	end
	local motors, servos = {}, {}
	for _, child in chassis:GetChildren() do
		if child:IsA("HingeConstraint") then
			if child.Name == "Drive" then
				table.insert(motors, child)
			elseif child.Name == "Steer" then
				table.insert(servos, child)
			end
		end
	end
	return { model = model, chassis = chassis, seat = seat, motors = motors, servos = servos }
end

-- A "Drive" prompt on your own matatu, created only on your client so nobody else sees it.
-- Press F (gamepad Y, or tap on mobile) to hop back in after getting out.
local function updateEnterPrompt(prompt: ProximityPrompt)
	local folder = workspace:FindFirstChild("Matatus")
	local model = folder and folder:FindFirstChild(`Matatu_{player.UserId}`)
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
		Text = "N",
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
	local lookupTimer = 0

	RunService.Heartbeat:Connect(function(dt: number)
		-- Re-resolve the vehicle a few times a second (it changes when you respawn or swap tiers).
		lookupTimer -= dt
		if lookupTimer <= 0 or (vehicle and not vehicle.model.Parent) then
			lookupTimer = 0.25
			vehicle = findMyVehicle()
			updateEnterPrompt(prompt)
		end
		local v = vehicle
		gui.Enabled = v ~= nil
		if not v then
			return
		end

		local model = v.model
		local maxSpeed = (model:GetAttribute("MaxSpeed") :: number?) or 32
		local torque = (model:GetAttribute("Torque") :: number?) or 9000
		local driveSign = (model:GetAttribute("DriveSign") :: number?) or -1
		local maxSteer = (model:GetAttribute("MaxSteer") :: number?) or 32
		local wheelRadius = (model:GetAttribute("WheelRadius") :: number?) or 2

		local throttle, steer = readInput(v.seat)
		local velocity = v.chassis.AssemblyLinearVelocity
		local forwardSpeed = velocity:Dot(v.chassis.CFrame.LookVector)

		local wheelSpeed = 0 -- rad/s, + is forward
		local motorTorque = torque * 0.12 -- light engine braking when coasting
		local gear = "N"

		if throttle > 0.05 then
			if forwardSpeed < -BRAKE_THRESHOLD then
				motorTorque, gear = torque * 1.2, "B"
			else
				wheelSpeed, motorTorque, gear = throttle * maxSpeed, torque, "D"
			end
		elseif throttle < -0.05 then
			if forwardSpeed > BRAKE_THRESHOLD then
				motorTorque, gear = torque * 1.2, "B"
			else
				wheelSpeed, motorTorque, gear = throttle * maxSpeed * REVERSE_SPEED_FACTOR, torque, "R"
			end
		elseif math.abs(forwardSpeed) < 0.5 then
			motorTorque, gear = torque * 0.6, "P" -- hold still on slopes when stopped
		end

		for _, motor in v.motors do
			motor.AngularVelocity = driveSign * wheelSpeed
			motor.MotorMaxTorque = motorTorque
		end

		local topSpeed = maxSpeed * wheelRadius
		local steerScale = 1 - 0.55 * math.clamp(math.abs(forwardSpeed) / topSpeed, 0, 1)
		for _, servo in v.servos do
			servo.TargetAngle = -steer * maxSteer * steerScale
		end

		gearLabel.Text = gear
		gearLabel.TextColor3 = if gear == "R"
			then UI.Colors.pink
			elseif gear == "B" then UI.Colors.danger
			elseif gear == "D" then UI.Colors.green
			else UI.Colors.text
		speedLabel.Text = tostring(math.floor(math.abs(forwardSpeed) * STUDS_TO_KMH + 0.5))
	end)
end

return Drive
