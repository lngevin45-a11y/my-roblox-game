--!nocheck
-- CreatureSystem: the heart of the loop.
--   - Weighted-random wild creature spawns along the linear lane.
--   - Creatures detect + physically move toward nearby food, eat it (filling a
--     server-tracked Tame Meter), and at 100% roll a mutation.
--   - Tamed creatures return to the owner's nest, dock, and generate $/sec.
--   - Cash accrues on the plot and is collected at the cash pad (ClickDetector).
--   - Saved (docked) creatures are re-created on player rejoin.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerService = require(script.Parent.PlayerService)
local FoodSystem = require(script.Parent.FoodSystem)

local CreatureSystem = {}
CreatureSystem.creatures = {}
CreatureSystem.spawnTimer = 0
CreatureSystem.eggTimer = 0

-- ---------------------------------------------------------------------------
-- Billboard helpers
-- ---------------------------------------------------------------------------
local function makeBillboard(part, text)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 200, 0, 60)
	bg.StudsOffset = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = part
	bg.Parent = part

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0
	tl.Text = text
	tl.Parent = bg
	return bg, tl
end

-- REAL animals in a chunky voxel style. Each tier maps to a distinct animal with
-- its own silhouette, built from small cubes welded to a root Part.
local TIER_ANIMAL = {
	Common = "Rabbit", Uncommon = "Fox", Rare = "Wolf", Epic = "Bear", Mythic = "Tiger",
}
local ANIMAL_DEFS = {
	Rabbit = { body = Vector3.new(1.8, 1.6, 2.2), head = Vector3.new(1.3, 1.3, 1.3), headOff = Vector3.new(0, 1.1, 1.1), ear = "long",   tail = "fluff", snout = false, stripes = false },
	Fox    = { body = Vector3.new(2.0, 1.6, 2.4), head = Vector3.new(1.3, 1.3, 1.3), headOff = Vector3.new(0, 1.0, 1.2), ear = "pointy", tail = "bushy", snout = true,  stripes = false },
	Wolf   = { body = Vector3.new(2.4, 1.8, 2.8), head = Vector3.new(1.4, 1.4, 1.4), headOff = Vector3.new(0, 1.2, 1.4), ear = "pointy", tail = "bushy", snout = true,  stripes = false },
	Bear   = { body = Vector3.new(2.6, 2.2, 2.6), head = Vector3.new(1.7, 1.7, 1.6), headOff = Vector3.new(0, 1.5, 1.3), ear = "round",  tail = "short", snout = true,  stripes = false },
	Tiger  = { body = Vector3.new(2.6, 1.8, 3.0), head = Vector3.new(1.6, 1.5, 1.5), headOff = Vector3.new(0, 1.3, 1.5), ear = "round",  tail = "bushy", snout = true,  stripes = true  },
}

local function cubePart(size, color)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.Parent = nil
	return p
end

-- Builds a voxel real-animal model. Returns (model, root, bodyParts, bodyVelocity).
local function makeCreatureModel(tier, mutation, position)
	local animal = TIER_ANIMAL[tier] or "Rabbit"
	local def = ANIMAL_DEFS[animal]
	local base = (mutation and Config.MUTATIONS[mutation].color) or Config.CREATURES[tier].color
	local dark = base:Lerp(Color3.new(0, 0, 0), 0.35)
	local eye = Color3.new(0.05, 0.05, 0.08)

	local model = Instance.new("Model")
	model.Name = "Creature_" .. tier

	local root = cubePart(def.body, base)
	root.CanCollide = true
	root.Position = position
	root.Parent = model
	model.PrimaryPart = root

	local body = { root }
	local function add(off, size, color)
		local c = cubePart(size, color)
		c.CFrame = root.CFrame * CFrame.new(off)
		c.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = c
		w.Parent = c
		return c
	end

	-- head
	local head = add(def.headOff, def.head, base)
	table.insert(body, head)
	local hy, hz, hx = def.headOff.Y, def.headOff.Z, def.head.X

	-- ears
	if def.ear == "long" then
		add(Vector3.new(-0.35, hy + def.head.Y / 2 + 0.7, hz), Vector3.new(0.4, 1.4, 0.4), base)
		add(Vector3.new( 0.35, hy + def.head.Y / 2 + 0.7, hz), Vector3.new(0.4, 1.4, 0.4), base)
	elseif def.ear == "pointy" then
		add(Vector3.new(-0.45, hy + def.head.Y / 2 + 0.3, hz), Vector3.new(0.5, 0.7, 0.5), base)
		add(Vector3.new( 0.45, hy + def.head.Y / 2 + 0.3, hz), Vector3.new(0.5, 0.7, 0.5), base)
	elseif def.ear == "round" then
		add(Vector3.new(-0.6, hy + def.head.Y / 2 + 0.05, hz), Vector3.new(0.6, 0.6, 0.5), base)
		add(Vector3.new( 0.6, hy + def.head.Y / 2 + 0.05, hz), Vector3.new(0.6, 0.6, 0.5), base)
	end

	-- snout
	if def.snout then
		add(Vector3.new(0, hy - 0.1, hz + def.head.Z / 2 + 0.1), Vector3.new(def.head.X * 0.5, 0.5, 0.5), base)
	end

	-- eyes
	add(Vector3.new(-0.4, hy + 0.1, hz + def.head.Z / 2 - 0.05), Vector3.new(0.3, 0.3, 0.2), eye)
	add(Vector3.new( 0.4, hy + 0.1, hz + def.head.Z / 2 - 0.05), Vector3.new(0.3, 0.3, 0.2), eye)

	-- legs (darker)
	local ly = -def.body.Y / 2 - 0.4
	local lx = def.body.X / 2 - 0.4
	local lz = def.body.Z / 2 - 0.5
	for _, o in ipairs({
		Vector3.new(-lx, ly, lz), Vector3.new(lx, ly, lz),
		Vector3.new(-lx, ly, -lz), Vector3.new(lx, ly, -lz),
	}) do
		add(o, Vector3.new(0.6, 0.9, 0.6), dark)
	end

	-- tail
	if def.tail == "bushy" then
		add(Vector3.new(0, 0.2, -def.body.Z / 2 - 0.6), Vector3.new(0.8, 0.8, 1.0), base)
	elseif def.tail == "fluff" then
		add(Vector3.new(0, def.body.Y / 2 + 0.2, -def.body.Z / 2 - 0.3), Vector3.new(0.7, 0.7, 0.7), base)
	elseif def.tail == "short" then
		add(Vector3.new(0, -0.2, -def.body.Z / 2 - 0.2), Vector3.new(0.5, 0.5, 0.5), base)
	end

	-- stripes (tiger)
	if def.stripes then
		for i = -1, 1 do
			add(Vector3.new(-def.body.X / 2 - 0.01, 0.3, i * 0.6), Vector3.new(0.1, 0.6, 0.3), dark)
			add(Vector3.new( def.body.X / 2 + 0.01, 0.3, i * 0.6), Vector3.new(0.1, 0.6, 0.3), dark)
		end
	end

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = root

	return model, root, body, bv
end

-- ---------------------------------------------------------------------------
-- Spawning
-- ---------------------------------------------------------------------------
local function spawnCreature(G)
	if #CreatureSystem.creatures >= Config.MAX_WILD_CREATURES then
		return
	end
	local tier = Config.weightedCreatureTier()
	local lane = G.world.lane
	local x = math.random(lane.minX + 10, lane.maxX - 10)
	local z = math.random(lane.minZ + 5, lane.maxZ - 5)

	local model, root, body, bv = makeCreatureModel(tier, nil, Vector3.new(x, 3, z))
	model.Parent = G.world.folders.creatures

	local bg, tl = makeBillboard(root, tier .. " 0%")

	local cr = {
		part = root,
		model = model,
		body = body,
		vel = bv,
		tier = tier,
		mutation = nil,
		tame = 0,
		mutationScore = 0,
		state = "wild",
		target = nil,
		owner = nil,
		dockSlot = nil,
		billboard = bg,
		label = tl,
	}
	table.insert(CreatureSystem.creatures, cr)
end

-- ---------------------------------------------------------------------------
-- Targeting / eating / taming
-- ---------------------------------------------------------------------------
local function pickTarget(cr)
	local pos = cr.part.Position
	local best, bestD = nil, Config.CREATURE_DETECT_RADIUS
	for _, f in ipairs(FoodSystem.food) do
		if f.available and f.part and f.part.Parent then
			local d = (f.part.Position - pos).Magnitude
			if d < bestD then
				bestD = d
				best = f
			end
		end
	end
	return best
end

local function removeFood(rec)
	if rec.part and rec.part.Parent then
		rec.part:Destroy()
	end
	for i, v in ipairs(FoodSystem.food) do
		if v == rec then
			table.remove(FoodSystem.food, i)
			break
		end
	end
end

local function eat(cr, f, G)
	local food = Config.FOOD[f.tier]
	cr.tame = math.min(Config.TAME_MAX, cr.tame + food.tameFill)
	cr.mutationScore = cr.mutationScore + food.mutationBonus
	cr.owner = f.owner or cr.owner -- credit the thrower
	removeFood(f)
	cr.target = nil
	cr.label.Text = cr.tier .. " " .. math.floor(cr.tame) .. "%"
	if cr.tame >= Config.TAME_MAX then
		tameComplete(cr, G)
	end
end

local function tameComplete(cr, G)
	local chance = math.clamp(Config.BASE_MUTATION_CHANCE + cr.mutationScore, Config.BASE_MUTATION_CHANCE, Config.MAX_MUTATION_CHANCE)
	local mutation = "None"
	if math.random() < chance then
		local opts = { "Golden", "Shadow", "Overcharged" }
		mutation = opts[math.random(1, #opts)]
		local mdef = Config.MUTATIONS[mutation]
		if mdef and mdef.color then
			for _, b in ipairs(cr.body) do
				b.Color = mdef.color
			end
		end
	end
	cr.mutation = mutation
	cr.state = "returning"
	cr.vel.Velocity = Vector3.new(0, 0, 0)
	cr.label.Text = "TAMED " .. mutation

	if cr.owner then
		G.world.remotes.Hud:FireClient(cr.owner, "log", "Tamed a " .. mutation .. " " .. cr.tier .. " creature!")
	else
		-- No owner credited (left before tame) -> release back to wild.
		cr.state = "wild"
		cr.tame = 0
		cr.mutation = nil
		cr.label.Text = cr.tier .. " 0%"
	end
end

-- Spawns a voxel egg on a nest pedestal (visual only; cash is tracked separately).
local function spawnEgg(G, plot, slot, mutation)
	plot.eggs = plot.eggs or {}
	if plot.eggs[slot] and plot.eggs[slot].Parent then
		plot.eggs[slot]:Destroy()
	end
	local mdef = Config.MUTATIONS[mutation] or Config.MUTATIONS.None
	local egg = Instance.new("Part")
	egg.Name = "Egg_" .. slot
	egg.Shape = Enum.PartType.Block
	egg.Size = Vector3.new(1.6, 1.6, 1.6)
	egg.Color = mdef.color or Color3.fromRGB(245, 240, 230)
	egg.Material = Enum.Material.SmoothPlastic
	egg.Anchored = true
	egg.CanCollide = false
	egg.Position = plot.nestPos + Vector3.new(0, 3.4, 0)
	egg.Parent = G.world.folders.eggs
	plot.eggs[slot] = egg
end

-- ---------------------------------------------------------------------------
-- Docking + cash generation
-- ---------------------------------------------------------------------------
local function dock(cr, G)
	local pdata = PlayerService.state.players[cr.owner]
	if not pdata then
		cr.state = "wild"
		cr.tame = 0
		cr.label.Text = cr.tier .. " 0%"
		return
	end
	local plot = G.world.plots[pdata.plotId]

	-- Find a free nest slot (fallback to slot 1 if full)
	local slot = 1
	for i = 1, Config.NEST_SLOTS do
		if not plot.nests[i] then
			slot = i
			break
		end
		if i == Config.NEST_SLOTS then
			slot = 1
		end
	end

	local nestData = { tier = cr.tier, mutation = cr.mutation or "None" }
	plot.nests[slot] = nestData
	pdata.nests[slot] = nestData

	cr.dockSlot = slot
	cr.plotId = plot.id
	cr.state = "docked"
	cr.part.CFrame = CFrame.new(plot.nestPos + Vector3.new(0, 2, 0))
	cr.vel.Velocity = Vector3.new(0, 0, 0)
	cr.label.Text = cr.tier .. " " .. (cr.mutation or "None") .. " $" .. Config.valueFor(cr.tier, cr.mutation or "None") .. "/s"
	spawnEgg(G, plot, slot, cr.mutation or "None")

	G.world.remotes.Hud:FireClient(cr.owner, "log", "Creature docked! Generating cash at your nest.")
end

-- Called by RaidSystem when a thief banks a stolen creature at their own base.
-- cr.owner must already be reassigned to the thief; dock() does the rest
-- (free-slot lookup, nest entries, egg visual, label).
function CreatureSystem.bankStolen(cr, G)
	cr.vel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	cr.tame = Config.TAME_MAX
	dock(cr, G)
end

local function eggTick(G, dt)
	for _, plot in pairs(G.world.plots) do
		local total = 0
		for _, nest in pairs(plot.nests) do
			if nest and nest.tier then
				total += Config.valueFor(nest.tier, nest.mutation) * dt
			end
		end
		if total > 0 then
			plot.pendingCash = (plot.pendingCash or 0) + total
		end
	end
end

-- ---------------------------------------------------------------------------
-- Per-frame stepping
-- ---------------------------------------------------------------------------
local function stepCreature(cr, G)
	if cr.state == "carried" then
		cr.vel.Velocity = Vector3.new(0, 0, 0)
		return
	end
	if cr.state == "wild" then
		if not cr.target or (cr.target.part and not cr.target.part.Parent) then
			cr.target = pickTarget(cr)
		end
		if cr.target and cr.target.part and cr.target.part.Parent then
			local dir = cr.target.part.Position - cr.part.Position
			local dist = dir.Magnitude
			if dist <= Config.EAT_RADIUS then
				eat(cr, cr.target, G)
			else
				local flat = Vector3.new(dir.X, 0, dir.Z)
				if flat.Magnitude > 0.01 then
					cr.vel.Velocity = flat.Unit * Config.CREATURE_SPEED
				end
			end
		else
			cr.vel.Velocity = Vector3.new(0, 0, 0)
		end

	elseif cr.state == "returning" then
		local pdata = PlayerService.state.players[cr.owner]
		if not pdata or not pdata.plotId then
			cr.state = "wild"
			cr.tame = 0
			cr.owner = nil
			cr.label.Text = cr.tier .. " 0%"
			return
		end
		local plot = G.world.plots[pdata.plotId]
		local target = plot.nestPos
		local dir = Vector3.new(target.X - cr.part.Position.X, 0, target.Z - cr.part.Position.Z)
		local dist = dir.Magnitude
		if dist <= 3 then
			dock(cr, G)
		elseif dist > 0.01 then
			cr.vel.Velocity = dir.Unit * Config.CREATURE_SPEED
		end

	elseif cr.state == "docked" then
		cr.vel.Velocity = Vector3.new(0, 0, 0)
	end
end

-- ---------------------------------------------------------------------------
-- Cash pads (ClickDetector collection)
-- ---------------------------------------------------------------------------
-- Shield domes fade out when their timer expires. This is the hook the raiding
-- system will read (plot.shieldUntil) in the next pass.
local function updateShields(G)
	local now = Workspace:GetServerTimeNow()
	for _, plot in pairs(G.world.plots) do
		if plot.owner and plot.shieldUntil then
			local remaining = plot.shieldUntil - now
			if remaining <= 0 then
				plot.shield.Transparency = 1
				plot.shieldLabel.Text = "OPEN"
			else
				plot.shield.Transparency = 0.5
				plot.shieldLabel.Text = "SHIELD " .. math.ceil(remaining) .. "s"
			end
		else
			plot.shield.Transparency = 1
			plot.shieldLabel.Text = "OPEN"
		end
	end
end

local function setupCashPads(G)
	for _, plot in pairs(G.world.plots) do
		plot.pendingCash = 0

		local bg = Instance.new("BillboardGui")
		bg.Size = UDim2.new(0, 160, 0, 40)
		bg.StudsOffset = Vector3.new(0, 4, 0)
		bg.AlwaysOnTop = true
		bg.Parent = plot.cashPad
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.TextColor3 = Color3.new(1, 1, 1)
		tl.TextStrokeTransparency = 0
		tl.Text = "$0"
		tl.Parent = bg
		plot.cashLabel = tl

		plot.clickDetector.MouseClick:Connect(function(player)
			if player ~= plot.owner then
				G.world.remotes.Hud:FireClient(player, "log", "That's not your nest!")
				return
			end
			local amt = plot.pendingCash or 0
			if amt <= 0 then
				return
			end
			local pdata = PlayerService.state.players[player]
			if not pdata then
				return
			end
			pdata.cash += amt
			plot.pendingCash = 0
			G.world.remotes.Hud:FireClient(player, "cash", pdata.cash)
			G.world.remotes.Hud:FireClient(player, "log", "Collected $" .. math.floor(amt))
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function CreatureSystem.init(G)
	setupCashPads(G)

	-- Re-dock a saved (persisted) creature on rejoin. Defined as a closure so
	-- it captures G.
	local function onLoadNest(player, plot, slot, nest)
		local tier = nest.tier
		local mutation = nest.mutation or "None"
		local model, root, body, bv = makeCreatureModel(tier, mutation, plot.nestPos + Vector3.new(0, 3, 0))
		model.Parent = G.world.folders.creatures

		local bg, tl = makeBillboard(root, tier .. " " .. mutation .. " $" .. Config.valueFor(tier, mutation) .. "/s")
		local cr = {
			part = root,
			model = model,
			body = body,
			vel = bv,
			tier = tier,
			mutation = mutation,
			tame = Config.TAME_MAX,
			mutationScore = 0,
			state = "docked",
			target = nil,
			owner = player,
			plotId = plot.id,
			dockSlot = slot,
			billboard = bg,
			label = tl,
		}
		plot.nests[slot] = nest
		spawnEgg(G, plot, slot, mutation)
		table.insert(CreatureSystem.creatures, cr)
	end

	G.onLoadNest = onLoadNest

	-- Seed a few creatures immediately so the lane is alive on start.
	for _ = 1, 4 do
		spawnCreature(G)
	end

	RunService.Heartbeat:Connect(function(dt)
		-- Wild spawn timer
		CreatureSystem.spawnTimer += dt
		if CreatureSystem.spawnTimer >= Config.CREATURE_SPAWN_INTERVAL then
			CreatureSystem.spawnTimer = 0
			spawnCreature(G)
		end

		-- Step all creatures
		for _, cr in ipairs(CreatureSystem.creatures) do
			stepCreature(cr, G)
		end

		-- Shield dome visuals / expiry
		updateShields(G)

		-- Egg/cash tick
		CreatureSystem.eggTimer += dt
		if CreatureSystem.eggTimer >= Config.EGG_TICK then
			local d = CreatureSystem.eggTimer
			CreatureSystem.eggTimer = 0
			eggTick(G, d)
			for _, plot in pairs(G.world.plots) do
				if plot.cashLabel then
					plot.cashLabel.Text = "$" .. math.floor(plot.pendingCash or 0)
				end
			end
		end
	end)
end

return CreatureSystem
