local ADDON = 'Claw'
if select(2, UnitClass('player')) ~= 'DRUID' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
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

Claw = {}
local Opt -- use this as a local table reference to Claw

SLASH_Claw1, SLASH_Claw2 = '/claw', '/cl'
BINDING_HEADER_CLAW = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
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
		frenzied_threshold = 60,
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

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	form = FORM.NONE,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 100,
	mana_regen = 0,
	energy = 0,
	energy_max = 100,
	energy_regen = 0,
	rage = 0,
	rage_max = 100,
	astral_power = 0,
	astral_power_max = 100,
	combo_points = 0,
	combo_points_max = 5,
	moving = false,
	movement_speed = 100,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	berserk_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
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
clawCooldownPanel.cd = CreateFrame('Cooldown', nil, clawCooldownPanel, 'CooldownFrameTemplate')
clawCooldownPanel.cd:SetAllPoints(clawCooldownPanel)
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
clawInterruptPanel.cast = CreateFrame('Cooldown', nil, clawInterruptPanel, 'CooldownFrameTemplate')
clawInterruptPanel.cast:SetAllPoints(clawInterruptPanel)
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
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
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
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

function autoAoe:Purge()
	local update, guid, t
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		energy_cost = 0,
		ap_cost = 0,
		cp_cost = 0,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
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
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
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
	if not pool then
		if self:ManaCost() > Player.mana then
			return false
		end
		if Player.form == FORM.CAT and self:EnergyCost() > Player.energy then
			return false
		end
		if Player.form == FORM.BEAR and self:RageCost() > Player.rage then
			return false
		end
	end
	if Player.spec == SPEC.BALANCE and self:APCost() > Player.astral_power then
		return false
	end
	if self:CPCost() > Player.combo_points then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
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
	local _, i, id, expires, count
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
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
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

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
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

function Ability:CastEnergyRegen()
	return Player.energy_regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy + self:CastEnergyRegen()) < (Player.energy_max - (reduction or 5))
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
		targets = {}
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
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
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
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Druid Abilities
---- Multiple Specializations
local Barkskin = Ability:Add(22812, true, true)
Barkskin.buff_duration = 12
Barkskin.cooldown_duration = 90
Barkskin.tiggers_gcd = false
local BearForm = Ability:Add(5487, true, true)
local CatForm = Ability:Add(768, true, true)
local Growl = Ability:Add(6795, false, true)
Growl.buff_duration = 3
Growl.cooldown_duration = 8
local Moonfire = Ability:Add(8921, false, true, 164812)
Moonfire.buff_duration = 16
Moonfire.tick_interval = 2
Moonfire.hasted_ticks = true
local SkullBash = Ability:Add(106839, false, true)
SkullBash.cooldown_duration = 15
SkullBash.triggers_gcd = false
local Prowl = Ability:Add(5215, true, true)
Prowl.cooldown_duration = 6
local Rebirth = Ability:Add(20484, true, true)
Rebirth.cooldown_duration = 600
Rebirth.rage_cost = 30
local Regrowth = Ability:Add(8936, true, true)
Regrowth.buff_duration = 12
Regrowth.mana_cost = 14
Regrowth.tick_interval = 2
Regrowth.hasted_ticks = true
local SurvivalInstincts = Ability:Add(61336, true, true)
SurvivalInstincts.buff_duration = 6
SurvivalInstincts.cooldown_duration = 240
local Typhoon = Ability:Add(132469, false, true)
Typhoon.buff_duration = 6
Typhoon.cooldown_duration = 30
------ Procs

------ Talents
local MightyBash = Ability:Add(5211, false, true)
MightyBash.buff_duration = 4
MightyBash.cooldown_duration = 60
local WildCharge = Ability:Add(102401, false, true)
WildCharge.cooldown_duration = 15
local WildChargeCat = Ability:Add(49376, false, true)
WildChargeCat.cooldown_duration = 15
---- Balance
local Sunfire = Ability:Add(93402, false, true, 164815)
Sunfire.buff_duration = 18
Sunfire.tick_interval = 2
Sunfire.hasted_ticks = true
Sunfire:AutoAoe(false, 'apply')
local SolarBeam = Ability:Add(78675, false, true, 81261)
SolarBeam.buff_duration = 8
SolarBeam.cooldown_duration = 60
------ Talents

------ Procs

---- Feral
local Berserk = Ability:Add(106951, true, true)
Berserk.buff_duration = 20
local Rip = Ability:Add(1079, false, true)
Rip.buff_duration = 4
Rip.energy_cost = 20
Rip.cp_cost = 1
Rip.tick_interval = 2
Rip.hasted_ticks = true
Rip:TrackAuras()
local Rake = Ability:Add(1822, false, true, 155722)
Rake.buff_duration = 15
Rake.energy_cost = 35
Rake.tick_interval = 3
Rake.hasted_ticks = true
Rake:TrackAuras()
local Shred = Ability:Add(5221, false, true)
Shred.energy_cost = 40
local FerociousBite = Ability:Add(22568, false, true)
FerociousBite.cp_cost = 1
FerociousBite.energy_cost = 25
local ThrashCat = Ability:Add(106832, false, true, 106830)
ThrashCat.buff_duration = 15
ThrashCat.energy_cost = 40
ThrashCat.tick_interval = 3
ThrashCat.hasted_ticks = true
ThrashCat:AutoAoe(true)
ThrashCat:TrackAuras()
local SwipeCat = Ability:Add(106785, false, true)
SwipeCat.energy_cost = 35
SwipeCat:AutoAoe(true)
local TigersFury = Ability:Add(5217, true, true)
TigersFury.buff_duration = 12
TigersFury.cooldown_duration = 30
TigersFury.triggers_gcd = false
local Maim = Ability:Add(22570, false, true, 203123)
Maim.cooldown_duration = 20
Maim.energy_cost = 30
Maim.cp_cost = 1
------ Talents
local Bloodtalons = Ability:Add(155672, true, true, 145152)
Bloodtalons.buff_duration = 30
local BrutalSlash = Ability:Add(202028, false, true)
BrutalSlash.cooldown_duration = 8
BrutalSlash.energy_cost = 25
BrutalSlash.hasted_cooldown = true
BrutalSlash.requires_charge = true
BrutalSlash:AutoAoe(true)
local FeralFrenzy = Ability:Add(274837, false, true, 274838)
FeralFrenzy.buff_duration = 6
FeralFrenzy.cooldown_duration = 45
FeralFrenzy.energy_cost = 25
FeralFrenzy.tick_interval = 2
FeralFrenzy.hasted_ticks = true
local IncarnationKingOfTheJungle = Ability:Add(102543, true, true)
IncarnationKingOfTheJungle.buff_duration = 30
IncarnationKingOfTheJungle.cooldown_duration = 180
local JungleStalker = Ability:Add(252071, true, true)
JungleStalker.buff_duration = 30
local LunarInspiration = Ability:Add(155580, false, true)
local Sabertooth = Ability:Add(202031, false, true)
local SavageRoar = Ability:Add(52610, true, true)
SavageRoar.buff_duration = 12
SavageRoar.energy_cost = 25
SavageRoar.cp_cost = 1
local ScentOfBlood = Ability:Add(285564, true, true, 285646)
ScentOfBlood.buff_duration = 6
local PrimalWrath = Ability:Add(285381, false, true)
PrimalWrath.energy_cost = 1
PrimalWrath.cp_cost = 1
PrimalWrath:AutoAoe(true)
------ Procs
local Clearcasting = Ability:Add(16864, true, true, 135700)
Clearcasting.buff_duration = 15
local PredatorySwiftness = Ability:Add(16974, true, true, 69369)
PredatorySwiftness.buff_duration = 12
---- Guardian
local FrenziedRegeneration = Ability:Add(22842, true, true)
FrenziedRegeneration.buff_duration = 3
FrenziedRegeneration.cooldown_duration = 36
FrenziedRegeneration.rage_cost = 10
FrenziedRegeneration.tick_interval = 1
FrenziedRegeneration.hasted_cooldown = true
FrenziedRegeneration.requires_charge = true
local IncapacitatingRoar = Ability:Add(99, false, true)
IncapacitatingRoar.buff_duration = 3
IncapacitatingRoar.cooldown_duration = 30
local Ironfur = Ability:Add(192081, true, true)
Ironfur.buff_duration = 7
Ironfur.cooldown_duration = 0.5
Ironfur.rage_cost = 45
local Mangle = Ability:Add(33917, false, true)
Mangle.rage_cost = -8
Mangle.cooldown_duration = 6
Mangle.hasted_cooldown = true
local Maul = Ability:Add(6807, false, true)
Maul.rage_cost = 45
local Thrash = Ability:Add(77758, false, true, 192090)
Thrash.buff_duration = 15
Thrash.cooldown_duration = 6
Thrash.rage_cost = -5
Thrash.tick_interval = 3
Thrash.hasted_cooldown = true
Thrash.hasted_ticks = true
Thrash:AutoAoe(true)
local Swipe = Ability:Add(213771, false, true)
Swipe:AutoAoe(true)
------ Talents
local Brambles = Ability:Add(203953, false, true, 213709)
Brambles.tick_interval = 1
Brambles:AutoAoe()
local BristlingFur = Ability:Add(155835, true, true)
BristlingFur.buff_duration = 8
BristlingFur.cooldown_duration = 40
local GalacticGuardian = Ability:Add(203964, false, true, 213708)
GalacticGuardian.buff_duration = 15
local IncarnationGuardianOfUrsoc = Ability:Add(102558, true, true)
IncarnationGuardianOfUrsoc.buff_duration = 30
IncarnationGuardianOfUrsoc.cooldown_duration = 180
local LunarBeam = Ability:Add(204066, false, true, 204069)
LunarBeam.buff_duration = 8.5
LunarBeam.cooldown_duration = 75
LunarBeam.tick_interval = 1
local Pulverize = Ability:Add(80313, true, true, 158792)
Pulverize.buff_duration = 20
------ Procs

---- Restoration

------ Talents

------ Procs

-- Covenant abilities
local ConvokeTheSpirits = Ability:Add(323764, false, true)
ConvokeTheSpirits.cooldown_duration = 120
-- Legendary effects
local ApexPredatorsCarving = Ability:Add(339139, true, true, 339140)
ApexPredatorsCarving.buff_duration = 15
ApexPredatorsCarving.bonus_id = 7091
-- Racials
local Shadowmeld = Ability:Add(58984, true, true)
-- PvP talents
local Thorns = Ability:Add(305497, true, true)
Thorns.buff_duration = 12
Thorns.cooldown_duration = 45
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
		count = max(count, 1)
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
local GreaterFlaskOfEndlessFathoms = InventoryItem:Add(168652)
GreaterFlaskOfEndlessFathoms.buff = Ability:Add(298837, true, true)
local GreaterFlaskOfTheCurrents = InventoryItem:Add(168651)
GreaterFlaskOfTheCurrents.buff = Ability:Add(298836, true, true)
local SuperiorBattlePotionOfAgility = InventoryItem:Add(168489)
SuperiorBattlePotionOfAgility.buff = Ability:Add(298146, true, true)
SuperiorBattlePotionOfAgility.buff.triggers_gcd = false
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Mana()
	return self.mana
end

function Player:Energy()
	return self.energy
end

function Player:EnergyRegen()
	return self.energy_regen
end

function Player:EnergyDeficit(energy)
	return (energy or self.energy_max) - self.energy
end

function Player:EnergyTimeToMax(energy)
	local deficit = self:EnergyDeficit(energy)
	if deficit <= 0 then
		return 0
	end
	return deficit / self:EnergyRegen()
end

function Player:ComboPoints()
	return self.combo_points
end

function Player:Rage()
	return self.rage
end

function Player:RageDeficit()
	return self.rage_max - self.rage
end

function Player:Stealthed()
	return Prowl:Up() or (Shadowmeld.known and Shadowmeld:Up()) or (IncarnationKingOfTheJungle.known and self.berserk_remains > 0)
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId)
	local i, id, link, item
	for i = 1, 19 do
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

function Player:UpdateAbilities()
	self.mana_max = UnitPowerMax('player', 0)
	self.energy_max = UnitPowerMax('player', 3)
	self.rage_max = UnitPowerMax('player', 1)
	self.combo_points_max = UnitPowerMax('player', 4)

	local _, ability, spellId

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			ability.known = C_Soulbinds.IsConduitInstalledInSoulbind(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
		end
	end

	WildChargeCat.known = WildCharge.known
	if self.spec == SPEC.FERAL then
		SwipeCat.known = not BrutalSlash.known
		self.rip_multiplier_max = Rip:MultiplierMax()
	end
	if self.spec == SPEC.GUARDIAN then
		Swipe.known = true
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
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

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
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
		local i
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
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

-- End Target API

-- Start Ability Modifications

function Ability:EnergyCost()
	local cost  = self.energy_cost
	if Player.spec == SPEC.FERAL then
		if (self == Shred or self == ThrashCat or self == SwipeCat) and Clearcasting:Up() then
			return 0
		end
		if IncarnationKingOfTheJungle.known and IncarnationKingOfTheJungle:Up() then
			cost = cost - (cost * 0.20)
		end
	end
	return cost
end

function FerociousBite:EnergyCost()
	if ApexPredatorsCarving.known and ApexPredatorsCarving:Up() then
		return 0
	end
	return Ability.EnergyCost(self)
end

function Ironfur:RageCost()
	local cost  = self.rage_cost
	if GuardiansWrath.known then
		cost = cost - (GuardiansWrath:Stack() * 15)
	end
	return cost
end

function Regrowth:ManaCost()
	if PredatorySwiftness:Up() then
		return 0
	end
	return Ability.ManaCost(self)
end

function Rake:ApplyAura(guid)
	local aura = {
		expires = Player.time + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Rake:RefreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	aura.expires = Player.time + min(1.3 * self.buff_duration, (aura.expires - Player.time) + self.buff_duration)
	aura.multiplier = self.next_multiplier
end

function Rake:Multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Rake:NextMultiplier()
	local multiplier = 1.00
	local stealthed = false
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if Shadowmeld:Match(id) or Prowl:Match(id) or Berserk:Match(id) or IncarnationKingOfTheJungle:Match(id) then
			stealthed = true
		elseif TigersFury:Match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:Match(id) then
			multiplier = multiplier * 1.15
		end
	end
	if stealthed then
		multiplier = multiplier * 1.60
	end
	return multiplier
end

function Rip:ApplyAura(guid)
	local duration
	if self.next_applied_by == Rip then
		duration = 4 + (4 * self.next_combo_points)
	elseif self.next_applied_by == PrimalWrath then
		duration = 2 + (2 * self.next_combo_points)
	elseif self.next_applied_by == FerociousBite then
		return
	end
	local aura = {
		expires = Player.time + duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Rip:RefreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration, max_duration
	if self.next_applied_by == Rip then
		duration = 4 + (4 * self.next_combo_points)
		max_duration = 1.3 * duration
		aura.multiplier = self.next_multiplier
	elseif self.next_applied_by == PrimalWrath then
		duration = 2 + (2 * self.next_combo_points)
		max_duration = 1.3 * duration
		aura.multiplier = self.next_multiplier
	elseif self.next_applied_by == FerociousBite then
		duration = self.next_combo_points
		max_duration = 1.3 * (4 + (4 * Player.combo_points_max))
	end
	aura.expires = Player.time + min(max_duration, (aura.expires - Player.time) + duration)
end

-- this will return the lowest remaining duration Rip on an enemy that isn't main target
function Rip:LowestRemainsOthers()
	local guid, aura, lowest
	for guid, aura in next, self.aura_targets do
		if guid ~= Target.guid and autoAoe.targets[guid] and (not lowest or aura.expires < lowest) then
			lowest = aura.expires
		end
	end
	if lowest then
		return lowest - Player.time
	end
	return 0
end

function Rip:Multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Rip:MultiplierSum()
	local sum, guid, aura = 0
	for guid, aura in next, self.aura_targets do
		if autoAoe.targets[guid] then
			sum = sum + (aura.multiplier or 0)
		end
	end
	return sum
end

function Rip:MultiplierMax()
	local multiplier = 1.00
	if TigersFury.known then
		multiplier = multiplier * 1.15
	end
	if SavageRoar.known then
		multiplier = multiplier * 1.15
	end
	if Bloodtalons.known then
		multiplier = multiplier * 1.30
	end
	return multiplier
end

function Rip:NextMultiplier()
	local multiplier = 1.00
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if TigersFury:Match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:Match(id) then
			multiplier = multiplier * 1.15
		elseif Bloodtalons:Match(id) then
			multiplier = multiplier * 1.30
		end
	end
	return multiplier
end

function ThrashCat:ApplyAura(guid)
	local aura = {
		expires = Player.time + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function ThrashCat:RefreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	aura.expires = Player.time + min(1.3 * self.buff_duration, (aura.expires - Player.time) + self.buff_duration)
	aura.multiplier = self.next_multiplier
end

function ThrashCat:Multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function ThrashCat:NextMultiplier()
	local multiplier = 1.00
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if TigersFury:Match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:Match(id) then
			multiplier = multiplier * 1.15
		end
	end
	return multiplier
end

function Prowl:Usable()
	if Prowl:Up() or Shadowmeld:Up() or (InCombatLockdown() and not JungleStalker:Up()) then
		return false
	end
	return Ability.Usable(self)
end

function Shadowmeld:Usable()
	if Prowl:Up() or Shadowmeld:Up() or not UnitInParty('player') then
		return false
	end
	return Ability.Usable(self)
end

function Maim:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end
MightyBash.Usable = Maim.Usable
Typhoon.Usable = Maim.Usable

function Moonfire:Duration()
	return Ability:Duration(self) + 6
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

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.BALANCE] = {},
	[SPEC.FERAL] = {},
	[SPEC.GUARDIAN] = {},
	[SPEC.RESTORATION] = {},
}

APL[SPEC.BALANCE].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
end

APL[SPEC.FERAL].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
# It is worth it for almost everyone to maintain thrash
actions.precombat+=/variable,name=use_thrash,value=0
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/cat_form
actions.precombat+=/prowl
actions.precombat+=/potion,dynamic_prepot=1
actions.precombat+=/berserk
]]
		if Prowl:Usable() then
			UseCooldown(Prowl)
		elseif CatForm:Down() then
			UseCooldown(CatForm)
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
--[[
actions=auto_attack,if=!buff.prowl.up&!buff.shadowmeld.up
actions+=/run_action_list,name=opener,if=variable.opener_done=0
actions+=/cat_form,if=!buff.cat_form.up
actions+=/rake,if=buff.prowl.up|buff.shadowmeld.up
actions+=/call_action_list,name=cooldowns
actions+=/ferocious_bite,target_if=dot.rip.ticking&dot.rip.remains<3&target.time_to_die>10&(talent.sabertooth.enabled)
actions+=/run_action_list,name=finishers,if=combo_points>4
actions+=/run_action_list,name=generators
]]
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or Player.berserk_remains > 0
	if not Player.opener_done then
		return self:opener()
	end
	if CatForm:Down() then
		return CatForm
	end
	if Prowl:Up() or Shadowmeld:Up() then
		return Rake
	end
	self:cooldowns()
	if Sabertooth.known and FerociousBite:Usable(0, true) and Rip:Up() and Rip:Remains() < 3 and Target.timeToDie > 10 and (Player.enemies < 3 or Rip:LowestRemainsOthers() > 8) then
		return Pool(FerociousBite, Rip:Remains() < 1 and 0 or 25)
	end
	if Player:HealthPct() < 65 and Regrowth:Usable() and PredatorySwiftness:Up() and Regrowth:WontCapEnergy() and not Player:Stealthed() then
		UseExtra(Regrowth)
	end
	if ApexPredatorsCarving.known and FerociousBite:Usable() and ApexPredatorsCarving:Up() and (not Bloodtalons.known or Bloodtalons:Up() or Rip:Ticking() > 4) then
		return FerociousBite
	end
	if Player:ComboPoints() == 5 then
		return self:finishers()
	end
	return self:generators()
end

APL[SPEC.FERAL].cooldowns = function(self)
--[[
actions.cooldowns=berserk,if=energy>=30&(cooldown.tigers_fury.remains>5|buff.tigers_fury.up)
actions.cooldowns+=/tigers_fury,if=energy.deficit>=60
actions.cooldowns+=/berserking
actions.cooldowns+=/thorns,if=active_enemies>desired_targets|raid_event.adds.in>45
actions.cooldowns+=/feral_frenzy,if=combo_points=0
actions.cooldowns+=/incarnation,if=energy>=30&(cooldown.tigers_fury.remains>15|buff.tigers_fury.up)
actions.cooldowns+=/potion,if=target.time_to_die<65|(time_to_die<180&(buff.berserk.up|buff.incarnation.up))
actions.cooldowns+=/shadowmeld,if=combo_points<5&energy>=action.rake.cost&dot.rake.pmultiplier<1.7&buff.tigers_fury.up&(!talent.incarnation.enabled|cooldown.incarnation.remains>18)&!buff.incarnation.up
actions.cooldowns+=/use_items,if=buff.tigers_fury.up|target.time_to_die<20
]]
	if Player.use_cds then
		if Berserk:Usable() and Player:Energy() >= 40 and (TigersFury:Ready(5) or TigersFury:Up()) then
			return UseCooldown(Berserk)
		end
		if IncarnationKingOfTheJungle:Usable() and Player:Energy() >= 40 and (not TigersFury:Ready(15) or TigersFury:Up()) then
			return UseCooldown(IncarnationKingOfTheJungle)
		end
	end
	if TigersFury:Usable() and Player:EnergyDeficit() >= 60 then
		return UseCooldown(TigersFury)
	end
	if Thorns:Usable() and Player:UnderAttack() and Thorns:WontCapEnergy() then
		return UseCooldown(Thorns)
	end
	if FeralFrenzy:Usable() and Player:ComboPoints() == 0 then
		return UseCooldown(FeralFrenzy)
	end
	if ConvokeTheSpirits:Usable() and Player:ComboPoints() <= (Player.berserk_remains > 0 and 2 or 0) and TigersFury:Remains() > 4 and (not SavageRoar.known or SavageRoar:Remains() > 4) then
		return UseCooldown(ConvokeTheSpirits)
	end
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and (Target.timeToDie < 65 or (Target.timeToDie < 180 and Player.berserk_remains > 0)) then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if Player.use_cds and Shadowmeld:Usable() and Player:ComboPoints() < 5 and Player:Energy() >= Rake:EnergyCost() and Rake:Multiplier() < 1.7 and TigersFury:Up() and Player.berserk_remains == 0 and ((not Berserk.known and not IncarnationKingOfTheJungle.known) or (Berserk.known and not Berserk:Ready(18)) or (IncarnationKingOfTheJungle.known and not IncarnationKingOfTheJungle:Ready(18))) then
		return UseCooldown(Shadowmeld)
	end
	if Opt.trinket and Player.use_cds and ((Target.boss and Target.timeToDie < 20) or TigersFury:Up()) then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.FERAL].finishers = function(self)
--[[
actions.finishers=pool_resource,for_next=1
actions.finishers+=/savage_roar,if=buff.savage_roar.down
actions.finishers+=/pool_resource,for_next=1
actions.finishers+=/primal_wrath,target_if=spell_targets.primal_wrath>1&dot.rip.remains<4
actions.finishers+=/pool_resource,for_next=1
actions.finishers+=/primal_wrath,target_if=spell_targets.primal_wrath>=2
actions.finishers+=/pool_resource,for_next=1
actions.finishers+=/rip,target_if=!ticking|(remains<=duration*0.3)&(!talent.sabertooth.enabled)|(remains<=duration*0.8&persistent_multiplier>dot.rip.pmultiplier)&target.time_to_die>8
actions.finishers+=/pool_resource,for_next=1
actions.finishers+=/savage_roar,if=buff.savage_roar.remains<12
actions.finishers+=/pool_resource,for_next=1
actions.finishers+=/ferocious_bite,max_energy=1,target_if=max:druid.rip.ticks_gained_on_refresh
]]
	if SavageRoar:Usable(0, true) and SavageRoar:Down() then
		return Pool(SavageRoar)
	end
	if Target.timeToDie > max(8, Rip:Remains() + 4) and Rip:Multiplier() < Player.rip_multiplier_max and Rip:NextMultiplier() >= Player.rip_multiplier_max then
		if PrimalWrath:Usable(0, true) and (Sabertooth.known or Player.enemies >= 3) then
			return Pool(PrimalWrath)
		elseif Rip:Usable(0, true) then
			return Pool(Rip)
		end
	end
	if Sabertooth.known and FerociousBite:Usable(0, true) and Rip:Up() and between(Player.enemies, 2, 3) and Rip:LowestRemainsOthers() > ((Player.berserk_remains > 0 and 5 or 8) * (Player.enemies - 1)) then
		return Pool(FerociousBite, Rip:Remains() < 1 and 0 or 25)
	end
	if PrimalWrath:Usable(0, true) and Player.enemies > 1 and (Player.enemies >= 5 or Rip:NextMultiplier() > (Rip:MultiplierSum() / Player.enemies) or Rip:LowestRemainsOthers() < (Player.berserk_remains > 0 and 3.6 or 7.2)) then
		return Pool(PrimalWrath)
	end
	if Target.timeToDie > 8 and (Player.enemies == 1 or not PrimalWrath.known) and (Rip:Down() or (not Sabertooth.known and Rip:Remains() < 7.2) or (Rip:Remains() < 19.2 and Rip:NextMultiplier() > Rip:Multiplier())) then
		if PrimalWrath:Usable(0, true) and Sabertooth.known then
			return Pool(PrimalWrath)
		elseif Rip:Usable(0, true) then
			return Pool(Rip)
		end
	end
	if SavageRoar:Usable(0, true) and SavageRoar:Remains() < 12 then
		return Pool(SavageRoar)
	end
	if FerociousBite:Usable(0, true) then
		return Pool(FerociousBite, 25)
	end
end

APL[SPEC.FERAL].generators = function(self)
--[[
actions.generators+=/brutal_slash,if=spell_targets.brutal_slash>desired_targets
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(refreshable)&(spell_targets.thrash_cat>2)
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(talent.scent_of_blood.enabled&buff.scent_of_blood.down)&spell_targets.thrash_cat>3
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=buff.scent_of_blood.up|(action.swipe_cat.damage*spell_targets.swipe_cat>(action.rake.damage+(action.rake_bleed.tick_damage*5)))
actions.generators+=/pool_resource,for_next=1
actions.generators+=/rake,target_if=!ticking|refreshable&target.time_to_die>4
actions.generators+=/brutal_slash,if=(buff.tigers_fury.up&(raid_event.adds.in>(1+max_charges-charges_fractional)*recharge_time))
actions.generators+=/moonfire_cat,target_if=refreshable
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=refreshable&variable.use_thrash=1&buff.clearcasting.react&!buff.incarnation.up
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.generators+=/shred,if=dot.rake.remains>(action.shred.cost+action.rake.cost-energy)%energy.regen|buff.clearcasting.react
]]
	if Sabertooth.known and Player.enemies == 1 and Player:ComboPoints() >= 2 and Rip:Down() and Rip:Usable() and Rip:NextMultiplier() >= Player.rip_multiplier_max and (TigersFury:Remains() < 1.5 or Bloodtalons:Remains() < 1.5 or Bloodtalons:Stack() == 1) then
		return Rip
	end
	if ThrashCat:Usable(0, true) and Player.enemies > 2 then
		if ThrashCat:Refreshable() and (Player.berserk_remains == 0 or Player.enemies > 3) then
			return Pool(ThrashCat)
		end
		if ScentOfBlood.known and ScentOfBlood:Down() and Player.enemies > 3 then
			return Pool(ThrashCat)
		end
	end
	if BrutalSlash:Usable() and Player.enemies > 2 and (Player:Energy() < 50 or Player:ComboPoints() < 4) then
		return BrutalSlash
	end
	if ScentOfBlood.known and SwipeCat:Usable(0, true) and ScentOfBlood:Up() then
		return Pool(SwipeCat)
	end
	if Player.enemies < 6 or not PrimalWrath.known then
		if Rake:Usable(0, true) and (Rake:Down() or Target.timeToDie > 4 and Rake:Refreshable()) then
			return Pool(Rake)
		end
		if LunarInspiration.known and Moonfire:Usable() and Moonfire:Refreshable() then
			return Pool(Moonfire)
		end
	end
	if BrutalSlash:Usable() and Player:EnergyTimeToMax() > 1.5 and (TigersFury:Up() or BrutalSlash:ChargesFractional() > 2.5) then
		return BrutalSlash
	end
	if ThrashCat:Usable(0, true) and Player.enemies >= 2 and ThrashCat:Refreshable() and Clearcasting:Up() and Target.timeToDie > (ThrashCat:Remains() + 9) and Player.berserk_remains == 0 then
		return ThrashCat
	end
	if SwipeCat:Usable(0, true) and Player.enemies > 1 and Player.berserk_remains == 0 then
		return Pool(SwipeCat)
	end
	if Shred:Usable() and (Clearcasting:Up() or Rake:Remains() > ((Shred:EnergyCost() + Rake:EnergyCost() - Player:Energy()) / Player:EnergyRegen())) then
		return Shred
	end
end

APL[SPEC.FERAL].opener = function(self)
--[[
# The opener generally follow the logic of the rest of the apl, but is separated out here for logical clarity
# We will open with TF, you can safely cast this from stealth without breaking it.
actions.opener=tigers_fury
# Always open with rake, consuming stealth and one BT charge (if talented)
actions.opener+=/rake,if=!ticking|buff.prowl.up
# Lets make sure we end the opener "sequence" when our first rip is ticking
actions.opener+=/variable,name=opener_done,value=dot.rip.ticking
# Break out of the action list
actions.opener+=/wait,sec=0.001,if=dot.rip.ticking
# If we have LI, and haven't applied it yet use moonfire.
actions.opener+=/moonfire_cat,if=!ticking
# no need to wait for 5 CPs anymore, just rip and we are up and running
actions.opener+=/rip,if=!ticking
]]
	if Player:ComboPoints() == 5 then
		Player.opener_done = true
		return self:main()
	end
	if TigersFury:Usable() and TigersFury:Remains() < 4 then
		UseCooldown(TigersFury)
	end
	if Rake:Usable() and (Rake:Down() or Prowl:Up()) then
		return Rake
	end
	if Rip:Up() or Player.enemies > 1 then
		Player.opener_done = true
		return self:main()
	end
	if LunarInspiration.known and Moonfire:Down() then
		return Moonfire
	end
	if Player:ComboPoints() >= ((Berserk:Remains() > 6 or TigersFury:Ready()) and 3 or 5) and PrimalWrath:Usable() then
		return PrimalWrath
	end
	if Rip:Usable() then
		return Rip
	end
end

APL[SPEC.GUARDIAN].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and SuperiorBattlePotionOfAgility:Usable() then
				UseCooldown(SuperiorBattlePotionOfAgility)
			end
		end
	end
--[[
actions=auto_attack
actions+=/call_action_list,name=cooldowns
actions+=/maul,if=rage.deficit<10&active_enemies<4
actions+=/ironfur,if=cost=0
actions+=/pulverize,target_if=dot.thrash_bear.stack=dot.thrash_bear.max_stacks
actions+=/moonfire,target_if=dot.moonfire.refreshable&active_enemies<2
actions+=/incarnation
actions+=/thrash,if=(buff.incarnation.down&active_enemies>1)|(buff.incarnation.up&active_enemies>4)
actions+=/swipe,if=buff.incarnation.down&active_enemies>4
actions+=/mangle,if=dot.thrash_bear.ticking
actions+=/moonfire,target_if=buff.galactic_guardian.up&active_enemies<2
actions+=/thrash
actions+=/maul
actions+=/swipe
]]
	if BearForm:Down() then
		return BearForm
	end
	self:cooldowns()
	if Maul:Usable() and Player:RageDeficit() < 10 and Player.enemies < 4 then
		return Maul
	end
	if Ironfur:Usable() and Ironfur:RageCost() == 0 then
		UseExtra(Ironfur)
	end
	if Pulverize:Usable() and Thrash:Stack() == 3 then
		return Pulverize
	end
	if Moonfire:Usable() and Moonfire:Refreshable() and Player.enemies < 2 then
		return Moonfire
	end
	if IncarnationGuardianOfUrsoc:Usable() then
		UseCooldown(IncarnationGuardianOfUrsoc)
	end
	if Thrash:Usable() and ((Player.enemies > 1 and (not IncarnationGuardianOfUrsoc.known or IncarnationGuardianOfUrsoc:Down())) or (Player.enemies > 4 and IncarnationGuardianOfUrsoc.known and IncarnationGuardianOfUrsoc:Up())) then
		return Thrash
	end
	if Swipe:Usable() and Player.enemies > 4 and (not IncarnationGuardianOfUrsoc.known or IncarnationGuardianOfUrsoc:Down()) then
		return Swipe
	end
	if Mangle:Usable() and Thrash:Up() then
		return Mangle
	end
	if GalacticGuardian.known and Moonfire:Usable() and Player.enemies < 2 and GalacticGuardian:Up() then
		return Moonfire
	end
	if Thrash:Usable() then
		return Thrash
	end
	if Maul:Usable() and (Player:RageDeficit() < 30 or (GuardiansWrath.known and GuardiansWrath:Stack() < 3)) then
		return Maul
	end
	if Swipe:Usable() then
		return Swipe
	end
end

APL[SPEC.GUARDIAN].cooldowns = function(self)
--[[
actions.cooldowns=potion
actions.cooldowns+=/blood_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/arcane_torrent
actions.cooldowns+=/lights_judgment
actions.cooldowns+=/fireblood
actions.cooldowns+=/ancestral_call
actions.cooldowns+=/barkskin,if=buff.bear_form.up
actions.cooldowns+=/lunar_beam,if=buff.bear_form.up
actions.cooldowns+=/bristling_fur,if=buff.bear_form.up
actions.cooldowns+=/use_items
]]
	if BearForm:Down() then
		return
	end
	if FrenziedRegeneration:Usable() and Player:HealthPct() <= Opt.frenzied_threshold then
		UseExtra(FrenziedRegeneration)
	end
	if Thorns:Usable() and Player:UnderAttack() and Player:HealthPct() > 60 then
		return UseCooldown(Thorns)
	end
	if Barkskin:Usable() then
		return UseCooldown(Barkskin)
	end
	if LunarBeam:Usable() then
		return UseCooldown(LunarBeam)
	end
	if BristlingFur:Usable() then
		return UseCooldown(BristlingFur)
	end
end

APL[SPEC.RESTORATION].main = function(self)

end

APL.Interrupt = function(self)
	if SkullBash:Usable() then
		return SkullBash
	end
	if SolarBeam:Usable() then
		return SolarBeam
	end
	if Maim:Usable() then
		return Maim
	end
	if MightyBash:Usable() then
		return MightyBash
	end
	if Typhoon:Usable() then
		return Typhoon
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
	local w, h, glow, i
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
	local b, i
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
	local glow, icon, i
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

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[FORM.NONE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[FORM.MOONKIN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[FORM.CAT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -24 }
		},
		[FORM.BEAR] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[FORM.TRAVEL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[FORM.NONE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[FORM.MOONKIN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[FORM.CAT] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[FORM.BEAR] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[FORM.TRAVEL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
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
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center, text_tl
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.berserk_remains > 0 then
		text_tl = format('%.1fs', Player.berserk_remains)
	end
	clawPanel.dimmer:SetShown(dim)
	clawPanel.text.center:SetText(text_center)
	clawPanel.text.tl:SetText(text_tl)
	--clawPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId, speed, max_speed
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	Player.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	if Player.form == FORM.CAT then
		Player.gcd = 1
		Player.energy_regen = GetPowerRegen()
		Player.energy_max = UnitPowerMax('player', 3)
		Player.energy = UnitPower('player', 3) + (Player.energy_regen * Player.execute_remains)
		Player.energy = min(max(Player.energy, 0), Player.energy_max)
		Player.combo_points = UnitPower('player', 4)
	else
		Player.mana_regen = GetPowerRegen()
		Player.gcd = 1.5 * Player.haste_factor
	end
	if Player.form == FORM.BEAR then
		Player.rage = UnitPower('player', 1)
	end
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:ManaCost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	speed, max_speed = GetUnitSpeed('player')
	Player.moving = speed ~= 0
	Player.movement_speed = max_speed / 7 * 100
	if Berserk.known then
		Player.berserk_remains = Berserk:Remains()
	elseif IncarnationKingOfTheJungle.known then
		Player.berserk_remains = IncarnationKingOfTheJungle:Remains()
	end

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		clawPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		clawCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		clawExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			clawInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			clawInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		clawInterruptPanel.icon:SetShown(Player.interrupt)
		clawInterruptPanel.border:SetShown(Player.interrupt)
		clawInterruptPanel:SetShown(start and not notInterruptible)
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
		Opt = Claw
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
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
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
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		Player.last_ability = ability
		ability.last_used = Player.time
		if ability.triggers_gcd then
			Player.previous_gcd[10] = nil
			table.insert(Player.previous_gcd, 1, ability)
		end
		if ability.travel_start then
			ability.travel_start[dstGUID] = Player.time
		end
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
		elseif ability == Shred and Player.berserk_remains == 0 then
			Player:SetTargetMode(1)
		elseif ability == Rake and (eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH') then
			autoAoe:Add(dstGUID, true)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Sabertooth.known and ability == FerociousBite and Rip.aura_targets[dstGUID] and (eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_ABSORBED') then
			Rip:RefreshAura(dstGUID)
		end
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
	Target.estimated_range = 30
	Player.previous_gcd = {}
	Player.opener_done = false
	if Player.last_ability then
		Player.last_ability = nil
		clawPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
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
	local _, i, equipType, hasCooldown
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

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	Player.berserk_remains = 0
	clawPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:UPDATE_SHAPESHIFT_FORM()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		clawPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and (powerType == 'COMBO_POINTS' or powerType == 'LUNAR_POWER') then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_SENT(srcName, destName, castId, spellId)
	if srcName ~= 'player' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability == Rip or ability == PrimalWrath or (Sabertooth.known and ability == FerociousBite) then
		Rip.next_applied_by = ability
		Rip.next_combo_points = UnitPower('player', 4)
		Rip.next_multiplier = Rip:NextMultiplier()
	elseif ability == Rake then
		Rake.next_multiplier = Rake:NextMultiplier()
	elseif ability == ThrashCat then
		ThrashCat.next_multiplier = ThrashCat:NextMultiplier()
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

function events:UPDATE_SHAPESHIFT_FORM()
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
	Player:UpdateAbilities()
	UI.OnResourceFrameShow()
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
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
local event
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
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				clawPanel:ClearAllPoints()
			end
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
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
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
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
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
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.balance = not Opt.hide.balance
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Balance specialization', not Opt.hide.balance)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.feral = not Opt.hide.feral
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Feral specialization', not Opt.hide.feral)
			end
			if startsWith(msg[2], 'g') then
				Opt.hide.guardian = not Opt.hide.guardian
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Guardian specialization', not Opt.hide.guardian)
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.restoration = not Opt.hide.restoration
				events:PLAYER_SPECIALIZATION_CHANGED('player')
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
	if startsWith(msg[1], 'fr') then
		if msg[2] then
			Opt.frenzied_threshold = tonumber(msg[2]) or 60
		end
		return Status('Health threshold to recommend Frenzied Regeneration at in Bear Form', Opt.frenzied_threshold .. '%')
	end
	if msg[1] == 'reset' then
		clawPanel:ClearAllPoints()
		clawPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
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
		'hidespec |cFFFFD000balance|r/|cFFFFD000feral|r/|cFFFFD000guardian|r/|cFFFFD000restoration|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'frenzied |cFFFFD000[health]|r  - health threshold to recommend Frenzied Regeneration at in Bear Form (default is 60%)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Claw1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
