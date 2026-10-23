--!strict
-- The touting rhythm minigame. The server sends beat times; we show an approach ring for each
-- beat and record when the player shouts. The server scores the presses, not this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local UI = require(script.Parent.UI)
local Hud = require(script.Parent.Hud)

local Tout = {}

local player = Players.LocalPlayer
local SHOUTS = { "Tao! Tao!", "Estates, mbili mbili!", "Panda gari!", "Ingia ingia!", "Tunaenda!" }

local gui: ScreenGui
local panel: Frame
local ring: Frame
local approach: Frame
local feedback: TextLabel
local shoutButton: TextButton

local active: Types.ToutRound? = nil
local presses: { number } = {}
local requesting = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flash(text: string, color: Color3)
	feedback.Text = text
	feedback.TextColor3 = color
	feedback.TextTransparency = 0
	TweenService:Create(feedback, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
end

local function shout()
	local round = active
	if not round then
		return
	end
	local t = now()
	table.insert(presses, t)

	-- Local feedback only; the server decides what actually counts.
	local best = math.huge
	for _, beat in round.beats do
		best = math.min(best, math.abs(t - beat))
	end
	if best <= round.perfectWindow then
		flash("PERFECT!", UI.Colors.green)
	elseif best <= round.goodWindow then
		flash("GOOD", UI.Colors.accent)
	else
		flash("MISS", UI.Colors.danger)
	end
	shoutButton.Text = SHOUTS[math.random(1, #SHOUTS)]
end

local function finish(round: Types.ToutRound)
	if active ~= round then
		return
	end
	active = nil
	Net.event("SubmitTout"):FireServer(round.roundId, presses)
	task.delay(0.6, function()
		if not active then
			panel.Visible = false
		end
	end)
end

local function begin()
	if active or requesting then
		return
	end
	requesting = true
	local round = Net.func("StartTout"):InvokeServer() :: Types.ToutRound?
	requesting = false
	if not round then
		return
	end
	active = round
	presses = {}
	panel.Visible = true
	shoutButton.Text = "SHOUT!"
	feedback.TextTransparency = 1

	local lastBeat = round.beats[#round.beats]
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if active ~= round then
			connection:Disconnect()
			return
		end
		local t = now()
		-- Find the next beat that hasn't passed its good window.
		local nextBeat: number? = nil
		for _, beat in round.beats do
			if beat + round.goodWindow >= t then
				nextBeat = beat
				break
			end
		end
		if nextBeat then
			local untilBeat = nextBeat - t
			-- The approach ring shrinks from 3x to 1x over the 0.8 s before the beat.
			local scale = 1 + math.clamp(untilBeat / 0.8, 0, 1) * 2
			approach.Size = UDim2.fromScale(scale, scale)
			approach.Visible = untilBeat < 0.8
			local inWindow = math.abs(untilBeat) <= round.goodWindow
			ring.BackgroundColor3 = if inWindow then UI.Colors.accent else UI.Colors.panelLight
		else
			approach.Visible = false
		end
		if t > lastBeat + 0.4 then
			connection:Disconnect()
			finish(round)
		end
	end)
end

function Tout.start()
	gui = UI.create("ScreenGui", {
		Name = "Tout",
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	panel = UI.create("Frame", {
		Size = UDim2.fromOffset(300, 300),
		Position = UDim2.new(0.5, -150, 0.5, -170),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UI.label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, -6),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.heavy,
		TextSize = 22,
		Text = "SHOUT when the ring lands!",
		TextStrokeTransparency = 0.4,
		Parent = panel,
	})
	ring = UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = UI.Colors.panelLight,
		BackgroundTransparency = 0.15,
		Parent = panel,
	}, { UI.corner(55), UI.stroke(UI.Colors.accent, 4) })
	approach = UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(3, 3),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = ring,
	}, { UI.create("UICorner", { CornerRadius = UDim.new(1, 0) }), UI.stroke(UI.Colors.pink, 4) })
	feedback = UI.label({
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.5, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Fonts.heavy,
		TextSize = 30,
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		Parent = panel,
	})
	shoutButton = UI.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, 0, 1, 10),
		BackgroundColor3 = UI.Colors.pink,
		TextColor3 = UI.Colors.text,
		TextSize = 22,
		Text = "SHOUT!",
		Parent = panel,
	})
	shoutButton.Activated:Connect(shout)

	Hud.actions.tout = function()
		if active then
			shout()
		else
			begin()
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.T or input.KeyCode == Enum.KeyCode.E then
			if active then
				shout()
			elseif input.KeyCode == Enum.KeyCode.T then
				begin()
			end
		end
	end)

	Net.event("ToutResult").OnClientEvent:Connect(function(boarded: number, perfect: number, good: number)
		if boarded > 0 then
			Hud.toast(`{boarded} passengers boarded! ({perfect} perfect, {good} good)`, "money")
		else
			Hud.toast("Nobody bought it. Try again!", "warn")
		end
	end)
end

return Tout
