--!strict
-- Builds drivable matatus from parts and constraints, drives them from the VehicleSeat on the
-- server, applies Vibe cosmetics, and watches for impossible speeds.
--
-- Chassis layout: forward is the chassis's -Z (its LookVector). Rear wheels are motor hinges,
-- front wheels hang off servo-steered knuckles.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vehicles = require(Shared.Config.Vehicles)
local World = require(Shared.Config.World)
local Net = require(Shared.Net)

type VehicleTier = Vehicles.VehicleTier

export type VehicleRecord = {
	owner: Player,
	tier: VehicleTier,
	model: Model,
	chassis: BasePart,
	body: BasePart,
	seat: VehicleSeat,
	rearMotors: { HingeConstraint },
	steerServos: { HingeConstraint },
	cosmetics: Folder,
	label: TextLabel,
	ledParts: { BasePart },
	flagged: boolean, -- set when the anti-exploit check fails; cancels the current trip
	overSpeedTime: number,
	upsideDownTime: number,
}

-- Flip to 1 if your matatus drive backwards (depends on hinge axis conventions).
local DRIVE_SIGN = -1
local WHEEL_RADIUS = 2
local WHEEL_WIDTH = 1.4
local MAX_STEER_DEGREES = 32
local SPEED_TOLERANCE = 1.5 -- allowed multiple of the theoretical top speed before flagging

-- Optional audio. Paste your own uploaded/licensed asset ids here ("rbxassetid://123").
local HORN_SOUND_ID = ""
local MUSIC_SOUND_ID = ""

local VehicleService = {}

local services: any
local records: { [Player]: VehicleRecord } = {}
local despawnCallbacks: { (Player) -> () } = {}
local vehiclesFolder: Folder
local spawnLimiter = Net.rateLimiter(0.5, 2)

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function attachment(parent: BasePart, cframe: CFrame, name: string?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name or "Attachment"
	a.CFrame = cframe
	a.Parent = parent
	return a
end

local UP_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- rotates an attachment's primary axis (X) to point up

local function buildWheel(
	model: Model,
	chassis: BasePart,
	root: CFrame,
	localPos: Vector3,
	isFront: boolean,
	tier: VehicleTier
): (BasePart, HingeConstraint?, HingeConstraint?)
	local wheel = newPart({
		Name = isFront and "FrontWheel" or "RearWheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(WHEEL_WIDTH, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2),
		CFrame = root * CFrame.new(localPos),
		Color = Color3.fromRGB(28, 28, 30),
		Material = Enum.Material.SmoothPlastic,
		CustomPhysicalProperties = PhysicalProperties.new(0.9, 1.4, 0.1, 100, 1),
		Parent = model,
	})
	local wheelAttachment = attachment(wheel, CFrame.new(), "Axle")

	if isFront then
		-- Knuckle: steers around Y, the wheel spins freely around the knuckle's X.
		local knuckle = newPart({
			Name = "Knuckle",
			Size = Vector3.new(0.5, 0.5, 0.5),
			CFrame = root * CFrame.new(localPos),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		local steerA0 = attachment(chassis, CFrame.new(localPos) * UP_AXIS, "SteerBase")
		local steerA1 = attachment(knuckle, UP_AXIS, "SteerKnuckle")
		local servo = Instance.new("HingeConstraint")
		servo.Name = "Steer"
		servo.Attachment0 = steerA0
		servo.Attachment1 = steerA1
		servo.ActuatorType = Enum.ActuatorType.Servo
		servo.ServoMaxTorque = 1e7
		servo.AngularSpeed = 5
		servo.LimitsEnabled = true
		servo.LowerAngle = -MAX_STEER_DEGREES
		servo.UpperAngle = MAX_STEER_DEGREES
		servo.Parent = chassis

		local axle = Instance.new("HingeConstraint")
		axle.Name = "FreeAxle"
		axle.Attachment0 = attachment(knuckle, CFrame.new(), "Axle")
		axle.Attachment1 = wheelAttachment
		axle.Parent = knuckle
		return wheel, nil, servo
	else
		local motor = Instance.new("HingeConstraint")
		motor.Name = "Drive"
		motor.Attachment0 = attachment(chassis, CFrame.new(localPos), "RearAxle")
		motor.Attachment1 = wheelAttachment
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = tier.torque
		motor.AngularVelocity = 0
		motor.Parent = chassis
		return wheel, motor, nil
	end
end

local function buildLabel(body: BasePart, owner: Player): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffset = Vector3.new(0, body.Size.Y / 2 + 3, 0)
	gui.MaxDistance = 250
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = `{owner.DisplayName}'s matatu`
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = body
	return label
end

local function buildMatatu(owner: Player, tier: VehicleTier, spawnAt: CFrame): VehicleRecord
	local model = Instance.new("Model")
	model.Name = `Matatu_{owner.UserId}`
	model:SetAttribute("OwnerUserId", owner.UserId)

	local W, L, H = tier.width, tier.length, tier.height
	local root = spawnAt

	local chassis = newPart({
		Name = "Chassis",
		Size = Vector3.new(W, 1.2, L),
		CFrame = root,
		Color = Color3.fromRGB(40, 40, 44),
		CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0.2),
		Parent = model,
	})
	model.PrimaryPart = chassis

	local bodyHeight = H - 1.6
	local body = newPart({
		Name = "Body",
		Size = Vector3.new(W, bodyHeight, L),
		CFrame = root * CFrame.new(0, 0.6 + bodyHeight / 2, 0),
		Color = tier.bodyColor,
		Material = Enum.Material.SmoothPlastic,
		Massless = true,
		Parent = model,
	})
	weld(chassis, body)

	-- Window band and windscreen.
	local windows = newPart({
		Name = "Windows",
		Size = Vector3.new(W + 0.1, bodyHeight * 0.32, L - 2),
		CFrame = body.CFrame * CFrame.new(0, bodyHeight * 0.18, 0.4),
		Color = Color3.fromRGB(20, 26, 34),
		Material = Enum.Material.Glass,
		Reflectance = 0.2,
		Massless = true,
		CanCollide = false,
		Parent = model,
	})
	weld(body, windows)
	local windscreen = newPart({
		Name = "Windscreen",
		Size = Vector3.new(W - 1, bodyHeight * 0.4, 0.2),
		CFrame = body.CFrame * CFrame.new(0, bodyHeight * 0.15, -L / 2 - 0.05),
		Color = Color3.fromRGB(20, 26, 34),
		Material = Enum.Material.Glass,
		Reflectance = 0.2,
		Massless = true,
		CanCollide = false,
		Parent = model,
	})
	weld(body, windscreen)

	-- Headlights.
	for _, side in { -1, 1 } do
		local lamp = newPart({
			Name = "Headlight",
			Size = Vector3.new(1.4, 0.8, 0.2),
			CFrame = body.CFrame * CFrame.new(side * (W / 2 - 1.2), -bodyHeight / 2 + 1, -L / 2 - 0.1),
			Color = Color3.fromRGB(255, 250, 220),
			Material = Enum.Material.Neon,
			Massless = true,
			CanCollide = false,
			Parent = model,
		})
		weld(body, lamp)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Range = 40
		light.Angle = 60
		light.Brightness = 2
		light.Parent = lamp
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = root * CFrame.new(-W / 4, 1.1, -L / 2 + 3.5)
	seat.Transparency = 1
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- legacy drive off; we drive the constraints ourselves
	seat.Torque = 0
	seat.Parent = model
	weld(chassis, seat)

	local rearMotors: { HingeConstraint } = {}
	local steerServos: { HingeConstraint } = {}
	local axleX = W / 2 + WHEEL_WIDTH / 2 + 0.2
	local axleZ = L / 2 - 3
	for _, z in { -axleZ, axleZ } do
		local isFront = z < 0
		for _, side in { -1, 1 } do
			local _, motor, servo =
				buildWheel(model, chassis, root, Vector3.new(side * axleX, -0.4, z), isFront, tier)
			if motor then
				table.insert(rearMotors, motor)
			end
			if servo then
				table.insert(steerServos, servo)
			end
		end
	end

	local cosmetics = Instance.new("Folder")
	cosmetics.Name = "Cosmetics"
	cosmetics.Parent = model

	local label = buildLabel(body, owner)

	model.Parent = vehiclesFolder

	return {
		owner = owner,
		tier = tier,
		model = model,
		chassis = chassis,
		body = body,
		seat = seat,
		rearMotors = rearMotors,
		steerServos = steerServos,
		cosmetics = cosmetics,
		label = label,
		ledParts = {},
		flagged = false,
		overSpeedTime = 0,
		upsideDownTime = 0,
	}
end

-- Cosmetic part welded to the body, defined in body-local space.
local function deco(record: VehicleRecord, props: { [string]: any }, offset: CFrame): Part
	props.Massless = true
	props.CanCollide = false
	props.CanQuery = false
	props.Parent = record.cosmetics
	props.CFrame = record.body.CFrame * offset
	local p = newPart(props)
	weld(record.body, p)
	return p
end

local GRAFFITI = {
	Color3.fromRGB(255, 64, 129),
	Color3.fromRGB(0, 229, 255),
	Color3.fromRGB(255, 214, 0),
	Color3.fromRGB(118, 255, 3),
	Color3.fromRGB(213, 0, 249),
}

local function applyCosmetics(record: VehicleRecord, upgrades: { [string]: number })
	record.cosmetics:ClearAllChildren()
	table.clear(record.ledParts)
	for _, sound in record.body:GetChildren() do
		if sound:IsA("Sound") then
			sound:Destroy()
		end
	end

	local body = record.body
	local W, Hb, L = body.Size.X, body.Size.Y, body.Size.Z
	local rng = Random.new(record.owner.UserId)

	-- Paint & graffiti
	local paint = upgrades.Paint or 0
	body.Color = record.tier.bodyColor
	if paint >= 1 then
		for _, side in { -1, 1 } do
			deco(record, {
				Name = "Stripe",
				Size = Vector3.new(0.1, 0.7, L - 0.4),
				Color = Color3.fromRGB(255, 196, 0),
				Material = Enum.Material.SmoothPlastic,
			}, CFrame.new(side * (W / 2 + 0.06), -Hb * 0.12, 0))
		end
	end
	if paint >= 2 then
		for _, side in { -1, 1 } do
			for i = 1, 6 do
				local w = rng:NextNumber(1.2, 3.4)
				local h = rng:NextNumber(0.8, 1.6)
				deco(record, {
					Name = "Graffiti",
					Size = Vector3.new(0.1, h, w),
					Color = GRAFFITI[rng:NextInteger(1, #GRAFFITI)],
					Material = Enum.Material.SmoothPlastic,
				}, CFrame.new(side * (W / 2 + 0.08), -Hb * 0.3 + rng:NextNumber(-0.3, 0.3), -L / 2 + i * (L / 7)))
			end
		end
	end
	if paint >= 3 then
		body.Color = Color3.fromRGB(20, 20, 26)
		deco(record, {
			Name = "RoofArt",
			Size = Vector3.new(W - 0.6, 0.1, L - 1),
			Color = GRAFFITI[rng:NextInteger(1, #GRAFFITI)],
			Material = Enum.Material.SmoothPlastic,
		}, CFrame.new(0, Hb / 2 + 0.06, 0))
	end

	-- Lights
	local lights = upgrades.Lights or 0
	if lights >= 1 then
		local glow = deco(record, {
			Name = "Underglow",
			Size = Vector3.new(W - 0.6, 0.2, L - 1),
			Color = Color3.fromRGB(0, 229, 255),
			Material = Enum.Material.Neon,
		}, CFrame.new(0, -Hb / 2 - 0.9, 0))
		local light = Instance.new("PointLight")
		light.Color = glow.Color
		light.Range = 14
		light.Brightness = 3
		light.Parent = glow
		table.insert(record.ledParts, glow)
	end
	if lights >= 2 then
		local bar = deco(record, {
			Name = "RoofNeon",
			Size = Vector3.new(W - 1, 0.5, 0.6),
			Color = Color3.fromRGB(255, 64, 129),
			Material = Enum.Material.Neon,
		}, CFrame.new(0, Hb / 2 + 0.3, -L / 2 + 1))
		table.insert(record.ledParts, bar)
	end
	if lights >= 3 then
		for _, side in { -1, 1 } do
			local strip = deco(record, {
				Name = "LedStrip",
				Size = Vector3.new(0.15, 0.25, L - 0.6),
				Color = Color3.fromRGB(118, 255, 3),
				Material = Enum.Material.Neon,
			}, CFrame.new(side * (W / 2 + 0.1), Hb / 2 - 0.2, 0))
			table.insert(record.ledParts, strip)
		end
		record.model:SetAttribute("BeatLeds", true)
	else
		record.model:SetAttribute("BeatLeds", false)
	end

	-- Sound system
	local sound = upgrades.Sound or 0
	if sound >= 1 then
		for _, side in { -1, 1 } do
			deco(record, {
				Name = "Speaker",
				Size = Vector3.new(1.2, 1.2, 0.3),
				Color = Color3.fromRGB(30, 30, 30),
				Material = Enum.Material.Metal,
			}, CFrame.new(side * (W / 2 - 1.4), -Hb * 0.1, L / 2 + 0.16))
		end
	end
	if sound >= 2 then
		for _, side in { -1, 1 } do
			deco(record, {
				Name = "Subwoofer",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 2.2, 2.2),
				Color = Color3.fromRGB(60, 60, 64),
				Material = Enum.Material.Metal,
			}, CFrame.new(side * 1.6, -Hb * 0.25, L / 2 + 0.2) * CFrame.Angles(0, math.pi / 2, 0))
		end
	end
	record.model:SetAttribute("BassLevel", sound)
	if sound >= 1 and MUSIC_SOUND_ID ~= "" then
		local music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundId = MUSIC_SOUND_ID
		music.Looped = true
		music.Volume = 0.15 + 0.15 * sound
		music.RollOffMaxDistance = 60 + 30 * sound
		music.Parent = body
		music:Play()
	end

	-- Interior (seen through the windows as tint, trim and a rear screen)
	local interior = upgrades.Interior or 0
	local windows = record.model:FindFirstChild("Windows") :: BasePart?
	if windows then
		windows.Color = if interior >= 1 then Color3.fromRGB(40, 20, 60) else Color3.fromRGB(20, 26, 34)
	end
	if interior >= 2 then
		local screen = deco(record, {
			Name = "RearScreen",
			Size = Vector3.new(W - 2.4, Hb * 0.3, 0.1),
			Color = Color3.new(0, 0, 0),
			Material = Enum.Material.SmoothPlastic,
		}, CFrame.new(0, Hb * 0.18, L / 2 + 0.06))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = GRAFFITI[rng:NextInteger(1, #GRAFFITI)]
		text.Text = string.upper(record.owner.DisplayName)
		text.Parent = gui
		gui.Parent = screen
	end
	if interior >= 3 then
		for _, side in { -1, 1 } do
			deco(record, {
				Name = "GoldTrim",
				Size = Vector3.new(0.12, 0.2, L - 1),
				Color = Color3.fromRGB(212, 175, 55),
				Material = Enum.Material.Metal,
			}, CFrame.new(side * (W / 2 + 0.06), Hb * 0.36, 0))
		end
	end

	-- Body kit
	local kit = upgrades.BodyKit or 0
	if kit >= 1 then
		deco(record, {
			Name = "BullBar",
			Size = Vector3.new(W - 1, 0.4, 0.4),
			Color = Color3.fromRGB(200, 200, 205),
			Material = Enum.Material.Metal,
		}, CFrame.new(0, -Hb / 2 + 0.4, -L / 2 - 0.5))
		if HORN_SOUND_ID ~= "" then
			local horn = Instance.new("Sound")
			horn.Name = "Horn"
			horn.SoundId = HORN_SOUND_ID
			horn.Volume = 0.8
			horn.Parent = body
		end
	end
	for _, wheel in record.model:GetChildren() do
		if wheel:IsA("BasePart") and (wheel.Name == "FrontWheel" or wheel.Name == "RearWheel") then
			wheel.Color = if kit >= 2 then Color3.fromRGB(205, 205, 210) else Color3.fromRGB(28, 28, 30)
			wheel.Material = if kit >= 2 then Enum.Material.Metal else Enum.Material.SmoothPlastic
		end
	end
	if kit >= 3 then
		deco(record, {
			Name = "Spoiler",
			Size = Vector3.new(W, 0.3, 1.6),
			Color = GRAFFITI[1],
			Material = Enum.Material.SmoothPlastic,
		}, CFrame.new(0, Hb / 2 + 0.9, L / 2 - 0.6))
		for _, side in { -1, 1 } do
			deco(record, {
				Name = "SideSkirt",
				Size = Vector3.new(0.4, 0.6, L - 6.5),
				Color = Color3.fromRGB(30, 30, 34),
				Material = Enum.Material.SmoothPlastic,
			}, CFrame.new(side * (W / 2 + 0.2), -Hb / 2 + 0.3, 0))
		end
	end
end

local function playerCharacterHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function setOwner(record: VehicleRecord, owner: Player?)
	for _, descendant in record.model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(owner)
			end)
		end
	end
end

local function onOccupantChanged(record: VehicleRecord)
	local occupant = record.seat.Occupant
	if not occupant then
		setOwner(record, nil)
		services.StateService.push(record.owner)
		return
	end
	local character = occupant.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player ~= record.owner then
		-- Only the owner may drive their matatu.
		occupant.Sit = false
		occupant.Jump = true
		return
	end
	-- Give the driver physics ownership of every assembly (chassis, wheels, knuckles) for smooth
	-- driving. The server still decides fares, so a tampered client can't print money.
	setOwner(record, record.owner)
	services.StateService.push(record.owner)
end

local function stageNearestTo(position: Vector3): string
	local best, bestDistance = "CBD", math.huge
	for id, stage in World.Stages do
		local d = (stage.position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = id, d
		end
	end
	return best
end

function VehicleService.get(player: Player): VehicleRecord?
	return records[player]
end

function VehicleService.isDriving(player: Player): boolean
	local record = records[player]
	if not record or not record.seat.Occupant then
		return false
	end
	return Players:GetPlayerFromCharacter(record.seat.Occupant.Parent) == player
end

function VehicleService.speed(record: VehicleRecord): number
	return record.chassis.AssemblyLinearVelocity.Magnitude
end

function VehicleService.position(record: VehicleRecord): Vector3
	return record.chassis.Position
end

function VehicleService.onDespawn(callback: (Player) -> ())
	table.insert(despawnCallbacks, callback)
end

function VehicleService.despawn(player: Player)
	local record = records[player]
	if not record then
		return
	end
	records[player] = nil
	for _, callback in despawnCallbacks do
		task.spawn(callback, player)
	end
	record.model:Destroy()
end

function VehicleService.refreshCosmetics(player: Player)
	local record = records[player]
	local profile = services.PlayerDataService.get(player)
	if record and profile then
		applyCosmetics(record, profile.upgrades)
	end
end

function VehicleService.spawn(player: Player): (boolean, string)
	local profile = services.PlayerDataService.get(player)
	if not profile then
		return false, "Still loading your data"
	end
	local tier = Vehicles[profile.equippedTier] or Vehicles[1]

	-- Spawn at whichever stage the player (or their old matatu) is closest to.
	local from = Vector3.zero
	local existing = records[player]
	if existing then
		from = existing.chassis.Position
	elseif player.Character and player.Character.PrimaryPart then
		from = player.Character.PrimaryPart.Position
	end
	local stageId = stageNearestTo(from)
	VehicleService.despawn(player)

	local stage = World.Stages[stageId]
	local record = buildMatatu(player, tier, stage.vehicleSpawn)
	records[player] = record
	applyCosmetics(record, profile.upgrades)

	record.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(record)
	end)

	local humanoid = playerCharacterHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		task.defer(function()
			if record.model.Parent then
				record.seat:Sit(humanoid)
			end
		end)
	end
	services.StateService.push(player)
	return true, `{tier.displayName} ready at {stage.displayName}`
end

function VehicleService.setLabel(player: Player, text: string)
	local record = records[player]
	if record then
		record.label.Text = text
	end
end

local function step(dt: number)
	local now = os.clock()
	for player, record in records do
		if not record.model.Parent then
			records[player] = nil
			continue
		end
		local seat = record.seat
		local tier = record.tier
		local driving = seat.Occupant ~= nil
		local throttle = if driving then seat.ThrottleFloat else 0
		local steer = if driving then seat.SteerFloat else 0

		local speed = record.chassis.AssemblyLinearVelocity.Magnitude
		local topSpeed = tier.maxSpeed * WHEEL_RADIUS

		for _, motor in record.rearMotors do
			motor.AngularVelocity = DRIVE_SIGN * throttle * tier.maxSpeed
			-- With no throttle the motor holds the wheels still, acting as a brake.
			motor.MotorMaxTorque = if throttle ~= 0 then tier.torque else tier.torque * 0.35
		end
		-- Less steering lock at speed so the matatu doesn't flip.
		local steerScale = 1 - 0.55 * math.clamp(speed / topSpeed, 0, 1)
		for _, servo in record.steerServos do
			servo.TargetAngle = -steer * MAX_STEER_DEGREES * steerScale
		end

		-- Anti-exploit: impossible speed cancels the trip.
		if speed > topSpeed * SPEED_TOLERANCE then
			record.overSpeedTime += dt
			if record.overSpeedTime > 0.75 and not record.flagged then
				record.flagged = true
				Net.event("Notify"):FireClient(player, "Speed check failed: this trip won't pay.", "warn")
			end
		else
			record.overSpeedTime = math.max(0, record.overSpeedTime - dt)
		end

		-- Auto-recover a flipped matatu after a few seconds.
		if record.chassis.CFrame.UpVector.Y < 0.3 and speed < 6 then
			record.upsideDownTime += dt
			if record.upsideDownTime > 3 then
				record.upsideDownTime = 0
				local pos = record.chassis.Position
				local look = record.chassis.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude < 0.1 then
					flatLook = Vector3.new(0, 0, -1)
				end
				record.model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 5, 0), pos + Vector3.new(0, 5, 0) + flatLook))
			end
		else
			record.upsideDownTime = 0
		end

		-- Beat-synced LEDs (Lights level 3).
		if record.model:GetAttribute("BeatLeds") then
			local hue = (now * 0.35 + player.UserId % 10 / 10) % 1
			local color = Color3.fromHSV(hue, 0.9, 1)
			for _, led in record.ledParts do
				led.Color = color
			end
		end
	end
end

function VehicleService.init(registry: any)
	services = registry
	vehiclesFolder = Instance.new("Folder")
	vehiclesFolder.Name = "Matatus"
	vehiclesFolder.Parent = workspace
end

function VehicleService.start()
	Net.func("SpawnVehicle").OnServerInvoke = function(player: Player)
		if not spawnLimiter:allow(player) then
			return false, "Slow down: try again in a moment"
		end
		return VehicleService.spawn(player)
	end

	local hornLimiter = Net.rateLimiter(1, 2)
	Net.event("Horn").OnServerEvent:Connect(function(player: Player)
		if not hornLimiter:allow(player) or not VehicleService.isDriving(player) then
			return
		end
		local record = records[player]
		local horn = record and record.body:FindFirstChild("Horn")
		if horn and horn:IsA("Sound") then
			horn:Play()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.despawn(player)
	end)

	RunService.Heartbeat:Connect(step)
end

return VehicleService
