--!strict
-- Studio-only camera tool for capturing store thumbnails and the gameplay video from the real
-- game. Does nothing in a live server.
--
--   P   next photo shot (HUD hidden) - take a screenshot for a thumbnail
--   K   play the fly-through (HUD hidden) - screen-record it for the video
--   O   back to the normal camera and HUD
--
-- Shots are placed from Config/World, so they follow the map if it changes. For clean captures
-- untick Workspace.StreamingEnabled in Studio first (don't save that), so distant parts load.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local Cinematic = {}

local player = Players.LocalPlayer

type Shot = { name: string, from: Vector3, to: Vector3, fov: number? }

local function node(id: string): Vector3
	return World.Nodes[id].position
end

local function stage(id: string): World.Stage
	return World.Stages[id]
end

local function landmark(id: string): Vector3
	for _, item in World.Landmarks do
		if item.id == id then
			return item.position
		end
	end
	return Vector3.zero
end

local UP = Vector3.yAxis

-- Photo shots: a camera position and a point to look at.
local function photoShots(): { Shot }
	local railways = stage("Railways")
	local westlands = stage("Westlands")
	local kibera = stage("Kibera")
	local kawangware = stage("Kawangware")
	local kicc = landmark("kicc")
	return {
		{
			name = "Railways stage, CBD",
			from = railways.position + railways.side * 14 - railways.roadDirection * 40 + UP * 8,
			to = railways.position + railways.roadDirection * 80 + UP * 10,
		},
		{
			name = "Uhuru Highway from above",
			from = node("haileSelassieRb") + UP * 70 - (node("museumHill") - node("haileSelassieRb")).Unit * 60,
			to = node("universityWayRb") + UP * 10,
			fov = 60,
		},
		{ name = "KICC", from = kicc + Vector3.new(-110, 30, 90), to = kicc + UP * 60, fov = 55 },
		{
			name = "Westlands, Waiyaki Way",
			from = node("westlandsRb") + UP * 14 + (node("westlandsRb") - westlands.position).Unit * 30,
			to = westlands.position + UP * 20,
		},
		{ name = "Kibera rooftops", from = kibera.position + kibera.side * 120 + UP * 45, to = kibera.position + UP * 4, fov = 55 },
		{
			name = "Kawangware street",
			from = kawangware.position + kawangware.side * 10 - kawangware.roadDirection * 50 + UP * 7,
			to = kawangware.position + kawangware.roadDirection * 60 + UP * 6,
		},
		{ name = "Ngong Road", from = node("adams") + UP * 12 + Vector3.new(-30, 0, 20), to = node("prestige") + UP * 8 },
		{ name = "City overview", from = node("kenyattaRb") + Vector3.new(-700, 380, 600), to = node("hurlinghamRb"), fov = 50 },
	}
end

-- The fly-through: each leg glides from one shot to the next.
local LEG_SECONDS = 6

local hiddenGuis: { ScreenGui } = {}
local running = false
local photoIndex = 0
local playToken = 0

local function hideHud()
	if #hiddenGuis > 0 then
		return
	end
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled then
			gui.Enabled = false
			table.insert(hiddenGuis, gui)
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
end

local function restore()
	playToken += 1
	running = false
	for _, gui in hiddenGuis do
		gui.Enabled = true
	end
	table.clear(hiddenGuis)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

local function streamAround(position: Vector3)
	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(position, 2)
		end)
	end
end

local function place(shot: Shot)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = shot.fov or 70
	camera.CFrame = CFrame.lookAt(shot.from, shot.to)
end

local function nextPhoto()
	local shots = photoShots()
	photoIndex = photoIndex % #shots + 1
	local shot = shots[photoIndex]
	hideHud()
	streamAround(shot.to)
	place(shot)
	print(`[Cinematic] photo {photoIndex}/{#shots}: {shot.name}`)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function flyThrough()
	if running then
		return
	end
	running = true
	playToken += 1
	local token = playToken
	hideHud()
	local shots = photoShots()
	task.spawn(function()
		for i = 1, #shots - 1 do
			local a, b = shots[i], shots[i + 1]
			streamAround(b.to)
			local started = os.clock()
			while os.clock() - started < LEG_SECONDS do
				if token ~= playToken then
					return
				end
				local t = smooth((os.clock() - started) / LEG_SECONDS)
				local camera = workspace.CurrentCamera
				camera.CameraType = Enum.CameraType.Scriptable
				local from = a.from:Lerp(b.from, t)
				local to = a.to:Lerp(b.to, t)
				camera.FieldOfView = (a.fov or 70) + ((b.fov or 70) - (a.fov or 70)) * t
				camera.CFrame = CFrame.lookAt(from, to)
				RunService.RenderStepped:Wait()
			end
		end
		if token == playToken then
			print("[Cinematic] fly-through finished; press O to return")
			running = false
		end
	end)
end

function Cinematic.start()
	if not RunService:IsStudio() then
		return
	end
	if workspace.StreamingEnabled then
		print("[Cinematic] tip: untick Workspace.StreamingEnabled while capturing so the whole city loads")
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			nextPhoto()
		elseif input.KeyCode == Enum.KeyCode.K then
			flyThrough()
		elseif input.KeyCode == Enum.KeyCode.O then
			restore()
		end
	end)
end

return Cinematic
