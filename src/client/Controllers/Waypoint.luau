--!strict
-- A tall beacon at the next checkpoint (or destination stage) so drivers always know where to go.
-- Purely visual and local; the server tracks checkpoints itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Waypoint = {}

local player = Players.LocalPlayer

function Waypoint.start()
	local beacon = Instance.new("Part")
	beacon.Name = "WaypointBeacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = UI.Colors.accent
	beacon.Transparency = 0.45
	beacon.Size = Vector3.new(4, 60, 4)
	beacon.Shape = Enum.PartType.Block

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 34, 0)
	gui.AlwaysOnTop = true
	local label = UI.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.heavy,
		TextSize = 20,
		TextColor3 = UI.Colors.accent,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})
	gui.Parent = beacon

	local target: Vector3? = nil
	local destination: string? = nil

	State.subscribe(function(state: Types.ClientState)
		target = state.nextCheckpoint
		destination = state.destination
		if target then
			beacon.Position = target + Vector3.new(0, 30, 0)
			beacon.Parent = workspace
		else
			beacon.Parent = nil
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not target or not beacon.Parent then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = math.floor((root.Position - target).Magnitude)
			label.Text = `{destination or "Next"} · {distance}m`
		end
		-- Gentle pulse so it reads as a marker, not a building.
		beacon.Transparency = 0.45 + math.sin(os.clock() * 4) * 0.15
	end)
end

return Waypoint
