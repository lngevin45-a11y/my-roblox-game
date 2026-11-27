--!nocheck
-- Hud: builds a ScreenGui and listens to the server "Hud" RemoteEvent for
-- cash / food / log / shield updates. Pure client-side rendering.

local Replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = Replicated:WaitForChild("Shared")
local Config = require(Shared.Config)

local Hud = {}

local gui
local cashLabel
local foodLabel
local shieldLabel
local logFrame

local function ensureGui()
	if gui then
		return
	end
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "GameHud"
	gui.ResetOnSpawn = false
	gui.Parent = pg

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 280, 0, 170)
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	panel.BackgroundTransparency = 0.3
	panel.Parent = gui

	cashLabel = Instance.new("TextLabel")
	cashLabel.Size = UDim2.new(1, 0, 0, 30)
	cashLabel.Position = UDim2.new(0, 0, 0, 4)
	cashLabel.Text = "Cash: $0"
	cashLabel.TextColor3 = Color3.new(1, 1, 1)
	cashLabel.BackgroundTransparency = 1
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.Parent = panel

	foodLabel = Instance.new("TextLabel")
	foodLabel.Size = UDim2.new(1, 0, 0, 70)
	foodLabel.Position = UDim2.new(0, 0, 0, 34)
	foodLabel.Text = "Food:\nBerry x0\nMeat x0\nFeast x0"
	foodLabel.TextColor3 = Color3.new(1, 1, 1)
	foodLabel.BackgroundTransparency = 1
	foodLabel.TextXAlignment = Enum.TextXAlignment.Left
	foodLabel.Parent = panel

	shieldLabel = Instance.new("TextLabel")
	shieldLabel.Size = UDim2.new(1, 0, 0, 24)
	shieldLabel.Position = UDim2.new(0, 0, 0, 108)
	shieldLabel.Text = "Shield: --"
	shieldLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
	shieldLabel.BackgroundTransparency = 1
	shieldLabel.TextXAlignment = Enum.TextXAlignment.Left
	shieldLabel.Parent = panel

	logFrame = Instance.new("Frame")
	logFrame.Size = UDim2.new(0, 380, 0, 170)
	logFrame.Position = UDim2.new(0, 12, 0, 200)
	logFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	logFrame.BackgroundTransparency = 0.4
	logFrame.Parent = gui
end

local function log(text)
	if not logFrame then
		return
	end
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 20)
	l.Position = UDim2.new(0, 4, 0, #logFrame:GetChildren() * 20)
	l.Text = tostring(text)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = logFrame

	local kids = logFrame:GetChildren()
	if #kids > 7 then
		kids[1]:Destroy()
	end
end

function Hud.init()
	ensureGui()

	local remotes = Replicated:WaitForChild("Remotes")
	local hud = remotes:WaitForChild(Config.REMOTES.Hud)

	hud.OnClientEvent:Connect(function(kind, payload)
		if kind == "cash" then
			cashLabel.Text = "Cash: $" .. math.floor(payload)
		elseif kind == "food" then
			foodLabel.Text = string.format(
				"Food:\nBerry x%d\nMeat x%d\nFeast x%d",
				payload.Berry or 0, payload.Meat or 0, payload.Feast or 0
			)
		elseif kind == "log" then
			log(payload)
		elseif kind == "shield" then
			shieldLabel.Text = "Shield: " .. math.floor(payload) .. "s"
		end
	end)
end

return Hud
