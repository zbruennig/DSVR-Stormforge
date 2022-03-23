--[[--------------------------------------------------------------------
	DreadSprayVR.lua
	VR HUD for Dread Spray sequences in the Sha of Fear encounter
----------------------------------------------------------------------]]

--[[-Constants----------------------------------------------------------]]

-- Bowman NPCIDs
local BowmanID = { 61038,	-- Yang Guoshi
				   61042,	-- Cheng Kang
				   61046 }	-- Jinlun Kun

-- Sha of Fear NPCID
local ShaID	= 60999

-- Terrace instanceID
local TerraceID = 996

-- Bowman Locations
local BowmanLoc = { {x = .4654, y = .9069},		-- Yang Guoshi
					{x = .1136, y = .6092},		-- Cheng Kang
					{x = .3528, y = .0907} }	-- Jinlun Kun

-- Sequences
local BowmanSeq = { {6, 2, 2, 6, 7, 3, 3, 7, 8, 4, 4, 8, 1, 5, 5, 1},	-- Yang Guoshi
					{1, 6, 5, 4, 7, 4, 3, 2, 5, 2, 1, 8, 3, 8, 7, 6},	-- Cheng Kang
					{5, 4, 2, 1, 3, 2, 8, 7, 1, 8, 6, 5, 7, 6, 4, 3} }	-- Jinlun Kun

-- Colors
local Colors = { {r = 0, g = 0.9, b = 0},		-- green (safe)
				 {r = 0.9, g = 0, b = 0},		-- red (next 4 shots)
				 {r = 0.9, g = 0.45, b = 0},	-- orange (future shots 5 - 8)
				 {r = 0.9, g = 0.9, b = 0} }	-- yellow (future shots 9+)

-- pi
local m_pi4 = math.pi / 4
local m_3pi2 = 3 * math.pi / 2

-- spells
local Cackle = GetSpellInfo(129147)		-- ominous cackle debuff
local Fearless = GetSpellInfo(118977)	-- fearless buff
local Fading = GetSpellInfo(129378)		-- fading light buff

----------------------------------------------------------------------]]

-- saved variables
DreadSprayVRDB = { }

-- upvalues
local GetPlayerMapPosition = GetPlayerMapPosition
local SetMapToCurrentZone = SetMapToCurrentZone
local GetPlayerFacing = GetPlayerFacing
local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local UnitGUID = UnitGUID
local GetTime = GetTime
local m_atan2 = math.atan2
local sqrt = math.sqrt
local tonum = tonumber

-- locals
local DreadSprayVR
local i
local events = { }
local locked = true

-- states
local terrace = false
local sha = false
local ported = false
local onplatform = false

-- rotation
local cx		-- center point
local cy
local ex		-- entry point
local ey
local etheta	-- base offset angle

-- sequence
local playing = false
local Bowman = 1
local Shot = 1
local seq_time
local spray_time


--[[-Moving and Sizing--------------------------------------------------]]

local function onDragStart(self) self:StartMoving() end

local function onDragStop(self)
	self:StopMovingOrSizing()
	DreadSprayVRDB.x = self:GetLeft()
	DreadSprayVRDB.y = self:GetTop()
end

local function OnDragHandleMouseDown(self) self.frame:StartSizing("BOTTOMRIGHT") end

local function OnDragHandleMouseUp(self, button) self.frame:StopMovingOrSizing() end

local function onResize(self, width, height)
	-- keep the field a square
	DreadSprayVRDB.width = width
	DreadSprayVRDB.height = width
	
	-- size of other elements is relative to the size of the field
	local sectionsize = DreadSprayVRDB.width * 1.25
		
	for i = 1, 8 do
		DreadSprayVR.section[i]:SetSize(sectionsize, sectionsize)
	end

	local playersize = DreadSprayVRDB.width * 0.28
	DreadSprayVR.player:SetSize(playersize, playersize)

	local barheight = DreadSprayVRDB.width * .1
	DreadSprayVR.bar:SetSize(DreadSprayVRDB.width, barheight)
end


----------------------------------------------------------------------]]


--[[-Draw Sequence------------------------------------------------------
		Colors the field segements based on the current shot in a given
		sequence
----------------------------------------------------------------------]]
local function DrawSequence(bowman, shot)
	local j, c

	if bowman then
		for i = 1, 8 do
			c = 1
			for j = shot, 16 do
				if BowmanSeq[bowman][j] == i then
					if j - shot < 4 then c = 2
					elseif j - shot < 8 then c = 3
					else c = 4
					end
					break
				end
			end
			DreadSprayVR.section[i]:SetVertexColor(Colors[c].r, Colors[c].g, Colors[c].b, 0.9)
		end
	end
end


--[[-Rotate Field-------------------------------------------------------
		Rotates the sections display as the player moves around the bowman
		Requires a valid entry offset angle
----------------------------------------------------------------------]]
local function RotateField(self, elapsed)
	
	-- position and angle data
	SetMapToCurrentZone()
	local px, py = GetPlayerMapPosition("player")
	local dpx = px - cx
	local dpy = py - cy
	local dtheta = m_atan2(dpy, dpx)
	local rtheta = dtheta - etheta

	-- update frame
	local now = GetTime()
	local diff = now - spray_time
	
	if playing then		-- playing a sequence

		-- advance the sequence on timer
		if now - seq_time > 0.5 then
			seq_time = now
			Shot = Shot + 1
			if Shot > 16 then	-- sequence over, stop and reset
				Shot = 1
				playing = false
			end
			DrawSequence(Bowman, Shot)
		end

		-- update the warning bar
		DreadSprayVR.bar:SetValue(0)
		DreadSprayVR.text:SetText("Spraying!")
		DreadSprayVR.text:SetTextColor(1, 0.2, 0.2)
		
	else				-- not playing a sequence
		-- update warning bar
		if diff < 19 then
			DreadSprayVR.text:SetText("")
			DreadSprayVR.bar:SetValue(19 - diff)
		else
			DreadSprayVR.bar:SetValue(0)
			DreadSprayVR.text:SetText("Spray Soon!")
			DreadSprayVR.text:SetTextColor(1, 0.7, 0.2)
		end
	end

	-- update sections
	for i = 1, 8 do
		DreadSprayVR.section[i]:SetRotation(rtheta + (m_pi4 * (i - 1)))
	end

	-- update player marker
	local offset = sqrt(dpx * dpx + dpy * dpy) * -1667
	if offset < DreadSprayVRDB.height * -.4 then offset = DreadSprayVRDB.height * -.4 end
	local facing = GetPlayerFacing()
	DreadSprayVR.player:SetPoint("CENTER", 0, offset + 10)
	DreadSprayVR.player:SetRotation(facing + m_3pi2 + dtheta)
	
	-- dead on platform
	if not UnitExists("boss1") then
		if onplatform then
			DreadSprayVR:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			DreadSprayVR:UnregisterEvent("UNIT_AURA")
			sha = false
			ported = false
			onplatform = false
			playing = false
			Shot = 1
			DreadSprayVR:Hide()
		end
	end
end


--[[-Slash Command------------------------------------------------------]]

SLASH_DREADSPRAYVR1 = "/dsvr"
local function SlashHandler(msg, editbox)
	if locked then
		--DEBUG:
		print("DreadSprayVR: Frame Unlocked (lock before engaging!)")
		
		-- test data
		Bowman = 2
		Shot = 1
		DrawSequence(Bowman, 1)
		playing = true
		seq_time = GetTime()
		spray_time = GetTime()
		SetMapToCurrentZone()
		ex, ey = GetPlayerMapPosition("player")
		cx = ex + .01
		cy = ey + .01
		etheta = m_atan2(ey - cy, ex - cx)

		locked = false
		DreadSprayVR.drag:Show()
		DreadSprayVR:Show()
		DreadSprayVR:EnableMouse(true)
		DreadSprayVR:SetMovable(true)
		DreadSprayVR:SetResizable(true)
		DreadSprayVR:RegisterForDrag("LeftButton")
		DreadSprayVR:SetScript("OnSizeChanged", onResize)
		DreadSprayVR:SetScript("OnDragStart", onDragStart)
		DreadSprayVR:SetScript("OnDragStop", onDragStop)

	else
		--DEBUG:
		print("DreadSprayVR: Frame Locked")

		-- cleanup
		Shot = 1
		playing = false
		
		locked = true
		DreadSprayVR.drag:Hide()
		DreadSprayVR:SetMovable(false)
		DreadSprayVR:SetResizable(false)
		DreadSprayVR:EnableMouse(false)
		DreadSprayVR:RegisterForDrag()
		DreadSprayVR:SetScript("OnSizeChanged", nil)
		DreadSprayVR:SetScript("OnDragStart", nil)
		DreadSprayVR:SetScript("OnDragStop", nil)

		DreadSprayVR:SetWidth(DreadSprayVRDB.width)
		DreadSprayVR:SetHeight(DreadSprayVRDB.height)

		local sectionsize = DreadSprayVRDB.width * 1.25
		
		for i = 1, 8 do
			DreadSprayVR.section[i]:SetSize(sectionsize, sectionsize)
		end

		local playersize = DreadSprayVRDB.width * 0.28
		DreadSprayVR.player:SetSize(playersize, playersize)

		local barheight = DreadSprayVRDB.width * .1
		DreadSprayVR.bar:SetSize(DreadSprayVRDB.width, barheight)

		DreadSprayVR:Hide()
	end
end
SlashCmdList["DREADSPRAYVR"] = SlashHandler;

----------------------------------------------------------------------]]


--[[-Event Handlers-----------------------------------------------------]]

function events:ADDON_LOADED(...)
	if select(1, ...) == "DreadSprayVR" then
		DreadSprayVRDB.x = DreadSprayVRDB.x or 100
		DreadSprayVRDB.y = DreadSprayVRDB.y or 500
		DreadSprayVRDB.width = DreadSprayVRDB.width or 200
		DreadSprayVRDB.height = DreadSprayVRDB.height or 200
		DreadSprayVRDB.fixed = DreadSprayVRDB.fixed or false


		DreadSprayVR:SetWidth(DreadSprayVRDB.width)
		DreadSprayVR:SetHeight(DreadSprayVRDB.height)

		local sectionsize = DreadSprayVRDB.width * 1.25
		
		for i = 1, 8 do
			DreadSprayVR.section[i]:SetSize(sectionsize, sectionsize)
		end

		local playersize = DreadSprayVRDB.width * 0.28
		DreadSprayVR.player:SetSize(playersize, playersize)

		local barheight = DreadSprayVRDB.width * .1
		DreadSprayVR.bar:SetSize(DreadSprayVRDB.width, barheight)
		
		DreadSprayVR:ClearAllPoints()
		DreadSprayVR:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DreadSprayVRDB.x, DreadSprayVRDB.y)
		DreadSprayVR:SetScript("OnUpdate", RotateField)
		DreadSprayVR:Hide()
	end
end

function events:PLAYER_ENTERING_WORLD(...)
	local _, _, _, _, _, _, _, id = GetInstanceInfo()

	if id == TerraceID then
		-- start looking at boss engage
		DreadSprayVR:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		terrace = true
	elseif terrace then
		-- stop looking at boss engage
		DreadSprayVR:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		terrace = false

		-- if needed stop looking at other things too
		if sha then
			DreadSprayVR:UnregisterEvent("UNIT_AURA")
			sha = false
		end

		if onplatform then
			DreadSprayVR:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
			ported = false
			onplatform = false
			playing = false
			Shot = 1
			DreadSprayVR:Hide()
		end
	end
end

function events:INSTANCE_ENCOUNTER_ENGAGE_UNIT(...)
	if UnitExists("boss1") and not sha then
		local bossID = tonum(UnitGUID("boss1"):sub(6,10), 16)
		if bossID == ShaID then
			-- check if we're engaging sha in terrace or dread expanse
			-- uses the fact that dread expanse has no position data, pretty hackish
			SetMapToCurrentZone()
			local tx, ty = GetPlayerMapPosition("player")
			if tx > 0.1 then
				DreadSprayVR:RegisterUnitEvent("UNIT_AURA", "player")
				sha = true
			end
		end
	end
end

function events:UNIT_AURA(...)
	local cackle = UnitDebuff("player", Cackle)
	local fearless = UnitBuff("player", Fearless)
	local fading = UnitBuff("player", Fading)

	-- unit gained fading light, don't care about bowmen in p2
	if fading then

		-- unregister events
		DreadSprayVR:UnregisterEvent("UNIT_AURA")
		sha = false
				
		-- cleanup if in flight
		if ported then ported = false end
		
		-- cleanup if on platform
		if onplatform then
			DreadSprayVR:Hide()
			onplatform = false
			Shot = 1
			playing = false
			DreadSprayVR:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		end

		--DEBUG: keep this cause it amused people
		print("DreadSprayVR: Phase 2 Good Luck")

		return
	end

	-- unit gained fearless
	if fearless and onplatform then
		-- hide frame
		DreadSprayVR:Hide()
		
		-- unregister events
		DreadSprayVR:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

		-- reset sequence
		Shot = 1
		onplatform = false
		playing = false
	end

	-- unit gained cackle
	if cackle and not ported then
		ported = true

		-- start spray timer
		playing = false
		spray_time = GetTime()
		return
	end

	-- unit lost cackle
	if not cackle and ported then
		
		ported = false
		onplatform = true
		Shot = 1

		-- determine bowman
		SetMapToCurrentZone()
		ex, ey = GetPlayerMapPosition("player")
		if ey >= BowmanLoc[1].y then Bowman = 1
		elseif ex <= BowmanLoc[2].x then Bowman = 2
		elseif ey <= BowmanLoc[3].y then Bowman = 3
		end

		-- set up base point and offset angle
		cx = BowmanLoc[Bowman].x			-- center point
		cy = BowmanLoc[Bowman].y
		etheta = m_atan2(ey - cy, ex - cx)	-- base offset angle

		-- seed sequence into frame
		DrawSequence(Bowman, 1)
		
		-- show frame
		DreadSprayVR:Show()

		-- register events
		DreadSprayVR:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(...)
	local _, event, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _ = ...

	local sourceID = tonum(sourceGUID:sub(6, 10), 16)
	local destID = tonum(destGUID:sub(6, 10), 16)

	if sourceID == BowmanID[Bowman] then
		if event == "SPELL_CAST_SUCCESS" then
			local spellId, spellName = select(12, ...)

			-- Dread Spray Buff
			if spellId == 120047 then
				-- start the sequence
				seq_time = GetTime()
				spray_time = GetTime()
				playing = true
			end
		end
	elseif destID == BowmanID[Bowman] then
		-- Bowman died, reset the sequence
		if event == "UNIT_DIED" then
			Shot = 1
			DrawSequence(Bowman, 1)
			playing = false
		end
	end
end

----------------------------------------------------------------------]]


--[[-Frame Creation-----------------------------------------------------]]

-- Main Frame
DreadSprayVR = CreateFrame("Frame", "DreadSprayVRField", UIParent)
DreadSprayVR.section = { }
DreadSprayVR:SetWidth(200)
DreadSprayVR:SetHeight(200)
DreadSprayVR:SetMinResize(80, 80)
DreadSprayVR:SetClampedToScreen(true)
DreadSprayVR:EnableMouse(false)

-- Background
local bg = DreadSprayVR:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(DreadSprayVR)
bg:SetBlendMode("BLEND")
bg:SetTexture(0, 0, 0, 0.3)
DreadSprayVR.background = bg

-- Section Setup
local section
for i = 1, 8 do
	section = DreadSprayVR:CreateTexture(nil, "ARTWORK")
	section:SetPoint("CENTER", 0, 10)
	section:SetWidth(250)
	section:SetHeight(250)
	section:SetTexture([[Interface\AddOns\DreadSprayVR\section.tga]])
	section:SetBlendMode("ADD")
	section:SetRotation(m_pi4 * (i - 1))
	DreadSprayVR.section[i] = section
end

-- Player Marker
local player = DreadSprayVR:CreateTexture(nil, "OVERLAY")
player:SetSize(52, 52)
player:SetTexture([[Interface\Minimap\MinimapArrow]])
player:SetBlendMode("BLEND")
player:SetPoint("CENTER", 0, -100)
DreadSprayVR.player = player

-- Drag Handle
local drag = CreateFrame("Frame", nil, DreadSprayVR)
drag.frame = DreadSprayVR
drag:SetFrameLevel(DreadSprayVR:GetFrameLevel() + 2)
drag:SetWidth(16)
drag:SetHeight(16)
drag:SetPoint("BOTTOMRIGHT", DreadSprayVR, -1, 1)
drag:EnableMouse(true)
drag:SetScript("OnMouseDown", OnDragHandleMouseDown)
drag:SetScript("OnMouseUp", OnDragHandleMouseUp)
drag:SetAlpha(0.5)
DreadSprayVR.drag = drag

local tex = drag:CreateTexture(nil, "OVERLAY")
tex:SetTexture([[Interface\AddOns\DreadSprayVR\drag.tga]])
tex:SetWidth(16)
tex:SetHeight(16)
tex:SetBlendMode("ADD")
tex:SetPoint("CENTER", drag)

DreadSprayVR.drag:Hide()

-- Timer Bar
local bar = CreateFrame("StatusBar", nil, DreadSprayVR)
bar.frame = DreadSprayVR
drag:SetFrameLevel(DreadSprayVR:GetFrameLevel() + 1)
bar:SetWidth(200)
bar:SetHeight(20)
bar:SetPoint("BOTTOMLEFT", DreadSprayVR, 0, 0)
bar:SetOrientation("HORIZONTAL")
bar:SetMinMaxValues(0, 12)
bar:SetValue(6)
bar:SetBackdropColor(0, 0, 0, 0)
DreadSprayVR.bar = bar

local bartex = bar:CreateTexture(nil, "ARTWORK")
bartex:SetTexture([[Interface\AddOns\DreadSprayVR\bar.tga]])
bartex:SetBlendMode("BLEND")
bartex:SetVertexColor(0, 1, 0, 1)

bar:SetStatusBarTexture(bartex)

-- Bar Text
local text = DreadSprayVR.bar:CreateFontString(nil, "OVERLAY")
text:SetFont([[Interface\AddOns\DreadSprayVR\Tw_Cen_MT_Bold.TTF]], 16, "OUTLINE")
text:SetShadowColor(0, 0, 0, 1)
text:SetShadowOffset(1, -1)
text:SetPoint("CENTER")
DreadSprayVR.text = text

-- OnEvent Script
DreadSprayVR:SetScript("OnEvent", function(self, event, ...)
 events[event](self, ...);
end);

-- Initial event registration
DreadSprayVR:RegisterEvent("ADDON_LOADED")
DreadSprayVR:RegisterEvent("PLAYER_ENTERING_WORLD")

----------------------------------------------------------------------]]
