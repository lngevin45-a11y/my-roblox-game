--!nocheck
-- Server entry point. Greybox generates the world + remotes, then each system
-- is initialised in dependency order. Siblings are children of this Script
-- (Rojo maps src/server/* into ServerScriptService.Server).

local Greybox = require(script.Greybox)
local DataStore = require(script.DataStore)
local PlayerService = require(script.PlayerService)
local FoodSystem = require(script.FoodSystem)
local CreatureSystem = require(script.CreatureSystem)
local RaidSystem = require(script.RaidSystem)

local G = Greybox.generate()
G.DataStore = DataStore

PlayerService.init(G)
FoodSystem.init(G)
CreatureSystem.init(G)
RaidSystem.init(G)

print("[BaitTameSteal] Server initialised on the linear Safari Lane.")
