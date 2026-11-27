--!nocheck
-- GreyboxGenerator: programmatically builds the entire linear map and the
-- RemoteEvents on startup, so the game is playable in Studio with zero
-- external models. Returns a "world" table consumed by the other systems.

local Replicated = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = Replicated:WaitForChild("Shared")
local Config = require(Shared.Config)

local Greybox = {}

local function makePart(name, size, cframe, color, parent, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = anchored == nil and true or anchored
	p.CanCollide = anchored == nil and true or anchored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Greybox.generate()
	-- ----- RemoteEvents -----
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = Replicated

	local function remote(name)
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = remotes
		return e
	end
	local ThrowFood = remote(Config.REMOTES.ThrowFood)
	local Stun = remote(Config.REMOTES.Stun)
	local Hud = remote(Config.REMOTES.Hud)

	-- ----- World container -----
	local world = Instance.new("Model")
	world.Name = "World"
	world.Parent = Workspace

	local M = Config.MAP
	local laneHalfLen = M.LaneLength / 2
	local laneHalfWid = M.LaneWidth / 2

	-- Lane floor split into biome segments along X (long multi-biome path).
	local biomeCount = #Config.BIOMES
	local segW = M.LaneLength / biomeCount
	for i, biome in ipairs(Config.BIOMES) do
		local cx = -laneHalfLen + segW * (i - 0.5)
		makePart("Lane_" .. biome.name, Vector3.new(segW, 2, M.LaneWidth), CFrame.new(cx, -1, 0), biome.color, world, true)
	end

	-- Folders for dynamic objects
	local creaturesFolder = Instance.new("Folder"); creaturesFolder.Name = "Creatures"; creaturesFolder.Parent = world
	local foodFolder = Instance.new("Folder"); foodFolder.Name = "Food"; foodFolder.Parent = world
	local eggsFolder = Instance.new("Folder"); eggsFolder.Name = "Eggs"; eggsFolder.Parent = world

	-- ----- Base plots along the -Z edge, spread along X -----
	local plots = {}
	local span = M.PlotCount * M.PlotWidth + (M.PlotCount - 1) * M.PlotGap
	local startX = -laneHalfLen + 6 -- cluster the base camp at the START of the path
	local plotZ = -laneHalfWid - M.PlotDepth / 2 - 2

	-- Builds a low wooden fence (visual only) around a plot footprint.
	local function buildFence(plotModel, cx, cz, w, d)
		local fh, post, step = 2, 0.4, 4
		local function postAt(px, pz)
			local p = Instance.new("Part")
			p.Size = Vector3.new(post, fh, post)
			p.Color = Config.FENCE_COLOR
			p.Material = Enum.Material.Wood
			p.Anchored = true
			p.CanCollide = false
			p.Position = Vector3.new(px, 1 + fh / 2, pz)
			p.Parent = plotModel
		end
		local x0, x1 = cx - w / 2, cx + w / 2
		local z0, z1 = cz - d / 2, cz + d / 2
		for x = x0, x1, step do postAt(x, z0); postAt(x, z1) end
		for z = z0, z1, step do postAt(x0, z); postAt(x1, z) end
	end

	for i = 1, M.PlotCount do
		local x = startX + (i - 1) * (M.PlotWidth + M.PlotGap)
		local center = Vector3.new(x, 0, plotZ)

		local plotModel = Instance.new("Model")
		plotModel.Name = "Plot" .. i
		plotModel.Parent = world

		-- Floor pad
		makePart("Floor", Vector3.new(M.PlotWidth, 1, M.PlotDepth), CFrame.new(x, 0.5, plotZ), Config.COLORS.PlotFloor, plotModel, true)

		-- Nest pedestal (near the lane edge)
		local nestPos = Vector3.new(x, 2.5, plotZ + M.PlotDepth / 2 - 3)
		local nestPart = makePart("Nest", Vector3.new(4, 5, 4), CFrame.new(nestPos), Config.COLORS.Nest, plotModel, true)

		-- Cash-collection pad (front corner)
		local cashPos = Vector3.new(x - M.PlotWidth / 2 + 3, 0.6, plotZ + M.PlotDepth / 2 - 2)
		local cashPad = makePart("CashPad", Vector3.new(5, 1, 5), CFrame.new(cashPos), Config.COLORS.CashPad, plotModel, true)
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 12
		cd.Parent = cashPad

		-- Timed shield dome (visual only for the slice)
		local domeSize = math.max(M.PlotWidth, M.PlotDepth) + 6
		local shield = Instance.new("Part")
		shield.Name = "Shield"
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(domeSize, domeSize, M.PlotDepth + 10)
		shield.CFrame = CFrame.new(x, 6, plotZ)
		shield.Color = Config.COLORS.Shield
		shield.Transparency = 0.5
		shield.Anchored = true
		shield.CanCollide = false
		shield.Material = Enum.Material.Glass
		shield.Parent = plotModel

		local sb = Instance.new("BillboardGui")
		sb.Size = UDim2.new(0, 160, 0, 40)
		sb.StudsOffset = Vector3.new(0, 10, 0)
		sb.AlwaysOnTop = true
		sb.Parent = shield
		local st = Instance.new("TextLabel")
		st.Size = UDim2.new(1, 0, 1, 0)
		st.BackgroundTransparency = 1
		st.TextColor3 = Color3.new(1, 1, 1)
		st.TextStrokeTransparency = 0
		st.Text = "SHIELD"
		st.Parent = sb

		-- Visual fence around the plot (upgrade logic deferred).
		buildFence(plotModel, x, plotZ, M.PlotWidth, M.PlotDepth)

		local spawnPos = Vector3.new(x, 3, plotZ + M.PlotDepth / 2 - 4)

		plots[i] = {
			id = i,
			center = center,
			nestPos = nestPos,
			nestPart = nestPart,
			cashPad = cashPad,
			shield = shield,
			shieldLabel = st,
			spawn = spawnPos,
			owner = nil,
			nests = {},
			pendingCash = 0,
			clickDetector = cd,
		}
	end

	return {
		model = world,
		lane = { minX = -laneHalfLen, maxX = laneHalfLen, minZ = -laneHalfWid, maxZ = laneHalfWid, y = 0 },
		plots = plots,
		plotCount = M.PlotCount,
		remotes = { ThrowFood = ThrowFood, Stun = Stun, Hud = Hud },
		folders = { creatures = creaturesFolder, food = foodFolder, eggs = eggsFolder },
	}
end

return Greybox
