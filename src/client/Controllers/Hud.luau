--!strict
-- Money, level, Vibe, trip status, action buttons and toast notifications.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Hud = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local toastList: Frame

-- Callbacks other controllers register for the action buttons.
Hud.actions = {
	tout = function() end,
	garage = function() end,
}

local function toast(text: string, kind: string?)
	local color = UI.Colors.text
	if kind == "money" then
		color = UI.Colors.green
	elseif kind == "level" then
		color = UI.Colors.accent
	elseif kind == "warn" then
		color = UI.Colors.danger
	end
	local item = UI.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = UI.Colors.panel,
		BackgroundTransparency = 0.1,
		TextColor3 = color,
		Font = UI.Fonts.bold,
		TextSize = 17,
		TextWrapped = true,
		Text = text,
		Parent = toastList,
	}, { UI.corner(8), UI.padding(6) })
	task.delay(3.5, function()
		local tween = TweenService:Create(
			item,
			TweenInfo.new(0.4),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		item:Destroy()
	end)
end
Hud.toast = toast

local function formatClock(clock: number): string
	local hours = math.floor(clock)
	local minutes = math.floor((clock - hours) * 60)
	return string.format("%02d:%02d", hours, minutes)
end

function Hud.start()
	gui = UI.create("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Wallet card (top-left)
	local wallet = UI.create("Frame", {
		Size = UDim2.fromOffset(250, 112),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = UI.Colors.panel,
		BackgroundTransparency = 0.08,
		Parent = gui,
	}, { UI.corner(12), UI.padding(10) })
	local bobLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "Bob 0",
		Font = UI.Fonts.heavy,
		TextSize = 26,
		TextColor3 = UI.Colors.accent,
		Parent = wallet,
	})
	local levelLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 34),
		Text = "Level 1",
		TextSize = 16,
		Parent = wallet,
	})
	local xpTrack = UI.create("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		Position = UDim2.fromOffset(0, 58),
		BackgroundColor3 = UI.Colors.panelLight,
		Parent = wallet,
	}, { UI.corner(4) })
	local xpFill = UI.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = UI.Colors.accent,
		Parent = xpTrack,
	}, { UI.corner(4) })
	local vibeLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 72),
		Text = "Vibe 0 / 100",
		TextSize = 16,
		TextColor3 = UI.Colors.pink,
		Parent = wallet,
	})

	-- Clock and rush-hour banner (top-centre)
	local clockLabel = UI.label({
		Size = UDim2.fromOffset(220, 32),
		Position = UDim2.new(0.5, -110, 0, 12),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = UI.Colors.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.heavy,
		TextSize = 18,
		Parent = gui,
	})
	UI.corner(10).Parent = clockLabel

	-- Trip panel (bottom-centre)
	local tripPanel = UI.label({
		Size = UDim2.fromOffset(460, 54),
		Position = UDim2.new(0.5, -230, 1, -150),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = UI.Colors.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextSize = 18,
		Parent = gui,
	})
	UI.corner(12).Parent = tripPanel

	-- Action buttons (right side) — also work as tap targets on mobile.
	local actions = UI.create("Frame", {
		Size = UDim2.fromOffset(170, 230),
		Position = UDim2.new(1, -182, 0.5, -115),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local spawnButton = UI.button({
		Size = UDim2.new(1, 0, 0, 48),
		Text = "Get matatu",
		LayoutOrder = 1,
		Parent = actions,
	})
	local toutButton = UI.button({
		Size = UDim2.new(1, 0, 0, 48),
		Text = "Tout  [T]",
		BackgroundColor3 = UI.Colors.pink,
		TextColor3 = UI.Colors.text,
		LayoutOrder = 2,
		Parent = actions,
	})
	local garageButton = UI.button({
		Size = UDim2.new(1, 0, 0, 48),
		Text = "Garage  [G]",
		BackgroundColor3 = UI.Colors.cyan,
		LayoutOrder = 3,
		Parent = actions,
	})
	local hornButton = UI.button({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Horn  [H]",
		BackgroundColor3 = UI.Colors.panelLight,
		TextColor3 = UI.Colors.text,
		LayoutOrder = 4,
		Parent = actions,
	})

	toastList = UI.create("Frame", {
		Size = UDim2.fromOffset(320, 300),
		Position = UDim2.new(1, -332, 0, 12),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UI.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local spawning = false
	spawnButton.Activated:Connect(function()
		if spawning then
			return
		end
		spawning = true
		local ok, message = Net.func("SpawnVehicle"):InvokeServer()
		toast(message, if ok then "info" else "warn")
		spawning = false
	end)
	toutButton.Activated:Connect(function()
		Hud.actions.tout()
	end)
	garageButton.Activated:Connect(function()
		Hud.actions.garage()
	end)
	hornButton.Activated:Connect(function()
		Net.event("Horn"):FireServer()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			Hud.actions.garage()
		elseif input.KeyCode == Enum.KeyCode.H then
			Net.event("Horn"):FireServer()
		end
	end)

	State.subscribe(function(state: Types.ClientState)
		bobLabel.Text = `Bob {UI.formatBob(state.bob)}`
		levelLabel.Text = `Level {state.level}  ·  {state.xp} / {state.xpToNext} XP`
		xpFill.Size = UDim2.fromScale(math.clamp(state.xp / math.max(1, state.xpToNext), 0, 1), 1)
		vibeLabel.Text = `Vibe {state.vibe} / 100`
		spawnButton.Text = if state.hasVehicle then "Respawn matatu" else "Get matatu"

		if not state.hasVehicle then
			tripPanel.Text = "Tap \"Get matatu\" to start your empire"
		elseif not state.isDriving then
			tripPanel.Text = "Hop into the driver's seat"
		elseif state.passengersAboard > 0 and state.destination then
			tripPanel.Text = `{state.passengersAboard}/{state.seats} aboard  ·  Drive to {state.destination}`
		elseif state.atStage then
			tripPanel.Text = "You're at a stage: press T to tout for passengers!"
		else
			tripPanel.Text = "Drive into a stage zone, stop, and tout"
		end
	end)

	Net.event("Notify").OnClientEvent:Connect(toast)

	-- Clock updates locally from replicated Lighting.
	task.spawn(function()
		while true do
			local state = State.get()
			local rush = state and state.rushHour
			clockLabel.Text = if rush
				then `RUSH HOUR  {formatClock(Lighting.ClockTime)}`
				else formatClock(Lighting.ClockTime)
			clockLabel.TextColor3 = if rush then UI.Colors.accent else UI.Colors.text
			task.wait(0.5)
		end
	end)
end

return Hud
