local ADDON = 'Claw'
if select(2, UnitClass('player')) ~= 'DRUID' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetComboPoints = _G.GetComboPoints
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitAttackPower = _G.UnitAttackPower
local UnitAura = _G.UnitAura
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

ClawConfig = {}
local Opt -- use this as a local table reference to ClawConfig

SLASH_Claw1, SLASH_Claw2 = '/claw', '/cl'
BINDING_HEADER_CLAW = ADDON

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
	SetDefaults(ClawConfig, { -- defaults
		locked = false,
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
			color = { r = 1, g = 1, b = 1 },
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
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
		conserve_powershift = false,
		mana_threshold_powershift = 20,
		tick_padding_ms = 100,
		front_mode = false,
		faerie_fire = true,
		cower_pct = 90,
		swipe_st_ap = 2700,
		swipe_st_threat = 10000,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

--- form constants
local FORM = {
	NONE = 0,
	MOONKIN = 1,
	CAT = 2,
	BEAR = 3,
	TRAVEL = 4,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	form = FORM.NONE,
	target_mode = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	mana = {
		base = 0,
		current = 0,
		max = 0,
		regen = 0,
		tick_mana = 0,
		tick_interval = 2,
		next_tick = 0,
		per_tick = 0,
		time_until_tick = 0,
	},
	energy = {
		current = 0,
		max = 0,
		regen = 0,
		tick_energy = 0,
		tick_interval = 2,
		next_tick = 0,
		per_tick = 0,
		time_until_tick = 0,
	},
	combo_points = 0,
	rage = {
		current = 0,
		max = 0,
	},
	group_size = 1,
	moving = false,
	movement_speed = 100,
	threat = 0,
	threat_pct = 0,
	thread_lead = 0,
	attack_power = 0,
	last_swing_taken = 0,
	last_swing_taken_physical = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
	npc_swing_types = { -- [npcId] = type
	},
}

local clawPanel = CreateFrame('Frame', 'clawPanel', UIParent)
clawPanel:SetPoint('CENTER', 0, -169)
clawPanel:SetFrameStrata('BACKGROUND')
clawPanel:SetSize(64, 64)
clawPanel:SetMovable(true)
clawPanel:Hide()
clawPanel.icon = clawPanel:CreateTexture(nil, 'BACKGROUND')
clawPanel.icon:SetAllPoints(clawPanel)
clawPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
clawPanel.border = clawPanel:CreateTexture(nil, 'ARTWORK')
clawPanel.border:SetAllPoints(clawPanel)
clawPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
clawPanel.border:Hide()
clawPanel.dimmer = clawPanel:CreateTexture(nil, 'BORDER')
clawPanel.dimmer:SetAllPoints(clawPanel)
clawPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
clawPanel.dimmer:Hide()
clawPanel.swipe = CreateFrame('Cooldown', nil, clawPanel, 'CooldownFrameTemplate')
clawPanel.swipe:SetAllPoints(clawPanel)
clawPanel.text = CreateFrame('Frame', nil, clawPanel)
clawPanel.text:SetAllPoints(clawPanel)
clawPanel.text.tl = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.tl:SetPoint('TOPLEFT', clawPanel, 'TOPLEFT', 2.5, -3)
clawPanel.text.tl:SetJustifyH('LEFT')
clawPanel.text.tr = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.tr:SetPoint('TOPRIGHT', clawPanel, 'TOPRIGHT', -2.5, -3)
clawPanel.text.tr:SetJustifyH('RIGHT')
clawPanel.text.bl = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.bl:SetPoint('BOTTOMLEFT', clawPanel, 'BOTTOMLEFT', 2.5, 3)
clawPanel.text.bl:SetJustifyH('LEFT')
clawPanel.text.br = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.br:SetPoint('BOTTOMRIGHT', clawPanel, 'BOTTOMRIGHT', -2.5, 3)
clawPanel.text.br:SetJustifyH('RIGHT')
clawPanel.text.center = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.center:SetAllPoints(clawPanel.text)
clawPanel.text.center:SetJustifyH('CENTER')
clawPanel.text.center:SetJustifyV('CENTER')
clawPanel.button = CreateFrame('Button', nil, clawPanel)
clawPanel.button:SetAllPoints(clawPanel)
clawPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local clawPreviousPanel = CreateFrame('Frame', 'clawPreviousPanel', UIParent)
clawPreviousPanel:SetFrameStrata('BACKGROUND')
clawPreviousPanel:SetSize(64, 64)
clawPreviousPanel:Hide()
clawPreviousPanel:RegisterForDrag('LeftButton')
clawPreviousPanel:SetScript('OnDragStart', clawPreviousPanel.StartMoving)
clawPreviousPanel:SetScript('OnDragStop', clawPreviousPanel.StopMovingOrSizing)
clawPreviousPanel:SetMovable(true)
clawPreviousPanel.icon = clawPreviousPanel:CreateTexture(nil, 'BACKGROUND')
clawPreviousPanel.icon:SetAllPoints(clawPreviousPanel)
clawPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
clawPreviousPanel.border = clawPreviousPanel:CreateTexture(nil, 'ARTWORK')
clawPreviousPanel.border:SetAllPoints(clawPreviousPanel)
clawPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local clawCooldownPanel = CreateFrame('Frame', 'clawCooldownPanel', UIParent)
clawCooldownPanel:SetSize(64, 64)
clawCooldownPanel:SetFrameStrata('BACKGROUND')
clawCooldownPanel:Hide()
clawCooldownPanel:RegisterForDrag('LeftButton')
clawCooldownPanel:SetScript('OnDragStart', clawCooldownPanel.StartMoving)
clawCooldownPanel:SetScript('OnDragStop', clawCooldownPanel.StopMovingOrSizing)
clawCooldownPanel:SetMovable(true)
clawCooldownPanel.icon = clawCooldownPanel:CreateTexture(nil, 'BACKGROUND')
clawCooldownPanel.icon:SetAllPoints(clawCooldownPanel)
clawCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
clawCooldownPanel.border = clawCooldownPanel:CreateTexture(nil, 'ARTWORK')
clawCooldownPanel.border:SetAllPoints(clawCooldownPanel)
clawCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
clawCooldownPanel.dimmer = clawCooldownPanel:CreateTexture(nil, 'BORDER')
clawCooldownPanel.dimmer:SetAllPoints(clawCooldownPanel)
clawCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
clawCooldownPanel.dimmer:Hide()
clawCooldownPanel.swipe = CreateFrame('Cooldown', nil, clawCooldownPanel, 'CooldownFrameTemplate')
clawCooldownPanel.swipe:SetAllPoints(clawCooldownPanel)
local clawInterruptPanel = CreateFrame('Frame', 'clawInterruptPanel', UIParent)
clawInterruptPanel:SetFrameStrata('BACKGROUND')
clawInterruptPanel:SetSize(64, 64)
clawInterruptPanel:Hide()
clawInterruptPanel:RegisterForDrag('LeftButton')
clawInterruptPanel:SetScript('OnDragStart', clawInterruptPanel.StartMoving)
clawInterruptPanel:SetScript('OnDragStop', clawInterruptPanel.StopMovingOrSizing)
clawInterruptPanel:SetMovable(true)
clawInterruptPanel.icon = clawInterruptPanel:CreateTexture(nil, 'BACKGROUND')
clawInterruptPanel.icon:SetAllPoints(clawInterruptPanel)
clawInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
clawInterruptPanel.border = clawInterruptPanel:CreateTexture(nil, 'ARTWORK')
clawInterruptPanel.border:SetAllPoints(clawInterruptPanel)
clawInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
clawInterruptPanel.swipe = CreateFrame('Cooldown', nil, clawInterruptPanel, 'CooldownFrameTemplate')
clawInterruptPanel.swipe:SetAllPoints(clawInterruptPanel)
local clawExtraPanel = CreateFrame('Frame', 'clawExtraPanel', UIParent)
clawExtraPanel:SetFrameStrata('BACKGROUND')
clawExtraPanel:SetSize(64, 64)
clawExtraPanel:Hide()
clawExtraPanel:RegisterForDrag('LeftButton')
clawExtraPanel:SetScript('OnDragStart', clawExtraPanel.StartMoving)
clawExtraPanel:SetScript('OnDragStop', clawExtraPanel.StopMovingOrSizing)
clawExtraPanel:SetMovable(true)
clawExtraPanel.icon = clawExtraPanel:CreateTexture(nil, 'BACKGROUND')
clawExtraPanel.icon:SetAllPoints(clawExtraPanel)
clawExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
clawExtraPanel.border = clawExtraPanel:CreateTexture(nil, 'ARTWORK')
clawExtraPanel.border:SetAllPoints(clawExtraPanel)
clawExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	{1, ''},
	{2, '2'},
	{3, '3'},
	{4, '4'},
	{5, '5+'},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes)
	self.enemies = self.target_modes[self.target_mode][1]
	clawPanel.text.br:SetText(self.target_modes[self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes or mode)
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		rank = 0,
		icon = false,
		requires_charge = false,
		triggers_combat = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		energy_cost = 0,
		cp_cost = 0,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 30,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		if spell == self.spellId then
			return true
		end
		for _, id in next, self.spellIds do
			if spell == id then
				return true
			end
		end
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self.requires_bear and Player.form ~= FORM.BEAR then
		return false
	end
	if self.requires_cat and Player.form ~= FORM.CAT then
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
	if Player.form == FORM.CAT and self:CPCost() > Player.combo_points then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(mine)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter .. (mine and '|PLAYER' or ''))
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - Player.execute_remains)
		end
	end
	return 0
end

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
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
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:CPCost()
	return self.cp_cost
end

function Ability:RageCost()
	return self.rage_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana.regen * self:CastTime() - self:ManaCost()
end

function Ability:CastEnergyRegen()
	return Player.energy.regen * self:CastTime() - self:EnergyCost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID, timeStamp)
	self.last_used = timeStamp
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
end

function Ability:CastLanded(dstGUID, timeStamp, eventType)
	if not self.traveling then
		return
	end
	local oldest
	for guid, cast in next, self.traveling do
		if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
			self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
		elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
			oldest = cast
		end
	end
	if oldest then
		Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, timeStamp - oldest.start)))
		self.traveling[oldest.guid] = nil
	end
end

-- Start DoT Tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	return self:ApplyAura(guid)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT Tracking

-- Druid Abilities
---- General

---- Balance
local FaerieFire = Ability:Add({770, 778, 9749, 9907, 26993})
FaerieFire.mana_costs = {55, 75, 95, 115, 145}
FaerieFire.buff_duration = 40
local Thorns = Ability:Add({467, 782, 1075, 8914, 9756, 9910, 26992}, true, false)
Thorns.mana_costs = {35, 60, 105, 170, 240, 320, 400}
Thorns.buff_duration = 600
Thorns.can_clearcast = true
------ Talents

------ Procs

---- Feral
local Bash = Ability:Add({5211, 6798, 8983}, false, false)
Bash.rage_cost = 10
Bash.cooldown_duration = 60
Bash.requires_bear = true
Bash.can_clearcast = true
local BearForm = Ability:Add({5487, 9634}, true, true)
BearForm.mana_cost_pct = 35
local CatForm = Ability:Add({768}, true, true)
CatForm.mana_cost_pct = 35
local Claw = Ability:Add({1082, 3029, 5201, 9849, 9850, 27000}, false, true)
Claw.energy_cost = 45
Claw.requires_cat = true
Claw.can_clearcast = true
local Cower = Ability:Add({8998, 9000, 9892, 31709, 27004}, false, true)
Cower.cooldown_duration = 10
Cower.energy_cost = 20
Cower.requires_cat = true
Cower.can_clearcast = true
local DemoralizingRoar = Ability:Add({99, 1735, 9490, 9747, 9898, 26998}, false, false)
DemoralizingRoar.rage_cost = 10
DemoralizingRoar.requires_bear = true
DemoralizingRoar.can_clearcast = true
local Enrage = Ability:Add({5229}, true, true)
Enrage.cooldown_duration = 60
Enrage.buff_duration = 10
Enrage.requires_bear = true
local FerociousBite = Ability:Add({22568, 22827, 22828, 22829, 31018, 24248}, false, true)
FerociousBite.cp_cost = 1
FerociousBite.energy_cost = 35
FerociousBite.requires_cat = true
FerociousBite.can_clearcast = true
local Growl = Ability:Add({2649}, false, true)
local Lacerate = Ability:Add({33745}, false, true)
Lacerate.buff_duration = 15
Lacerate.rage_cost = 15
Lacerate.tick_interval = 3
Lacerate.requires_bear = true
Lacerate.can_clearcast = true
local Maul = Ability:Add({6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996}, false, true)
Maul.rage_cost = 15
Maul.requires_bear = true
Maul.can_clearcast = true
Maul.swing_queue = true
local Prowl = Ability:Add({5215, 6783, 9913}, true, true)
Prowl.cooldown_duration = 10
Prowl.requires_cat = true
local Rake = Ability:Add({1822, 1823, 1824, 9904, 27003}, false, true)
Rake.buff_duration = 9
Rake.energy_cost = 40
Rake.tick_interval = 3
Rake.requires_cat = true
Rake.can_clearcast = true
local Ravage = Ability:Add({6785, 6787, 9866, 9867, 27005}, false, true)
Ravage.energy_cost = 60
Ravage.requires_cat = true
Ravage.can_clearcast = true
local Rip = Ability:Add({1079, 9492, 9493, 9752, 9894, 9896, 27008}, false, true)
Rip.buff_duration = 12
Rip.cp_cost = 1
Rip.energy_cost = 30
Rip.tick_interval = 2
Rip.requires_cat = true
Rip.can_clearcast = true
local Pounce = Ability:Add({9005, 9823, 9827, 27006}, false, true)
Pounce.buff_duration = 3
Pounce.energy_cost = 50
Pounce.requires_cat = true
Pounce.can_clearcast = true
Pounce.bleed = Ability:Add({9007, 9824, 9826, 27007}, false, true)
Pounce.bleed.buff_duration = 18
Pounce.bleed.tick_interval = 3
local Shred = Ability:Add({5221, 6800, 8992, 9829, 9830, 27001, 27002}, false, true)
Shred.energy_cost = 60
Shred.requires_cat = true
Shred.can_clearcast = true
local Swipe = Ability:Add({779, 780, 769, 9754, 9908, 26997}, false, true)
Swipe.rage_cost = 20
Swipe.requires_bear = true
Swipe.can_clearcast = true
------ Talents
local FaerieFireFeral = Ability:Add({16857, 17390, 17391, 17392, 27011})
FaerieFireFeral.cooldown_duration = 6
FaerieFireFeral.buff_duration = 40
local FeralCharge = Ability:Add({16979}, false, false)
FeralCharge.rage_cost = 5
FeralCharge.cooldown_duration = 15
FeralCharge.requires_bear = true
FeralCharge.can_clearcast = true
local Ferocity = Ability:Add({16934, 16935, 16936, 16937, 16938}, true, true)
local MangleBear = Ability:Add({33878, 33986, 33987}, false, false)
MangleBear.rage_cost = 20
MangleBear.requires_bear = true
MangleBear.can_clearcast = true
local MangleCat = Ability:Add({33876, 33982, 33983}, false, false)
MangleCat.energy_cost = 45
MangleCat.requires_cat = true
MangleCat.can_clearcast = true
local PrimalFury = Ability:Add({37116, 37117}, true, true)
local ShreddingAttacks = Ability:Add({16966, 16968}, true, true)
------ Procs

---- Restoration
local GiftOfTheWild = Ability:Add({21849, 21850, 26991}, true, false)
GiftOfTheWild.mana_costs = {900, 1200, 1515}
GiftOfTheWild.buff_duration = 3600
local MarkOfTheWild = Ability:Add({1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990}, true, false)
MarkOfTheWild.mana_costs = {20, 50, 100, 160, 240, 340, 445, 565}
MarkOfTheWild.buff_duration = 1800
------ Talents
local Furor = Ability:Add({17056, 17058, 17059, 17060, 17061}, true, true)
local NaturalShapeshifter = Ability:Add({16833, 16834, 16835}, true, true)
local OmenOfClarity = Ability:Add({16864}, true, true)
local Clearcasting = Ability:Add({16870}, true, true)
------ Procs

-- Racials

-- Class Debuffs
local CurseOfRecklessness = Ability:Add({704, 7658, 7659, 11717, 27226}) -- Applied by Warlocks
local DemoralizingShout = Ability:Add({1160, 6190, 11554, 11555, 11556, 25202, 25203}) -- Applied by Warriors, doesn't stack with Demoralizing Roar
local ExposeArmor = Ability:Add({8647, 8649, 8650, 11197, 11198, 26866}) -- Applied by Rogues, doesn't stack with Sunder Armor
local PierceArmor = Ability:Add({38187}) -- Applied by Murloc MC on Tidewalker
local SunderArmor = Ability:Add({7386, 7405, 8380, 11596, 11597, 25225}) -- Applied by Warriors, doesn't stack with Expose Armor
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
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
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
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
local WolfsheadHelm = InventoryItem:Add(8345)
local StaffOfNaturalFury = InventoryItem:Add(31334)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaPct()
	return self.mana.current / self.mana.max * 100
end

function Player:ManaTick(timerTrigger)
	local time = GetTime()
	local mana = UnitPower('player', 0)
	if (
		(not timerTrigger and mana > self.mana.tick_mana) or
		(timerTrigger and mana >= self.mana.max)
	) then
		self.mana.next_tick = time + self.mana.tick_interval
		if mana >= self.mana.max then
			C_Timer.After(self.mana.tick_interval, function() Player:ManaTick(true) end)
		end
	end
	self.mana.tick_mana = mana
end

function Player:Energy()
	return self.energy.current
end

function Player:EnergyDeficit(energy)
	return (energy or self.energy.max) - self.energy.current
end

function Player:EnergyTimeToMax(energy)
	local deficit = self:EnergyDeficit(energy)
	if deficit <= 0 then
		return 0
	end
	return (floor(deficit / self.energy.regen / self.energy.tick_interval) * self.energy.tick_interval) + self.energy.time_until_tick
end

function Player:EnergyTick(timerTrigger)
	local time = GetTime()
	local energy = UnitPower('player', 3)
	if time == self.shapeshift_time then
		return
	end
	if (
		(not timerTrigger and energy > self.energy.tick_energy) or
		(timerTrigger and energy >= self.energy.max)
	) then
		self.energy.next_tick = time + self.energy.tick_interval
		if energy >= self.energy.max then
			C_Timer.After(self.energy.tick_interval, function() Player:EnergyTick(true) end)
		end
	end
	self.energy.tick_energy = energy
end

function Player:RageDeficit()
	return self.rage.max - self.rage.current
end

function Player:Stealthed()
	return Prowl:Up() or (Shadowmeld.known and Shadowmeld:Up())
end

function Player:UnderMeleeAttack(physical)
	return (self.time - (physical and self.last_swing_taken_physical or self.last_swing_taken)) < 3
end

function Player:UnderAttack()
	return self.threat >= 3 or self:UnderMeleeAttack()
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:UpdateAbilities()
	local int = UnitStat('player', 4)
	self.mana.max = UnitPowerMax('player', 0)
	self.mana.base = self.mana.max - (min(20, int) + 15 * (int - min(20, int)))
	self.energy.max = UnitPowerMax('player', 3)
	self.rage.max = UnitPowerMax('player', 1)

	-- Update spell ranks first
	for _, ability in next, abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
				if ability.mana_costs then
					ability.mana_cost = ability.mana_costs[i] -- update mana_cost to current rank
				end
				if ability.mana_cost_pct then
					ability.mana_cost = floor(self.mana.base * (ability.mana_cost_pct / 100))
				end
			end
		end
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
	end

	Clearcasting.known = OmenOfClarity.known
	if Pounce.known then
		Pounce.bleed.known = true
		Pounce.bleed.spellId = Pounce.bleed.spellIds[Pounce.rank]
		Pounce.bleed.rank = Pounce.rank
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			for i, spellId in next, ability.spellIds do
				abilities.bySpellId[spellId] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:UpdateThreat()
	local _, threat, threat_pct
	_, threat, threat_pct = UnitDetailedThreatSituation('player', 'target')
	self.threat = threat or 0
	self.threat_pct = threat_pct or 0
	self.threat_lead = 0
	if self.threat >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat_lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed, ap_base, ap_neg, ap_pos
	self.ctime = GetTime()
	self.time = self.ctime - self.time_diff
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_energy = nil
	self.wait_seconds = nil
	start, duration = GetSpellCooldown(47524)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.execute_remains = max(remains and (remains / 1000 - self.ctime) or 0, self.gcd_remains)
	self.haste_factor = 1 / (1 + GetCombatRatingBonus(CR_HASTE_SPELL) / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.mana.current = UnitPower('player', 0)
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.per_tick = floor(self.mana.regen * self.mana.tick_interval)
	self.mana.time_until_tick = max(0, self.mana.next_tick - self.ctime)
	if self.ability_casting then
		self.mana.current = self.mana.current - self.ability_casting:ManaCost()
	end
	if self.execute_remains > self.mana.time_until_tick then
		self.mana.current = self.mana.current + self.mana.per_tick
	end
	self.mana.current = max(0, min(self.mana.max, self.mana.current))
	self.energy.current = UnitPower('player', 3)
	self.energy.regen = GetPowerRegenForPowerType(3)
	self.energy.per_tick = floor(self.energy.regen * self.energy.tick_interval)
	self.energy.time_until_tick = max(0, self.energy.next_tick - self.ctime)
	if self.execute_remains > self.energy.time_until_tick then
		self.energy.current = max(0, min(self.energy.max, self.energy.current + self.energy.per_tick))
	end
	self.combo_points = GetComboPoints('player', 'target')
	self.rage.current = UnitPower('player', 1)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	ap_base, ap_pos, ap_neg = UnitAttackPower('player')
	self.attack_power = ap_base + ap_pos + ap_neg
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
	end
	clawPreviousPanel.ability = nil
	Player.guid = UnitGUID('player')
	Player.name = UnitName('player')
	Player.level = UnitLevel('player')
	_, Player.instance = IsInInstance()
	Player:SetTargetMode(1)
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:UPDATE_SHAPESHIFT_FORM()
	events:PLAYER_REGEN_ENABLED()
	Target:Update()
	Player:Update()
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * (Player.form == FORM.BEAR and 18 or 10)
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.npcid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.type = 'Humanoid'
		self.player = false
		self.level = Player.level
		self.hostile = true
		for i = 1, 25 do
			self.health_array[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			clawPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			clawPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		self.npcid = tonumber(guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.type = UnitCreatureType('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		clawPanel:Show()
		return true
	end
end

function Target:Stunned()
	if Pounce:Up() or Bash:Up() then
		return true
	end
	return false
end

function Target:DealsPhysicalDamage()
	if self.npcid and Target.npc_swing_types[self.npcid] then
		return bit.band(Target.npc_swing_types[self.npcid], 1) > 0
	end
	return true
end

-- End Target API

-- Start Ability Modifications

function Ability:EnergyCost()
	if self.can_clearcast and Clearcasting.known and Clearcasting:Up() then
		return 0
	end
	return self.energy_cost
end

function Ability:RageCost()
	if self.can_clearcast and Clearcasting.known and Clearcasting:Up() then
		return 0
	end
	return self.rage_cost
end

function Ability:ManaCost()
	if self.can_clearcast and Clearcasting.known and Clearcasting:Up() then
		return 0
	end
	return self.mana_cost
end

function Ability:ShapeshiftForEnergy(energy)
	if Target.timeToDie < 2 or Player:ManaPct() < Opt.mana_threshold_powershift then
		return false -- don't powershift if the target is about to die or we are low on mana
	end
	if CatForm:ShapeshiftEnergyGain() < Player.energy.per_tick * (Opt.conserve_powershift and 2 or 1) then
		return false -- if conserving mana, only powershift for at least 2 ticks of energy gain
	end
	if (energy or self:EnergyCost()) - Player.energy.current > Player.energy.per_tick * 2 then
		return true -- don't care about clipping energy ticks if it's still worth powershifting after the next tick
	end
	if Player.execute_remains + (Opt.tick_padding_ms / 1000) >= Player.energy.time_until_tick then
		return false -- prevent clipping an energy tick
	end
	if (energy or self:EnergyCost()) - Player.energy.current > Player.energy.per_tick then
		return true -- powershift if we will have to wait 2 or more ticks to use the ability
	end
	return false
end

function BearForm:ShapeshiftRageGain()
	return ((Furor.known and 10 or 0) + (WolfsheadHelm:Equipped() and 5 or 0)) - Player.rage.current
end

function CatForm:ManaCost()
	local cost = Ability.ManaCost(self)
	if StaffOfNaturalFury:Equipped() then
		cost = cost - 200
	end
	if NaturalShapeshifter.known then
		cost = cost - (cost * 0.10 * NaturalShapeshifter.rank)
	end
	return floor(cost + 0.5)
end
BearForm.ManaCost = CatForm.ManaCost

function CatForm:ShapeshiftEnergyGain()
	return ((Furor.known and 40 or 0) + (WolfsheadHelm:Equipped() and 20 or 0)) - Player.energy.current
end

function Claw:EnergyCost()
	local cost = Ability.EnergyCost(self)
	if Ferocity.known then
		cost = cost - Ferocity.rank
	end
	return max(0, cost)
end
Rake.EnergyCost = Claw.EnergyCost
MangleCat.EnergyCost = Claw.EnergyCost

function Lacerate:RageCost()
	local cost = Ability.RageCost(self)
	if ShreddingAttacks.known then
		cost = cost - ShreddingAttacks.rank
	end
	return max(0, cost)
end

function Maul:RageCost()
	local cost = Ability.RageCost(self)
	if Ferocity.known then
		cost = cost - Ferocity.rank
	end
	return max(0, cost)
end
Swipe.RageCost = Maul.RageCost
MangleBear.RageCost = Maul.RageCost

function Shred:EnergyCost()
	local cost = Ability.EnergyCost(self)
	if ShreddingAttacks.known then
		cost = cost - (ShreddingAttacks.rank * 9)
	end
	return max(0, cost)
end

function Shred:Usable(seconds, pool)
	if Opt.front_mode then
		return false
	end
	if Player.threat >= 3 and not Target:Stunned() then
		return false
	end
	if Player.group_size == 1 and Player:TimeInCombat() == 0 and Prowl:Down() then
		return false
	end
	return Ability.Usable(self, seconds, pool)
end

function Prowl:Usable()
	if Player:TimeInCombat() > 0 then
		return false
	end
	return Ability.Usable(self)
end

function Ravage:Usable(seconds, pool)
	if Opt.front_mode then
		return false
	end
	if Prowl:Down() then
		return false
	end
	return Ability.Usable(self, seconds, pool)
end

function Pounce:Usable(seconds, pool)
	if Prowl:Down() then
		return false
	end
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, seconds, pool)
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
	Player.pool_energy = min(Player.energy.max, ability:EnergyCost() + (extra or 0))
	return ability
end

local function WaitForDrop(ability)
	Player.wait_seconds = ability:Remains()
	return ability
end

-- Begin Action Priority Lists

local APL = {}

APL.Main = function(self)
	if Player:TimeInCombat() == 0 then
		local apl = self:Buffs(Target.boss and 180 or 30)
		if apl then
			if Prowl:Up() then
				UseExtra(apl)
			else
				return apl
			end
		end
		if Player.form == FORM.CAT and Player.level >= 40 and not WolfsheadHelm:Equipped() and WolfsheadHelm:Count() > 0 then
			return WolfsheadHelm
		end
	else
		local apl = self:Buffs(10)
		if apl then UseExtra(apl) end
	end
	if Player.form == FORM.BEAR then
		return self:Bear()
	elseif Player.form == FORM.CAT then
		return self:Cat()
	end
	if WolfsheadHelm:Equipped() then
		return CatForm
	end
	return BearForm
end

APL.Buffs = function(self, remains)
	if MarkOfTheWild:Usable() and MarkOfTheWild:Remains() < remains and GiftOfTheWild:Remains() < remains then
		return MarkOfTheWild
	end
	if OmenOfClarity:Usable() and OmenOfClarity:Remains() < remains then
		return OmenOfClarity
	end
	if Thorns:Usable() and Thorns:Remains() < remains then
		return Thorns
	end
end

APL.Bear = function(self)
	self.ff_mine = max(FaerieFireFeral:Remains(true), FaerieFire:Remains(true))
	self.ff_remains = self.ff_mine > 0 and self.ff_mine or max(FaerieFireFeral:Remains(), FaerieFire:Remains())
	self.ff_mine = self.ff_mine > 0

	if Player:TimeInCombat() == 0 then
		if BearForm:Usable() and BearForm:ShapeshiftRageGain() > 0 then
			UseCooldown(BearForm)
		elseif Enrage:Usable() and Player.rage.current < 30 then
			UseCooldown(Enrage)
		end
		if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) then
			return FaerieFireFeral
		end
	end
	if DemoralizingRoar:Usable() and DemoralizingRoar:Remains() < 5 and (Player.enemies > 1 or Target.timeToDie > DemoralizingRoar:Remains()) and DemoralizingShout:Down() then
		UseExtra(DemoralizingRoar, true)
	end
	if Growl:Usable() and Player.threat < 3 then
		UseCooldown(Growl)
	elseif Maul:Usable() and Player.rage.current >= 50 then
		UseCooldown(Maul)
	elseif Enrage:Usable() and Player.rage.current < 15 then
		UseCooldown(Enrage)
	end
	if MangleBear:Usable((Player.enemies >= 3 and 0 or 0.5), true) then
		return MangleBear
	end
	if Lacerate:Usable(0, true) and Lacerate:Stack() >= 3 and Lacerate:Remains() < 6 and Target.timeToDie > Lacerate:Remains() then
		return Lacerate
	end
	if Swipe:Usable() and Player.enemies >= 3 and (Player.rage.current >= (15 + Swipe:RageCost()) or not MangleBear:Ready(3)) then
		return Swipe
	end
	if Lacerate:Usable() and Lacerate:Stack() < 5 and Target.timeToDie > (Lacerate:TickTime() * 3) then
		return Lacerate
	end
	if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) then
		return FaerieFireFeral
	end
	if Swipe:Usable() and Player.rage.current >= (15 + Swipe:RageCost()) then
		if Player.enemies >= 2 or Player.group_size == 1 then
			return Swipe
		end
		if Opt.swipe_st_ap > 0 and Player.attack_power >= Opt.swipe_st_ap then
			return Swipe
		end
		if Opt.swipe_st_threat > 0 and Player.threat_lead >= Opt.swipe_st_threat then
			return Swipe
		end
	end
	if Lacerate:Usable() and Player.rage.current >= (15 + Lacerate:RageCost()) and (Player.group_size > 1 or Target.timeToDie > (Lacerate:TickTime() * 2)) then
		return Lacerate
	end
	if Swipe:Usable() and Player.rage.current >= (15 + Swipe:RageCost()) then
		return Swipe
	end
	if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_mine and Player.group_size > 1 then
		return FaerieFireFeral
	end
end

APL.Cat = function(self)
	self.mangle_mine = max(MangleCat:Remains(true), MangleBear:Remains(true))
	self.mangle_remains = self.mangle_mine > 0 and self.mangle_mine or max(MangleCat:Remains(), MangleBear:Remains())
	self.mangle_mine = self.mangle_mine > 0
	self.ff_mine = max(FaerieFireFeral:Remains(true), FaerieFire:Remains(true))
	self.ff_remains = self.ff_mine > 0 and self.ff_mine or max(FaerieFireFeral:Remains(), FaerieFire:Remains())
	self.ff_mine = self.ff_mine > 0
	self.rip_remains = Rip:Remains()

	if Prowl:Usable() then
		UseCooldown(Prowl)
	end
	if Target.boss and Player.threat_pct >= Opt.cower_pct and Cower:Usable(0, true) then
		UseCooldown(Cower)
	end
	if Pounce:Usable(0, true) and (Player.instance == 'none' or Player.group_size == 1) then
		return Pool(Pounce, Shred:EnergyCost())
	end
	if Ravage:Usable(0, true) then
		return Pool(Ravage)
	end
	if Player.combo_points >= ((PrimalFury.known or Target.timeToDie < 2) and 4 or 5) then
		return self:Cat_Finisher()
	end
	return self:Cat_Generator()
end

APL.Cat_Finisher = function(self)
	if FerociousBite:Usable(0, true) then
		self.ar_pen = (self.ff_remains > 0 and 610 or 0) + (ExposeArmor:Up() and 3075 or 0) + (SunderArmor:Stack() * 520) + (CurseOfRecklessnesss:Up() and 800 or 0) + (PierceArmor:Up() and 5775 or 0)
		if self.ar_pen > 5000 or self.rip_remains > ((self.ar_pen > 4400 and 0 or self.ar_pen > 3200 and 3 or 6) + Player:EnergyTimeToMax(FerociousBite:EnergyCost())) then
			if FerociousBite:EnergyCost() > Player.energy.current and CatForm:Usable() and Target.timeToDie > 1.8 then
				return CatForm
			end
			return Pool(FerociousBite)
		end
	end
	if Rip:Usable(0, true) and Target.timeToDie > (self.rip_remains + (Rip:TickTime() * (self.mangle_remains > 0 and 2 or 3))) then
		if self.rip_remains > 1.5 or (self.rip_remains > 0 and (Clearcasting:Up() or Player:EnergyTimeToMax(72) < (self.rip_remains + 0.5))) then
			return self:Cat_Generator()
		end
		if Rip:ShapeshiftForEnergy() and CatForm:Usable() then
			return CatForm
		end
		return self.rip_remains > 0 and WaitForDrop(Rip) or Pool(Rip)
	end
	if FerociousBite:Usable(0, true) then
		if FerociousBite:ShapeshiftForEnergy() and CatForm:Usable() and Target.timeToDie > 1.8 then
			return CatForm
		end
		return Pool(FerociousBite)
	end
end

APL.Cat_Generator = function(self)
	if MangleCat:Usable(0, true) and Target.timeToDie > self.mangle_remains and (self.mangle_remains == 0 or (self.mangle_mine and (self.mangle_remains <= Player:EnergyTimeToMax(Shred:EnergyCost()) or (Player.combo_points >= 4 and self.mangle_remains <= (Player.gcd * 2))))) then
		if MangleCat:ShapeshiftForEnergy() and CatForm:Usable() then
			return CatForm
		end
		if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) and not MangleCat:Usable() then
			return FaerieFireFeral
		end
		return Pool(MangleCat)
	end
	if Shred:Usable(0, true) then
		if Shred:ShapeshiftForEnergy() and CatForm:Usable() then
			return CatForm
		end
		if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) and not Shred:Usable() then
			return FaerieFireFeral
		end
		return Pool(Shred)
	elseif MangleCat.known then
		if Rake:Usable(0, true) and self.mangle_remains > 0 and Target.timeToDie > (Rake:TickTime() * 4) and Rake:Down() then
			if Rake:ShapeshiftForEnergy() and CatForm:Usable() then
				return CatForm
			end
			return Pool(Rake)
		end
		if MangleCat:Usable(0, true) then
			if MangleCat:ShapeshiftForEnergy() and CatForm:Usable() then
				return CatForm
			end
			if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) and not MangleCat:Usable() then
				return FaerieFireFeral
			end
			return Pool(MangleCat)
		end
	else
		if Rake:Usable(0, true) and Target.timeToDie > (Rake:TickTime() * 2) and Rake:Down() then
			if Rake:ShapeshiftForEnergy() and CatForm:Usable() then
				return CatForm
			end
			return Pool(Rake)
		end
		if Claw:Usable(0, true) then
			if Claw:ShapeshiftForEnergy() and CatForm:Usable() then
				return CatForm
			end
			if Opt.faerie_fire and FaerieFireFeral:Usable() and self.ff_remains < 4 and (self.ff_mine or self.ff_remains == 0) and Target.timeToDie > (4 + self.ff_remains) and not Claw:Usable() then
				return FaerieFireFeral
			end
			return Pool(Claw)
		end
	end
end

APL.Interrupt = function(self)
	if FeralCharge:Usable() then
		return FeralCharge
	end
	if Bash:Usable() then
		return Bash
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['StanceButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	clawPanel:EnableMouse(Opt.aoe or not Opt.locked)
	clawPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		clawPanel:SetScript('OnDragStart', nil)
		clawPanel:SetScript('OnDragStop', nil)
		clawPanel:RegisterForDrag(nil)
		clawPreviousPanel:EnableMouse(false)
		clawCooldownPanel:EnableMouse(false)
		clawInterruptPanel:EnableMouse(false)
		clawExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			clawPanel:SetScript('OnDragStart', clawPanel.StartMoving)
			clawPanel:SetScript('OnDragStop', clawPanel.StopMovingOrSizing)
			clawPanel:RegisterForDrag('LeftButton')
		end
		clawPreviousPanel:EnableMouse(true)
		clawCooldownPanel:EnableMouse(true)
		clawInterruptPanel:EnableMouse(true)
		clawExtraPanel:EnableMouse(true)
	end
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
	clawPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	clawCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
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
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, dim_cd, text_center, text_tr
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.wait_seconds then
		text_center = format('WAIT\n%.1fs', Player.wait_seconds)
		dim = Opt.dimmer
	end
	if Player.main == CatForm and Player.form == FORM.CAT and Player.energy.time_until_tick > 0 then
		text_center = format('TICK\n%.1fs', Player.energy.time_until_tick)
	end
	if Opt.front_mode then
		text_tr = 'F'
	end
	if Player.main and Player.main_freecast then
		if not clawPanel.freeCastOverlayOn then
			clawPanel.freeCastOverlayOn = true
			clawPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif clawPanel.freeCastOverlayOn then
		clawPanel.freeCastOverlayOn = false
		clawPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end
	if Player.cd and Player.cd.queue_time then
		if not clawCooldownPanel.swingQueueOverlayOn then
			clawCooldownPanel.swingQueueOverlayOn = true
			clawCooldownPanel.border:SetTexture(ADDON_PATH .. 'swingqueue.blp')
		end
	elseif clawCooldownPanel.swingQueueOverlayOn then
		clawCooldownPanel.swingQueueOverlayOn = false
		clawCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	clawPanel.dimmer:SetShown(dim)
	clawPanel.text.center:SetText(text_center)
	clawPanel.text.tr:SetText(text_tr)
	clawCooldownPanel.dimmer:SetShown(dim_cd)
	--clawPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL:Main()
	if Player.main then
		clawPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main.spellId and ((Player.form == FORM.CAT and Player.main.energy_cost > 0 and Player.main:EnergyCost() == 0) or (Player.form == FORM.BEAR and Player.main.rage_cost > 0 and Player.main:RageCost() == 0))
	end
	if Player.cd then
		clawCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			clawCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		clawExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends = UnitChannelInfo('target')
		end
		if start then
			Player.interrupt = APL.Interrupt()
			clawInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			clawInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		clawInterruptPanel.icon:SetShown(Player.interrupt)
		clawInterruptPanel.border:SetShown(Player.interrupt)
		clawInterruptPanel:SetShown(start)
	end
	clawPanel.icon:SetShown(Player.main)
	clawPanel.border:SetShown(Player.main)
	clawCooldownPanel:SetShown(Player.cd)
	clawExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = ClawConfig
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Claw1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, spellSchool, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
			local npcId = tonumber(srcGUID:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
			if npcId > 0 then
				if spellSchool then
					if spellSchool > 1 and Target.npc_swing_types[npcId] ~= spellSchool then
						Target.npc_swing_types[npcId] = spellSchool
					end
				elseif Target.npc_swing_types[npcId] then
					spellSchool = Target.npc_swing_types[npcId]
				end
			end
			if not spellSchool or bit.band(spellSchool, 1) > 0 then
				Player.last_swing_taken_physical = Player.time
			end
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_ENERGIZE' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		ability:CastSuccess(dstGUID, timeStamp)
		if Opt.previous and clawPanel:IsVisible() then
			clawPreviousPanel.ability = ability
			clawPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
			clawPreviousPanel.icon:SetTexture(ability.icon)
			clawPreviousPanel:Show()
		end
		return
	end
	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, timeStamp, eventType)
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and clawPanel:IsVisible() and ability == clawPreviousPanel.ability then
			clawPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Player.last_swing_taken_physical = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		clawPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local equipType, hasCooldown
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
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Player:UpdateAbilities()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(47524)
		end
		clawPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_SENT(srcName, dstName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.swing_queue then
		ability.queue_time = GetTime()
	end
end

function events:UNIT_SPELLCAST_FAILED(srcName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.swing_queue then
		ability.queue_time = nil
	end
end
events.UNIT_SPELLCAST_FAILED_QUIET = events.UNIT_SPELLCAST_FAILED

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
	if ability.swing_queue then
		ability.queue_time = nil
	end
end

function events:UNIT_POWER_FREQUENT(srcName, powerType)
	if srcName ~= 'player' then
		return
	elseif powerType == 'MANA' then
		Player:ManaTick()
	elseif powerType == 'ENERGY' then
		Player:EnergyTick()
	end
end

function events:UPDATE_SHAPESHIFT_FORM()
	Player.shapeshift_time = GetTime()
	local form = GetShapeshiftFormID() or 0
	if form == 1 then
		Player.form = FORM.CAT
	elseif form == 5 or form == 8 then
		Player.form = FORM.BEAR
	elseif form == 31 or form == 35 then
		Player.form = FORM.MOONKIN
	elseif form == 3 or form == 4 or form == 27 or form == 29 then
		Player.form = FORM.TRAVEL
	else
		Player.form = FORM.NONE
	end
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

clawPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
for event in next, events do
	clawPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
	if startsWith(msg[1], 'con') then
		if msg[2] then
			Opt.conserve_powershift = msg[2] == 'on'
		end
		return Status('Conserve mana by only powershifting for 2+ energy ticks', Opt.conserve_powershift)
	end
	if startsWith(msg[1], 'mana') then
		if msg[2] then
			Opt.mana_threshold_powershift = max(0, min(100, tonumber(msg[2]) or 20))
		end
		return Status('Powershift when mana is above', Opt.mana_threshold_powershift, '%')
	end
	if startsWith(msg[1], 'pad') then
		if msg[2] then
			Opt.tick_padding_ms = max(0, min(500, tonumber(msg[2]) or 100))
		end
		return Status('Powershift when next energy tick is at least', Opt.tick_padding_ms, 'ms away')
	end
	if startsWith(msg[1], 'fr') then
		if msg[2] then
			Opt.front_mode = msg[2] == 'on'
		end
		return Status('Front mode (unable to Shred/Ravage, displays F in top right)', Opt.front_mode)
	end
	if startsWith(msg[1], 'fa') then
		if msg[2] then
			Opt.faerie_fire = msg[2] == 'on'
		end
		return Status('Use Faerie Fire (turn off when playing with Balance druid)', Opt.faerie_fire)
	end
	if startsWith(msg[1], 'cow') then
		if msg[2] then
			Opt.cower_pct = max(0, min(100, tonumber(msg[2]) or 90))
		end
		return Status('Recommend Cower when threat reaches', Opt.cower_pct, '%')
	end
	if startsWith(msg[1], 'swap') then
		if msg[2] then
			Opt.swipe_st_ap = max(0, min(10000, tonumber(msg[2]) or 2700))
		end
		return Status('Recommend Swipe in single target above when above', Opt.swipe_st_ap, 'attack power (0 is off)')
	end
	if startsWith(msg[1], 'swt') then
		if msg[2] then
			Opt.swipe_st_threat = max(0, min(100000, tonumber(msg[2]) or 10000))
		end
		Status('Recommend Swipe in single target when', Opt.swipe_st_threat, 'threat above next highest threat (0 is off)')
		return Status('This feature requires Details! Tiny Threat plugin to be enabled! Tiny Threat status', DETAILS_PLUGIN_TINY_THREAT and DETAILS_PLUGIN_TINY_THREAT.Enabled)
	end
	if msg[1] == 'reset' then
		clawPanel:ClearAllPoints()
		clawPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'conserve |cFF00C000on|r/|cFFC00000off|r - conserve mana by only powershifting for 2+ energy ticks',
		'mana |cFFFFD000[percent]|r -  powershift when mana is above a percent threshold (default is 20%)',
		'pad |cFFFFD000[0-500]|r - powershift when next energy tick is at least X milliseconds away (default is 100ms)',
		'front |cFF00C000on|r/|cFFC00000off|r - enable front mode (unable to Shred/Ravage)',
		'faerie |cFF00C000on|r/|cFFC00000off|r - use Faerie Fire (turn off when playing with Balance druid)',
		'cower |cFFFFD000[percent]|r -  recommend Cower when above a percent threat threshold (default is 90%)',
		'swap |cFFFFD000[attack power]|r -  recommend Swipe in single target above X attack power (default is 2700, 0 is off)',
		'swt |cFFFFD000[threat]|r -  recommend Swipe in single target when X threat above next highest (default is 10000, 0 is off)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Claw1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
