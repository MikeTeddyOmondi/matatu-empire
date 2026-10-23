--!strict
-- The garage panel: Vibe upgrades and matatu tiers. It only sends requests; the server checks
-- prices, levels and ownership.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)
local Vehicles = require(Shared.Config.Vehicles)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)

local Garage = {}

local player = Players.LocalPlayer

type Row = { title: TextLabel, detail: TextLabel, button: TextButton }

local function makeRow(parent: Instance, order: number): Row
	local row = UI.create("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = UI.Colors.panelLight,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(10), UI.padding(10) })
	local title = UI.label({
		Size = UDim2.new(1, -140, 0, 22),
		TextSize = 17,
		Parent = row,
	})
	local detail = UI.label({
		Size = UDim2.new(1, -140, 0, 18),
		Position = UDim2.fromOffset(0, 24),
		TextSize = 14,
		Font = UI.Fonts.body,
		TextColor3 = UI.Colors.muted,
		Parent = row,
	})
	local button = UI.button({
		Size = UDim2.fromOffset(126, 40),
		Position = UDim2.new(1, -126, 0.5, -20),
		TextSize = 15,
		Parent = row,
	})
	return { title = title, detail = detail, button = button }
end

local function request(remoteName: string, arg: any)
	local ok, message = Net.func(remoteName):InvokeServer(arg)
	Hud.toast(message, if ok then "money" else "warn")
end

function Garage.start()
	local gui = UI.create("ScreenGui", {
		Name = "Garage",
		ResetOnSpawn = false,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local panel = UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 560),
		BackgroundColor3 = UI.Colors.panel,
		Parent = gui,
	}, {
		UI.corner(16),
		UI.padding(16),
		UI.create("UISizeConstraint", { MaxSize = Vector2.new(520, 560) }),
	})
	UI.label({
		Size = UDim2.new(1, -50, 0, 34),
		Text = "GARAGE",
		Font = UI.Fonts.heavy,
		TextSize = 28,
		TextColor3 = UI.Colors.accent,
		Parent = panel,
	})
	local close = UI.button({
		Size = UDim2.fromOffset(40, 34),
		Position = UDim2.new(1, -40, 0, 0),
		Text = "X",
		BackgroundColor3 = UI.Colors.panelLight,
		TextColor3 = UI.Colors.text,
		Parent = panel,
	})
	local list = UI.create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		UI.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local order = 0
	local function heading(text: string)
		order += 1
		UI.label({
			Size = UDim2.new(1, 0, 0, 26),
			Text = text,
			Font = UI.Fonts.heavy,
			TextSize = 18,
			TextColor3 = UI.Colors.pink,
			LayoutOrder = order,
			Parent = list,
		})
	end

	heading("VIBE UPGRADES")
	local upgradeRows: { [string]: Row } = {}
	for _, slot in Upgrades.Slots do
		order += 1
		local row = makeRow(list, order)
		upgradeRows[slot.id] = row
		row.button.Activated:Connect(function()
			request("BuyUpgrade", slot.id)
		end)
	end

	heading("MATATUS")
	local vehicleRows: { [number]: Row } = {}
	for _, tier in Vehicles do
		order += 1
		local row = makeRow(list, order)
		vehicleRows[tier.tier] = row
		row.button.Activated:Connect(function()
			local state = State.get()
			if state and table.find(state.ownedTiers, tier.tier) then
				request("EquipVehicle", tier.tier)
			else
				request("BuyVehicle", tier.tier)
			end
		end)
	end

	State.subscribe(function(state: Types.ClientState)
		for _, slot in Upgrades.Slots do
			local row = upgradeRows[slot.id]
			local owned = state.upgrades[slot.id] or 0
			local current = slot.levels[owned]
			local nextLevel = slot.levels[owned + 1]
			row.title.Text = `{slot.displayName}  ·  {owned}/{#slot.levels}`
			if nextLevel then
				row.detail.Text = if current
					then `{current.label} → {nextLevel.label}`
					else `Next: {nextLevel.label}`
				row.button.Text = `{UI.formatBob(nextLevel.cost)} Bob`
				local affordable = state.bob >= nextLevel.cost
				row.button.BackgroundColor3 = if affordable then UI.Colors.accent else UI.Colors.panel
				row.button.TextColor3 = if affordable then Color3.fromRGB(20, 20, 20) else UI.Colors.muted
				row.button.AutoButtonColor = affordable
			else
				row.detail.Text = current and current.label or ""
				row.button.Text = "MAXED"
				row.button.BackgroundColor3 = UI.Colors.green
				row.button.TextColor3 = Color3.fromRGB(20, 20, 20)
				row.button.AutoButtonColor = false
			end
		end
		for _, tier in Vehicles do
			local row = vehicleRows[tier.tier]
			local owned = table.find(state.ownedTiers, tier.tier) ~= nil
			row.title.Text = tier.displayName
			row.detail.Text = `{tier.seats} seats  ·  unlocks at level {tier.unlockLevel}`
			if owned and state.equippedTier == tier.tier then
				row.button.Text = "DRIVING"
				row.button.BackgroundColor3 = UI.Colors.green
			elseif owned then
				row.button.Text = "EQUIP"
				row.button.BackgroundColor3 = UI.Colors.cyan
			elseif state.level < tier.unlockLevel then
				row.button.Text = `Lvl {tier.unlockLevel}`
				row.button.BackgroundColor3 = UI.Colors.panel
			else
				row.button.Text = `{UI.formatBob(tier.cost)} Bob`
				row.button.BackgroundColor3 = if state.bob >= tier.cost then UI.Colors.accent else UI.Colors.panel
			end
			row.button.TextColor3 = if row.button.BackgroundColor3 == UI.Colors.panel
				then UI.Colors.muted
				else Color3.fromRGB(20, 20, 20)
		end
	end)

	local function toggle()
		gui.Enabled = not gui.Enabled
	end
	close.Activated:Connect(toggle)
	Hud.actions.garage = toggle
end

return Garage
