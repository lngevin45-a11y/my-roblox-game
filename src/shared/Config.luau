--!nocheck
-- Shared configuration & tunables for "Bait, Tame & Steal an Egg".
-- This module is replicated to the client and server. No runtime state here.

local Config = {}

-- RemoteEvent names (created at runtime by Greybox into ReplicatedStorage.Remotes)
Config.REMOTES = {
	ThrowFood = "ThrowFood", -- client -> server : (tier:string, dir:Vector3)
	Stun = "Stun",           -- client -> server : (dir:Vector3)  -- raid defense tool
	Hud = "Hud",             -- server -> client : (kind:string, payload:any)
}

-- =========================================================================
-- LINEAR MAP ("Safari Lane") dimensions, in studs.
-- Lane runs along the X axis; player plots line the -Z edge in a row.
-- =========================================================================
Config.MAP = {
	LaneLength = 240, -- along X
	LaneWidth = 40,   -- along Z
	PlotDepth = 28,   -- into -Z from the lane edge
	PlotWidth = 26,   -- along X
	PlotCount = 8,    -- number of base plots (also the player cap for the slice)
	PlotGap = 6,
}

-- Player starting state
Config.START_CASH = 0
Config.START_FOOD = { Berry = 12, Meat = 6, Feast = 3 }
Config.SHIELD_TIME = 30 -- seconds of protective dome on (re)spawn
Config.NEST_SLOTS = 2   -- nest pedestal slots per plot
Config.THROW_COOLDOWN = 0.6
Config.THROW_SPEED = 90

-- =========================================================================
-- Food tiers: how much tame they fill, and the mutation-bonus they add.
-- =========================================================================
Config.FOOD = {
	Berry = { tameFill = 22, mutationBonus = 0.00, color = Color3.fromRGB(80, 200, 90),  radius = 0.8 },
	Meat  = { tameFill = 45, mutationBonus = 0.06, color = Color3.fromRGB(220, 170, 40), radius = 1.0 },
	Feast = { tameFill = 80, mutationBonus = 0.14, color = Color3.fromRGB(190, 70, 220), radius = 1.3 },
}
Config.FOOD_ORDER = { "Berry", "Meat", "Feast" }

-- =========================================================================
-- Creature tiers: spawn weight (weighted RNG) + base passive $/sec.
-- =========================================================================
Config.CREATURES = {
	Common  = { weight = 60, value = 1,  color = Color3.fromRGB(150, 150, 150) },
	Uncommon= { weight = 25, value = 3,  color = Color3.fromRGB(90,  200, 120) },
	Rare    = { weight = 10, value = 9,  color = Color3.fromRGB(80,  150, 230) },
	Epic    = { weight = 4,  value = 24, color = Color3.fromRGB(170, 90,  220) },
	Mythic  = { weight = 1,  value = 60, color = Color3.fromRGB(240, 200, 60)  },
}
Config.CREATURE_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Mythic" }

-- =========================================================================
-- Mutations applied on tame. mult multiplies the creature's $/sec.
-- =========================================================================
Config.MUTATIONS = {
	None        = { mult = 1.0, color = nil },
	Golden      = { mult = 2.0, color = Color3.fromRGB(255, 215, 0) },
	Shadow      = { mult = 1.5, color = Color3.fromRGB(40, 40, 60) },
	Overcharged = { mult = 3.0, color = Color3.fromRGB(0, 255, 255) },
}
Config.BASE_MUTATION_CHANCE = 0.10 -- from a pure-Common-food tame
Config.MAX_MUTATION_CHANCE = 0.75

-- =========================================================================
-- Creature AI / loop tuning
-- =========================================================================
Config.MAX_WILD_CREATURES = 10
Config.CREATURE_SPAWN_INTERVAL = 4   -- seconds between wild spawns
Config.CREATURE_SPEED = 10           -- studs/sec toward target
Config.CREATURE_DETECT_RADIUS = 40   -- how far a creature "smells" food
Config.EAT_RADIUS = 2.5
Config.TAME_MAX = 100

-- =========================================================================
-- Egg / cash production
-- =========================================================================
Config.EGG_TICK = 1 -- seconds per cash accrual tick

-- =========================================================================
-- Raid / egg-theft tuning (System 3)
-- =========================================================================
Config.RAID = {
	STEAL_HOLD = 2.5,       -- seconds a rival must hold the prompt to steal
	CARRY_WALKSPEED = 8,    -- thief walk speed while carrying (default 16)
	STUN_RANGE = 12,         -- reach of the stun/knockback tool
	STUN_COOLDOWN = 1.5,     -- per-player stun cooldown
	DEPOSIT_RADIUS = 9,      -- distance to own plot center to complete theft
}

-- =========================================================================
-- Color palette for greybox geometry
-- =========================================================================
Config.COLORS = {
	Lane      = Color3.fromRGB(70, 110, 70),
	Wall      = Color3.fromRGB(90, 90, 100),
	PlotFloor = Color3.fromRGB(216, 197, 158),
	Nest      = Color3.fromRGB(160, 120, 70),
	Shield    = Color3.fromRGB(150, 215, 255),
	CashPad   = Color3.fromRGB(60, 200, 120),
}

-- Biome segments for the long multi-biome lane (ordered start -> far).
Config.BIOMES = {
	{ name = "Meadow",  color = Color3.fromRGB(95, 165, 85) },
	{ name = "Forest",  color = Color3.fromRGB(40, 110, 55) },
	{ name = "Desert",  color = Color3.fromRGB(210, 180, 110) },
	{ name = "Tundra",  color = Color3.fromRGB(200, 220, 235) },
	{ name = "Volcano", color = Color3.fromRGB(125, 45, 40) },
}
Config.FENCE_COLOR = Color3.fromRGB(120, 80, 45)

-- =========================================================================
-- Helpers
-- =========================================================================

-- Passive cash/sec for a docked creature given its tier + mutation.
function Config.valueFor(tier: string, mutation: string): number
	local c = Config.CREATURES[tier]
	local m = Config.MUTATIONS[mutation] or Config.MUTATIONS.None
	return (c and c.value or 0) * (m and m.mult or 1)
end

-- Weighted-random creature tier pick.
function Config.weightedCreatureTier(): string
	local total = 0
	for _, t in ipairs(Config.CREATURE_ORDER) do
		total += Config.CREATURES[t].weight
	end
	local r = math.random() * total
	local acc = 0
	for _, t in ipairs(Config.CREATURE_ORDER) do
		acc += Config.CREATURES[t].weight
		if r <= acc then
			return t
		end
	end
	return Config.CREATURE_ORDER[1]
end

return Config
