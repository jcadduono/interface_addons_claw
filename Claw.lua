local ADDON = 'Claw'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_CLAW = ADDON
BINDING_NAME_CLAW_TARGETMORE = "Toggle Targets +"
BINDING_NAME_CLAW_TARGETLESS = "Toggle Targets -"
BINDING_NAME_CLAW_TARGET1 = "Set Targets to 1"
BINDING_NAME_CLAW_TARGET2 = "Set Targets to 2"
BINDING_NAME_CLAW_TARGET3 = "Set Targets to 3"
BINDING_NAME_CLAW_TARGET4 = "Set Targets to 4"
BINDING_NAME_CLAW_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'DRUID' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Claw = {}
local Opt -- use this as a local table reference to Claw

SLASH_Claw1, SLASH_Claw2 = '/claw', '/cl'

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Claw, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			balance = false,
			feral = false,
			guardian = false,
			restoration = true,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		keybinds = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
		heal = 60,
		multipliers = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	buttons = {},
	action_slots = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	tracked = {},
	bloodtalons = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	BALANCE = 1,
	FERAL = 2,
	GUARDIAN = 3,
	RESTORATION = 4,
}

-- form constants
local FORM = {
	NONE = 0,
	MOONKIN = 1,
	CAT = 2,
	BEAR = 3,
	TRAVEL = 4,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.BALANCE] = {},
	[SPEC.FERAL] = {},
	[SPEC.GUARDIAN] = {},
	[SPEC.RESTORATION] = {},
}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	form = FORM.NONE,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
		regen = 0,
	},
	energy = {
		current = 0,
		max = 100,
		deficit = 100,
		regen = 0,
	},
	rage = {
		current = 0,
		max = 100,
		deficit = 100,
	},
	combo_points = {
		current = 0,
		max = 5,
		deficit = 5,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t33 = 0, -- Mane of the Greatlynx
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	berserk_remains = 0,
	berserk_up = false,
}

-- base mana pool max for each level
Player.BaseMana = {
	260,     270,     285,     300,     310,     -- 5
	330,     345,     360,     380,     400,     -- 10
	430,     465,     505,     550,     595,     -- 15
	645,     700,     760,     825,     890,     -- 20
	965,     1050,    1135,    1230,    1335,    -- 25
	1445,    1570,    1700,    1845,    2000,    -- 30
	2165,    2345,    2545,    2755,    2990,    -- 35
	3240,    3510,    3805,    4125,    4470,    -- 40
	4845,    5250,    5690,    6170,    6685,    -- 45
	7245,    7855,    8510,    9225,    10000,   -- 50
	11745,   13795,   16205,   19035,   22360,   -- 55
	26265,   30850,   36235,   42565,   50000,   -- 60
	58730,   68985,   81030,   95180,   111800,  -- 65
	131325,  154255,  181190,  212830,  250000,  -- 70
	293650,  344930,  405160,  475910,  559015,  -- 75
	656630,  771290,  905970,  1064170, 2500000, -- 80
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BALANCE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.FERAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.GUARDIAN] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.RESTORATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	clawPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Claw_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Claw_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Claw_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		energy_cost = 0,
		cp_cost = 0,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self.requires_form and Player.form ~= self.requires_form then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if not pool then
		if self:ManaCost() > Player.mana.current then
			return false
		end
		if Player.form == FORM.CAT and self:EnergyCost() > Player.energy.current then
			return false
		end
		if Player.form == FORM.BEAR and self:RageCost() > Player.rage.current then
			return false
		end
	end
	if self:CPCost() > Player.combo_points.current then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:APCost()
	return self.ap_cost
end

function Ability:CPCost()
	return self.cp_cost
end

function Ability:RageCost()
	return self.rage_cost
end

function Ability:Free()
	return (
		((Player.form == FORM.NONE or Player.form == FORM.TRAVEL) and (
			(self.mana_cost > 0 and self:ManaCost() == 0)
		)) or
		(Player.form == FORM.BEAR and (
			(self.rage_cost > 0 and self:RageCost() == 0)
		)) or
		(Player.form == FORM.CAT and (
			(self.energy_cost > 0 and self:EnergyCost() == 0) or
			(self.cp_cost > 0 and self:CPCost() == 0)
		)) or
		(Player.form == FORM.MOONKIN and (
			(self.ap_cost > 0 and self:APCost() == 0)
		))
	)
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastEnergyRegen()
	return Player.energy.regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy.current + self:CastEnergyRegen()) < (Player.energy.max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.triggers_bt then
		self.bt_trigger = self.last_used
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		clawPreviousPanel.ability = self
		clawPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		clawPreviousPanel.icon:SetTexture(self.icon)
		clawPreviousPanel:SetShown(clawPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and clawPreviousPanel.ability == self then
		clawPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration(self.next_combo_points, self.next_applied_by)
	if self.next_multiplier then
		aura.multiplier = self.next_multiplier
	end
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration(self.next_combo_points, self.next_applied_by)
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	if self.next_multiplier and (
		not self.retain_higher_multiplier or
		not aura.multiplier or
		self.next_multiplier > aura.multiplier
	) then
		aura.multiplier = self.next_multiplier
	end
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration(self.next_combo_points, self.next_applied_by)
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
		if self.next_multiplier and (
			not self.retain_higher_multiplier or
			not aura.multiplier or
			self.next_multiplier > aura.multiplier
		) then
			aura.multiplier = self.next_multiplier
		end
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

function Ability:Multiplier(guid)
	local aura = self.aura_targets[guid or Target.guid]
	return aura and aura.multiplier or 0
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Druid Abilities
---- Class
------ Baseline
local Barkskin = Ability:Add(22812, true, true)
Barkskin.buff_duration = 12
Barkskin.cooldown_duration = 90
Barkskin.off_gcd = true
Barkskin.triggers_gcd = false
local BearForm = Ability:Add(5487, true, true)
local CatForm = Ability:Add(768, true, true)
local FerociousBite = Ability:Add(22568, false, true)
FerociousBite.cp_cost = 1
FerociousBite.energy_cost = 25
FerociousBite.requires_form = FORM.CAT
local Growl = Ability:Add(6795, false, true)
Growl.buff_duration = 3
Growl.cooldown_duration = 8
Growl.requires_form = FORM.BEAR
local Mangle = Ability:Add(33917, false, true)
Mangle.cooldown_duration = 6
Mangle.hasted_cooldown = true
Mangle.requires_form = FORM.BEAR
local MarkOfTheWild = Ability:Add(1126, true)
MarkOfTheWild.buff_duration = 3600
MarkOfTheWild.mana_cost = 20
local Moonfire = Ability:Add(8921, false, true, 164812)
Moonfire.buff_duration = 18
Moonfire.tick_interval = 2
Moonfire.hasted_ticks = true
local Prowl = Ability:Add(5215, true, true, 102547)
Prowl.cooldown_duration = 6
local Rebirth = Ability:Add(20484, true, true)
Rebirth.cooldown_duration = 600
Rebirth.rage_cost = 30
local Regrowth = Ability:Add(8936, true, true)
Regrowth.buff_duration = 12
Regrowth.mana_cost = 14
Regrowth.tick_interval = 2
Regrowth.hasted_ticks = true
local Shred = Ability:Add(5221, false, true)
Shred.energy_cost = 40
Shred.triggers_bt = true
Shred.requires_form = FORM.CAT
------ Procs

------ Talents
local CircleOfLifeAndDeath = Ability:Add(391969, true, true) -- Guardian and Restoration
local ConvokeTheSpirits = Ability:Add(391528, false, true)
ConvokeTheSpirits.buff_duration = 4
ConvokeTheSpirits.cooldown_duration = 120
ConvokeTheSpirits.tick_interval = 0.25
local FrenziedRegeneration = Ability:Add(22842, true, true)
FrenziedRegeneration.buff_duration = 3
FrenziedRegeneration.cooldown_duration = 36
FrenziedRegeneration.energy_cost = 40
FrenziedRegeneration.rage_cost = 10
FrenziedRegeneration.tick_interval = 1
FrenziedRegeneration.hasted_cooldown = true
FrenziedRegeneration.requires_charge = true
local HeartOfTheWild = Ability:Add(319454, true, true, 108291)
HeartOfTheWild.buff_duration = 45
HeartOfTheWild.cooldown_duration = 300
local IncapacitatingRoar = Ability:Add(99, false, true)
IncapacitatingRoar.buff_duration = 3
IncapacitatingRoar.cooldown_duration = 30
local Ironfur = Ability:Add(192081, true, true)
Ironfur.buff_duration = 8
Ironfur.cooldown_duration = 0.5
Ironfur.rage_cost = 40
Ironfur.off_gcd = true
Ironfur.triggers_gcd = false
Ironfur.requires_form = FORM.BEAR
local Maim = Ability:Add(22570, false, true, 203123)
Maim.cooldown_duration = 20
Maim.energy_cost = 30
Maim.cp_cost = 1
Maim.requires_form = FORM.CAT
local MightyBash = Ability:Add(5211, false, true)
MightyBash.buff_duration = 4
MightyBash.cooldown_duration = 60
local MoonkinForm = Ability:Add(197625, true, true)
local NaturesVigil = Ability:Add(124974, true, true)
NaturesVigil.buff_duration = 30
NaturesVigil.cooldown_duration = 90
NaturesVigil.off_gcd = true
NaturesVigil.triggers_gcd = false
local Rake = Ability:Add(1822, false, true, 155722)
Rake.buff_duration = 15
Rake.energy_cost = 35
Rake.tick_interval = 3
Rake.hasted_ticks = true
Rake.triggers_bt = true
Rake.requires_form = FORM.CAT
Rake:Track()
Rake:AutoAoe(false, 'apply')
local Rip = Ability:Add(1079, false, true)
Rip.buff_duration = 4
Rip.energy_cost = 20
Rip.cp_cost = 1
Rip.tick_interval = 2
Rip.hasted_ticks = true
Rip.requires_form = FORM.CAT
Rip:Track()
local SkullBash = Ability:Add(106839, false, true)
SkullBash.cooldown_duration = 15
SkullBash.triggers_gcd = false
local Starfire = Ability:Add(197628, false, true)
Starfire.mana_cost = 3
local Starsurge = Ability:Add(197626, false, true)
Starsurge.cooldown_duration = 10
Starsurge.mana_cost = 3
local Sunfire = Ability:Add(93402, false, true, 164815)
Sunfire.buff_duration = 18
Sunfire.tick_interval = 2
Sunfire.hasted_ticks = true
Sunfire:AutoAoe(false, 'apply')
local SurvivalInstincts = Ability:Add(61336, true, true)
SurvivalInstincts.buff_duration = 6
SurvivalInstincts.cooldown_duration = 180
SurvivalInstincts.requires_charge = true
SurvivalInstincts.off_gcd = true
SurvivalInstincts.triggers_gcd = false
local Swipe = Ability:Add(213771, false, true)
Swipe:AutoAoe(true)
Swipe.learn_spellId = 213764
Swipe.requires_form = FORM.BEAR
local SwipeCat = Ability:Add(106785, false, true)
SwipeCat.energy_cost = 35
SwipeCat.triggers_bt = true
SwipeCat:AutoAoe(true)
SwipeCat.learn_spellId = 213764
SwipeCat.requires_form = FORM.CAT
local Thrash = Ability:Add(77758, false, true, 192090)
Thrash.buff_duration = 15
Thrash.cooldown_duration = 6
Thrash.tick_interval = 3
Thrash.hasted_cooldown = true
Thrash.hasted_ticks = true
Thrash.requires_form = FORM.BEAR
Thrash:AutoAoe(true)
local ThrashCat = Ability:Add(106830, false, true, 405233)
ThrashCat.learn_spellId = 106832
ThrashCat.buff_duration = 12
ThrashCat.energy_cost = 40
ThrashCat.tick_interval = 3
ThrashCat.hasted_ticks = true
ThrashCat.triggers_bt = true
ThrashCat.requires_form = FORM.CAT
ThrashCat:AutoAoe(true)
ThrashCat:Track()
local Typhoon = Ability:Add(132469, false, true)
Typhoon.buff_duration = 6
Typhoon.cooldown_duration = 30
local WildCharge = Ability:Add(102401, false, true)
WildCharge.cooldown_duration = 15
WildCharge.Cat = Ability:Add(49376, false, true)
WildCharge.Cat.cooldown_duration = 15
WildCharge.Cat.learn_spellId = 102401
---- Balance
------ Talents
local SolarBeam = Ability:Add(78675, false, true, 81261)
SolarBeam.buff_duration = 8
SolarBeam.cooldown_duration = 60
------ Procs

---- Feral
------ Talents
local AdaptiveSwarm = Ability:Add(391888, false, true)
AdaptiveSwarm.cooldown_duration = 25
AdaptiveSwarm.mana_cost = 5
AdaptiveSwarm:SetVelocity(12)
AdaptiveSwarm.dot = Ability:Add(391889, false, true)
AdaptiveSwarm.dot.buff_duration = 12
AdaptiveSwarm.dot.tick_interval = 2
AdaptiveSwarm.dot.hasted_ticks = true
AdaptiveSwarm.dot.learn_spellId = 391888
AdaptiveSwarm.dot:SetVelocity(12)
AdaptiveSwarm.dot:Track()
AdaptiveSwarm.hot = Ability:Add(391891, true, true)
AdaptiveSwarm.hot.buff_duration = 12
AdaptiveSwarm.hot.tick_interval = 2
AdaptiveSwarm.hot.hasted_ticks = true
AdaptiveSwarm.hot.learn_spellId = 391888
AdaptiveSwarm.hot:SetVelocity(12)
AdaptiveSwarm.hot:Track()
local AshamanesGuidance = Ability:Add(391548, false, true)
local Berserk = Ability:Add(106951, true, true)
Berserk.buff_duration = 20
Berserk.off_gcd = true
Berserk.triggers_gcd = false
local BerserkFrenzy = Ability:Add(384668, false, true)
local BrutalSlash = Ability:Add(202028, false, true)
BrutalSlash.cooldown_duration = 8
BrutalSlash.energy_cost = 25
BrutalSlash.hasted_cooldown = true
BrutalSlash.requires_charge = true
BrutalSlash.triggers_bt = true
BrutalSlash.requires_form = FORM.CAT
BrutalSlash:AutoAoe(true)
local CarnivorousInstinct = Ability:Add(390902, true, true)
CarnivorousInstinct.talent_node = 82110
local CircleOfLifeAndDeathFeral = Ability:Add(400320, true, true)
local FeralFrenzy = Ability:Add(274837, false, true, 274838)
FeralFrenzy.buff_duration = 6
FeralFrenzy.cooldown_duration = 45
FeralFrenzy.energy_cost = 25
FeralFrenzy.tick_interval = 2
FeralFrenzy.hasted_ticks = true
FeralFrenzy.triggers_bt = true
FeralFrenzy.requires_form = FORM.CAT
local IncarnationAvatarOfAshamane = Ability:Add(102543, true, true)
IncarnationAvatarOfAshamane.buff_duration = 30
IncarnationAvatarOfAshamane.cooldown_duration = 180
IncarnationAvatarOfAshamane.off_gcd = true
IncarnationAvatarOfAshamane.triggers_gcd = false
IncarnationAvatarOfAshamane.prowl = Ability:Add(252071, true, true)
local MomentOfClarity = Ability:Add(236068, true, true)
local MoonfireCat = Ability:Add(155625, false, true)
MoonfireCat.buff_duration = 16
MoonfireCat.energy_cost = 30
MoonfireCat.tick_interval = 2
MoonfireCat.hasted_ticks = true
MoonfireCat.triggers_bt = true
MoonfireCat.learn_spellId = 155580 -- Lunar Inspiration
MoonfireCat:Track()
local PrimalWrath = Ability:Add(285381, false, true)
PrimalWrath.energy_cost = 1
PrimalWrath.cp_cost = 1
PrimalWrath.requires_form = FORM.CAT
PrimalWrath:AutoAoe(true)
local SoulOfTheForest = Ability:Add(158476, true, true)
local TigersFury = Ability:Add(5217, true, true)
TigersFury.buff_duration = 10
TigersFury.cooldown_duration = 30
TigersFury.triggers_gcd = false
TigersFury.requires_form = FORM.CAT
local Veinripper = Ability:Add(391978, true, true)
------ Procs
local ApexPredatorsCraving = Ability:Add(391881, true, true, 391882)
ApexPredatorsCraving.buff_duration = 15
local Bloodtalons = Ability:Add(319439, true, true, 145152)
Bloodtalons.buff_duration = 30
Bloodtalons:Track()
local Clearcasting = Ability:Add(16864, true, true, 135700)
Clearcasting.buff_duration = 15
local PredatorySwiftness = Ability:Add(16974, true, true, 69369)
PredatorySwiftness.buff_duration = 12
local Sabertooth = Ability:Add(202031, false, true, 391722)
Sabertooth.buff_duration = 4
local SuddenAmbush = Ability:Add(384667, true, true, 391974)
SuddenAmbush.buff_duration = 15
---- Guardian
------ Talents
local Brambles = Ability:Add(203953, false, true, 213709)
Brambles.tick_interval = 1
Brambles:AutoAoe()
local BristlingFur = Ability:Add(155835, true, true)
BristlingFur.buff_duration = 8
BristlingFur.cooldown_duration = 40
BristlingFur.requires_form = FORM.BEAR
local DreamOfCenarius = Ability:Add(372119, true, true, 372152)
DreamOfCenarius.buff_duration = 30
local FlashingClaws = Ability:Add(393427, false, true)
FlashingClaws.talent_node = 82154
local FuryOfNature = Ability:Add(370695, false, true)
local Gore = Ability:Add(210706, true, true, 93622)
Gore.buff_duration = 10
local GoryFur = Ability:Add(200854, true, true, 201671)
local IncarnationGuardianOfUrsoc = Ability:Add(102558, true, true)
IncarnationGuardianOfUrsoc.buff_duration = 30
IncarnationGuardianOfUrsoc.cooldown_duration = 180
IncarnationGuardianOfUrsoc.off_gcd = true
IncarnationGuardianOfUrsoc.triggers_gcd = false
local LunarBeam = Ability:Add(204066, true, true, 204069)
LunarBeam.buff_duration = 8.5
LunarBeam.cooldown_duration = 60
LunarBeam.damage = Ability:Add(414613, false, true)
local Maul = Ability:Add(6807, false, true)
Maul.rage_cost = 40
Maul.requires_form = FORM.BEAR
local Pulverize = Ability:Add(80313, false, true)
Pulverize.buff_duration = 10
Pulverize.cooldown_duration = 45
Pulverize.requires_form = FORM.BEAR
local RageOfTheSleeper = Ability:Add(200851, true, true)
RageOfTheSleeper.buff_duration = 10
RageOfTheSleeper.cooldown_duration = 60
RageOfTheSleeper.off_gcd = true
RageOfTheSleeper.triggers_gcd = false
RageOfTheSleeper.requires_form = FORM.BEAR
local Raze = Ability:Add(400254, false, true)
Raze.rage_cost = 40
Raze.requires_form = FORM.BEAR
Raze:AutoAoe()
local ReinforcedFur = Ability:Add(393618, false, true)
local ThornsOfIron = Ability:Add(400222, false, true, 400223)
ThornsOfIron:AutoAoe()
local ToothAndClaw = Ability:Add(135288, true, true, 135286)
ToothAndClaw.buff_duration = 15
ToothAndClaw.debuff = Ability:Add(135601, false, true)
ToothAndClaw.debuff.buff_duration = 6
local UncheckedAggression = Ability:Add(377623, true, true)
local ViciousCycle = Ability:Add(371999, true, true)
ViciousCycle.Mangle = Ability:Add(372019, true, true)
ViciousCycle.Mangle.buff_duration = 15
ViciousCycle.Maul = Ability:Add(372015, true, true)
ViciousCycle.Maul.buff_duration = 15
------ Procs
local GalacticGuardian = Ability:Add(203964, false, true, 213708)
GalacticGuardian.buff_duration = 15
---- Restoration

------ Talents

------ Procs

-- Hero talents
local EmpoweredShapeshifting = Ability:Add(441689, true, true)
local Ravage = Ability:Add(441583, true, true)
RavageBear = Ability:Add(441605, true, true, 441602)
RavageBear.buff_duration = 15
RavageBear.rage_cost = 40
RavageBear.requires_form = FORM.BEAR
RavageBear.requires_react = true
RavageCat = Ability:Add(441591, true, true, 441585)
RavageCat.buff_duration = 15
RavageCat.cp_cost = 1
RavageCat.energy_cost = 25
RavageCat.requires_form = FORM.CAT
RavageCat.requires_react = true
local DreadfulWound = Ability:Add(441809, false, true, 441812)
DreadfulWound.buff_duration = 6
DreadfulWound.tick_interval = 2
DreadfulWound.retain_higher_multiplier = true
DreadfulWound:Track()
-- PvP talents
local Thorns = Ability:Add(305497, true, true)
Thorns.buff_duration = 12
Thorns.cooldown_duration = 45
-- Racials
local Shadowmeld = Ability:Add(58984, true, true)
-- Trinket effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

local InventoryItems = {
	all = {},
	byItemId = {},
}

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	wipe(self.bloodtalons)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
			if ability.triggers_bt then
				self.bloodtalons[#self.bloodtalons + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:Stealthed()
	return Prowl:Up() or (Shadowmeld.known and Shadowmeld:Up()) or (IncarnationAvatarOfAshamane.known and self.berserk_up)
end

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

function Player:EnergyTimeToMax(energy)
	local deficit = (energy or self.energy.max) - self.energy.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.energy.regen
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	self.bs_inc = Berserk
	if IncarnationAvatarOfAshamane.known then
		IncarnationAvatarOfAshamane.prowl.known = true
		Berserk.known = false
		self.bs_inc = IncarnationAvatarOfAshamane
	elseif IncarnationGuardianOfUrsoc.known then
		Berserk.known = false
		self.bs_inc = IncarnationGuardianOfUrsoc
	end
	if BrutalSlash.known then
		SwipeCat.known = false
	end
	if Rip.known then
		Rip.multiplier_max = Rip:MultiplierMax()
	end
	if Ravage.known then
		RavageBear.known = Player.spec == SPEC.GUARDIAN
		RavageCat.known = Player.spec == SPEC.FERAL
	end

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed, speed_mh, speed_oh
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self.pool_energy = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability and self.cast.ability.mana_cost > 0 then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	if self.form == FORM.CAT then
		self.gcd = 1
		self.energy.regen = GetPowerRegenForPowerType(3)
		self.energy.current = UnitPower('player', 3) + (self.energy.regen * self.execute_remains)
		self.energy.current = clamp(self.energy.current, 0, self.energy.max)
		self.energy.deficit = self.energy.max - self.energy.current
		self.combo_points.current = UnitPower('player', 4)
	else
		self.gcd = 1.5 * self.haste_factor
	end
	if self.form == FORM.BEAR then
		self.rage.current = UnitPower('player', 1)
		self.rage.deficit = self.rage.max - self.rage.current
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self:UpdateThreat()

	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.berserk_remains = self.bs_inc:Remains()
	self.berserk_up = self.berserk_remains > 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if not self.initialized then
		UI:ScanActionButtons()
		UI:ScanActionSlots()
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	clawPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * (
		15 + (Player.spec == SPEC.RESTORATION and 10 or 0) + (Player.spec == SPEC.GUARDIAN and 5 or 0)
	)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			clawPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			clawPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		clawPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return MightyBash:Up() or Maim:Up()
end

-- End Target Functions

-- Start Ability Modifications

function Ability:EnergyCost()
	local cost  = self.energy_cost
	if Player.spec == SPEC.FERAL then
		if (self == Shred or self == ThrashCat or self == SwipeCat) and Clearcasting:Up() then
			return 0
		end
		if IncarnationAvatarOfAshamane.known and IncarnationAvatarOfAshamane:Up() then
			cost = cost - (cost * 0.20)
		end
	end
	return cost
end

function Ability:Bloodtalons()
	return self.bt_trigger and (Player.time - self.bt_trigger) < 4
end

function Bloodtalons:ApplyAura(...)
	Ability.ApplyAura(self, ...)
	self:Reset()
end

function Bloodtalons:RefreshAura(...)
	Ability.RefreshAura(self, ...)
	self:Reset()
end

function Bloodtalons:ActiveTriggers()
	local count = 0
	local _, ability
	for _, ability in next, Abilities.bloodtalons do
		if ability:Bloodtalons() then
			count = count + 1
		end
	end
	return count
end

function Bloodtalons:SecondsSinceLastTrigger()
	local seconds = 5
	local _, ability
	for _, ability in next, Abilities.bloodtalons do
		if ability.bt_trigger and (Player.time - ability.bt_trigger) < seconds then
			seconds = Player.time - ability.bt_trigger
		end
	end
	return seconds
end

function Bloodtalons:Reset()
	local _, ability
	for _, ability in next, Abilities.bloodtalons do
		ability.bt_trigger = 0
	end
end

function FerociousBite:Usable(...)
	if RavageCat.known and RavageCat:Up() then
		return false
	end
	return Ability.Usable(self, ...)
end

function FerociousBite:CPCost()
	if ApexPredatorsCraving.known and ApexPredatorsCraving:Up() then
		return 0
	end
	return Ability.CPCost(self)
end
RavageCat.CPCost = FerociousBite.CPCost

function FerociousBite:EnergyCost()
	if ApexPredatorsCraving.known and ApexPredatorsCraving:Up() then
		return 0
	end
	return Ability.EnergyCost(self)
end
RavageCat.EnergyCost = FerociousBite.EnergyCost

function Regrowth:ManaCost()
	if PredatorySwiftness:Up() then
		return 0
	end
	return Ability.ManaCost(self)
end

function TigersFury:Multiplier()
	local multiplier = 1.15
	if CarnivorousInstinct.known then
		multiplier = multiplier + CarnivorousInstinct.rank * 0.06
	end
	return multiplier
end

function Rake:Duration()
	local duration = self.buff_duration
	if CircleOfLifeAndDeath.known then
		duration = duration * 0.75
	elseif CircleOfLifeAndDeathFeral.known then
		duration = duration * 0.80
	end
	if Veinripper.known then
		duration = duration * 1.25
	end
	return duration
end
Thrash.Duration = Rake.Duration
ThrashCat.Duration = Rake.Duration

function Rake:NextMultiplier()
	local multiplier, stealthed, aura = 1.00, false
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		elseif Shadowmeld:Match(aura.spellId) or Prowl:Match(aura.spellId) or Berserk:Match(aura.spellId) or IncarnationAvatarOfAshamane:Match(aura.spellId) or SuddenAmbush:Match(aura.spellId) then
			stealthed = true
		elseif TigersFury:Match(aura.spellId) then
			multiplier = multiplier * TigersFury:Multiplier()
		end
	end
	if stealthed then
		multiplier = multiplier * 1.60
	end
	return multiplier
end

function Rip:Duration(comboPoints, appliedBy)
	local duration = self.buff_duration + (self.buff_duration * (comboPoints or Player.combo_points.current))
	if appliedBy == PrimalWrath then
		duration = duration * 0.50
	end
	if CircleOfLifeAndDeath.known then
		duration = duration * 0.75
	elseif CircleOfLifeAndDeathFeral.known then
		duration = duration * 0.80
	end
	if Veinripper.known then
		duration = duration * 1.25
	end
	return duration
end

function Rip:MultiplierSum()
	local sum, guid, aura = 0
	for guid, aura in next, self.aura_targets do
		if AutoAoe.targets[guid] then
			sum = sum + (aura.multiplier or 0)
		end
	end
	return sum
end

function Rip:MultiplierMax()
	local multiplier = 1.00
	if TigersFury.known then
		multiplier = multiplier * TigersFury:Multiplier()
	end
	if Bloodtalons.known then
		multiplier = multiplier * 1.25
	end
	return multiplier
end

function Rip:NextMultiplier()
	local multiplier, aura = 1.00
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		elseif TigersFury:Match(aura.spellId) then
			multiplier = multiplier * TigersFury:Multiplier()
		elseif Bloodtalons:Match(aura.spellId) then
			multiplier = multiplier * 1.25
		end
	end
	return multiplier
end

function PrimalWrath:Multiplier()
	return Rip:Multiplier()
end

function PrimalWrath:NextMultiplier()
	return Rip:NextMultiplier()
end

function Moonfire:Duration()
	local duration = self.buff_duration
	if CircleOfLifeAndDeathFeral.known then
		duration = duration * 0.80
	end
	if CircleOfLifeAndDeath.known then
		duration = duration * 0.75
	end
	return duration
end
MoonfireCat.Duration = Moonfire.Duration
AdaptiveSwarm.dot.Duration = Moonfire.Duration
AdaptiveSwarm.hot.Duration = Moonfire.Duration

function MoonfireCat:NextMultiplier()
	local multiplier, aura = 1.00
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		elseif TigersFury:Match(aura.spellId) then
			multiplier = multiplier * TigersFury:Multiplier()
		end
	end
	return multiplier
end

DreadfulWound.NextMultiplier = MoonfireCat.NextMultiplier

function RavageCat:Multiplier()
	return DreadfulWound:Multiplier()
end

function RavageCat:NextMultiplier()
	return max(DreadfulWound:Multiplier(), DreadfulWound:NextMultiplier())
end

function Shred:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if Opt.auto_aoe and not Bloodtalons.known and Player.berserk_remains == 0 then
		Player:SetTargetMode(1)
	end
end

function ThrashCat:NextMultiplier()
	local multiplier, aura = 1.00
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not aura then
			break
		end
		if TigersFury:Match(aura.spellId) then
			multiplier = multiplier * TigersFury:Multiplier()
		end
	end
	return multiplier
end

function Prowl:Usable(...)
	if Prowl:Up() or Shadowmeld:Up() or (InCombatLockdown() and not IncarnationAvatarOfAshamane.prowl:Up()) then
		return false
	end
	return Ability.Usable(self, ...)
end

function Shadowmeld:Usable(...)
	if Prowl:Up() or Shadowmeld:Up() or not UnitInParty('player') then
		return false
	end
	return Ability.Usable(self, ...)
end

function Maim:Usable(...)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, ...)
end
MightyBash.Usable = Maim.Usable
Typhoon.Usable = Maim.Usable

function AdaptiveSwarm.dot:CastLanded(...)
	AdaptiveSwarm:CastLanded(...)
end
AdaptiveSwarm.hot.CastLanded = AdaptiveSwarm.dot.CastLanded

function Thrash:MaxStack()
	return 3 + FlashingClaws.rank
end

function Ironfur:RageCost()
	local cost = Ability.RageCost(self)
	if GoryFur.known and GoryFur:Up() then
		cost = cost * (1 - 0.25)
	end
	return cost
end

function Maul:Usable(...)
	if RavageBear.known and RavageBear:Up() then
		return false
	end
	return Ability.Usable(self, ...)
end

function Maul:RageCost()
	if ToothAndClaw.known and ToothAndClaw:Up() then
		return 0
	end
	local cost = Ability.RageCost(self)
	if UncheckedAggression.known and Player.berserk_up then
		cost = cost * 0.50
	end
	return cost
end
Raze.RageCost = Maul.RageCost
RavageBear.RageCost = Maul.RageCost

function ConvokeTheSpirits:Duration()
	local duration = self.buff_duration
	if AshamanesGuidance.known then
		duration = duration * (1 - 0.25)
	end
	return duration
end

function Regrowth:Free()
	return PredatorySwiftness.known and PredatorySwiftness:Up()
end

function FrenziedRegeneration:Usable(...)
	if not (
		Player.form == FORM.BEAR or
		(Player.form == FORM.CAT and EmpoweredShapeshifting.known)
	) then
		return false
	end
	return Ability.Usable(self, ...)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function Pool(ability, extra)
	Player.pool_energy = ability:EnergyCost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 300 then
			return MarkOfTheWild
		end
	else
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 10 then
			UseExtra(MarkOfTheWild)
		end
	end
end

APL[SPEC.BALANCE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 300 then
			return MarkOfTheWild
		end
	else
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 10 then
			UseExtra(MarkOfTheWild)
		end
	end
end

APL[SPEC.FERAL].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/cat_form
actions.precombat+=/prowl
]]
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 300 then
			return MarkOfTheWild
		end
		if Prowl:Usable() then
			UseCooldown(Prowl)
		end
		if CatForm:Down() then
			return CatForm
		end
	else
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 10 then
			UseExtra(MarkOfTheWild)
		end
	end
--[[
actions=prowl
actions+=/invoke_external_buff,name=power_infusion,if=buff.bs_inc.up|fight_remains<cooldown.bs_inc.remains
actions+=/variable,name=need_bt,value=talent.bloodtalons.enabled&buff.bloodtalons.down
actions+=/tigers_fury
actions+=/rake,if=buff.prowl.up|buff.shadowmeld.up
actions+=/cat_form,if=!buff.cat_form.up
actions+=/auto_attack,if=!buff.prowl.up&!buff.shadowmeld.up
actions+=/call_action_list,name=cooldown
actions+=/feral_frenzy,if=combo_points<2|combo_points=2&buff.bs_inc.up
actions+=/run_action_list,name=aoe,if=spell_targets.swipe_cat>1&talent.primal_wrath.enabled
actions+=/ferocious_bite,if=buff.apex_predators_craving.up&(buff.apex_predators_craving.remains<2|dot.rip.ticking)
actions+=/run_action_list,name=bloodtalons,if=variable.need_bt&!buff.bs_inc.up&(combo_points<5|active_bt_triggers>1)
actions+=/run_action_list,name=finisher,if=combo_points=5
actions+=/run_action_list,name=berserk_builders,if=combo_points<5&buff.bs_inc.up
actions+=/run_action_list,name=builder,if=combo_points<5
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or Player.berserk_up
	self.need_bt = Bloodtalons.known and Bloodtalons:Down()
	if TigersFury:Usable() and TigersFury:Down() then
		UseCooldown(TigersFury)
	end
	if CatForm:Down() then
		return CatForm
	end
	if Prowl:Up() or Shadowmeld:Up() then
		return Rake
	end
	self:cooldown()
	if Player.health.pct < 85 and not Player:Stealthed() then
		if Regrowth:Usable() and (Player.health.pct <= Opt.heal or Player.combo_points.current >= 5) and Regrowth:Free() and Regrowth:WontCapEnergy() then
			UseExtra(Regrowth)
		elseif FrenziedRegeneration:Usable() and Player.health.pct <= Opt.heal and FrenziedRegeneration:Down() then
			UseExtra(FrenziedRegeneration)
		elseif NaturesVigil:Usable() then
			UseExtra(NaturesVigil)
		end
	end
	if FeralFrenzy:Usable() and Player.combo_points.current < (Player.berserk_up and 3 or 2) then
		return FeralFrenzy
	end
	if Player.enemies > 1 and PrimalWrath.known then
		return self:aoe()
	end
	if ApexPredatorsCraving.known and RavageCat:Usable() and ApexPredatorsCraving:Up() and (ApexPredatorsCraving:Remains() < 2 or Rip:Up()) then
		return RavageCat
	end
	if ApexPredatorsCraving.known and FerociousBite:Usable() and ApexPredatorsCraving:Up() and (ApexPredatorsCraving:Remains() < 2 or Rip:Up()) then
		return FerociousBite
	end
	if self.need_bt and Player.berserk_remains == 0 and (Player.combo_points.current < 5 or Bloodtalons:ActiveTriggers() > 1) then
		return self:bloodtalons()
	end
	if Player.combo_points.current >= 5 then
		return self:finisher()
	end
	if Player.berserk_up then
		return self:berserk_builders()
	end
	return self:builder()
end

APL[SPEC.FERAL].cooldown = function(self)
--[[
actions.cooldown=berserk
actions.cooldown+=/incarnation
actions.cooldown+=/convoke_the_spirits,if=buff.tigers_fury.up&combo_points<3|fight_remains<5
actions.cooldown+=/berserking
actions.cooldown+=/adaptive_swarm,target_if=((!dot.adaptive_swarm_damage.ticking|dot.adaptive_swarm_damage.remains<2)&(dot.adaptive_swarm_damage.stack<3|!dot.adaptive_swarm_heal.stack>1)&!action.adaptive_swarm_heal.in_flight&!action.adaptive_swarm_damage.in_flight&!action.adaptive_swarm.in_flight)&target.time_to_die>5|active_enemies>2&!dot.adaptive_swarm_damage.ticking&energy<35&target.time_to_die>5
actions.cooldown+=/shadowmeld,if=buff.tigers_fury.up&buff.bs_inc.down&combo_points<4&buff.sudden_ambush.down&dot.rake.pmultiplier<1.6&energy>40&druid.rake.ticks_gained_on_refresh>spell_targets.swipe_cat*2-2&target.time_to_die>5
actions.cooldown+=/potion,if=buff.bs_inc.up|fight_remains<cooldown.bs_inc.remains|fight_remains<35
actions.cooldown+=/use_item,name=manic_grieftorch,if=energy.deficit>40
actions.cooldown+=/use_items
]]
	if AdaptiveSwarm:Usable() and Target.timeToDie > 5 and AdaptiveSwarm.dot:Up() and AdaptiveSwarm.dot:Remains() < (3 + AdaptiveSwarm:TravelTime()) then
		return UseCooldown(AdaptiveSwarm)
	end
	if self.use_cds and Player.bs_inc:Usable() then
		return UseCooldown(Player.bs_inc)
	end
	if self.use_cds and ConvokeTheSpirits:Usable() and ((Player.combo_points.current < 3 and TigersFury:Remains() > 3) or (Target.boss and Target.timeToDie < 5)) then
		return UseCooldown(ConvokeTheSpirits)
	end
	if TigersFury:Usable() and (Player.energy.deficit > 60 or (TigersFury:Remains() < 2 and (Player.berserk_up or (Bloodtalons.known and Rip:Refreshable() and Bloodtalons:Up())))) then
		return UseCooldown(TigersFury)
	end
	if Thorns:Usable() and Player:UnderAttack() and Thorns:WontCapEnergy() then
		return UseCooldown(Thorns)
	end
	if AdaptiveSwarm:Usable() and Target.timeToDie > 5 and (Rip:Up() or Player.energy.current < 35) and ((AdaptiveSwarm:Traveling() == 0 and (AdaptiveSwarm.dot:Ticking() == 0 or AdaptiveSwarm.dot:Remains() < (Player.gcd * 2)) and (AdaptiveSwarm.dot:Stack() < 3 or AdaptiveSwarm.hot:Stack() <= 1)) or (Player.enemies > 2 and AdaptiveSwarm.dot:Ticking() == 0 and Player.energy.current < 35)) then
		return UseCooldown(AdaptiveSwarm)
	end
	if self.use_cds and Shadowmeld:Usable() and Player.combo_points.current < 4 and Rake:Usable() and Rake:Multiplier() < 1.6 and TigersFury:Remains() > 1.5 and Player.berserk_remains == 0 and SuddenAmbush:Down() and not Player.bs_inc:Ready(Rake:Duration()) then
		return UseCooldown(Shadowmeld)
	end
--[[
	if Opt.pot and Target.boss and ElementalPotionOfPower:Usable() and (Player.berserk_up or Target.timeToDie < 35 or not Player.bs_inc:Ready(Target.timeToDie)) then
		return UseCooldown(ElementalPotionOfPower)
	end
--]]
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.FERAL].aoe = function(self)
--[[
actions.aoe=pool_resource,for_next=1
actions.aoe+=/primal_wrath,if=combo_points=5
actions.aoe+=/ferocious_bite,if=buff.apex_predators_craving.up&debuff.sabertooth.down
actions.aoe+=/run_action_list,name=bloodtalons,if=variable.need_bt&active_bt_triggers>=1
actions.aoe+=/pool_resource,for_next=1
actions.aoe+=/thrash_cat,target_if=refreshable
# At this target count BRS also crushes everything except full thrashes
actions.aoe+=/brutal_slash
# This means that a full rake (5.5+ ticks) is stronger up to 10ish targets
actions.aoe+=/pool_resource,for_next=1
actions.aoe+=/rake,target_if=max:dot.rake.ticks_gained_on_refresh.pmult,if=((dot.rake.ticks_gained_on_refresh.pmult*(1+talent.doubleclawed_rake.enabled))>(spell_targets.swipe_cat*0.216+3.32))
# Full Lis beat Swipe up til around 3-ish targets depending on haste
actions.aoe+=/lunar_inspiration,target_if=max:((ticks_gained_on_refresh+1)-(spell_targets.swipe_cat*2.492))
actions.aoe+=/swipe_cat
# If we have BrS and nothing better to cast, check if Thrash DD beats Shred
actions.aoe+=/shred,if=action.shred.damage>action.thrash_cat.damage
actions.aoe+=/thrash_cat
]]
	if RavageCat:Usable() and (
		(Player.combo_points.current >= 5 and Rip:Ticking() >= Player.enemies and Rip:LowestRemains() > (Rip:TickTime() * (Player.berserk_remains > 3 and 2 or 3))) or
		(ApexPredatorsCraving.known and ApexPredatorsCraving:Up() and (ApexPredatorsCraving:Remains() < (Player.gcd * 2) or Rip:Up())) or
		(Player.combo_points.current >= 3 and RavageCat:React() < (Player.gcd * 2))
	) then
		return Pool(RavageCat)
	end
	if FerociousBite:Usable() and Player.enemies <= 5 and Player.combo_points.current >= 5 and Rip:LowestRemains() > (Rip:TickTime() * (4 + (RavageCat.known and 1 or 0) - (Player.berserk_remains > 3 and 1 or 0))) then
		return Pool(FerociousBite)
	end
	if PrimalWrath:Usable(0, true) and Player.combo_points.current >= 5 then
		return Pool(PrimalWrath)
	end
	if ApexPredatorsCraving.known and FerociousBite:Usable() and ApexPredatorsCraving:Up() and (ApexPredatorsCraving:Remains() < (Player.gcd * 2) or (Rip:Up() and Sabertooth:Down())) then
		return FerociousBite
	end
	if self.need_bt and Bloodtalons:ActiveTriggers() >= 1 then
		return self:bloodtalons()
	end
	if ThrashCat:Usable(0, true) and ThrashCat:Refreshable() then
		return Pool(ThrashCat)
	end
	if BrutalSlash:Usable() then
		return BrutalSlash
	end
	if Rake:Usable(0, true) and (Rake:Refreshable() or (SuddenAmbush:Up() and Rake:NextMultiplier() > Rake:Multiplier())) then -- this one will take some work...
		return Pool(Rake)
	end
	if MoonfireCat:Usable() and MoonfireCat:Refreshable() and Player.enemies < 5 then
		return MoonfireCat
	end
	if SwipeCat:Usable(0, true) then
		return Pool(SwipeCat)
	end
	if Shred:Usable() and Player.enemies < 5 then
		return Shred
	end
	if ThrashCat:Usable() then
		return ThrashCat
	end
end

APL[SPEC.FERAL].bloodtalons = function(self)
--[[
actions.bloodtalons=rake,target_if=max:druid.rake.ticks_gained_on_refresh,if=(refreshable|1.4*persistent_multiplier>dot.rake.pmultiplier)&buff.bt_rake.down
actions.bloodtalons+=/lunar_inspiration,if=refreshable&buff.bt_moonfire.down
actions.bloodtalons+=/brutal_slash,if=buff.bt_brutal_slash.down
actions.bloodtalons+=/thrash_cat,target_if=refreshable&buff.bt_thrash.down
actions.bloodtalons+=/swipe_cat,if=spell_targets.swipe_cat>1&buff.bt_swipe.down
actions.bloodtalons+=/shred,if=buff.bt_shred.down
actions.bloodtalons+=/swipe_cat,if=buff.bt_swipe.down
actions.bloodtalons+=/thrash_cat,if=buff.bt_thrash.down
actions.bloodtalons+=/rake,if=buff.bt_rake.down&combo_points>4
]]
	if Rake:Usable() and not Rake:Bloodtalons() and (Rake:Refreshable() or (1.4 * Rake:NextMultiplier()) > Rake:Multiplier()) then
		return Rake
	end
	if MoonfireCat:Usable() and not MoonfireCat:Bloodtalons() and MoonfireCat:Refreshable() then
		return MoonfireCat
	end
	if BrutalSlash:Usable() and not BrutalSlash:Bloodtalons() then
		return BrutalSlash
	end
	if ThrashCat:Usable() and not ThrashCat:Bloodtalons() and ThrashCat:Refreshable() and (Player.enemies > 1 or Target.timeToDie > (ThrashCat:Remains() + ThrashCat:TickTime() * 4)) then
		return ThrashCat
	end
	if SwipeCat:Usable() and Player.enemies > 1 and not SwipeCat:Bloodtalons() then
		return SwipeCat
	end
	if Shred:Usable() and not Shred:Bloodtalons() then
		return Shred
	end
	if SwipeCat:Usable() and not SwipeCat:Bloodtalons() then
		return SwipeCat
	end
	if ThrashCat:Usable() and not ThrashCat:Bloodtalons() then
		return ThrashCat
	end
	if MoonfireCat:Usable() and not MoonfireCat:Bloodtalons() then
		return MoonfireCat
	end
	if Rake:Usable() and not Rake:Bloodtalons() and Player.combo_points.current > 4 then
		return ThrashCat
	end
end

APL[SPEC.FERAL].finisher = function(self)
--[[
actions.finisher=primal_wrath,if=spell_targets.primal_wrath>2
actions.finisher+=/primal_wrath,target_if=refreshable,if=spell_targets.primal_wrath>1
actions.finisher+=/rip,target_if=refreshable
actions.finisher+=/pool_resource,for_next=1
actions.finisher+=/ferocious_bite,max_energy=1,if=!buff.bs_inc.up|(buff.bs_inc.up&!talent.soul_of_the_forest.enabled)
actions.finisher+=/ferocious_bite,if=(buff.bs_inc.up&talent.soul_of_the_forest.enabled)
]]
	if RavageCat:Usable(0, true) and Target.timeToDie < 2 then
		return Pool(RavageCat)
	end
	if PrimalWrath:Usable(0, true) and (Player.enemies > 2 or (Player.enemies > 1 and Rip:Refreshable(nil, PrimalWrath))) then
		return Pool(PrimalWrath)
	end
	if Rip:Usable(0, true) and Rip:Refreshable() and Target.timeToDie > (Rip:Remains() + Rip:TickTime() * 4) then
		return Pool(Rip)
	end
	if RavageCat:Usable(0, true) then
		return Pool(RavageCat, (Player.berserk_remains == 0 or not SoulOfTheForest.known) and Target.timeToDie > 2 and 25 or 0)
	end
	if FerociousBite:Usable(0, true) then
		return Pool(FerociousBite, (Player.berserk_remains == 0 or not SoulOfTheForest.known) and Target.timeToDie > 2 and 25 or 0)
	end
end

APL[SPEC.FERAL].clearcasting = function(self)
--[[
actions.clearcasting=thrash_cat,if=refreshable
actions.clearcasting+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.clearcasting+=/brutal_slash,if=spell_targets.brutal_slash>5&talent.moment_of_clarity.enabled
actions.clearcasting+=/shred
]]
	if ThrashCat:Usable() and ThrashCat:Refreshable() then
		return ThrashCat
	end
	if SwipeCat:Usable() and Player.enemies > 1 then
		return SwipeCat
	end
	if BrutalSlash:Usable() and Player.enemies > 5 and MomentOfClarity.known then
		return BrutalSlash
	end
	if Shred:Usable() then
		return Shred
	end
end

APL[SPEC.FERAL].berserk_builders = function(self)
--[[
actions.berserk_builders=rake,target_if=refreshable
actions.berserk_builders+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.berserk_builders+=/brutal_slash,if=active_bt_triggers=2&buff.bt_brutal_slash.down|charges>=2&spell_targets.brutal_slash>2
actions.berserk_builders+=/moonfire_cat,target_if=refreshable
actions.berserk_builders+=/shred
]]
	if Rake:Usable() and Rake:Refreshable() then
		return Rake
	end
	if SwipeCat:Usable() and Player.enemies > 1 then
		return SwipeCat
	end
	if BrutalSlash:Usable() and ((Bloodtalons:ActiveTriggers() == 2 and not BrutalSlash:Bloodtalons()) or (BrutalSlash:Charges() >= 2 and Player.enemies > 2)) then
		return BrutalSlash
	end
	if MoonfireCat:Usable() and MoonfireCat:Refreshable() then
		return MoonfireCat
	end
	if Shred:Usable() then
		return Shred
	end
end

APL[SPEC.FERAL].builder = function(self)
--[[
actions.builder=run_action_list,name=clearcasting,if=buff.clearcasting.react
actions.builder+=/rake,target_if=max:ticks_gained_on_refresh,if=refreshable|(buff.sudden_ambush.up&persistent_multiplier>dot.rake.pmultiplier&dot.rake.duration>6)
actions.builder+=/moonfire_cat,target_if=refreshable
actions.builder+=/pool_resource,for_next=1
actions.builder+=/thrash_cat,target_if=refreshable
actions.builder+=/brutal_slash
actions.builder+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.builder+=/shred
]]
	if Clearcasting:Up() then
		return self:clearcasting()
	end
	if Rake:Usable(0, true) and (Rake:Refreshable() or (SuddenAmbush:Up() and Rake:NextMultiplier() > Rake:Multiplier())) then
		return Pool(Rake)
	end
	if MoonfireCat:Usable() and MoonfireCat:Refreshable() then
		return MoonfireCat
	end
	if ThrashCat:Usable(0, true) and ThrashCat:Refreshable() and (Player.enemies > 1 or Target.timeToDie > (ThrashCat:Remains() + ThrashCat:TickTime() * 4)) then
		return Pool(ThrashCat)
	end
	if BrutalSlash:Usable() then
		return BrutalSlash
	end
	if SwipeCat:Usable(0, true) and Player.enemies > 1 then
		return Pool(SwipeCat)
	end
	if Shred:Usable() then
		return Shred
	end
end

APL[SPEC.GUARDIAN].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 300 then
			return MarkOfTheWild
		end
	else
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 10 then
			UseExtra(MarkOfTheWild)
		end
	end
--[[
actions=auto_attack,if=!buff.prowl.up
actions+=/use_item,slot=trinket1
actions+=/use_item,slot=trinket2
actions+=/potion,if=((talent.heart_of_the_wild.enabled&buff.heart_of_the_wild.up)|((buff.berserk_bear.up|buff.incarnation_guardian_of_ursoc.up)&(!druid.catweave_bear&!druid.owlweave_bear)))
actions+=/run_action_list,name=catweave,if=(target.cooldown.pause_action.remains|time>=30)&druid.catweave_bear=1&buff.tooth_and_claw.remains>1.5&(buff.incarnation_guardian_of_ursoc.down&buff.berserk_bear.down)&(cooldown.thrash_bear.remains>0&cooldown.mangle.remains>0&dot.moonfire.remains>=2)|(buff.cat_form.up&energy>25&druid.catweave_bear=1&buff.tooth_and_claw.remains>1.5)|(buff.heart_of_the_wild.up&energy>90&druid.catweave_bear=1&buff.tooth_and_claw.remains>1.5)
actions+=/run_action_list,name=bear
]]
	if Player.health.pct <= Opt.heal then
		if FrenziedRegeneration:Usable() and FrenziedRegeneration:Down() and FrenziedRegeneration:ChargesFractional() >= 1.5 then
			UseExtra(FrenziedRegeneration)
		end
		if DreamOfCenarius.known and Regrowth:Usable() and DreamOfCenarius:Up() and FrenziedRegeneration:Remains() < 1 then
			UseExtra(Regrowth)
		end
		if FrenziedRegeneration:Usable() and FrenziedRegeneration:Down() then
			UseExtra(FrenziedRegeneration)
		end
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
	return self:bear()
end

APL[SPEC.GUARDIAN].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=If_build,value=1,value_else=0,if=talent.thorns_of_iron.enabled&talent.reinforced_fur.enabled
actions.precombat+=/cat_form,if=(druid.catweave_bear=1&(cooldown.pause_action.remains|time>30))
actions.precombat+=/moonkin_form,if=(!druid.catweave_bear=1)&(cooldown.pause_action.remains|time>30)
actions.precombat+=/heart_of_the_Wild,if=talent.heart_of_the_wild.enabled
actions.precombat+=/prowl,if=druid.catweave_bear=1&(cooldown.pause_action.remains|time>30)
actions.precombat+=/bear_form,if=(!buff.prowl.up)
]]
	self.If_build = ThornsOfIron.known and ReinforcedFur.known
end

APL[SPEC.GUARDIAN].bear = function(self)
--[[
actions.bear=bear_form,if=!buff.bear_form.up
actions.bear+=/heart_of_the_Wild,if=talent.heart_of_the_wild.enabled
actions.bear+=/moonfire,cycle_targets=1,if=(((!ticking&time_to_die>12)|(refreshable&time_to_die>12))&active_enemies<7&talent.fury_of_nature.enabled)|(((!ticking&time_to_die>12)|(refreshable&time_to_die>12))&active_enemies<4&!talent.fury_of_nature.enabled)
actions.bear+=/thrash_bear,target_if=refreshable|(dot.thrash_bear.stack<5&talent.flashing_claws.rank=2|dot.thrash_bear.stack<4&talent.flashing_claws.rank=1|dot.thrash_bear.stack<3&!talent.flashing_claws.enabled)
actions.bear+=/bristling_fur,if=!cooldown.pause_action.remains
actions.bear+=/barkskin,if=buff.bear_form.up
actions.bear+=/convoke_the_spirits
actions.bear+=/berserk_bear
actions.bear+=/incarnation
actions.bear+=/lunar_beam
actions.bear+=/rage_of_the_sleeper,if=buff.incarnation_guardian_of_ursoc.down&cooldown.incarnation_guardian_of_ursoc.remains>60|buff.incarnation_guardian_of_ursoc.up|(talent.convoke_the_spirits.enabled)
actions.bear+=/berserking,if=(buff.berserk_bear.up|buff.incarnation_guardian_of_ursoc.up)
actions.bear+=/maul,if=(buff.rage_of_the_sleeper.up&buff.tooth_and_claw.stack>0&active_enemies<=6&!talent.raze.enabled&variable.If_build=0)|(buff.rage_of_the_sleeper.up&buff.tooth_and_claw.stack>0&active_enemies=1&talent.raze.enabled&variable.If_build=0)
actions.bear+=/raze,if=buff.rage_of_the_sleeper.up&buff.tooth_and_claw.stack>0&variable.If_build=0&active_enemies>1
actions.bear+=/maul,if=(((buff.incarnation.up|buff.berserk_bear.up)&active_enemies<=5&!talent.raze.enabled&(buff.tooth_and_claw.stack>=1))&variable.If_build=0)|(((buff.incarnation.up|buff.berserk_bear.up)&active_enemies=1&talent.raze.enabled&(buff.tooth_and_claw.stack>=1))&variable.If_build=0)
actions.bear+=/raze,if=(buff.incarnation.up|buff.berserk_bear.up)&(variable.If_build=0)&active_enemies>1
actions.bear+=/ironfur,target_if=!debuff.tooth_and_claw_debuff.up,if=!buff.ironfur.up&rage>50&!cooldown.pause_action.remains&variable.If_build=0&!buff.rage_of_the_sleeper.up|rage>90&variable.If_build=0&!buff.rage_of_the_sleeper.up
actions.bear+=/ironfur,if=rage>90&variable.If_build=1|(buff.incarnation.up|buff.berserk_bear.up)&rage>20&variable.If_build=1
actions.bear+=/raze,if=(buff.tooth_and_claw.up)&active_enemies>1
actions.bear+=/raze,if=(variable.If_build=0)&active_enemies>1
actions.bear+=/mangle,if=buff.gore.up&active_enemies<11|buff.vicious_cycle_mangle.stack=3
actions.bear+=/maul,if=(buff.tooth_and_claw.up&active_enemies<=5&!talent.raze.enabled)|(buff.tooth_and_claw.up&active_enemies=1&talent.raze.enabled)
actions.bear+=/maul,if=(active_enemies<=5&!talent.raze.enabled&variable.If_build=0)|(active_enemies=1&talent.raze.enabled&variable.If_build=0)
actions.bear+=/thrash_bear,target_if=active_enemies>=5
actions.bear+=/swipe,if=buff.incarnation_guardian_of_ursoc.down&buff.berserk_bear.down&active_enemies>=11
actions.bear+=/mangle,if=(buff.incarnation.up&active_enemies<=4)|(buff.incarnation.up&talent.soul_of_the_forest.enabled&active_enemies<=5)|((rage<90)&active_enemies<11)|((rage<85)&active_enemies<11&talent.soul_of_the_forest.enabled)
actions.bear+=/thrash_bear,if=active_enemies>1
actions.bear+=/pulverize,target_if=dot.thrash_bear.stack>2
actions.bear+=/thrash_bear
actions.bear+=/moonfire,if=buff.galactic_guardian.up
actions.bear+=/swipe_bear
]]
	if BearForm:Usable() and BearForm:Down() then
		return BearForm
	end
--[[
	if HeartOfTheWild:Usable() then
		UseCooldown(HeartOfTheWild)
	end
]]
	if RavageBear:Usable() and Player.enemies > 1 then
		return RavageBear
	end
	if Moonfire:Usable() and Moonfire:Refreshable() and Target.timeToDie > 12 and Player.enemies < (FuryOfNature.known and 7 or 4) then
		return Moonfire
	end
	if Thrash:Usable() and (Thrash:Refreshable() or Thrash:Stack() < Thrash:MaxStack()) then
		return Thrash
	end
	if BristlingFur:Usable() and Player:UnderAttack() then
		UseCooldown(BristlingFur)
	end
	if Barkskin:Usable() and Player:UnderAttack() then
		UseCooldown(Barkskin)
	end
	if ConvokeTheSpirits:Usable() then
		UseCooldown(ConvokeTheSpirits)
	end
	if Player.bs_inc:Usable() then
		UseCooldown(Player.bs_inc)
	end
	if LunarBeam:Usable() then
		UseCooldown(LunarBeam)
	end
	if RageOfTheSleeper:Usable() and RageOfTheSleeper:Down() and (not IncarnationGuardianOfUrsoc.known or IncarnationGuardianOfUrsoc:CooldownExpected() > 45 or IncarnationGuardianOfUrsoc:Up()) then
		UseCooldown(RageOfTheSleeper)
	end
	if RavageBear:Usable() then
		return RavageBear
	end
	if not self.If_build then
		if RageOfTheSleeper.known and RageOfTheSleeper:Up() and ToothAndClaw:Stack() > 0 then
			if Maul:Usable() and Player.enemies <= (Raze.known and 1 or 6) then
				return Maul
			end
			if Raze:Usable() and Player.enemies > 1 then
				return Raze
			end
		end
		if Maul:Usable() and Player.berserk_up and Player.enemies <= (Raze.known and 1 or 5) and ToothAndClaw:Stack() >= 1 then
			return Maul
		end
		if Raze:Usable() and Player.berserk_up and Player.enemies > 1 then
			return Raze
		end
	end
	if Ironfur:Usable() and (
		(not self.If_build and (not RageOfTheSleeper.known or RageOfTheSleeper:Down()) and (Player.rage.current > 90 or (Ironfur:Remains() < 0.5 and Player.rage.current > 50 and Player:UnderMeleeAttack()))) or
		(self.If_build and (Player.rage.current > 90 or (Player.berserk_up and Player.rage.current > 20 and Player:UnderMeleeAttack())))
	) then
		UseExtra(Ironfur)
	end
	if Raze:Usable() and Player.enemies > 1 and (not self.If_build or ToothAndClaw:Up()) then
		return Raze
	end
	if Mangle:Usable() and ((Gore.known and Gore:Up() and Player.enemies < 11) or (ViciousCycle.known and ViciousCycle.Mangle:Stack() >= 3)) then
		return Mangle
	end
	if Maul:Usable() and (not self.If_build or ToothAndClaw:Up()) and Player.enemies <= (Raze.known and 1 or 5) then
		return Maul
	end
	if Thrash:Usable() and Player.enemies >= 5 then
		return Thrash
	end
	if Swipe:Usable() and not Player.berserk_up and Player.enemies >= 11 then
		return Swipe
	end
	if Mangle:Usable() and (
		(IncarnationGuardianOfUrsoc.known and Player.berserk_up and Player.enemies <= (SoulOfTheForest.known and 5 or 4)) or
		(Player.enemies < 11 and Player.rage.current < (SoulOfTheForest.known and 85 or 90))
	) then
		return Mangle
	end
	if Thrash:Usable() and Player.enemies > 1 then
		return Thrash
	end
	if Pulverize:Usable() and Thrash:Stack() > 2 then
		return Pulverize
	end
	if Thrash:Usable() then
		return Thrash
	end
	if GalacticGuardian.known and Moonfire:Usable() and GalacticGuardian:Up() then
		return Moonfire
	end
	if Swipe:Usable() then
		return Swipe
	end
end

APL[SPEC.RESTORATION].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 300 then
			return MarkOfTheWild
		end
	else
		if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < 10 then
			UseExtra(MarkOfTheWild)
		end
	end
end

APL.Interrupt = function(self)
	if SkullBash:Usable() then
		return SkullBash
	end
	if SolarBeam:Usable() then
		return SolarBeam
	end
	if MightyBash:Usable() then
		return MightyBash
	end
	if Maim:Usable() then
		return Maim
	end
	if IncapacitatingRoar:Usable() then
		return IncapacitatingRoar
	end
	if Typhoon:Usable() then
		return Typhoon
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:ScanActionButtons()
	wipe(self.buttons)
	if Bartender4 then
		for i = 1, 120 do
			self.buttons[#self.buttons + 1] = _G['BT4Button' .. i]
		end
		for i = 1, 10 do
			self.buttons[#self.buttons + 1] = _G['BT4PetButton' .. i]
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['ElvUI_Bar' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['LUIBarBottom' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarLeft' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarRight' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			self.buttons[#self.buttons + 1] = _G['DominosActionButton' .. i]
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		self.buttons[#self.buttons + 1] = _G['ActionButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar5Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar6Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar7Button' .. i]
	end
	for i = 1, 10 do
		self.buttons[#self.buttons + 1] = _G['PetActionButton' .. i]
	end
end

function UI:CreateOverlayGlows()
	local glow
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON] or CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
		glow:Hide()
		glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
		glow.button = button
		button['glow' .. ADDON] = glow
	end
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, action
	for _, slot in next, self.action_slots do
		action = slot.action
		for _, button in next, slot.buttons do
			glow = button['glow' .. ADDON]
			if action and button:IsVisible() and (
				(Opt.glow.main and action == Player.main) or
				(Opt.glow.cooldown and action == Player.cd) or
				(Opt.glow.interrupt and action == Player.interrupt) or
				(Opt.glow.extra and action == Player.extra)
			) then
				if not glow:IsVisible() then
					glow:Show()
					if Opt.glow.animation then
						glow.ProcStartAnim:Play()
					else
						glow.ProcLoop:Play()
					end
				end
			elseif glow:IsVisible() then
				if glow.ProcStartAnim:IsPlaying() then
					glow.ProcStartAnim:Stop()
				end
				if glow.ProcLoop:IsPlaying() then
					glow.ProcLoop:Stop()
				end
				glow:Hide()
			end
		end
	end
end

UI.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function UI:GetButtonKeybind(button)
	local bind = button.bindingAction or (button.config and button.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, self.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			return key
		end
	end
end

function UI:GetActionFromID(actionId)
	local actionType, id, subType = GetActionInfo(actionId)
	if id and type(id) == 'number' and id > 0 then
		if (actionType == 'item' or (actionType == 'macro' and subType == 'item')) then
			return InventoryItems.byItemId[id]
		elseif (actionType == 'spell' or (actionType == 'macro' and subType == 'spell')) then
			return Abilities.bySpellId[id]
		end
	end
end

function UI:UpdateActionSlot(actionId)
	local slot = self.action_slots[actionId]
	if not slot then
		return
	end
	local action = self:GetActionFromID(actionId)
	if action ~= slot.action then
		if slot.action then
			slot.action.keybinds[actionId] = nil
		end
		slot.action = action
	end
	if not action then
		return
	end
	for _, button in next, slot.buttons do
		action.keybinds[actionId] = self:GetButtonKeybind(button)
		if action.keybinds[actionId] then
			return
		end
	end
	action.keybinds[actionId] = nil
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for actionId in next, self.action_slots do
		self:UpdateActionSlot(actionId)
	end
end

function UI:ScanActionSlots()
	wipe(self.action_slots)
	local actionId, buttons
	for _, button in next, self.buttons do
		actionId = (
			(button._state_type == 'action' and button._state_action) or
			(button.CalculateAction and button:CalculateAction()) or
			(button:GetAttribute('action'))
		) or 0
		if actionId > 0 then
			if not self.action_slots[actionId] then
				self.action_slots[actionId] = {
					buttons = {},
				}
			end
			buttons = self.action_slots[actionId].buttons
			buttons[#buttons + 1] = button
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	clawPanel:SetMovable(not Opt.snap)
	clawPreviousPanel:SetMovable(not Opt.snap)
	clawCooldownPanel:SetMovable(not Opt.snap)
	clawInterruptPanel:SetMovable(not Opt.snap)
	clawExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		clawPanel:SetUserPlaced(true)
		clawPreviousPanel:SetUserPlaced(true)
		clawCooldownPanel:SetUserPlaced(true)
		clawInterruptPanel:SetUserPlaced(true)
		clawExtraPanel:SetUserPlaced(true)
	end
	clawPanel:EnableMouse(draggable or Opt.aoe)
	clawPanel.button:SetShown(Opt.aoe)
	clawPreviousPanel:EnableMouse(draggable)
	clawCooldownPanel:EnableMouse(draggable)
	clawInterruptPanel:EnableMouse(draggable)
	clawExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	clawPanel:SetAlpha(Opt.alpha)
	clawPreviousPanel:SetAlpha(Opt.alpha)
	clawCooldownPanel:SetAlpha(Opt.alpha)
	clawInterruptPanel:SetAlpha(Opt.alpha)
	clawExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	clawPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	clawPanel.text:SetScale(Opt.scale.main)
	clawPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	clawCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	clawCooldownPanel.text:SetScale(Opt.scale.cooldown)
	clawInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	clawExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	clawPreviousPanel:ClearAllPoints()
	clawPreviousPanel:SetPoint('TOPRIGHT', clawPanel, 'BOTTOMLEFT', -3, 40)
	clawCooldownPanel:ClearAllPoints()
	clawCooldownPanel:SetPoint('TOPLEFT', clawPanel, 'BOTTOMRIGHT', 3, 40)
	clawInterruptPanel:ClearAllPoints()
	clawInterruptPanel:SetPoint('BOTTOMLEFT', clawPanel, 'TOPRIGHT', 3, -21)
	clawExtraPanel:ClearAllPoints()
	clawExtraPanel:SetPoint('BOTTOMRIGHT', clawPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[FORM.NONE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[FORM.MOONKIN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[FORM.CAT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -30 },
		},
		[FORM.BEAR] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[FORM.TRAVEL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[FORM.NONE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[FORM.MOONKIN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[FORM.CAT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[FORM.BEAR] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[FORM.TRAVEL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		clawPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.form][Opt.snap]
		clawPanel:ClearAllPoints()
		clawPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.BALANCE and Opt.hide.balance) or
		(Player.spec == SPEC.FERAL and Opt.hide.feral) or
		(Player.spec == SPEC.GUARDIAN and Opt.hide.guardian) or
		(Player.spec == SPEC.RESTORATION and Opt.hide.restoration))
end

function UI:Disappear()
	clawPanel:Hide()
	clawPanel.icon:Hide()
	clawPanel.border:Hide()
	clawCooldownPanel:Hide()
	clawInterruptPanel:Hide()
	clawExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	self:UpdateGlows()
end

function UI:Reset()
	clawPanel:ClearAllPoints()
	clawPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_cd, text_center, text_tl, text_tr, text_bl, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
		end
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if clawPanel.text.multiplier_diff and not text_center then
		if clawPanel.text.multiplier_diff >= 0 then
			text_center = format('|cFF00FF00+%d%%', clawPanel.text.multiplier_diff * 100)
		elseif clawPanel.text.multiplier_diff < 0 then
			text_center = format('|cFFFF0000%d%%', clawPanel.text.multiplier_diff * 100)
		end
	end
	if Player.berserk_up then
		text_bl = format('%.1fs', Player.berserk_remains)
	end
	if border ~= clawPanel.border.overlay then
		clawPanel.border.overlay = border
		clawPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	clawPanel.dimmer:SetShown(dim)
	clawPanel.text.center:SetText(text_center)
	clawPanel.text.tl:SetText(text_tl)
	clawPanel.text.tr:SetText(text_tr)
	clawPanel.text.bl:SetText(text_bl)
	clawCooldownPanel.dimmer:SetShown(dim_cd)
	clawCooldownPanel.text.center:SetText(text_cd_center)
	clawCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		clawPanel.icon:SetTexture(Player.main.icon)
		if Opt.multipliers and Player.main.NextMultiplier then
			clawPanel.text.multiplier_diff = Player.main:NextMultiplier() - Player.main:Multiplier()
		else
			clawPanel.text.multiplier_diff = nil
		end
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		clawCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			clawCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
	end
	if Player.extra then
		clawExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			clawInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			clawInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		clawInterruptPanel.icon:SetShown(Player.interrupt)
		clawInterruptPanel.border:SetShown(Player.interrupt)
		clawInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and clawPreviousPanel.ability then
		if (Player.time - clawPreviousPanel.ability.last_used) > 10 then
			clawPreviousPanel.ability = nil
			clawPreviousPanel:Hide()
		end
	end

	clawPanel.icon:SetShown(Player.main)
	clawPanel.border:SetShown(Player.main)
	clawCooldownPanel:SetShown(Player.cd)
	clawExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Claw
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Claw1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.rage.max = UnitPowerMax(unitId, 1)
		Player.energy.max = UnitPowerMax(unitId, 3)
		Player.combo_points.max = UnitPowerMax(unitId, 4)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability == Rip or ability == PrimalWrath then
		Rip.next_applied_by = ability
		Rip.next_combo_points = UnitPower('player', 4)
		ability = Rip
	elseif ability == RavageCat then
		ability = DreadfulWound
	end
	if ability.NextMultiplier then
		ability.next_multiplier = ability:NextMultiplier()
	end
end

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		clawPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
		end
	end

	Player.set_bonus.t33 = (Player:Equipped(212054) and 1 or 0) + (Player:Equipped(212055) and 1 or 0) + (Player:Equipped(212056) and 1 or 0) + (Player:Equipped(212057) and 1 or 0) + (Player:Equipped(212059) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	clawPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:UPDATE_SHAPESHIFT_FORM()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:UPDATE_BINDINGS()
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:UPDATE_SHAPESHIFT_FORM()
	local form = GetShapeshiftFormID() or 0
	if form == 1 then
		Player.form = FORM.CAT
	elseif form == 5 then
		Player.form = FORM.BEAR
	elseif form == 31 or form == 35 then
		Player.form = FORM.MOONKIN
	elseif form == 3 or form == 4 or form == 27 or form == 29 then
		Player.form = FORM.TRAVEL
	else
		Player.form = FORM.NONE
	end
	Player:UpdateKnown()
	UI.OnResourceFrameShow()
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		clawPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	if not slot or slot < 1 then
		UI:ScanActionSlots()
		UI:UpdateBindings()
	else
		UI:UpdateActionSlot(slot)
	end
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED(0)
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

clawPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

clawPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

clawPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	clawPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if startsWith(msg[1], 'hide') or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.balance = not Opt.hide.balance
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Balance specialization', not Opt.hide.balance)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.feral = not Opt.hide.feral
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Feral specialization', not Opt.hide.feral)
			end
			if startsWith(msg[2], 'g') then
				Opt.hide.guardian = not Opt.hide.guardian
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Guardian specialization', not Opt.hide.guardian)
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.restoration = not Opt.hide.restoration
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Restoration specialization', not Opt.hide.restoration)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000balance|r/|cFFFFD000feral|r/|cFFFFD000guardian|r/|cFFFFD000restoration|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
	end
	if startsWith(msg[1], 'mu') then
		if msg[2] then
			Opt.multipliers = msg[2] == 'on'
		end
		return Status('Show DoT multiplier differences (center)', Opt.multipliers)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000balance|r/|cFFFFD000feral|r/|cFFFFD000guardian|r/|cFFFFD000restoration|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'multipliers |cFF00C000on|r/|cFFC00000off|r - show DoT multiplier differences (center)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Claw1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
