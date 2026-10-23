--!strict
-- Builds drivable matatus, applies Vibe cosmetics, parks unattended matatus, and watches for
-- impossible speeds.
--
-- Handling is arcade-style, the approach most Roblox driving games use: the matatu rests on four
-- invisible frictionless skids, a LinearVelocity sets its speed along its heading (and kills
-- sideways sliding), and an AngularVelocity sets its yaw while keeping it level. The driver's
-- client owns the physics and sets both each frame (Controllers/Drive.luau). The visible wheels
-- are cosmetic and are spun and steered on every client. Forward is the chassis's -Z.

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
	drive: LinearVelocity,
	turn: AngularVelocity,
	parked: boolean, -- whether the parking brake values are currently applied
	lastUnstick: number,
	cosmetics: Folder,
	label: TextLabel,
	ledParts: { BasePart },
	paintPart: BasePart, -- the part whose colour is the matatu's paint (mesh body or the box body)
	glassPart: BasePart?,
	usesMesh: boolean,
	flagged: boolean, -- set when the anti-exploit check fails; cancels the current trip
	overSpeedTime: number,
	upsideDownTime: number,
}

local WHEEL_RADIUS = 2
local WHEEL_WIDTH = 1.4
local WHEEL_Y = -0.4 -- wheel centre relative to the chassis centre
local SKID_RADIUS = 1.25 -- invisible frictionless balls the matatu actually rests on
local PARK_FORCE = 120 -- parking brake strength, as acceleration (studs/s^2) times mass
local LEVEL_TORQUE = 6000 -- keeps the matatu level and sets yaw, as torque per unit of mass
local SPEED_TOLERANCE = 1.5 -- allowed multiple of the tier's top speed before flagging
local UNSTICK_COOLDOWN = 5 -- seconds between unstick requests
local ENTER_DISTANCE = 26 -- studs from the chassis within which you can hop back in

-- Optional audio. Paste your own uploaded/licensed asset ids here ("rbxassetid://123").
local HORN_SOUND_ID = ""
local MUSIC_SOUND_ID = ""

-- Optional imported model. Put a Model named "Matatu" in ReplicatedStorage.Assets containing
-- MeshParts named Body, Livery, Glass, Trim, Lights and TailLights (tools/make_matatu_mesh.py
-- generates exactly that). Set a number attribute "Yaw" = 180 on the Model if it faces backwards.

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

local FRICTIONLESS = PhysicalProperties.new(1, 0, 0, 100, 100)

-- A cosmetic wheel. It has no collision; a Weld holds it so clients can spin and steer it by
-- changing the weld's C0 (see Controllers/Drive.luau).
local function buildWheel(model: Model, chassis: BasePart, localPos: Vector3, isFront: boolean)
	local wheel = newPart({
		Name = if isFront then "FrontWheel" else "RearWheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(WHEEL_WIDTH, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2),
		CFrame = chassis.CFrame * CFrame.new(localPos),
		Color = Color3.fromRGB(28, 28, 30),
		Material = Enum.Material.SmoothPlastic,
		Massless = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	wheel:SetAttribute("Base", localPos)
	wheel:SetAttribute("Front", isFront)
	local mount = Instance.new("Weld")
	mount.Name = "Mount"
	mount.Part0 = chassis
	mount.Part1 = wheel
	mount.C0 = CFrame.new(localPos)
	mount.Parent = wheel
end

-- An invisible frictionless ball under each wheel. These are what touch the ground, so the
-- matatu glides wherever the LinearVelocity sends it and never snags or scrubs in corners.
local function buildSkid(model: Model, chassis: BasePart, localPos: Vector3)
	local skid = newPart({
		Name = "Skid",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * SKID_RADIUS * 2,
		CFrame = chassis.CFrame * CFrame.new(localPos),
		Transparency = 1,
		CustomPhysicalProperties = FRICTIONLESS,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	weld(chassis, skid)
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

local function findMeshTemplate(): (Model?, BasePart?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Matatu")
	if not template or not template:IsA("Model") then
		return nil, nil
	end
	local body = template:FindFirstChild("Body", true)
	if not body or not body:IsA("BasePart") then
		warn("[VehicleService] Assets.Matatu has no BasePart named Body; using the box matatu")
		return nil, nil
	end
	return template, body
end

-- Clone the imported matatu and fit it to the box body: the template's Body part is stretched
-- to the body's size and every other part keeps its position relative to Body, scaled the same way.
local function attachMesh(model: Model, body: BasePart, tier: VehicleTier): (BasePart?, BasePart?)
	local template, templateBody = findMeshTemplate()
	if not template or not templateBody then
		return nil, nil
	end
	local yaw = template:GetAttribute("Yaw")
	local turn = CFrame.Angles(0, math.rad(if type(yaw) == "number" then yaw else 0), 0)
	local factor = body.Size / templateBody.Size

	local visuals = Instance.new("Model")
	visuals.Name = "Visual"
	visuals.Parent = model

	local paintPart: BasePart? = nil
	local glassPart: BasePart? = nil
	for _, source in template:GetDescendants() do
		if not source:IsA("BasePart") then
			continue
		end
		local offset = templateBody.CFrame:ToObjectSpace(source.CFrame)
		local part = source:Clone()
		for _, child in part:GetChildren() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Size = source.Size * factor
		part.CFrame = body.CFrame * turn * CFrame.new(offset.Position * factor) * offset.Rotation
		part.Parent = visuals
		weld(body, part)

		if source.Name == "Body" then
			part.Color = tier.bodyColor
			paintPart = part
		elseif source.Name == "Glass" then
			part.Material = Enum.Material.Glass
			part.Reflectance = 0.2
			glassPart = part
		elseif source.Name == "Lights" or source.Name == "TailLights" then
			part.Material = Enum.Material.Neon
		end
	end
	return paintPart, glassPart
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
		-- Low friction so scraping along a wall or kerb slides instead of sticking.
		CustomPhysicalProperties = PhysicalProperties.new(3, 0.05, 0, 100, 100),
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
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 100, 100),
		Parent = model,
	})
	weld(chassis, body)

	local meshBody, meshGlass = attachMesh(model, body, tier)
	local usesMesh = meshBody ~= nil
	-- With a mesh, the box body stays as the invisible collision hull and cosmetics anchor.
	body.Transparency = if usesMesh then 1 else 0

	local boxGlass: BasePart? = nil
	if not usesMesh then
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
		boxGlass = windows
	end

	-- Headlights (the lamps are hidden under a mesh, but their SpotLights still shine).
	for _, side in { -1, 1 } do
		local lamp = newPart({
			Name = "Headlight",
			Size = Vector3.new(1.4, 0.8, 0.2),
			CFrame = body.CFrame * CFrame.new(side * (W / 2 - 1.2), -bodyHeight / 2 + 1, -L / 2 - 0.1),
			Color = Color3.fromRGB(255, 250, 220),
			Material = Enum.Material.Neon,
			Transparency = if usesMesh then 1 else 0,
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

	local axleX = W / 2 + WHEEL_WIDTH / 2 + 0.2
	local axleZ = L / 2 - 3
	local skidX = W / 2 - SKID_RADIUS
	local skidY = WHEEL_Y - WHEEL_RADIUS + SKID_RADIUS -- skid bottoms line up with the wheel bottoms
	for _, z in { -axleZ, axleZ } do
		for _, side in { -1, 1 } do
			buildWheel(model, chassis, Vector3.new(side * axleX, WHEEL_Y, z), z < 0)
			buildSkid(model, chassis, Vector3.new(side * skidX, skidY, z))
		end
	end

	-- Movers. With RelativeTo = Attachment0, a plane-mode LinearVelocity ignores
	-- Primary/SecondaryTangentAxis and uses the attachment's own axes instead: its X axis
	-- (Axis) is PlaneVelocity.X and its Y axis (SecondaryAxis) is PlaneVelocity.Y. So the
	-- attachment is rotated to X = right, Y = forward (the chassis's -Z). That leaves the
	-- chassis's up axis free, so gravity and kerbs still work.
	local rootAttachment = attachment(chassis, CFrame.new(), "Root")
	local planeAttachment =
		attachment(chassis, CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.zAxis), "DrivePlane")
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = planeAttachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.ForceLimitsEnabled = true
	drive.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	drive.PlaneVelocity = Vector2.zero -- X = sideways (kept at 0: no sliding), Y = forward speed
	drive.MaxForce = 0 -- set once the assembly mass is known
	drive.Parent = chassis

	-- World-relative, so X and Z stay 0 (the matatu can't roll or pitch over) and Y is the yaw.
	local turn = Instance.new("AngularVelocity")
	turn.Name = "Turn"
	turn.Attachment0 = rootAttachment
	turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.AngularVelocity = Vector3.zero
	turn.MaxTorque = 0
	turn.ReactionTorqueEnabled = false
	turn.Parent = chassis

	local cosmetics = Instance.new("Folder")
	cosmetics.Name = "Cosmetics"
	cosmetics.Parent = model

	local label = buildLabel(body, owner)

	-- Handling the client drive controller reads.
	model:SetAttribute("TopSpeed", tier.topSpeed)
	model:SetAttribute("ReverseSpeed", tier.reverseSpeed)
	model:SetAttribute("Acceleration", tier.acceleration)
	model:SetAttribute("BrakeDeceleration", tier.brakeDeceleration)
	model:SetAttribute("TurnRate", tier.turnRate)
	model:SetAttribute("TurnRadius", tier.turnRadius)
	model:SetAttribute("Wheelbase", axleZ * 2)
	model:SetAttribute("WheelRadius", WHEEL_RADIUS)
	model:SetAttribute("RideHeight", WHEEL_RADIUS - WHEEL_Y)

	model.Parent = vehiclesFolder

	local mass = chassis.AssemblyMass
	drive.MaxForce = mass * PARK_FORCE
	turn.MaxTorque = mass * LEVEL_TORQUE

	return {
		owner = owner,
		tier = tier,
		model = model,
		chassis = chassis,
		body = body,
		seat = seat,
		drive = drive,
		turn = turn,
		parked = true,
		lastUnstick = 0,
		cosmetics = cosmetics,
		label = label,
		ledParts = {},
		paintPart = meshBody or body,
		glassPart = meshGlass or boxGlass,
		usesMesh = usesMesh,
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
	record.paintPart.Color = record.tier.bodyColor
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
		record.paintPart.Color = Color3.fromRGB(20, 20, 26)
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
	local windows = record.glassPart
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
		local velocity = record.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude -- falling doesn't count
		local topSpeed = tier.topSpeed

		-- While someone drives, their client owns the physics and sets the movers every frame
		-- (Controllers/Drive.luau). An unattended matatu gets the parking brake from here: hold
		-- still and stay level. Written only on the transition, so it doesn't spam replication.
		if driving then
			record.parked = false
		elseif not record.parked then
			record.parked = true
			local mass = record.chassis.AssemblyMass
			record.drive.PlaneVelocity = Vector2.zero
			record.drive.MaxForce = mass * PARK_FORCE
			record.turn.AngularVelocity = Vector3.zero
			record.turn.MaxTorque = mass * LEVEL_TORQUE
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

local function flatten(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Ground height under a point, ignoring every matatu and character.
local function groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else 0
end

-- Closest point on the road centre line and the road's direction there (pointing the way the
-- matatu already faces).
local function nearestRoadPoint(position: Vector3, facing: Vector3): (Vector3, Vector3)
	local best, bestDir, bestDistance = World.RoadPath[1], Vector3.new(1, 0, 0), math.huge
	for i = 1, #World.RoadPath - 1 do
		local a, b = World.RoadPath[i], World.RoadPath[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local t = math.clamp(Vector3.new(position.X - a.X, 0, position.Z - a.Z):Dot(ab) / ab:Dot(ab), 0, 1)
		local point = a + ab * t
		local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if distance < bestDistance then
			best, bestDistance = point, distance
			bestDir = if ab.Unit:Dot(facing) >= 0 then ab.Unit else -ab.Unit
		end
	end
	return best, bestDir
end

-- Put a stuck matatu back on its wheels: level, slightly back from whatever it hit, or on the
-- nearest bit of road if every nearby spot overlaps a building. Passengers stay aboard.
local function unstick(record: VehicleRecord)
	local chassis = record.chassis
	local ignore: { Instance } = { vehiclesFolder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local crowds = workspace:FindFirstChild("Crowds")
	if crowds then
		table.insert(ignore, crowds)
	end

	local facing = flatten(chassis.CFrame.LookVector)
	local here = chassis.Position
	local rideHeight = (record.model:GetAttribute("RideHeight") :: number?) or 2.4
	local hull = Vector3.new(record.tier.width + 2, record.tier.height, record.tier.length + 2)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore

	local function fits(position: Vector3, look: Vector3): CFrame?
		local y = groundY(position, ignore)
		-- Check the space the body occupies, starting just above the ground so roads don't count.
		local centre = Vector3.new(position.X, y + 1 + hull.Y / 2, position.Z)
		local box = CFrame.lookAt(centre, centre + look)
		if #workspace:GetPartBoundsInBox(box, hull, overlap) > 0 then
			return nil
		end
		local at = Vector3.new(position.X, y + rideHeight + 0.6, position.Z)
		return CFrame.lookAt(at, at + look)
	end

	local target = fits(here, facing) or fits(here - facing * 8, facing) or fits(here + facing * 8, facing)
	if not target then
		local point, direction = nearestRoadPoint(here, facing)
		local y = groundY(point, ignore)
		local at = Vector3.new(point.X, y + rideHeight + 0.6, point.Z)
		target = CFrame.lookAt(at, at + direction)
	end

	record.model:PivotTo(target :: CFrame)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	record.upsideDownTime = 0
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

	Net.event("Unstick").OnServerEvent:Connect(function(player: Player)
		local record = records[player]
		if not record or not VehicleService.isDriving(player) then
			return
		end
		local now = os.clock()
		if now - record.lastUnstick < UNSTICK_COOLDOWN then
			Net.event("Notify"):FireClient(player, "Unstick is cooling down", "info")
			return
		end
		record.lastUnstick = now
		unstick(record)
	end)

	-- Get back into your own matatu (after hopping out with Space, for example).
	local enterLimiter = Net.rateLimiter(1, 2)
	Net.event("EnterVehicle").OnServerEvent:Connect(function(player: Player)
		if not enterLimiter:allow(player) then
			return
		end
		local record = records[player]
		local humanoid = playerCharacterHumanoid(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not record or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end
		if record.seat.Occupant or humanoid.SeatPart then
			return
		end
		if (root.Position - record.chassis.Position).Magnitude > ENTER_DISTANCE then
			return
		end
		record.seat:Sit(humanoid)
	end)

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.despawn(player)
	end)

	RunService.Heartbeat:Connect(step)
end

return VehicleService
