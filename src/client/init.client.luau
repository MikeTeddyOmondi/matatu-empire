--!strict
-- Client entry point.

local Controllers = script:WaitForChild("Controllers")

local State = require(Controllers:WaitForChild("State") :: ModuleScript) :: any
local Hud = require(Controllers:WaitForChild("Hud") :: ModuleScript) :: any
local Tout = require(Controllers:WaitForChild("Tout") :: ModuleScript) :: any
local Garage = require(Controllers:WaitForChild("Garage") :: ModuleScript) :: any
local Waypoint = require(Controllers:WaitForChild("Waypoint") :: ModuleScript) :: any

-- Order matters: Hud owns the action buttons that Tout and Garage hook into.
Hud.start()
Tout.start()
Garage.start()
Waypoint.start()
State.start()
