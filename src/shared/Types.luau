--!nocheck
-- Shared type aliases. Type-only; erased at runtime. Used for documentation
-- and (optionally) for a Luau type-checker. Safe to ignore at runtime.

export type FoodTier = "Berry" | "Meat" | "Feast"
export type CreatureTier = "Common" | "Uncommon" | "Rare" | "Epic" | "Mythic"
export type Mutation = "None" | "Golden" | "Shadow" | "Overcharged"

export type FoodInventory = { Berry: number, Meat: number, Feast: number }

export type PlayerData = {
	cash: number,
	food: FoodInventory,
	nests: { [number]: { tier: CreatureTier, mutation: Mutation }? },
	player: Player?,
	plotId: number?,
	lastThrow: number,
	shieldUntil: number,
}

export type PlotDef = {
	id: number,
	center: Vector3,
	nestPos: Vector3,
	cashPad: BasePart,
	shield: BasePart,
	shieldLabel: TextLabel,
	spawn: Vector3,
	owner: Player?,
	nests: { [number]: any },
	pendingCash: number,
	cashLabel: TextLabel?,
	clickDetector: ClickDetector,
}

export type CreatureRecord = {
	part: BasePart,
	vel: BodyVelocity,
	tier: CreatureTier,
	mutation: Mutation?,
	tame: number,
	mutationScore: number,
	state: string, -- "wild" | "returning" | "docked"
	target: any?,  -- a food record, or nil
	owner: Player?,
	dockSlot: number?,
	billboard: BillboardGui,
	label: TextLabel,
}

export type FoodRecord = {
	part: BasePart,
	tier: FoodTier,
	available: boolean,
	born: number,
	owner: Player?,
}

return {}
