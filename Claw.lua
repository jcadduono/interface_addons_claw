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

local currentSpec, currentForm, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {

}

-- Azerite trait API access
local Azerite = {}

local var = {
	gcd = 1.5,
	time_diff = 0,
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
clawPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
clawPanel.border:Hide()
clawPanel.text = clawPanel:CreateFontString(nil, 'OVERLAY')
clawPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.text:SetTextColor(1, 1, 1, 1)
clawPanel.text:SetAllPoints(clawPanel)
clawPanel.text:SetJustifyH('CENTER')
clawPanel.text:SetJustifyV('CENTER')
clawPanel.swipe = CreateFrame('Cooldown', nil, clawPanel, 'CooldownFrameTemplate')
clawPanel.swipe:SetAllPoints(clawPanel)
clawPanel.dimmer = clawPanel:CreateTexture(nil, 'BORDER')
clawPanel.dimmer:SetAllPoints(clawPanel)
clawPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
clawPanel.dimmer:Hide()
clawPanel.targets = clawPanel:CreateFontString(nil, 'OVERLAY')
clawPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
clawPanel.targets:SetPoint('BOTTOMRIGHT', clawPanel, 'BOTTOMRIGHT', -1.5, 3)
clawPanel.button = CreateFrame('Button', 'clawPanelButton', clawPanel)
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
	targetMode = min(mode, #targetModes[currentSpec])
	var.enemy_count = targetModes[currentSpec][targetMode][1]
	clawPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end
Claw_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end
Claw_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end
Claw_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {}
}

function autoAoe:add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = var.time
	if update and new then
		self:update()
	end
end

function autoAoe:remove(guid)
	self.blacklist[guid] = var.time
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear(guid)
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
	var.enemy_count = count
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			SetTargetMode(i)
			var.enemy_count = count
			return
		end
	end
end

function autoAoe:purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if var.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	for guid, t in next, self.blacklist do
		if var.time - t > 2 then
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
		if self:manaCost() > var.mana then
			return false
		end
		if self:energyCost() > var.energy then
			return false
		end
		if self:rageCost() > var.rage then
			return false
		end
	end
	if self:cpCost() > var.combo_points then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() then
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
			return max(expires - var.time - var.execute_remains, 0)
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
	if self:traveling() or self:casting() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if self:match(id) then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
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
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - (var.time - var.time_diff) > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:manaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_max) or 0
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
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe()
	self.auto_aoe = true
	self.first_hit_time = nil
	self.targets_hit = {}
end

function Ability:recordTargetHit(guid)
	self.targets_hit[guid] = var.time
	if not self.first_hit_time then
		self.first_hit_time = self.targets_hit[guid]
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and var.time - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		autoAoe:clear()
		local guid
		for guid in next, self.targets_hit do
			autoAoe:add(guid)
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local now = var.time - var.time_diff
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= now then
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

function Ability:applyAura(timeStamp, guid)
	local aura = {
		expires = timeStamp + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(timeStamp, guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	local duration = self:duration()
	aura.expires = timeStamp + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Druid Abilities
---- Multiple Specializations
local CatForm = Ability.add(768, true, true)
local SkullBash = Ability.add(106839, false, true)
SkullBash.cooldown_duration = 15
SkullBash.triggers_gcd = false
local Prowl = Ability.add(5215, true, true)
Prowl.cooldown_duration = 6
local Regrowth = Ability.add(8936, true, true)
Regrowth.buff_duration = 12
Regrowth.mana_cost = 14
Regrowth.tick_interval = 2
Regrowth.hasted_ticks = true
local Moonfire = Ability.add(8921, false, true, 164812)
Moonfire.buff_duration = 18
Moonfire.energy_cost = 30
Moonfire.tick_interval = 2
Moonfire.hasted_ticks = true
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
local Thrash = Ability.add(106830, false, true)
Thrash.buff_duration = 15
Thrash.energy_cost = 40
Thrash.tick_interval = 3
Thrash.hasted_ticks = true
Thrash:autoAoe()
Thrash:trackAuras()
local Swipe = Ability.add(106785, false, true)
Swipe.energy_cost = 35
Swipe:autoAoe()
local TigersFury = Ability.add(5217, true, true)
TigersFury.cooldown_duration = 30
TigersFury.triggers_gcd = false
local Maim = Ability.add(22570, false, true, 203123)
Maim.cooldown_duration = 20
Maim.energy_cost = 30
Maim.cp_cost = 1
------ Talents
local Bloodtalons = Ability.add(155672, true, true, 145152)
Bloodtalons.buff_duration = 30
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
PrimalWrath:autoAoe()
------ Procs
local Clearcasting = Ability.add(16864, true, true, 135700)
Clearcasting.buff_duration = 15
local PredatorySwiftness = Ability.add(16974, true, true, 69369)
PredatorySwiftness.buff_duration = 12
---- Guardian

------ Talents

------ Procs

---- Restoration

------ Talents

------ Procs

-- Azerite Traits
local IronJaws = Ability.add(276021, true, true)
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
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
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

local function Mana()
	return var.mana
end

local function Energy()
	return var.energy
end

local function EnergyRegen()
	return var.energy_regen
end

local function EnergyDeficit()
	return var.energy_max - var.energy
end

local function EnergyTimeToMax()
	local deficit = var.energy_max - var.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / var.energy_regen
end

local function ComboPoints()
	return var.combo_points
end

local function Rage()
	return var.rage
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return var.enemy_count
end

local function TimeInCombat()
	if combatStartTime > 0 then
		return var.time - combatStartTime
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Druid Pet - Core Hound)
			id == 160452 or -- Netherwinds (Druid Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Druid Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function TargetIsStunnable()
	if UnitIsPlayer('target') then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 25 then
		return false
	end
	return true
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function Ability:energyCost()
	local cost  = self.energy_cost
	if currentSpec == SPEC.FERAL then
		if (self == Shred or self == Thrash or self == Swipe) and Clearcasting:up() then
			return 0
		end
		if Berserk:up() then
			cost = cost - (cost * 0.40)
		end
	end
	return cost
end

function Regrowth:manaCost()
	if PredatorySwiftness:up() then
		return 0
	end
	return Ability.manaCost(self)
end

function Rake:applyAura(timeStamp, guid)
	local aura = {
		expires = timeStamp + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Rake:refreshAura(timeStamp, guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	aura.expires = timeStamp + min(1.3 * self.buff_duration, remains + self.buff_duration)
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

function Rip:applyAura(timeStamp, guid)
	local duration
	if self.next_applied_by == Rip then
		duration = 4 + (4 * self.next_combo_points)
	elseif self.next_applied_by == PrimalWrath then
		duration = 2 + (2 * self.next_combo_points)
	elseif self.next_applied_by == FerociousBite then
		return
	end
	local aura = {
		expires = timeStamp + duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Rip:refreshAura(timeStamp, guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
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
		max_duration = 1.3 * (4 + (4 * var.combo_points_max))
	end
	aura.expires = timeStamp + min(max_duration, remains + duration)
end

-- this will return the lowest remaining duration Rip on an enemy that isn't main target
function Rip:lowestRemainsOthers()
	local guid, aura, lowest
	for guid, aura in next, self.aura_targets do
		if guid ~= Target.guid and (not lowest or aura.expires < lowest) then
			lowest = aura.expires
		end
	end
	if lowest then
		return lowest - (var.time - var.time_diff)
	end
	return 0
end

function Rip:multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Rip:multiplierSum()
	local sum, aura, _ = 0
	for _, aura in next, self.aura_targets do
		sum = sum + (aura.multiplier or 0)
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

function Thrash:applyAura(timeStamp, guid)
	local aura = {
		expires = timeStamp + self.buff_duration,
		multiplier = self.next_multiplier
	}
	self.aura_targets[guid] = aura
end

function Thrash:refreshAura(timeStamp, guid)
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	aura.expires = timeStamp + min(1.3 * self.buff_duration, remains + self.buff_duration)
	aura.multiplier = self.next_multiplier
end

function Thrash:multiplier()
	local aura = self.aura_targets[Target.guid]
	return aura and aura.multiplier or 0
end

function Thrash:nextMultiplier()
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

-- End Ability Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
	end
end

local function Pool(ability, extra)
	var.pool_energy = ability:energyCost() + (extra or 0)
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
actions.precombat+=/regrowth,if=talent.bloodtalons.enabled
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
actions+=/regrowth,if=combo_points=5&buff.predatory_swiftness.up&talent.bloodtalons.enabled&buff.bloodtalons.down&(!buff.incarnation.up|dot.rip.remains<8)
actions+=/run_action_list,name=finishers,if=combo_points>4
actions+=/run_action_list,name=generators
]]
	if not var.opener_done then
		return self:opener()
	end
	if CatForm:down() then
		return CatForm
	end
	if Prowl:up() or Shadowmeld:up() then
		return Rake
	end
	self:cooldowns()
	if Sabertooth.known and FerociousBite:usable(true) and Rip:up() and Rip:remains() < 3 and Target.timeToDie > 10 and (Enemies() < 3 or Rip:lowestRemainsOthers() > 8) then
		return Pool(FerociousBite, Rip:remains() < 1 and 0 or 25)
	end
	if Bloodtalons.known and Regrowth:usable() and PredatorySwiftness:up() and Bloodtalons:down() then
		if ComboPoints() == 5 and (IncarnationKingOfTheJungle:down() or Rip:remains() < 8) then
			return Regrowth
		end
		if PredatorySwiftness:remains() < 1.5 and (EnergyTimeToMax() > GCD() or ComboPoints() >= 4) then
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
actions.cooldowns+=/shadowmeld,if=combo_points<5&energy>=action.rake.cost&dot.rake.pmultiplier<2.1&buff.tigers_fury.up&(buff.bloodtalons.up|!talent.bloodtalons.enabled)&(!talent.incarnation.enabled|cooldown.incarnation.remains>18)&!buff.incarnation.up
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
	if Target.timeToDie > max(8, Rip:remains() + 4) and Rip:multiplier() < var.rip_multiplier_max and Rip:nextMultiplier() >= var.rip_multiplier_max then
		if Sabertooth.known and PrimalWrath:usable(true) then
			return Pool(PrimalWrath)
		elseif Rip:usable(true) then
			return Pool(Rip)
		end
	end
	if Sabertooth.known and FerociousBite:usable(true) and Rip:up() and between(Enemies(), 2, 3) and Rip:lowestRemainsOthers() > (((Berserk:up() or IncarnationKingOfTheJungle:up()) and 5 or 8) * (Enemies() - 1)) then
		return Pool(FerociousBite, Rip:remains() < 1 and 0 or 25)
	end
	if PrimalWrath:usable(true) and Enemies() > 1 and (Enemies() >= 5 or Rip:nextMultiplier() > (Rip:multiplierSum() / Enemies()) or Rip:lowestRemainsOthers() < ((Berserk:up() or IncarnationKingOfTheJungle:up()) and 5 or 8)) then
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
actions.generators=regrowth,if=talent.bloodtalons.enabled&buff.predatory_swiftness.up&buff.bloodtalons.down&combo_points=4&dot.rake.remains<4
actions.generators+=/regrowth,if=talent.bloodtalons.enabled&buff.bloodtalons.down&buff.predatory_swiftness.up&talent.lunar_inspiration.enabled&dot.rake.remains<1
actions.generators+=/brutal_slash,if=spell_targets.brutal_slash>desired_targets
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(refreshable)&(spell_targets.thrash_cat>2)
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=(talent.scent_of_blood.enabled&buff.scent_of_blood.down)&spell_targets.thrash_cat>3
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=buff.scent_of_blood.up
actions.generators+=/pool_resource,for_next=1
actions.generators+=/rake,target_if=!ticking|(!talent.bloodtalons.enabled&remains<duration*0.3)&target.time_to_die>4
actions.generators+=/pool_resource,for_next=1
actions.generators+=/rake,target_if=talent.bloodtalons.enabled&buff.bloodtalons.up&((remains<=7)&persistent_multiplier>dot.rake.pmultiplier*0.85)&target.time_to_die>4
# With LI & BT, we can use moonfire to save BT charges, allowing us to better refresh rake
actions.generators+=/moonfire_cat,if=buff.bloodtalons.up&buff.predatory_swiftness.down&combo_points<5
actions.generators+=/brutal_slash,if=(buff.tigers_fury.up&(raid_event.adds.in>(1+max_charges-charges_fractional)*recharge_time))
actions.generators+=/moonfire_cat,target_if=refreshable
actions.generators+=/pool_resource,for_next=1
actions.generators+=/thrash_cat,if=refreshable&((variable.use_thrash=2&(!buff.incarnation.up|azerite.wild_fleshrending.enabled))|spell_targets.thrash_cat>1)
actions.generators+=/thrash_cat,if=refreshable&variable.use_thrash=1&buff.clearcasting.react&(!buff.incarnation.up|azerite.wild_fleshrending.enabled)
actions.generators+=/pool_resource,for_next=1
actions.generators+=/swipe_cat,if=spell_targets.swipe_cat>1
actions.generators+=/shred,if=dot.rake.remains>(action.shred.cost+action.rake.cost-energy)%energy.regen|buff.clearcasting.react
]]
	if Bloodtalons.known and Regrowth:usable() and PredatorySwiftness:up() and Bloodtalons:down() then
		if ComboPoints() == 4 and Rake:remains() < 4 then
			return Regrowth
		end
		if LunarInspiration.known and Rake:remains() < 1 then
			return Regrowth
		end
	end
	if Thrash:usable(true) then
		if Thrash:refreshable() and Enemies() > 2 then
			return Pool(Thrash)
		end
		if ScentOfBlood.known and ScentOfBlood:down() and Enemies() > 3 then
			return Pool(Thrash)
		end
	end
	if ScentOfBlood.known and Swipe:usable(true) and ScentOfBlood:up() then
		return Pool(Swipe)
	end
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
	if LunarInspiration.known and Moonfire:usable() then
		if Bloodtalons:up() and PredatorySwiftness:down() and ComboPoints() < 5 then
			return Moonfire
		end
		if Moonfire:refreshable() then
			return Moonfire
		end
	end
	if Thrash:usable(true) and Thrash:refreshable() and (Enemies() > 1 or Target.timeToDie > (Thrash:remains() + 4)) then
		if IncarnationKingOfTheJungle:down() or WildFleshrending.known or Enemies() > 1 then
			return Pool(Thrash)
		end
		if Clearcasting:up() and (IncarnationKingOfTheJungle:down() or WildFleshrending.known) then
			return Thrash
		end
	end
	if Swipe:usable(true) and Enemies() > 1 then
		return Pool(Swipe)
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
		var.opener_done = true
		return self:main()
	end
	if TigersFury:usable() then
		UseCooldown(TigersFury)
	end
	if Rake:usable() and (Rake:down() or Prowl:up()) then
		return Rake
	end
	if Rip:up() or Enemies() > 1 then
		var.opener_done = true
		return self:main()
	end
	if LunarInspiration.known and Moonfire:down() then
		return Moonfire
	end
	if ComboPoints() >= ((Berserk:remains() > 6 or TigersFury:ready()) and 3 or 5) and PrimalWrath:usable() then
		return PrimalWrath
	end
	if Rip:usable() then
		return Rip
	end
end

APL[SPEC.GUARDIAN].main = function(self)

end

APL[SPEC.RESTORATION].main = function(self)

end

APL.Interrupt = function(self)
	if SkullBash:usable() then
		return SkullBash
	end
	if Maim:usable() and TargetIsStunnable() then
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
		var.interrupt = nil
		clawInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		clawInterruptPanel.icon:SetTexture(var.interrupt.icon)
		clawInterruptPanel.icon:Show()
		clawInterruptPanel.border:Show()
	else
		clawInterruptPanel.icon:Hide()
		clawInterruptPanel.border:Hide()
	end
	clawInterruptPanel:Show()
	clawInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
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
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.BALANCE and Opt.hide.balance) or
		   (currentSpec == SPEC.FERAL and Opt.hide.feral) or
		   (currentSpec == SPEC.GUARDIAN and Opt.hide.guardian) or
		   (currentSpec == SPEC.RESTORATION and Opt.hide.restoration))
end

local function Disappear()
	clawPanel:Hide()
	clawPanel.icon:Hide()
	clawPanel.border:Hide()
	clawPanel.text:Hide()
	clawCooldownPanel:Hide()
	clawInterruptPanel:Hide()
	clawExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	clawPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		clawPanel.button:Show()
	else
		clawPanel.button:Hide()
	end
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
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
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
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 10
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	if Opt.dimmer then
		if not var.main then
			clawPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			clawPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			clawPanel.dimmer:Hide()
		else
			clawPanel.dimmer:Show()
		end
	end
	if var.pool_energy then
		local deficit = var.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			clawPanel.text:SetText(format('POOL %d', deficit))
			clawPanel.text:Show()
		else
			clawPanel.text:Hide()
		end
	else
		clawPanel.text:Hide()
	end
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	var.time = GetTime()
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.ability_casting = abilities.bySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	if currentForm == FORM.CAT then
		var.gcd = 1
		var.energy_regen = GetPowerRegen()
		var.energy_max = UnitPowerMax('player', 3)
		var.energy = UnitPower('player', 3) + (var.energy_regen * var.execute_remains)
		var.energy = min(max(var.energy, 0), var.energy_max)
		var.combo_points = UnitPower('player', 4)
	else
		var.mana_regen = GetPowerRegen()
		var.gcd = 1.5 * var.haste_factor
	end
	if currentForm == FORM.BEAR then
		var.rage = UnitPower('player', 1)
	end
	var.mana = UnitPower('player', 0) + (var.mana_regen * var.execute_remains)
	if var.ability_casting then
		var.mana = var.mana - var.ability_casting:manaCost()
	end
	var.mana = min(max(var.mana, 0), var.mana_max)

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			clawPanel.icon:SetTexture(var.main.icon)
			clawPanel.icon:Show()
			clawPanel.border:Show()
		else
			clawPanel.icon:Hide()
			clawPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			clawCooldownPanel.icon:SetTexture(var.cd.icon)
			clawCooldownPanel:Show()
		else
			clawCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			clawExtraPanel.icon:SetTexture(var.extra.icon)
			clawExtraPanel:Show()
		else
			clawExtraPanel:Hide()
		end
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
			if start <= 0 then
				return clawPanel.swipe:Hide()
			end
		end
		clawPanel.swipe:SetCooldown(start, duration)
		clawPanel.swipe:Show()
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
	local castedAbility = abilities.bySpellId[spellId]
	if not castedAbility then
		return
	end
	if castedAbility == Rip or castedAbility == PrimalWrath or (Sabertooth.known and castedAbility == FerociousBite) then
		Rip.next_applied_by = castedAbility
		Rip.next_combo_points = UnitPower('player', 4)
		Rip.next_multiplier = Rip:nextMultiplier()
	elseif castedAbility == Rake then
		Rake.next_multiplier = Rake:nextMultiplier()
	elseif castedAbility == Thrash then
		Thrash.next_multiplier = Thrash:nextMultiplier()
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
	local timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()
	var.time = GetTime()
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == var.player then
			autoAoe:add(srcGUID, true)
		elseif srcGUID == var.player then
			autoAoe:add(dstGUID, true)
		end
	end
	if srcGUID ~= var.player or not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end
	local castedAbility = abilities.bySpellId[spellId]
	if not castedAbility then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	var.time_diff = var.time - timeStamp
	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = var.time
		end
		if Opt.previous and clawPanel:IsVisible() then
			clawPreviousPanel.ability = castedAbility
			clawPreviousPanel.border:SetTexture('Interface\\AddOns\\Claw\\border.blp')
			clawPreviousPanel.icon:SetTexture(castedAbility.icon)
			clawPreviousPanel:Show()
		end
		return
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			castedAbility:applyAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:refreshAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			castedAbility:removeAura(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if eventType == 'SPELL_DAMAGE' and Sabertooth.known and castedAbility == FerociousBite and Rip.aura_targets[dstGUID] then
			Rip:refreshAura(timeStamp, dstGUID)
		end
		if Opt.auto_aoe then
			if castedAbility.auto_aoe then
				castedAbility:recordTargetHit(dstGUID)
			end
			if castedAbility == Shred then
				SetTargetMode(1)
			end
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and clawPanel:IsVisible() and castedAbility == clawPreviousPanel.ability then
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
		Target.hostile = true
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
		if Opt.previous and combatStartTime == 0 then
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
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	if UnitIsPlayer('target') then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
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
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		clawPreviousPanel:Hide()
	end
	if currentSpec == SPEC.FERAL then
		var.opener_done = nil
	end
end

local function UpdateAbilityData()
	var.mana_max = UnitPowerMax('player', 0)
	var.energy_max = UnitPowerMax('player', 3)
	var.rage_max = UnitPowerMax('player', 1)
	var.combo_points_max = UnitPowerMax('player', 4)
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	WildChargeCat.known = WildCharge.known
	if currentSpec == SPEC.FERAL then
		Swipe.known = true
		Thrash.known = true
		var.rip_multiplier_max = Rip:multiplierMax()
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

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
end

function events:UPDATE_SHAPESHIFT_FORM()
	local form = GetShapeshiftFormID() or 0
	if form == 1 then
		currentForm = FORM.CAT
	elseif form == 5 then
		currentForm = FORM.BEAR
	elseif form == 31 or form == 35 then
		currentForm = FORM.MOONKIN
	elseif form == 3 or form == 4 or form == 27 or form == 29 then
		currentForm = FORM.TRAVEL
	else
		currentForm = FORM.NONE
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		currentSpec = GetSpecialization() or 0
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		clawPreviousPanel.ability = nil
		PreviousGCD = {}
		SetTargetMode(1)
		UpdateTargetInfo()
		events:PLAYER_REGEN_ENABLED()
		events:UPDATE_SHAPESHIFT_FORM()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
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

function SlashCmdList.Claw(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Claw - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
		return print('Claw - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				clawPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Claw - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				clawPanel:SetScale(Opt.scale.main)
			end
			return print('Claw - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				clawCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Claw - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				clawInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Claw - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				clawExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Claw - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Claw - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Claw - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Claw - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return print('Claw - Calculation frequency (max time to wait between each update): Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Claw - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Claw - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Claw - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Claw - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Claw - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Claw - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Claw - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Claw - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Claw - Show the Claw UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Claw - Use Claw for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				clawPanel.swipe:Hide()
			end
		end
		return print('Claw - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				clawPanel.dimmer:Hide()
			end
		end
		return print('Claw - Dim main ability icon when you don\'t have enough resources to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Claw - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Claw_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Claw - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Claw - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.balance = not Opt.hide.balance
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Claw - Balance specialization: |cFFFFD000' .. (Opt.hide.balance and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.feral = not Opt.hide.feral
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Claw - Feral specialization: |cFFFFD000' .. (Opt.hide.feral and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'g') then
				Opt.hide.guardian = not Opt.hide.guardian
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Claw - Guardian specialization: |cFFFFD000' .. (Opt.hide.guardian and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.guardian = not Opt.hide.guardian
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Claw - Restoration specialization: |cFFFFD000' .. (Opt.hide.restoration and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Claw - Possible hidespec options: |cFFFFD000balance|r/|cFFFFD000feral|r/|cFFFFD000guardian|r/|cFFFFD000restoration|r - toggle disabling Claw for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Claw - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Claw - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Claw - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Claw - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		clawPanel:ClearAllPoints()
		clawPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Claw - Position has been reset to default')
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
		'|cFFFFD000reset|r - reset the location of the Claw UI to default',
	} do
		print('  ' .. SLASH_Claw1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFFFF7D0AKilobyte|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
