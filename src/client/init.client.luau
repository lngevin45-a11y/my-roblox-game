--!nocheck
-- Client entry point. Siblings are children of this LocalScript (Rojo maps
-- src/client/* into StarterPlayerScripts.Client).

local Hud = require(script.Hud)
local Input = require(script.Input)

Hud.init()
Input.init()
