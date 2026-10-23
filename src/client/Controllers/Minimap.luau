--!strict
-- A north-up map of the whole city: roads, stages (in district colours), you, your destination
-- and the next checkpoint. Press M (or tap the map) to switch between small, large and hidden.
-- Drawn entirely from Config/World, so it works even where the city hasn't streamed in yet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Types = require(Shared.Types)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Minimap = {}

local player = Players.LocalPlayer

local SIZES = { small = 210, large = 560 }

function Minimap.start()
	local gui = UI.create("ScreenGui", {
		Name = "Minimap",
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local frame = UI.create("TextButton", {
		Name = "Map",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(70, 100, 60),
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		Parent = gui,
	}, { UI.corner(12), UI.stroke(UI.Colors.panel, 3) })

	local extent = World.Bounds.max - World.Bounds.min
	local canvas = UI.create("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})

	-- World position -> 0..1 within the map (north up).
	local function toScale(position: Vector3): (number, number)
		return (position.X - World.Bounds.min.X) / extent.X, (position.Z - World.Bounds.min.Z) / extent.Z
	end

	type Drawn = { frame: Frame, a: Vector3, b: Vector3, width: number }
	local roads: { Drawn } = {}
	for _, segment in World.Segments do
		local road = UI.create("Frame", {
			BackgroundColor3 = if segment.road.kind == "highway" then Color3.fromRGB(250, 240, 200) else Color3.fromRGB(230, 230, 230),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = canvas,
		})
		table.insert(roads, { frame = road, a = segment.a, b = segment.b, width = segment.width })
	end

	local stageDots: { [string]: { dot: Frame, label: TextLabel } } = {}
	for id, stage in World.Stages do
		local x, y = toScale(stage.position)
		local dot = UI.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = stage.color,
			ZIndex = 3,
			Parent = canvas,
		}, { UI.create("UICorner", { CornerRadius = UDim.new(1, 0) }), UI.stroke(Color3.new(0, 0, 0), 1) })
		local label = UI.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(x, 0, y, -6),
			Size = UDim2.fromOffset(140, 16),
			Text = stage.displayName,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			ZIndex = 4,
			Parent = canvas,
		})
		stageDots[id] = { dot = dot, label = label }
	end

	local function marker(color: Color3, size: number, z: number): Frame
		return UI.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			Visible = false,
			ZIndex = z,
			Parent = canvas,
		}, { UI.create("UICorner", { CornerRadius = UDim.new(1, 0) }), UI.stroke(Color3.new(0, 0, 0), 2) })
	end
	local destination = marker(UI.Colors.green, 14, 5)
	local checkpoint = marker(UI.Colors.accent, 10, 5)
	local me = UI.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Text = "▲",
		TextColor3 = UI.Colors.pink,
		TextStrokeTransparency = 0,
		TextScaled = true,
		Font = UI.Fonts.heavy,
		ZIndex = 6,
		Parent = canvas,
	})

	local mode = "small"
	local function layout()
		gui.Enabled = mode ~= "hidden"
		local side = SIZES[mode] or SIZES.small
		local width = side
		local height = side * extent.Z / extent.X
		if mode == "large" then
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
		else
			frame.AnchorPoint = Vector2.new(0, 0)
			frame.Position = UDim2.fromOffset(12, 252)
		end
		frame.Size = UDim2.fromOffset(width, height)
		local scale = width / extent.X
		for _, road in roads do
			local x1, y1 = toScale(road.a)
			local x2, y2 = toScale(road.b)
			local dx, dy = (x2 - x1) * width, (y2 - y1) * height
			road.frame.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
			road.frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + road.width * scale, math.max(2, road.width * scale))
			road.frame.Rotation = math.deg(math.atan2(dy, dx))
		end
		for _, entry in stageDots do
			entry.label.Visible = mode == "large"
		end
	end
	layout()

	local function cycle()
		mode = if mode == "small" then "large" elseif mode == "large" then "hidden" else "small"
		layout()
	end
	frame.Activated:Connect(cycle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			cycle()
		end
	end)

	local current: Types.ClientState? = nil
	State.subscribe(function(state: Types.ClientState)
		current = state
	end)

	RunService.RenderStepped:Connect(function()
		if mode == "hidden" then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local x, y = toScale(root.Position)
			me.Position = UDim2.fromScale(x, y)
			local look = root.CFrame.LookVector
			me.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
		local state = current
		if state and state.destinationId and World.Stages[state.destinationId] then
			local x, y = toScale(World.Stages[state.destinationId].position)
			destination.Position = UDim2.fromScale(x, y)
			destination.Visible = true
		else
			destination.Visible = false
		end
		if state and state.nextCheckpoint then
			local x, y = toScale(state.nextCheckpoint)
			checkpoint.Position = UDim2.fromScale(x, y)
			checkpoint.Visible = true
		else
			checkpoint.Visible = false
		end
	end)
end

return Minimap
