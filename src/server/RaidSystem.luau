--!nocheck
-- RaidSystem: rival nest raiding + egg theft.
--
-- Rules (all server-authoritative):
--   * Every plot's nest gets a ProximityPrompt. A rival holding it for
--     RAID.STEAL_HOLD seconds steals the most valuable docked creature: the
--     egg pops off the nest and is welded above the thief's head.
--   * While carrying, the thief is slowed to RAID.CARRY_WALKSPEED and must
--     physically walk back into their own base to bank the creature forever
--     (it re-docks at their nest and earns cash for THEM).
--   * The victim's Stun tool: if the victim is within RAID.STUN_RANGE of the
--     thief, activating it knocks the creature loose. The thief is frozen
--     briefly, and the creature's physics are restored so it runs back to its
--     own nest (re-using the returning AI) and re-docks.
--   * If the thief dies or leaves mid-heist, the creature drops and runs home.
--   * Shields block stealing while active.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerService = require(script.Parent.PlayerService)
local CreatureSystem = require(script.Parent.CreatureSystem)

local RaidSystem = {}
RaidSystem.carrying = {} -- [thief Player] = { cr = creature, weld = WeldConstraint, victim = Player }
RaidSystem.lastStun = {} -- [Player] = last stun timestamp

local RESTORE_FORCE = Vector3.new(1e6, 1e6, 1e6)
local STUN_FREEZE = 2 -- seconds the thief is frozen after being stunned

local function hud(G, player, message)
	if player and player.Parent then
		G.world.remotes.Hud:FireClient(player, "log", message)
	end
end

local function rootOf(player)
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function setSpeed(player, speed)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.WalkSpeed = speed
	end
end

-- Most valuable docked creature on a plot (the juicy target).
local function richestDocked(plot)
	local best, bestVal = nil, -1
	for _, cr in ipairs(CreatureSystem.creatures) do
		if cr.state == "docked" and cr.plotId == plot.id then
			local v = Config.valueFor(cr.tier, cr.mutation or "None")
			if v > bestVal then
				bestVal = v
				best = cr
			end
		end
	end
	return best
end

-- Detach a carried creature: drop/loose it and let it run home (rescue = true)
-- or because the thief died/left (the creature still runs home to its owner).
local function dropCreature(G, thief, reasonLabel)
	local c = RaidSystem.carrying[thief]
	if not c then
		return
	end
	RaidSystem.carrying[thief] = nil

	if c.weld and c.weld.Parent then
		c.weld:Destroy()
	end
	setSpeed(thief, 16)

	local cr = c.cr
	if cr.model and cr.model.Parent then
		cr.part.CanCollide = true
		cr.vel.MaxForce = RESTORE_FORCE
		cr.vel.Velocity = Vector3.new(0, 0, 0)
		cr.state = "returning"
		cr.label.Text = reasonLabel
		hud(G, cr.owner, "log", "Your " .. cr.tier .. " got loose and is running home!")
	end
end

-- Execute the theft: detach the creature from the victim's nest and weld it to
-- the thief (who is slowed while carrying).
local function steal(G, plot, thief, cr)
	local root = rootOf(thief)
	if not root then
		return -- thief has no character (left?); abort cleanly
	end
	local victim = plot.owner
	local victimData = PlayerService.state.players[victim]
	local slot = cr.dockSlot

	-- Owner loses the nest entry (income stops) and the egg visual.
	if slot then
		plot.nests[slot] = nil
		if victimData and victimData.nests[slot] then
			victimData.nests[slot] = nil
		end
		plot.eggs = plot.eggs or {}
		if plot.eggs[slot] and plot.eggs[slot].Parent then
			plot.eggs[slot]:Destroy()
		end
		plot.eggs[slot] = nil
	end

	cr.dockSlot = nil
	cr.state = "carried"
	cr.vel.MaxForce = Vector3.zero
	cr.vel.Velocity = Vector3.new(0, 0, 0)
	cr.part.CanCollide = false

	cr.part.CFrame = root.CFrame * CFrame.new(0, 4, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = cr.part
	weld.Parent = cr.part

	RaidSystem.carrying[thief] = { cr = cr, weld = weld, victim = victim }
	setSpeed(thief, Config.RAID.CARRY_WALKSPEED)
	cr.label.Text = "STOLEN by " .. thief.Name .. "!"

	hud(G, thief, "You stole a " .. cr.mutation .. " " .. cr.tier .. "! Walk it back to YOUR base to keep it!")
	hud(G, victim, "THIEF! " .. thief.Name .. " is stealing your " .. cr.tier .. "! Stun them!")
end

local function onStealTriggered(G, plot, player)
	if not plot.owner or player == plot.owner then
		hud(G, player, "You can't steal from your own nest!")
		return
	end
	if RaidSystem.carrying[player] then
		hud(G, player, "You're already carrying a creature — bank it at your base first!")
		return
	end
	local now = Workspace:GetServerTimeNow()
	if plot.shieldUntil and plot.shieldUntil > now then
		hud(G, player, "Their shield is up! Come back when it drops.")
		return
	end
	local cr = richestDocked(plot)
	if not cr then
		hud(G, player, "Their nests are empty — nothing to steal yet.")
		return
	end
	steal(G, plot, player, cr)
end

-- Stun tool: knock the creature loose from a nearby thief carrying YOUR creature.
local function onStun(G, player)
	local now = Workspace:GetServerTimeNow()
	local last = RaidSystem.lastStun[player] or 0
	if now - last < Config.RAID.STUN_COOLDOWN then
		return
	end

	local myRoot = rootOf(player)
	if not myRoot then
		return
	end
	RaidSystem.lastStun[player] = now

	for thief, c in pairs(RaidSystem.carrying) do
		if c.cr.owner == player then
			local tRoot = rootOf(thief)
			if tRoot and (tRoot.Position - myRoot.Position).Magnitude <= Config.RAID.STUN_RANGE then
				dropCreature(G, thief, "RESCUED! heading home...")
				-- Freeze the thief briefly as punishment.
				setSpeed(thief, 0)
				task.delay(STUN_FREEZE, function()
					if thief.Parent and not RaidSystem.carrying[thief] then
						setSpeed(thief, 16)
					end
				end)
				hud(G, player, "STUNNED the thief! Your creature is heading home.")
				hud(G, thief, "You were stunned and lost the stolen creature!")
				return
			end
		end
	end
	hud(G, player, "No thief nearby is carrying your creature.")
end

-- Per-frame: bank carried creatures at the thief's own base; drop them if the
-- thief dies or leaves.
local function depositLoop(G)
	for thief, c in pairs(RaidSystem.carrying) do
		local hum = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
		if not thief.Parent or not hum or hum.Health <= 0 then
			local victim = c.victim
			dropCreature(G, thief, "DROPPED! heading home...")
			hud(G, victim, "The thief dropped your creature! It's heading home.")
		else
			local pdata = PlayerService.state.players[thief]
			local tRoot = rootOf(thief)
			if pdata and tRoot then
				local plot = G.world.plots[pdata.plotId]
				if plot and (tRoot.Position - plot.nestPos).Magnitude <= Config.RAID.DEPOSIT_RADIUS then
					local victim = c.victim
					local cr = c.cr
					RaidSystem.carrying[thief] = nil
					if c.weld and c.weld.Parent then
						c.weld:Destroy()
					end
					cr.part.CanCollide = true
					cr.owner = thief
					CreatureSystem.bankStolen(cr, G)
					setSpeed(thief, 16)
					hud(G, thief, "BANKED! The " .. cr.tier .. " is yours now — it earns cash at your nest.")
					hud(G, victim, thief.Name .. " got away with your " .. cr.tier .. "!")
				end
			end
		end
	end
end

function RaidSystem.init(G)
	-- One steal prompt per plot nest.
	for _, plot in pairs(G.world.plots) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Hold to Steal Egg"
		prompt.ObjectText = "Nest"
		prompt.HoldDuration = Config.RAID.STEAL_HOLD
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = plot.nestPart
		prompt.Triggered:Connect(function(player)
			onStealTriggered(G, plot, player)
		end)
	end

	G.world.remotes.Stun.OnServerEvent:Connect(function(player, dir)
		if typeof(dir) == "Vector3" then
			onStun(G, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if RaidSystem.carrying[player] then
			dropCreature(G, player, "DROPPED! heading home...")
		end
		RaidSystem.lastStun[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		depositLoop(G)
	end)
end

return RaidSystem
