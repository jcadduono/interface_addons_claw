if select(2, UnitClass('player')) ~= 'DRUID' then
	DisableAddOn('Claw')
	return
end

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
BINDING_HEADER_CLAW = 'Claw'

local function InitializeOpts()
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
		pot = false,
		trinket = true,
		frenzied_threshold = 60,
	})
end

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

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	form = FORM.NONE,
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
	combo_points = 0,
	combo_points_max = 5,
	previous_gcd = {},-- list of previous GCD abilities
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
}

-- Azerite trait API access
local Azerite = {}

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
clawPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
clawPanel.border:Hide()
clawPanel.dimmer = clawPanel:CreateTexture(nil, 'BORDER')
clawPanel.dimmer:SetAllPoints(clawPanel)
clawPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
clawPanel.dimmer:Hide()
clawPanel.swipe = CreateFrame('Cooldown', nil, clawPanel, 'CooldownFrameTemplate')
clawPanel.swipe:SetAllPoints(clawPanel)
clawPanel.text = CreateFrame('Frame', nil, clawPanel)
clawPanel.text:SetAllPoints(clawPanel)
clawPanel.text.br = clawPanel.text:CreateFontString(nil, 'OVERLAY')
clawPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text.br:SetPoint('BOTTOMRIGHT', clawPanel, 'BOTTOMRIGHT', -1.5, 3)
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
clawPreviousPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
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
clawCooldownPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
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
clawInterruptPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
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
clawExtraPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')

-- Start Auto AoE

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BALANCE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.FERAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'}
	},
	[SPEC.GUARDIAN] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.RESTORATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
}

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[Player.spec])
	Player.enemies = targetModes[Player.spec][targetMode][1]
	clawPanel.text.br:SetText(targetModes[Player.spec][targetMode][2])
end
Claw_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[Player.spec] and 1 or mode)
end
Claw_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[Player.spec] or mode)
end
Claw_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
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
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #targetModes[Player.spec], 1, -1 do
		if count >= targetModes[Player.spec][i][1] then
			SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:purge()
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
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
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
		cp_cost = 0,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(pool)
	if not self.known then
		return false
	end
	if not pool then
		if self:manaCost() > Player.mana then
			return false
		end
		if Player.form == FORM.CAT and self:energyCost() > Player.energy then
			return false
		end
		if Player.form == FORM.BEAR and self:rageCost() > Player.rage then
			return false
		end
	end
	if self:cpCost() > Player.combo_points then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:casting() or self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	return self:remains() > 0
end

function Ability:down()
	return self:remains() <= 0
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:travelTime()
	return Target.estimated_range / self.velocity
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:manaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
end

function Ability:energyCost()
	return self.energy_cost
end

function Ability:cpCost()
	return self.cp_cost
end

function Ability:rageCost()
	return self.rage_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return Player.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:tickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected, trigger)
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

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local remains = aura.expires - Player.time
	local duration = self:duration()
	aura.expires = Player.time + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Druid Abilities
---- Multiple Specializations
local Barkskin = Ability.add(22812, true, true)
Barkskin.buff_duration = 12
Barkskin.cooldown_duration = 90
Barkskin.tiggers_gcd = false
local BearForm = Ability.add(5487, true, true)
local CatForm = Ability.add(768, true, true)
local Growl = Ability.add(6795, false, true)
Growl.buff_duration = 3
Growl.cooldown_duration = 8
local SkullBash = Ability.add(106839, false, true)
SkullBash.cooldown_duration = 15
SkullBash.triggers_gcd = false
local Prowl = Ability.add(5215, true, true)
Prowl.cooldown_duration = 6
local Rebirth = Ability.add(20484, true, true)
Rebirth.cooldown_duration = 600
Rebirth.rage_cost = 30
local Regrowth = Ability.add(8936, true, true)
Regrowth.buff_duration = 12
Regrowth.mana_cost = 14
Regrowth.tick_interval = 2
Regrowth.hasted_ticks = true
local SurvivalInstincts = Ability.add(61336, true, true)
SurvivalInstincts.buff_duration = 6
SurvivalInstincts.cooldown_duration = 240
------ Procs

------ Talents
local WildCharge = Ability.add(102401, false, true)
WildCharge.cooldown_duration = 15
local WildChargeCat = Ability.add(49376, false, true)
WildChargeCat.cooldown_duration = 15
---- Balance

------ Talents

------ Procs

---- Feral
local Berserk = Ability.add(106951, true, true)
Berserk.buff_duration = 20
local Rip = Ability.add(1079, false, true)
Rip.buff_duration = 4
Rip.energy_cost = 20
Rip.cp_cost = 1
Rip.tick_interval = 2
Rip.hasted_ticks = true
Rip:trackAuras()
local Rake = Ability.add(1822, false, true, 155722)
Rake.buff_duration = 15
Rake.energy_cost = 35
Rake.tick_interval = 3
Rake.hasted_ticks = true
Rake:trackAuras()
local Shred = Ability.add(5221, false, true)
Shred.energy_cost = 40
local FerociousBite = Ability.add(22568, false, true)
FerociousBite.cp_cost = 1
FerociousBite.energy_cost = 25
local ThrashCat = Ability.add(106830, false, true)
ThrashCat.buff_duration = 15
ThrashCat.energy_cost = 40
ThrashCat.tick_interval = 3
ThrashCat.hasted_ticks = true
ThrashCat:autoAoe(true)
ThrashCat:trackAuras()
local SwipeCat = Ability.add(106785, false, true)
SwipeCat.energy_cost = 35
SwipeCat:autoAoe(true)
local TigersFury = Ability.add(5217, true, true)
TigersFury.cooldown_duration = 30
TigersFury.triggers_gcd = false
local Maim = Ability.add(22570, false, true, 203123)
Maim.cooldown_duration = 20
Maim.energy_cost = 30
Maim.cp_cost = 1
local MoonfireCat = Ability.add(8921, false, true, 164812)
MoonfireCat.buff_duration = 18
MoonfireCat.energy_cost = 30
MoonfireCat.tick_interval = 2
MoonfireCat.hasted_ticks = true
------ Talents
local Bloodtalons = Ability.add(155672, true, true, 145152)
Bloodtalons.buff_duration = 30
local BrutalSlash = Ability.add(202028, false, true)
BrutalSlash.cooldown_duration = 8
BrutalSlash.energy_cost = 25
BrutalSlash.hasted_cooldown = true
BrutalSlash.requires_charge = true
BrutalSlash:autoAoe(true)
local FeralFrenzy = Ability.add(274837, false, true, 274838)
FeralFrenzy.buff_duration = 6
FeralFrenzy.cooldown_duration = 45
FeralFrenzy.energy_cost = 25
FeralFrenzy.tick_interval = 2
FeralFrenzy.hasted_ticks = true
local IncarnationKingOfTheJungle = Ability.add(102543, true, true)
IncarnationKingOfTheJungle.buff_duration = 30
IncarnationKingOfTheJungle.cooldown_duration = 180
local JungleStalker = Ability.add(252071, true, true)
JungleStalker.buff_duration = 30
local LunarInspiration = Ability.add(155580, false, true)
local Sabertooth = Ability.add(202031, false, true)
local SavageRoar = Ability.add(52610, true, true)
SavageRoar.buff_duration = 12
SavageRoar.energy_cost = 25
SavageRoar.cp_cost = 1
local ScentOfBlood = Ability.add(285564, true, true, 285646)
ScentOfBlood.buff_duration = 6
local PrimalWrath = Ability.add(285381, false, true)
PrimalWrath.energy_cost = 1
PrimalWrath.cp_cost = 1
PrimalWrath:autoAoe(true)
------ Procs
local Clearcasting = Ability.add(16864, true, true, 135700)
Clearcasting.buff_duration = 15
local PredatorySwiftness = Ability.add(16974, true, true, 69369)
PredatorySwiftness.buff_duration = 12
---- Guardian
local FrenziedRegeneration = Ability.add(22842, true, true)
FrenziedRegeneration.buff_duration = 3
FrenziedRegeneration.cooldown_duration = 36
FrenziedRegeneration.rage_cost = 10
FrenziedRegeneration.tick_interval = 1
FrenziedRegeneration.hasted_cooldown = true
FrenziedRegeneration.requires_charge = true
local IncapacitatingRoar = Ability.add(99, false, true)
IncapacitatingRoar.buff_duration = 3
IncapacitatingRoar.cooldown_duration = 30
local Ironfur = Ability.add(192081, true, true)
Ironfur.buff_duration = 7
Ironfur.cooldown_duration = 0.5
Ironfur.rage_cost = 45
local Mangle = Ability.add(33917, false, true)
Mangle.rage_cost = -8
Mangle.cooldown_duration = 6
Mangle.hasted_cooldown = true
local Maul = Ability.add(6807, false, true)
Maul.rage_cost = 45
local MoonfireBear = Ability.add(8921, false, true, 164812)
MoonfireCat.buff_duration = 16
MoonfireCat.tick_interval = 2
MoonfireCat.hasted_ticks = true
local Thrash = Ability.add(77758, false, true, 192090)
Thrash.buff_duration = 15
Thrash.cooldown_duration = 6
Thrash.rage_cost = -5
Thrash.tick_interval = 3
Thrash.hasted_cooldown = true
Thrash.hasted_ticks = true
Thrash:autoAoe(true)
local Swipe = Ability.add(213771, false, true)
Swipe:autoAoe(true)
------ Talents
local Brambles = Ability.add(203953, false, true, 213709)
Brambles.tick_interval = 1
Brambles:autoAoe()
local BristlingFur = Ability.add(155835, true, true)
BristlingFur.buff_duration = 8
BristlingFur.cooldown_duration = 40
local GalacticGuardian = Ability.add(203964, false, true, 213708)
GalacticGuardian.buff_duration = 15
local IncarnationGuardianOfUrsoc = Ability.add(102558, true, true)
IncarnationGuardianOfUrsoc.buff_duration = 30
IncarnationGuardianOfUrsoc.cooldown_duration = 180
local LunarBeam = Ability.add(204066, false, true, 204069)
LunarBeam.buff_duration = 8.5
LunarBeam.cooldown_duration = 75
LunarBeam.tick_interval = 1
local Pulverize = Ability.add(80313, true, true, 158792)
Pulverize.buff_duration = 20
------ Procs

---- Restoration

------ Talents

------ Procs

-- Azerite Traits
local GuardiansWrath = Ability.add(278511, true, true, 279541)
GuardiansWrath.buff_duration = 30
local IronJaws = Ability.add(276021, true, true)
local LayeredMane = Ability.add(279552, true, true)
local PowerOfTheMoon = Ability.add(273367, true, true)
local WildFleshrending = Ability.add(279527, false, true)
-- Racials
local Shadowmeld = Ability.add(58984, true, true)
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:equipped()
	return self.equip_slot and true
end

function InventoryItem:usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:equipped() and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfTheCurrents = InventoryItem.add(152638)
FlaskOfTheCurrents.buff = Ability.add(251836, true, true)
local FlaskOfEndlessFathoms = InventoryItem.add(152693)
FlaskOfEndlessFathoms.buff = Ability.add(251837, true, true)
local BattlePotionOfAgility = InventoryItem.add(163223)
BattlePotionOfAgility.buff = Ability.add(279152, true, true)
BattlePotionOfAgility.buff.triggers_gcd = false
local BattlePotionOfIntellect = InventoryItem.add(163222)
BattlePotionOfIntellect.buff = Ability.add(279151, true, true)
BattlePotionOfIntellect.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem.add(0)
local Trinket2 = InventoryItem.add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Health()
	return Player.health
end

local function HealthMax()
	return Player.health_max
end

local function HealthPct()
	return Player.health / Player.health_max * 100
end

local function Mana()
	return Player.mana
end

local function Energy()
	return Player.energy
end

local function EnergyRegen()
	return Player.energy_regen
end

local function EnergyDeficit()
	return Player.energy_max - Player.energy
end

local function EnergyTimeToMax()
	local deficit = Player.energy_max - Player.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / Player.energy_regen
end

local function ComboPoints()
	return Player.combo_points
end

local function Rage()
	return Player.rage
end

local function RageDeficit()
	return Player.rage_max - Player.rage
end

local function TimeInCombat()
	if Player.combat_start > 0 then
		return Player.time - Player.combat_start
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
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

local function InArenaOrBattleground()
	return Player.instance == 'arena' or Player.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function Ability:energyCost()
	local cost  = self.energy_cost
	if Player.spec == SPEC.FERAL then
		if (self == Shred or self == ThrashCat or self == SwipeCat) and Clearcasting:up() then
			return 0
		end
		if Berserk:up() then
			cost = cost - (cost * 0.40)
		end
	end
	return cost
end

function Ironfur:rageCost()
	local cost  = self.rage_cost
	if GuardiansWrath.known then
		cost = cost - (GuardiansWrath:stack() * 15)
	end
	return cost
end

function Regrowth:manaCost()
	if PredatorySwiftness:up() then
		return 0
	end
	return Ability.manaCost(self)
end

function Rake:applyAura(guid)
	local aura = {
		expires = Player.time + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Rake:refreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local remains = aura.expires - Player.time
	aura.expires = Player.time + min(1.3 * self.buff_duration, remains + self.buff_duration)
	aura.multiplier = self.next_multiplier
end

function Rake:multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Rake:nextMultiplier()
	local multiplier = 1.00
	local stealthed = false
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if Shadowmeld:match(id) or Prowl:match(id) or IncarnationKingOfTheJungle:match(id) then
			stealthed = true
		elseif TigersFury:match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:match(id) then
			multiplier = multiplier * 1.10
		elseif Bloodtalons:match(id) then
			multiplier = multiplier * 1.25
		end
	end
	if stealthed then
		multiplier = multiplier * 2.00
	end
	return multiplier
end

function Rip:applyAura(guid)
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

function Rip:refreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local remains = aura.expires - Player.time
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
		duration = 4 * self.next_combo_points
		max_duration = 1.3 * (4 + (4 * Player.combo_points_max))
	end
	aura.expires = Player.time + min(max_duration, remains + duration)
end

-- this will return the lowest remaining duration Rip on an enemy that isn't main target
function Rip:lowestRemainsOthers()
	local guid, aura, lowest
	for guid, aura in next, self.aura_targets do
		if guid ~= Target.guid and autoAoe.targets[guid] and (not lowest or aura.expires < lowest) then
			lowest = aura.expires
		end
	end
	if lowest then
		return lowest - (Player.time - Player.time_diff)
	end
	return 0
end

function Rip:multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Rip:multiplierSum()
	local sum, guid, aura = 0
	for guid, aura in next, self.aura_targets do
		if autoAoe.targets[guid] then
			sum = sum + (aura.multiplier or 0)
		end
	end
	return sum
end

function Rip:nextMultiplier()
	local multiplier = 1.00
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if TigersFury:match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:match(id) then
			multiplier = multiplier * 1.10
		elseif Bloodtalons:match(id) then
			multiplier = multiplier * 1.25
		end
	end
	return multiplier
end

function Rip:multiplierMax()
	local multiplier = 1.00
	if TigersFury.known then
		multiplier = multiplier * 1.15
	end
	if SavageRoar.known then
		multiplier = multiplier * 1.10
	end
	if Bloodtalons.known then
		multiplier = multiplier * 1.25
	end
	return multiplier
end

function ThrashCat:applyAura(guid)
	local aura = {
		expires = Player.time + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function ThrashCat:refreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local remains = aura.expires - Player.time
	aura.expires = Player.time + min(1.3 * self.buff_duration, remains + self.buff_duration)
	aura.multiplier = self.next_multiplier
end

function ThrashCat:multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function ThrashCat:nextMultiplier()
	local multiplier = 1.00
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL|PLAYER')
		if not id then
			break
		end
		if TigersFury:match(id) then
			multiplier = multiplier * 1.15
		elseif SavageRoar:match(id) then
			multiplier = multiplier * 1.10
		elseif Bloodtalons:match(id) then
			multiplier = multiplier * 1.25
		end
	end
	return multiplier
end

function Bloodtalons:up()
	if self.known and Regrowth:casting() then
		return true
	end
	return Ability.up(self)
end

function Bloodtalons:remains()
	if self.known and Regrowth:casting() then
		return self:duration()
	end
	return Ability.remains(self)
end

function Prowl:usable()
	if Prowl:up() or Shadowmeld:up() or (InCombatLockdown() and not JungleStalker:up()) then
		return false
	end
	return Ability.usable(self)
end

function Shadowmeld:usable()
	if Prowl:up() or Shadowmeld:up() or not UnitInParty('player') then
		return false
	end
	return Ability.usable(self)
end

function Maim:usable()
	if not Target.stunnable then
		return false
	end
	return Ability.usable(self)
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
	Player.pool_energy = ability:energyCost() + (extra or 0)
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
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfIntellect:usable() then
				UseCooldown(BattlePotionOfIntellect)
			end
		end
	end
end

APL[SPEC.FERAL].main = function(self)
	if TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/regrowth,if=talent.balancetalons.enabled
# It is worth it for almost everyone to maintain thrash
actions.precombat+=/variable,name=use_thrash,value=0
actions.precombat+=/variable,name=use_thrash,value=2,if=azerite.wild_fleshrending.enabled
actions.precombat+=/cat_form
actions.precombat+=/prowl
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/berserk
]]
		if Prowl:usable() then
			UseCooldown(Prowl)
		elseif CatForm:down() then
			UseCooldown(CatForm)
		end
		if Bloodtalons.known and Bloodtalons:remains() < 6 then
			return Regrowth
		end
		if not InArenaOrBattleground() then
			if Opt.pot and BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
		if Berserk:usable() then
			UseCooldown(Berserk)
		end
	end
--[[
actions=auto_attack,if=!buff.prowl.up&!buff.shadowmeld.up
actions+=/run_action_list,name=opener,if=variable.opener_done=0
actions+=/cat_form,if=!buff.cat_form.up
actions+=/rake,if=buff.prowl.up|buff.shadowmeld.up
actions+=/call_action_list,name=cooldowns
actions+=/ferocious_bite,target_if=dot.rip.ticking&dot.rip.remains<3&target.time_to_die>10&(talent.sabertooth.enabled)
actions+=/regrowth,if=combo_points=5&buff.predatory_swiftness.up&talent.balancetalons.enabled&buff.balancetalons.down&(!buff.incarnation.up|dot.rip.remains<8)
actions+=/run_action_list,name=finishers,if=combo_points>4
actions+=/run_action_list,name=generators
]]
	if not Player.opener_done then
		return self:opener()
	end
	if CatForm:down() then
		return CatForm
	end
	if Prowl:up() or Shadowmeld:up() then
		return Rake
	end
	self:cooldowns()
	if Sabertooth.known and FerociousBite:usable(true) and Rip:up() and Rip:remains() < 3 and Target.timeToDie > 10 and (Player.enemies < 3 or Rip:lowestRemainsOthers() > 8) then
		return Pool(FerociousBite, Rip:remains() < 1 and 0 or 25)
	end
	if Bloodtalons.known and Regrowth:usable() and PredatorySwiftness:up() and Bloodtalons:down() then
		if ComboPoints() == 5 and (IncarnationKingOfTheJungle:down() or Rip:remains() < 8) then
			return Regrowth
		end
		if PredatorySwiftness:remains() < 1.5 and (EnergyTimeToMax() > Player.gcd or ComboPoints() >= 4) then
			return Regrowth
		end
	end
	if ComboPoints() == 5 then
		return self:finishers()
	end
	return self:generators()
end

APL[SPEC.FERAL].cooldowns = function(self)
--[[
actions.cooldowns=berserk,if=energy>=30&(cooldown.tigers_fury.remains>5|buff.tigers_fury.up)
actions.cooldowns+=/tigers_fury,if=energy.deficit>=60
actions.cooldowns+=/berserking
actions.cooldowns+=/feral_frenzy,if=combo_points=0
actions.cooldowns+=/incarnation,if=energy>=30&(cooldown.tigers_fury.remains>15|buff.tigers_fury.up)
actions.cooldowns+=/potion,name=battle_potion_of_agility,if=target.time_to_die<65|(time_to_die<180&(buff.berserk.up|buff.incarnation.up))
actions.cooldowns+=/shadowmeld,if=combo_points<5&energy>=action.rake.cost&dot.rake.pmultiplier<2.1&buff.tigers_fury.up&(buff.balancetalons.up|!talent.balancetalons.enabled)&(!talent.incarnation.enabled|cooldown.incarnation.remains>18)&!buff.incarnation.up
actions.cooldowns+=/use_items
]]
	if Berserk:usable() and Energy() >= 30 and (TigersFury:cooldown() > 5 or TigersFury:up()) then
		return UseCooldown(Berserk)
	end
	if TigersFury:usable() and EnergyDeficit() >= 60 then
		return UseCooldown(TigersFury)
	end
	if FeralFrenzy:usable() and ComboPoints() == 0 then
		return UseCooldown(FeralFrenzy)
	end
	if IncarnationKingOfTheJungle:usable() and Energy() >= 30 and (TigersFury:cooldown() > 15 or TigersFury:up()) then
		return UseCooldown(IncarnationKingOfTheJungle)
	end
	if Opt.pot and BattlePotionOfAgility:usable() and (Target.timeToDie < 65 or (Target.timeToDie < 180 and (Berserk:up() or IncarnationKingOfTheJungle:up()))) then
		return UseCooldown(BattlePotionOfAgility)
	end
	if Shadowmeld:usable() and ComboPoints() < 5 and Energy() >= Rake:energyCost() and Rake:multiplier() < 2.1 and TigersFury:up() and (not Bloodtalons.known or Bloodtalons:up()) and (not IncarnationKingOfTheJungle.known or (IncarnationKingOfTheJungle:down() and IncarnationKingOfTheJungle:cooldown() > 18)) then
		return UseCooldown(Shadowmeld)
	end
	if Opt.trinket then
		if Trinket1:usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:usable() then
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
actions.finishers+=/maim,if=buff.iron_jaws.up
actions.finishers+=/ferocious_bite,max_energy=1
]]
	if SavageRoar:usable(true) and SavageRoar:down() then
		return Pool(SavageRoar)
	end
	if Target.timeToDie > max(8, Rip:remains() + 4) and Rip:multiplier() < Player.rip_multiplier_max and Rip:nextMultiplier() >= Player.rip_multiplier_max then
		if Sabertooth.known and PrimalWrath:usable(true) then
			return Pool(PrimalWrath)
		elseif Rip:usable(true) then
			return Pool(Rip)
		end
	end
	if Sabertooth.known and FerociousBite:usable(true) and Rip:up() and between(Player.enemies, 2, 3) and Rip:lowestRemainsOthers() > (((Berserk:up() or IncarnationKingOfTheJungle:up()) and 5 or 8) * (Player.enemies - 1)) then
		return Pool(FerociousBite, Rip:remains() < 1 and 0 or 25)
	end
	if PrimalWrath:usable(true) and Player.enemies > 1 and (Player.enemies >= 5 or Rip:nextMultiplier() > (Rip:multiplierSum() / Player.enemies) or Rip:lowestRemainsOthers() < ((Berserk:up() or IncarnationKingOfTheJungle:up()) and 5 or 8)) then
		return Pool(PrimalWrath)
	end
	if Rip:down() or (Target.timeToDie > 8 and ((Rip:refreshable() and not Sabertooth.known) or (Rip:remains() <= Rip:duration() * 0.8 and Rip:nextMultiplier() > Rip:multiplier()))) then
		if Sabertooth.known and PrimalWrath:usable(true) then
			return Pool(PrimalWrath)
		elseif Rip:usable(true) then
			return Pool(Rip)
		end
	end
	if SavageRoar:usable(true) and SavageRoar:remains() < 12 then
		return Pool(SavageRoar)
	end
	if Maim:usable(true) and IronJaws:up() then
		return Pool(Maim)
	end
	if FerociousBite:usable(true) then
		return Pool(FerociousBite, 25)
	end
end

APL[SPEC.FERAL].generators = function(self)
--[[
actions.generators=regrowth,if=talent.balancetalons.enabled&buff.predatory_swiftness.up&buff.balancetalons.down&combo_points=4&dot.rake.remains<4
actions.generators+=/regrowth,if=talent.balancetalons.enabled&buff.balancetalons.down&buff.predatory_swiftness.up&talent.lunar_inspiration.enabled&dot.rake.remains<1
actions.generators+=/brutal_slash,if=spell_targets.brutal_slash>desired_targets
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(refreshable)&(spell_targets.thrash_cat>2)
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(talent.scent_of_balance.enabled&buff.scent_of_balance.down)&spell_targets.thrash_cat>3
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=buff.scent_of_balance.up
actions.generators+=/pool_resource,for_next=1
actions.generators+=/rake,target_if=!ticking|(!talent.balancetalons.enabled&remains<duration*0.3)&target.time_to_die>4
actions.generators+=/pool_resource,for_next=1
actions.generators+=/rake,target_if=talent.balancetalons.enabled&buff.balancetalons.up&((remains<=7)&persistent_multiplier>dot.rake.pmultiplier*0.85)&target.time_to_die>4
# With LI & BT, we can use moonfire to save BT charges, allowing us to better refresh rake
actions.generators+=/moonfire_cat,if=buff.balancetalons.up&buff.predatory_swiftness.down&combo_points<5
actions.generators+=/brutal_slash,if=(buff.tigers_fury.up&(raid_event.adds.in>(1+max_charges-charges_fractional)*recharge_time))
actions.generators+=/moonfire_cat,target_if=refreshable
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=refreshable&((variable.use_thrash=2&(!buff.incarnation.up|azerite.wild_fleshrending.enabled))|spell_targets.thrash_cat>1)
actions.generators+=/thrash_cat,if=refreshable&variable.use_thrash=1&buff.clearcasting.react&(!buff.incarnation.up|azerite.wild_fleshrending.enabled)
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.generators+=/shred,if=dot.rake.remains>(action.shred.cost+action.rake.cost-energy)%energy.regen|buff.clearcasting.react
]]
	if Sabertooth.known and Player.enemies == 1 and ComboPoints() >= 2 and Rip:down() and Rip:usable() and Rip:nextMultiplier() >= Player.rip_multiplier_max and (TigersFury:remains() < 1.5 or Bloodtalons:remains() < 1.5 or Bloodtalons:stack() == 1) then
		return Rip
	end
	if Bloodtalons.known and Regrowth:usable() and PredatorySwiftness:up() and Bloodtalons:down() then
		if ComboPoints() == 4 and Rake:remains() < 4 then
			return Regrowth
		end
		if LunarInspiration.known and Rake:remains() < 1 then
			return Regrowth
		end
	end
	if ThrashCat:usable(true) then
		if ThrashCat:refreshable() and Player.enemies > 2 then
			return Pool(ThrashCat)
		end
		if ScentOfBlood.known and ScentOfBlood:down() and Player.enemies > 3 then
			return Pool(ThrashCat)
		end
	end
	if BrutalSlash:usable() and Player.enemies > 2 and (Energy() < 50 or ComboPoints() < 4) then
		return BrutalSlash
	end
	if ScentOfBlood.known and SwipeCat:usable(true) and ScentOfBlood:up() then
		return Pool(SwipeCat)
	end
	if Player.enemies < 6 or not PrimalWrath.known then
		if Rake:usable(true) then
			if Rake:down() then
				return Pool(Rake)
			end
			if Target.timeToDie > 4 then
				if not Bloodtalons.known and Rake:refreshable() then
					return Pool(Rake)
				end
				if Bloodtalons.known and Bloodtalons:up() and Rake:remains() < 7 and Rake:nextMultiplier() > (Rake:multiplier() * 0.85) then
					return Pool(Rake)
				end
			end
		end
		if LunarInspiration.known and MoonfireCat:usable() then
			if Bloodtalons:up() and PredatorySwiftness:down() and ComboPoints() < 5 then
				return MoonfireCat
			end
			if MoonfireCat:refreshable() then
				return MoonfireCat
			end
		end
	end
	if BrutalSlash:usable() and EnergyTimeToMax() > 1.5 and (TigersFury:up() or BrutalSlash:chargesFractional() > 2.5) then
		return BrutalSlash
	end
	if ThrashCat:usable(true) and ThrashCat:refreshable() and (Player.enemies > 1 or Target.timeToDie > (ThrashCat:remains() + 4)) then
		if IncarnationKingOfTheJungle:down() or WildFleshrending.known or Player.enemies > 1 then
			return Pool(ThrashCat)
		end
		if Clearcasting:up() and (IncarnationKingOfTheJungle:down() or WildFleshrending.known) then
			return ThrashCat
		end
	end
	if SwipeCat:usable(true) and Player.enemies > 1 then
		return Pool(SwipeCat)
	end
	if Shred:usable() and (Clearcasting:up() or Rake:remains() > ((Shred:energyCost() + Rake:energyCost() - Energy()) / EnergyRegen())) then
		return Shred
	end
end

APL[SPEC.FERAL].opener = function(self)
--[[
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
	if ComboPoints() == 5 then
		Player.opener_done = true
		return self:main()
	end
	if TigersFury:usable() then
		UseCooldown(TigersFury)
	end
	if Rake:usable() and (Rake:down() or Prowl:up()) then
		return Rake
	end
	if Rip:up() or Player.enemies > 1 then
		Player.opener_done = true
		return self:main()
	end
	if LunarInspiration.known and MoonfireCat:down() then
		return MoonfireCat
	end
	if ComboPoints() >= ((Berserk:remains() > 6 or TigersFury:ready()) and 3 or 5) and PrimalWrath:usable() then
		return PrimalWrath
	end
	if Rip:usable() then
		return Rip
	end
end

APL[SPEC.GUARDIAN].main = function(self)
--[[
actions=auto_attack
actions+=/call_action_list,name=cooldowns
actions+=/maul,if=rage.deficit<10&active_enemies<4
actions+=/ironfur,if=cost=0|(rage>cost&azerite.layered_mane.enabled&active_enemies>2)
actions+=/pulverize,target_if=dot.thrash_bear.stack=dot.thrash_bear.max_stacks
actions+=/moonfire,target_if=dot.moonfire.refreshable&active_enemies<2
actions+=/incarnation
actions+=/thrash,if=(buff.incarnation.down&active_enemies>1)|(buff.incarnation.up&active_enemies>4)
actions+=/swipe,if=buff.incarnation.down&active_enemies>4
actions+=/mangle,if=dot.thrash_bear.ticking
actions+=/moonfire,target_if=buff.galactic_guardian.up&active_enemies<2
actions+=/thrash
actions+=/maul
# Fill with Moonfire with PotMx2
actions+=/moonfire,if=azerite.power_of_the_moon.rank>1&active_enemies=1
actions+=/swipe
]]
	if BearForm:down() then
		return BearForm
	end
	self:cooldowns()
	if Maul:usable() and RageDeficit() < 10 and Player.enemies < 4 then
		return Maul
	end
	if Ironfur:usable() and (Ironfur:rageCost() == 0 or (Rage() > Ironfur:rageCost() and LayeredMane.known and Player.enemies > 2)) then
		UseExtra(Ironfur)
	end
	if Pulverize:usable() and Thrash:stack() == 3 then
		return Pulverize
	end
	if MoonfireBear:usable() and MoonfireBear:refreshable() and Player.enemies < 2 then
		return MoonfireBear
	end
	if IncarnationGuardianOfUrsoc:usable() then
		UseCooldown(IncarnationGuardianOfUrsoc)
	end
	if Thrash:usable() and ((Player.enemies > 1 and (not IncarnationGuardianOfUrsoc.known or IncarnationGuardianOfUrsoc:down())) or (Player.enemies > 4 and IncarnationGuardianOfUrsoc.known and IncarnationGuardianOfUrsoc:up())) then
		return Thrash
	end
	if Swipe:usable() and Player.enemies > 4 and (not IncarnationGuardianOfUrsoc.known or IncarnationGuardianOfUrsoc:down()) then
		return Swipe
	end
	if Mangle:usable() and Thrash:up() then
		return Mangle
	end
	if GalacticGuardian.known and MoonfireBear:usable() and Player.enemies < 2 and GalacticGuardian:up() then
		return MoonfireBear
	end
	if Thrash:usable() then
		return Thrash
	end
	if Maul:usable() and (RageDeficit() < 30 or (GuardiansWrath.known and GuardiansWrath:stack() < 3)) then
		return Maul
	end
	if MoonfireBear:usable() and Player.enemies == 1 and PowerOfTheMoon:azeriteRank() > 1 then
		return MoonfireBear
	end
	if Swipe:usable() then
		return Swipe
	end
end

APL[SPEC.GUARDIAN].cooldowns = function(self)
--[[
actions.cooldowns=potion
actions.cooldowns+=/balance_fury
actions.cooldowns+=/berserking
actions.cooldowns+=/arcane_torrent
actions.cooldowns+=/lights_judgment
actions.cooldowns+=/firebalance
actions.cooldowns+=/ancestral_call
actions.cooldowns+=/barkskin,if=buff.bear_form.up
actions.cooldowns+=/lunar_beam,if=buff.bear_form.up
actions.cooldowns+=/bristling_fur,if=buff.bear_form.up
actions.cooldowns+=/use_items
]]
	if BearForm:down() then
		return
	end
	if FrenziedRegeneration:usable() and HealthPct() <= Opt.frenzied_threshold then
		UseExtra(FrenziedRegeneration)
	end
	if Barkskin:usable() then
		return UseCooldown(Barkskin)
	end
	if LunarBeam:usable() then
		return UseCooldown(LunarBeam)
	end
	if BristlingFur:usable() then
		return UseCooldown(BristlingFur)
	end
end

APL[SPEC.RESTORATION].main = function(self)

end

APL.Interrupt = function(self)
	if SkullBash:usable() then
		return SkullBash
	end
	if Maim:usable() then
		return Maim
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		Player.interrupt = nil
		clawInterruptPanel:Hide()
		return
	end
	Player.interrupt = APL.Interrupt()
	if Player.interrupt then
		clawInterruptPanel.icon:SetTexture(Player.interrupt.icon)
	end
	clawInterruptPanel.icon:SetShown(Player.interrupt)
	clawInterruptPanel.border:SetShown(Player.interrupt)
	clawInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
	clawInterruptPanel:Show()
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.BALANCE and Opt.hide.balance) or
		   (Player.spec == SPEC.FERAL and Opt.hide.feral) or
		   (Player.spec == SPEC.GUARDIAN and Opt.hide.guardian) or
		   (Player.spec == SPEC.RESTORATION and Opt.hide.restoration))
end

local function Disappear()
	clawPanel:Hide()
	clawPanel.icon:Hide()
	clawPanel.border:Hide()
	clawCooldownPanel:Hide()
	clawInterruptPanel:Hide()
	clawExtraPanel:Hide()
	Player.main, Player.last_main = nil
	Player.cd, Player.last_cd = nil
	Player.interrupt = nil
	Player.extra, Player.last_extra = nil
	UpdateGlows()
end

local function Equipped(itemID, slot)
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

local function UpdateDraggable()
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

local function SnapAllPanels()
	clawPreviousPanel:ClearAllPoints()
	clawPreviousPanel:SetPoint('BOTTOMRIGHT', clawPanel, 'BOTTOMLEFT', -10, -5)
	clawCooldownPanel:ClearAllPoints()
	clawCooldownPanel:SetPoint('BOTTOMLEFT', clawPanel, 'BOTTOMRIGHT', 10, -5)
	clawInterruptPanel:ClearAllPoints()
	clawInterruptPanel:SetPoint('TOPLEFT', clawPanel, 'TOPRIGHT', 16, 25)
	clawExtraPanel:ClearAllPoints()
	clawExtraPanel:SetPoint('TOPRIGHT', clawPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.BALANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.FERAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.GUARDIAN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
	},
	['kui'] = {
		[SPEC.BALANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.FERAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.GUARDIAN] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.RESTORATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		clawPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		clawPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][Player.spec][Opt.snap]
		clawPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	clawPanel:SetAlpha(Opt.alpha)
	clawPreviousPanel:SetAlpha(Opt.alpha)
	clawCooldownPanel:SetAlpha(Opt.alpha)
	clawInterruptPanel:SetAlpha(Opt.alpha)
	clawExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	local text_center, dim = false, false
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			clawPanel.text.center:SetText(format('POOL %d', deficit))
			text_center = true
			dim = Opt.dimmer
		end
	end
	clawPanel.dimmer:SetShown(dim)
	clawPanel.text.center:SetShown(text_center)
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.last_main = Player.main
	Player.last_cd = Player.cd
	Player.last_extra = Player.extra
	Player.main =  nil
	Player.cd = nil
	Player.extra = nil
	Player.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
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
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:manaCost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main ~= Player.last_main then
		if Player.main then
			clawPanel.icon:SetTexture(Player.main.icon)
		end
		clawPanel.icon:SetShown(Player.main)
		clawPanel.border:SetShown(Player.main)
	end
	if Player.cd ~= Player.last_cd then
		if Player.cd then
			clawCooldownPanel.icon:SetTexture(Player.cd.icon)
		end
		clawCooldownPanel:SetShown(Player.cd)
	end
	if Player.extra ~= Player.last_extra then
		if Player.extra then
			clawExtraPanel.icon:SetTexture(Player.extra.icon)
		end
		clawExtraPanel:SetShown(Player.extra)
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
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
	if srcName == 'player' and powerType == 'COMBO_POINTS' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
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
		Rip.next_multiplier = Rip:nextMultiplier()
	elseif ability == Rake then
		Rake.next_multiplier = Rake:nextMultiplier()
	elseif ability == ThrashCat then
		ThrashCat.next_multiplier = ThrashCat:nextMultiplier()
	end
end

function events:ADDON_LOADED(name)
	if name == 'Claw' then
		Opt = Claw
		if not Opt.frequency then
			print('It looks like this is your first time running Claw, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Claw1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Claw is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		clawPanel:SetScale(Opt.scale.main)
		clawPreviousPanel:SetScale(Opt.scale.previous)
		clawCooldownPanel:SetScale(Opt.scale.cooldown)
		clawInterruptPanel:SetScale(Opt.scale.interrupt)
		clawExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid then
			autoAoe:add(srcGUID, true)
		elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and clawPanel:IsVisible() then
				clawPreviousPanel.ability = ability
				clawPreviousPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
				clawPreviousPanel.icon:SetTexture(ability.icon)
				clawPreviousPanel:Show()
			end
		end
		return
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:refreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:removeAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:recordTargetHit(dstGUID)
		end
		if ability == Shred then
			SetTargetMode(1)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if eventType == 'SPELL_DAMAGE' and Sabertooth.known and ability == FerociousBite and Rip.aura_targets[dstGUID] then
			Rip:refreshAura(dstGUID)
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and clawPanel:IsVisible() and ability == clawPreviousPanel.ability then
			clawPreviousPanel.border:SetTexture('Interface\\AddOns\\Claw\\misseffect.blp')
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.player = false
		Target.hostile = true
		Target.stunnable = false
		Target.healthMax = 0
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			clawPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			clawPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.boss = false
	Target.stunnable = true
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.player = UnitIsPlayer('target')
	if not Target.player then
		if Target.level == -1 or (Player.instance == 'party' and Target.level >= UnitLevel('player') + 2) then
			Target.boss = true
			Target.stunnable = false
		elseif Player.instance == 'raid' or (Target.healthMax > Player.health_max * 10) then
			Target.stunnable = false
		end
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		clawPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
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
		autoAoe:clear()
		autoAoe:update()
	end
	Player.opener_done = nil
end

local function UpdateAbilityData()
	Player.mana_max = UnitPowerMax('player', 0)
	Player.energy_max = UnitPowerMax('player', 3)
	Player.rage_max = UnitPowerMax('player', 1)
	Player.combo_points_max = UnitPowerMax('player', 4)
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	WildChargeCat.known = WildCharge.known
	if Player.spec == SPEC.FERAL then
		SwipeCat.known = not BrutalSlash.known
		ThrashCat.known = true
		Player.rip_multiplier_max = Rip:multiplierMax()
	end
	if Player.spec == SPEC.GUARDIAN then
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
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	Trinket1.itemId = GetInventoryItemID('player', 13)
	Trinket2.itemId = GetInventoryItemID('player', 14)
	local _, i, equipType, hasCooldown
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	clawPreviousPanel.ability = nil
	SetTargetMode(1)
	UpdateTargetInfo()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:UPDATE_SHAPESHIFT_FORM()
	events:PLAYER_REGEN_ENABLED()
end

function events:PLAYER_PVP_TALENT_UPDATE()
	UpdateAbilityData()
end

function events:PLAYER_ENTERING_WORLD()
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

clawPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

clawPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

clawPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	clawPanel:RegisterEvent(event)
end

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
	print('Claw -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Claw(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
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
			OnResourceFrameShow()
		end
		return Status('Snap to Blizzard combat resources frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				clawPreviousPanel:SetScale(Opt.scale.previous)
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				clawPanel:SetScale(Opt.scale.main)
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				clawCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				clawInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				clawExtraPanel:SetScale(Opt.scale.extra)
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
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
				UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Show the Claw UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Claw for cooldown management', Opt.cooldown)
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
		return Status('Dim main ability icon when you don\'t have enough mana to use it', Opt.dimmer)
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
			Claw_SetTargetMode(1)
			UpdateDraggable()
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
			if startsWith(msg[2], 'ba') then
				Opt.hide.balance = not Opt.hide.balance
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Balance specialization', not Opt.hide.balance)
			end
			if startsWith(msg[2], 'fe') then
				Opt.hide.feral = not Opt.hide.feral
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Feral specialization', not Opt.hide.feral)
			end
			if startsWith(msg[2], 'gu') then
				Opt.hide.guardian = not Opt.hide.guardian
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Guardian specialization', not Opt.hide.guardian)
			end
			if startsWith(msg[2], 're') then
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
		SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Claw (version: |cFFFFD000' .. GetAddOnMetadata('Claw', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Claw UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Claw UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Claw UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Claw UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Claw UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Claw for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000balance|r/|cFFFFD000feral|r/|cFFFFD000guardian|r/|cFFFFD000restoration|r - toggle disabling Claw for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'frenzied |cFFFFD000[health]|r  - health threshold to recommend Frenzied Regeneration at in Bear Form (default is 60%)',
		'|cFFFFD000reset|r - reset the location of the Claw UI to default',
	} do
		print('  ' .. SLASH_Claw1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end
