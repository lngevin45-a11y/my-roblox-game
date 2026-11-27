--!nocheck
-- FoodSystem: validates throw intent from the client (cooldown + inventory),
-- then spawns a real physics projectile into the lane. Tracks active food so
-- the CreatureSystem can detect & eat it. Server-authoritative throughout.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerService = require(script.Parent.PlayerService)

local FoodSystem = {}
FoodSystem.food = {} -- list of FoodRecord

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

local function spawnProjectile(G, player, tier, dir)
	local food = Config.FOOD[tier]
	local char = player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
	if not root then
		return
	end

	local origin = root.Position + Vector3.new(0, 2.5, 0) + dir * 3

	local p = Instance.new("Part")
	p.Name = "Food_" .. tier
	p.Shape = Enum.PartType.Block
	p.Size = Vector3.new(food.radius * 2, food.radius * 2, food.radius * 2)
	p.Color = food.color
	p.Material = Enum.Material.Neon
	p.CanCollide = true
	p.Anchored = false
	p.CFrame = CFrame.new(origin)
	p:SetAttribute("FoodTier", tier)
	p.Parent = G.world.folders.food

	-- Real physics: initial velocity, gravity does the rest.
	p.AssemblyLinearVelocity = dir.Unit * Config.THROW_SPEED

	local rec = { part = p, tier = tier, available = false, born = Workspace:GetServerTimeNow(), owner = player }
	table.insert(FoodSystem.food, rec)

	-- Becomes "edible" after it has travelled/landed.
	task.delay(0.6, function()
		if rec.part and rec.part.Parent then
			rec.available = true
		end
	end)

	-- Max lifetime cleanup
	task.delay(20, function()
		removeFood(rec)
	end)
end

function FoodSystem.init(G)
	G.world.remotes.ThrowFood.OnServerEvent:Connect(function(player, tier, dir)
		-- ---- Server-authoritative validation ----
		if type(tier) ~= "string" or not Config.FOOD[tier] then
			return
		end
		if typeof(dir) ~= "Vector3" then
			return
		end

		local pdata = PlayerService.state.players[player]
		if not pdata or not pdata.plotId then
			return
		end

		local now = Workspace:GetServerTimeNow()
		if now - (pdata.lastThrow or 0) < Config.THROW_COOLDOWN then
			return -- spam guard
		end

		local inv = pdata.food[tier] or 0
		if inv <= 0 then
			G.world.remotes.Hud:FireClient(player, "log", "Out of " .. tier .. "!")
			return
		end

		-- Consume one and throw
		pdata.food[tier] = inv - 1
		pdata.lastThrow = now
		G.world.remotes.Hud:FireClient(player, "food", pdata.food)

		spawnProjectile(G, player, tier, dir.Unit)
	end)
end

return FoodSystem
