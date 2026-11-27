--!nocheck
-- PlayerService: on join, loads DataStore data, claims a base plot, grants food
-- tools, positions the character, re-docks saved creatures, and wires a HUD.
-- On leave, saves progress.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DataStore = require(script.Parent.DataStore)

local PlayerService = {}
PlayerService.state = { players = {} } -- Player -> PlayerData

local function makeTool(tier)
	local food = Config.FOOD[tier]
	local tool = Instance.new("Tool")
	tool.Name = "Food_" .. tier
	tool.RequiresHandle = true
	tool:SetAttribute("FoodTier", tier)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.4, 1.4, 1.4)
	handle.Color = food.color
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Parent = tool

	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 120, 0, 30)
	bg.StudsOffset = Vector3.new(0, 1.6, 0)
	bg.AlwaysOnTop = true
	bg.Parent = handle

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0
	tl.Text = tier
	tl.Parent = bg

	return tool
end

local function makeStunTool()
	local tool = Instance.new("Tool")
	tool.Name = "StunTool"
	tool.RequiresHandle = true
	tool:SetAttribute("StunTool", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 1.2, 1.2)
	handle.Color = Color3.fromRGB(255, 80, 80)
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Parent = tool

	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 120, 0, 30)
	bg.StudsOffset = Vector3.new(0, 1.6, 0)
	bg.AlwaysOnTop = true
	bg.Parent = handle

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0
	tl.Text = "STUN"
	tl.Parent = bg

	return tool
end

local function assignPlot(G, player)
	local plots = G.world.plots
	for i = 1, G.world.plotCount do
		if plots[i].owner == nil then
			plots[i].owner = player
			return plots[i]
		end
	end
	-- All plots taken (slice cap): reuse plot 1 (overcrowded).
	plots[1].owner = player
	return plots[1]
end

local function sendHud(G, player, pdata)
	G.world.remotes.Hud:FireClient(player, "cash", pdata.cash)
	G.world.remotes.Hud:FireClient(player, "food", pdata.food)
end

function PlayerService.init(G)
	local function onJoin(player)
		local pdata = DataStore.load(player)
		pdata.player = player
		pdata.lastThrow = 0
		pdata.shieldUntil = Workspace:GetServerTimeNow() + Config.SHIELD_TIME

		local plot = assignPlot(G, player)
		pdata.plotId = plot.id
		plot.shieldUntil = Workspace:GetServerTimeNow() + Config.SHIELD_TIME

		PlayerService.state.players[player] = pdata

		-- Grant food tools
		local backpack = player:WaitForChild("Backpack")
		for _, tier in ipairs(Config.FOOD_ORDER) do
			makeTool(tier).Parent = backpack
		end
		-- Raid defense tool (knocks a carried egg loose)
		makeStunTool().Parent = backpack

		-- Initial HUD
		sendHud(G, player, pdata)
		G.world.remotes.Hud:FireClient(player, "shield", Config.SHIELD_TIME)
		G.world.remotes.Hud:FireClient(player, "log", "Throw food into the lane to lure & tame creatures!")

		-- Re-dock saved tamed creatures
		for slot, nest in pairs(pdata.nests) do
			if G.onLoadNest then
				G.onLoadNest(player, plot, slot, nest)
			end
		end

		-- Spawn the character at the plot
		local function place(char)
			local root = char:WaitForChild("HumanoidRootPart")
			task.wait(0.1)
			root.CFrame = CFrame.new(plot.spawn)
		end
		player.CharacterAdded:Connect(place)
		if player.Character then
			place(player.Character)
		end
	end

	local function onLeave(player)
		local pdata = PlayerService.state.players[player]
		if pdata then
			DataStore.save(player, { cash = pdata.cash, food = pdata.food, nests = pdata.nests })
			PlayerService.state.players[player] = nil
		end
		-- Release the plot so a reconnect can reclaim it
		for i = 1, G.world.plotCount do
			if G.world.plots[i].owner == player then
				G.world.plots[i].owner = nil
			end
		end
	end

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, p)
	end
end

return PlayerService
