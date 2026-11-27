--!nocheck
-- DataStore persistence (real DataStoreService). Guarded with pcall so the
-- game still runs in Studio before the place is published + API enabled;
-- saves simply no-op with a warning until then.

local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local DataStore = {}

DataStore.Store = nil
pcall(function()
	DataStore.Store = DataStoreService:GetDataStore("BaitTameSteal_v1")
end)

local function defaultData()
	return {
		cash = Config.START_CASH,
		food = { Berry = Config.START_FOOD.Berry, Meat = Config.START_FOOD.Meat, Feast = Config.START_FOOD.Feast },
		nests = {}, -- slot -> { tier, mutation }
	}
end
DataStore.default = defaultData

function DataStore.load(player)
	local key = "plr_" .. player.UserId
	local ok, data = pcall(function()
		if not DataStore.Store then
			error("DataStore unavailable")
		end
		return DataStore.Store:GetAsync(key)
	end)

	if ok and type(data) == "table" then
		local d = defaultData()
		d.cash = tonumber(data.cash) or d.cash
		if type(data.food) == "table" then
			d.food.Berry = tonumber(data.food.Berry) or d.food.Berry
			d.food.Meat = tonumber(data.food.Meat) or d.food.Meat
			d.food.Feast = tonumber(data.food.Feast) or d.food.Feast
		end
		if type(data.nests) == "table" then
			d.nests = data.nests
		end
		return d
	end

	warn("[DataStore] load failed/unavailable for", player.Name, "- using session defaults (publish + enable API to persist)")
	return defaultData()
end

function DataStore.save(player, data)
	local key = "plr_" .. player.UserId
	local ok, err = pcall(function()
		if not DataStore.Store then
			error("DataStore unavailable")
		end
		DataStore.Store:SetAsync(key, data)
	end)
	if not ok then
		warn("[DataStore] save failed for", player.Name, "-", tostring(err))
	end
end

return DataStore
