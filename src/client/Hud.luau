--!nocheck
-- Hud: builds the ScreenGui (rounded stat panel with food chips + shield pill,
-- plus a fading bottom-center log feed) and listens to the server "Hud"
-- RemoteEvent. Pure client-side rendering, no external assets.

local Replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = Replicated:WaitForChild("Shared")
local Config = require(Shared.Config)

local Hud = {}

local PANEL_BG = Color3.fromRGB(24, 26, 34)
local CHIP_BG = Color3.fromRGB(38, 42, 54)

local gui
local cashLabel
local foodCounts = {} -- [tier] = count TextLabel
local shieldLabel
local logHolder

local function round(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function ensureGui()
	if gui then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "GameHud"
	gui.ResetOnSpawn = false
	gui.Parent = pg

	-- ----- Stat panel (top-left) -----
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 252, 0, 170)
	panel.Position = UDim2.new(0, 14, 0, 14)
	panel.BackgroundColor3 = PANEL_BG
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui
	round(panel, 14)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 16)
	title.Position = UDim2.new(0, 14, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextColor3 = Color3.fromRGB(150, 160, 180)
	title.Text = "BAIT · TAME · STEAL"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	cashLabel = Instance.new("TextLabel")
	cashLabel.Size = UDim2.new(1, -24, 0, 34)
	cashLabel.Position = UDim2.new(0, 14, 0, 28)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.GothamBold
	cashLabel.TextSize = 30
	cashLabel.TextColor3 = Color3.fromRGB(255, 205, 80)
	cashLabel.Text = "$0"
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.Parent = panel

	-- Food chips (one per food tier, colored swatch + count)
	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, -24, 0, 34)
	chipRow.Position = UDim2.new(0, 14, 0, 68)
	chipRow.BackgroundTransparency = 1
	chipRow.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = chipRow

	for _, tier in ipairs(Config.FOOD_ORDER) do
		local chip = Instance.new("Frame")
		chip.Size = UDim2.new(0, 72, 0, 34)
		chip.BackgroundColor3 = CHIP_BG
		chip.BorderSizePixel = 0
		chip.Parent = chipRow
		round(chip, 9)

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(0, 12, 0, 12)
		swatch.Position = UDim2.new(0, 9, 0, 11)
		swatch.BackgroundColor3 = (Config.FOOD[tier] and Config.FOOD[tier].color) or Color3.new(1, 1, 1)
		swatch.BorderSizePixel = 0
		swatch.Parent = chip
		round(swatch, 4)

		local count = Instance.new("TextLabel")
		count.Size = UDim2.new(1, -36, 1, 0)
		count.Position = UDim2.new(0, 27, 0, 0)
		count.BackgroundTransparency = 1
		count.Font = Enum.Font.GothamMedium
		count.TextSize = 15
		count.TextColor3 = Color3.new(1, 1, 1)
		count.Text = "x0"
		count.TextXAlignment = Enum.TextXAlignment.Left
		count.Parent = chip
		foodCounts[tier] = count
	end

	-- Shield pill
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(1, -28, 0, 30)
	pill.Position = UDim2.new(0, 14, 0, 124)
	pill.BackgroundColor3 = Color3.fromRGB(38, 78, 120)
	pill.BorderSizePixel = 0
	pill.Parent = panel
	round(pill, 15)

	shieldLabel = Instance.new("TextLabel")
	shieldLabel.Size = UDim2.new(1, 0, 1, 0)
	shieldLabel.BackgroundTransparency = 1
	shieldLabel.Font = Enum.Font.GothamBold
	shieldLabel.TextSize = 14
	shieldLabel.TextColor3 = Color3.fromRGB(190, 225, 255)
	shieldLabel.Text = "SHIELD READY"
	shieldLabel.Parent = pill

	-- ----- Log feed (bottom-center, newest at bottom) -----
	logHolder = Instance.new("Frame")
	logHolder.AnchorPoint = Vector2.new(0.5, 1)
	logHolder.Position = UDim2.new(0.5, 0, 1, -18)
	logHolder.Size = UDim2.new(0, 460, 0, 200)
	logHolder.BackgroundTransparency = 1
	logHolder.Parent = gui

	local logLayout = Instance.new("UIListLayout")
	logLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	logLayout.Padding = UDim.new(0, 6)
	logLayout.Parent = logHolder
end

local function log(text)
	if not logHolder then
		return
	end
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = PANEL_BG
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.Parent = logHolder
	round(row, 10)

	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 1, 0)
	l.Position = UDim2.new(0, 12, 0, 0)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = tostring(text)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = row

	local rows = 0
	for _, c in ipairs(logHolder:GetChildren()) do
		if c:IsA("Frame") then
			rows += 1
		end
	end
	if rows > 5 then
		-- Destroy the oldest (topmost) row.
		for _, c in ipairs(logHolder:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end

	-- Fade out and remove after a few seconds.
	task.delay(6, function()
		if not row.Parent then
			return
		end
		local tw = TweenService:Create(row, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
		local tw2 = TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1 })
		tw:Play()
		tw2:Play()
		task.wait(0.65)
		if row.Parent then
			row:Destroy()
		end
	end)
end

function Hud.init()
	ensureGui()

	local remotes = Replicated:WaitForChild("Remotes")
	local hud = remotes:WaitForChild(Config.REMOTES.Hud)

	hud.OnClientEvent:Connect(function(kind, payload)
		if kind == "cash" then
			cashLabel.Text = "$" .. math.floor(payload)
		elseif kind == "food" then
			for _, tier in ipairs(Config.FOOD_ORDER) do
				local lbl = foodCounts[tier]
				if lbl then
					lbl.Text = "x" .. (payload[tier] or 0)
				end
			end
		elseif kind == "log" then
			log(payload)
		elseif kind == "shield" then
			shieldLabel.Text = "SHIELD " .. math.floor(payload) .. "s"
		end
	end)
end

return Hud
