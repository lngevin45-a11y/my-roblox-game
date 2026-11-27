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

local function makeCreaturePart(tier, mutation, position)
	local def = Config.CREATURES[tier]
	local p = Instance.new("Part")
	p.Name = "Creature_" .. tier
	p.Size = Vector3.new(3, 3, 3)
	p.Color = (mutation and Config.MUTATIONS[mutation].color) or def.color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.Position = position
	p.Parent = nil

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = p
	return p, bv
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

	local part, bv = makeCreaturePart(tier, nil, Vector3.new(x, 2, z))
	part.Parent = G.world.folders.creatures

	local bg, tl = makeBillboard(part, tier .. " 0%")

	local cr = {
		part = part,
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
		if mdef.color then
			cr.part.Color = mdef.color
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
	cr.state = "docked"
	cr.part.CFrame = CFrame.new(plot.nestPos + Vector3.new(0, 2, 0))
	cr.vel.Velocity = Vector3.new(0, 0, 0)
	cr.label.Text = cr.tier .. " " .. (cr.mutation or "None") .. " $" .. Config.valueFor(cr.tier, cr.mutation or "None") .. "/s"

	G.world.remotes.Hud:FireClient(cr.owner, "log", "Creature docked! Generating cash at your nest.")
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
		local part, bv = makeCreaturePart(tier, mutation, plot.nestPos + Vector3.new(0, 2, 0))
		part.Parent = G.world.folders.creatures

		local bg, tl = makeBillboard(part, tier .. " " .. mutation .. " $" .. Config.valueFor(tier, mutation) .. "/s")
		local cr = {
			part = part,
			vel = bv,
			tier = tier,
			mutation = mutation,
			tame = Config.TAME_MAX,
			mutationScore = 0,
			state = "docked",
			target = nil,
			owner = player,
			dockSlot = slot,
			billboard = bg,
			label = tl,
		}
		plot.nests[slot] = nest
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
