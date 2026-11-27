--!nocheck
-- Input: wires food-tool activation to the server "ThrowFood" RemoteEvent.
-- Aiming uses the camera look vector, so you throw where you look down the lane.

local Replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = Replicated:WaitForChild("Shared")
local Config = require(Shared.Config)

local Input = {}

local wired = {} -- guard against double-wiring the same tool

local function wireTool(throw, tool)
	if not tool or wired[tool] then
		return
	end
	if not tool:GetAttribute("FoodTier") then
		return
	end
	wired[tool] = true
	tool.Activated:Connect(function()
		local cam = Workspace.CurrentCamera
		local dir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
		throw:FireServer(tool:GetAttribute("FoodTier"), dir)
	end)
end

function Input.init()
	local player = Players.LocalPlayer
	local remotes = Replicated:WaitForChild("Remotes")
	local throw = remotes:WaitForChild(Config.REMOTES.ThrowFood)

	local backpack = player:WaitForChild("Backpack")
	for _, t in ipairs(backpack:GetChildren()) do
		wireTool(throw, t)
	end
	backpack.ChildAdded:Connect(function(t)
		wireTool(throw, t)
	end)
end

return Input
