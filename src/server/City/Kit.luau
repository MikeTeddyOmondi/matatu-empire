--!strict
-- Shared helpers for the city generator: part factory, palette, and an occupancy grid so
-- buildings, trees and landmarks never overlap each other, the roads or the stages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local Kit = {}

Kit.Colors = {
	asphalt = Color3.fromRGB(46, 48, 52),
	lane = Color3.fromRGB(235, 235, 230),
	median = Color3.fromRGB(240, 200, 40),
	sidewalk = Color3.fromRGB(176, 170, 158),
	concrete = Color3.fromRGB(170, 168, 160),
	grass = Color3.fromRGB(96, 140, 72),
	dirt = Color3.fromRGB(140, 104, 74),
	signGreen = Color3.fromRGB(20, 110, 60),
}

-- Generator output goes here; set by WorldService before building.
Kit.root = nil :: Folder?

function Kit.folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent or Kit.root
	return folder
end

-- Anchored part with the given properties. Decorative parts pass CanCollide = false.
function Kit.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent or Kit.root
	return p
end

-- A part that is only for looks: no collision, no raycasts, no touch events.
function Kit.decor(props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return Kit.part(props)
end

-- Flat disc (a cylinder lying down) centred at `position`, top face at `top`.
function Kit.disc(props: { [string]: any }, position: Vector3, radius: number, thickness: number, top: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(thickness, radius * 2, radius * 2)
	props.CFrame = CFrame.new(position.X, top - thickness / 2, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	return Kit.part(props)
end

-- Billboard text that always faces the camera.
function Kit.billboard(parent: Instance, text: string, color: Color3, size: UDim2, offset: Vector3, maxDistance: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = parent
end

-- Text painted on one face of a part.
function Kit.paint(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, background: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.MaxDistance = 260
	gui.LightInfluence = 0.3
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
end

function Kit.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Occupancy ---------------------------------------------------------------------------------------

-- Circles already claimed by something solid, bucketed in a coarse grid.
local CELL = 64
local grid: { [string]: { { x: number, z: number, r: number } } } = {}

local function key(cx: number, cz: number): string
	return `{cx},{cz}`
end

function Kit.claim(position: Vector3, radius: number)
	local item = { x = position.X, z = position.Z, r = radius }
	local x0, x1 = math.floor((position.X - radius) / CELL), math.floor((position.X + radius) / CELL)
	local z0, z1 = math.floor((position.Z - radius) / CELL), math.floor((position.Z + radius) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local k = key(cx, cz)
			grid[k] = grid[k] or {}
			table.insert(grid[k], item)
		end
	end
end

function Kit.isFree(position: Vector3, radius: number): boolean
	local x0, x1 = math.floor((position.X - radius) / CELL), math.floor((position.X + radius) / CELL)
	local z0, z1 = math.floor((position.Z - radius) / CELL), math.floor((position.Z + radius) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local bucket = grid[key(cx, cz)]
			if bucket then
				for _, item in bucket do
					local dx, dz = position.X - item.x, position.Z - item.z
					if dx * dx + dz * dz < (radius + item.r) ^ 2 then
						return false
					end
				end
			end
		end
	end
	return true
end

-- Free of roads (with `setback` studs of pavement) and of everything already claimed.
function Kit.canPlace(position: Vector3, radius: number, setback: number): boolean
	return World.distanceToRoadEdge(position) >= radius + setback and Kit.isFree(position, radius)
end

-- Push a point away from the nearest road until a circle of `radius` clears it by `setback`.
function Kit.clearOfRoads(position: Vector3, radius: number, setback: number): Vector3
	local p = position
	for _ = 1, 40 do
		local gap = World.distanceToRoadEdge(p) - radius - setback
		if gap >= 0 then
			return p
		end
		local nearest = World.nearestRoadPoint(p)
		local away = Kit.flat(p - nearest)
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(1, 0, 0)
		p += away * (-gap + 2)
	end
	return p
end

function Kit.reset()
	table.clear(grid)
end

return Kit
