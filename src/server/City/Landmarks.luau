--!strict
-- Recognisable places: KICC, Uhuru Park, Nyayo Stadium, Kenyatta National Hospital, the malls
-- and the railway through Kibera. Simple shapes, placed clear of the roads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local Kit = require(script.Parent.Kit)
local Roads = require(script.Parent.Roads)

local Landmarks = {}

local TOP = World.RoadTop

-- Facing the nearest road, so fronts and signs look at the traffic.
local function facingRoad(position: Vector3): CFrame
	local nearest = World.nearestRoadPoint(position)
	local look = Kit.flat(nearest - position)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + look.Unit)
end

local function kicc(model: Model, at: Vector3)
	local terracotta = Color3.fromRGB(176, 92, 60)
	-- The conical amphitheatre beside the tower.
	Kit.disc({ Name = "Amphitheatre", Color = terracotta, Material = Enum.Material.Brick, Parent = model }, at + Vector3.new(28, 0, 8), 16, 10, 10)
	Kit.disc({ Name = "AmphitheatreRoof", Color = Color3.fromRGB(150, 74, 48), Material = Enum.Material.Slate, Parent = model }, at + Vector3.new(28, 0, 8), 12, 6, 15)
	-- The tower with its saucer-shaped helipad on top.
	local height = 105
	Kit.part({
		Name = "Tower",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 20, 20),
		CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = terracotta,
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	for floor = 6, height - 6, 5 do
		Kit.decor({
			Name = "Windows",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 20.3, 20.3),
			CFrame = CFrame.new(at + Vector3.new(0, floor, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(40, 50, 60),
			Material = Enum.Material.Glass,
			Parent = model,
		})
	end
	Kit.disc({ Name = "Saucer", Color = Color3.fromRGB(200, 120, 80), Material = Enum.Material.Concrete, Parent = model }, at, 18, 4, height + 4)
	Kit.disc({ Name = "Helipad", Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Concrete, Parent = model }, at, 14, 0.4, height + 4.3)
	local sign = Kit.decor({
		Name = "Label",
		Size = Vector3.one,
		Position = at + Vector3.new(0, height + 6, 0),
		Transparency = 1,
		Parent = model,
	})
	Kit.billboard(sign, "KICC", Color3.fromRGB(255, 196, 0), UDim2.fromOffset(120, 40), Vector3.new(0, 4, 0), 900)
	Kit.claim(at + Vector3.new(10, 0, 4), 40)
end

local function park(model: Model, at: Vector3, rng: Random)
	local radius = 105
	Kit.disc({ Name = "Lawn", Color = Color3.fromRGB(110, 165, 80), Material = Enum.Material.Grass, CanCollide = false, Parent = model }, at, radius, 0.2, 0.12)
	Kit.decor({
		Name = "Lake",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 70, 40),
		CFrame = CFrame.new(at + Vector3.new(-15, 0.2, 10)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(60, 120, 170),
		Material = Enum.Material.Glass,
		Transparency = 0.1,
		Parent = model,
	})
	Kit.claim(at, radius)
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(35, radius - 8)
		local spot = at + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if World.distanceToRoadEdge(spot) > 8 then
			Roads.tree(model, spot, rng, rng:NextNumber(1, 1.5))
		end
	end
	local sign = Kit.decor({ Name = "Label", Size = Vector3.one, Position = at + Vector3.new(0, 20, 0), Transparency = 1, Parent = model })
	Kit.billboard(sign, "UHURU PARK", Color3.fromRGB(118, 255, 3), UDim2.fromOffset(200, 40), Vector3.zero, 600)
end

local function stadium(model: Model, at: Vector3)
	Kit.disc({ Name = "Pitch", Color = Color3.fromRGB(70, 150, 60), Material = Enum.Material.Grass, CanCollide = false, Parent = model }, at, 34, 0.2, 0.15)
	Kit.disc({ Name = "Track", Color = Color3.fromRGB(180, 70, 50), Material = Enum.Material.Fabric, CanCollide = false, Parent = model }, at, 44, 0.2, 0.1)
	-- Stands: a ring of raked blocks.
	local count = 28
	for i = 0, count - 1 do
		local angle = i / count * 2 * math.pi
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local base = CFrame.lookAt(at + dir * 54, at)
		Kit.part({
			Name = "Stand",
			Size = Vector3.new(12.5, 14, 16),
			CFrame = base * CFrame.new(0, 7, 0) * CFrame.Angles(math.rad(-20), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(220, 220, 215) else Color3.fromRGB(30, 110, 60),
			Material = Enum.Material.Concrete,
			Parent = model,
		})
	end
	for i = 0, 3 do
		local angle = (i + 0.5) / 4 * 2 * math.pi
		local spot = at + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 66
		Kit.decor({ Name = "Floodlight", Size = Vector3.new(1, 40, 1), Position = spot + Vector3.new(0, 20, 0), Color = Color3.fromRGB(90, 90, 94), Material = Enum.Material.Metal, Parent = model })
		local lamp = Kit.decor({ Name = "Lamps", Size = Vector3.new(6, 3, 1), Position = spot + Vector3.new(0, 41, 0), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, Parent = model })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 60
		light.Brightness = 1
		light.Parent = lamp
	end
	local sign = Kit.decor({ Name = "Label", Size = Vector3.one, Position = at + Vector3.new(0, 30, 0), Transparency = 1, Parent = model })
	Kit.billboard(sign, "NYAYO STADIUM", Color3.fromRGB(255, 255, 255), UDim2.fromOffset(220, 40), Vector3.zero, 700)
	Kit.claim(at, 72)
end

local function building(model: Model, at: Vector3, size: Vector3, name: string, color: Color3, glassFront: boolean, signColor: Color3)
	local frame = facingRoad(at)
	local body = Kit.part({
		Name = "Building",
		Size = size,
		CFrame = frame * CFrame.new(0, size.Y / 2, 0),
		Color = color,
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	if glassFront then
		Kit.decor({
			Name = "Glass",
			Size = Vector3.new(size.X - 4, size.Y - 6, 0.3),
			CFrame = frame * CFrame.new(0, size.Y / 2 + 1, -size.Z / 2 - 0.15),
			Color = Color3.fromRGB(70, 110, 140),
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
			Parent = model,
		})
	end
	local sign = Kit.decor({
		Name = "Sign",
		Size = Vector3.new(math.min(size.X - 4, 36), 5, 0.4),
		CFrame = frame * CFrame.new(0, size.Y + 3, -size.Z / 2 + 1),
		Color = Color3.fromRGB(250, 250, 245),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	Kit.paint(sign, Enum.NormalId.Front, name, signColor)
	-- A tarmac forecourt between the building and the road.
	local forecourt = frame * CFrame.new(0, 0, -size.Z / 2 - 10)
	Kit.part({
		Name = "Forecourt",
		Size = Vector3.new(size.X, 1, 18),
		CFrame = forecourt * CFrame.new(0, TOP - 0.45, 0),
		Color = Color3.fromRGB(70, 72, 76),
		Material = Enum.Material.Asphalt,
		Parent = model,
	})
	Kit.claim(at, math.max(size.X, size.Z) / 2 + 4)
	return body
end

local function railway(model: Model, points: { Vector3 })
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = Kit.flat(b - a).Magnitude
		local frame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2)
		Kit.decor({ Name = "Ballast", Size = Vector3.new(9, 0.3, length + 2), CFrame = frame * CFrame.new(0, 0.15, 0), Color = Color3.fromRGB(120, 110, 100), Material = Enum.Material.Pebble, Parent = model })
		for _, offset in { -2.4, 2.4 } do
			Kit.decor({ Name = "Rail", Size = Vector3.new(0.4, 0.4, length + 2), CFrame = frame * CFrame.new(offset, 0.5, 0), Color = Color3.fromRGB(110, 90, 80), Material = Enum.Material.Metal, Parent = model })
		end
		-- Keep shacks and trees off the line (claim along it).
		for s = 0, length, 12 do
			Kit.claim(a + Kit.flat(b - a).Unit * s, 7)
		end
	end
end

function Landmarks.build()
	local folder = Kit.folder("Landmarks")
	local rng = Random.new(7)
	for _, landmark in World.Landmarks do
		local model = Instance.new("Model")
		model.Name = landmark.displayName
		model.Parent = folder
		if landmark.kind == "kicc" then
			kicc(model, Kit.clearOfRoads(landmark.position, 46, 10))
		elseif landmark.kind == "park" then
			park(model, Kit.clearOfRoads(landmark.position, 70, 8), rng)
		elseif landmark.kind == "stadium" then
			stadium(model, Kit.clearOfRoads(landmark.position, 72, 10))
		elseif landmark.kind == "hospital" then
			local size = landmark.size or Vector3.new(60, 36, 36)
			local at = Kit.clearOfRoads(landmark.position, math.max(size.X, size.Z) / 2, 24)
			local body = building(model, at, size, "KNH", Color3.fromRGB(235, 232, 220), false, Color3.fromRGB(200, 30, 30))
			Kit.paint(body, Enum.NormalId.Front, "+", Color3.fromRGB(220, 30, 30))
		elseif landmark.kind == "mall" then
			local size = landmark.size or Vector3.new(50, 18, 34)
			local at = Kit.clearOfRoads(landmark.position, math.max(size.X, size.Z) / 2, 24)
			building(model, at, size, landmark.displayName, Color3.fromRGB(225, 215, 200), true, Color3.fromRGB(30, 90, 160))
		elseif landmark.kind == "railway" and landmark.points then
			railway(model, landmark.points)
		end
	end
end

return Landmarks
