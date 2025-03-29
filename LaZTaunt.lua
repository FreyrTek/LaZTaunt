local ADDON_NAME = "LaZTaunt"
local isInitialized = false
local LaZTaunt = {} -- Define globally
local tauntHistory = {} -- Define globally to ensure persistence
local tauntRows = {} -- Define globally to ensure persistence

-- Default settings
local defaults = {
    pos = { "CENTER", "UIParent", "CENTER", 0, 0 },
    maxEntries = 15,
    frameWidth = 620, -- Adjusted to fit 600px scroll frame + padding
    frameHeight = 520, -- Keep height as before
    rowHeight = 43, -- Defined here, not in saved DB
}

-- Class colors for row backgrounds
local CLASS_COLORS = {
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43 },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73 },
    ["DEATHKNIGHT"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["DEMONHUNTER"] = { r = 0.64, g = 0.19, b = 0.79 },
    ["MONK"] = { r = 0.00, g = 1.00, b = 0.59 },
    ["DRUID"] = { r = 1.00, g = 0.49, b = 0.04 },
    ["HUNTER"] = { r = 0.67, g = 0.83, b = 0.45 },
    ["WARLOCK"] = { r = 0.53, g = 0.53, b = 0.93 },
}

-- Early check (minimal impact)
if not table.insert or not table.concat or not table.sort then
    -- print(ADDON_NAME .. ": Critical error - Lua table functions missing! Please report to Blizzard (11.1 bug).")
else
    LaZTauntDB = LaZTauntDB or CopyTable(defaults)
end

-- Get class color for a unit
local function GetClassColor(casterGUID)
    local _, class = GetPlayerInfoByGUID(casterGUID)
    if class and CLASS_COLORS[class] then
        return CLASS_COLORS[class].r, CLASS_COLORS[class].g, CLASS_COLORS[class].b
    end
    return 0.5, 0.5, 0.5 -- Fallback gray
end

-- Initialization function
local function InitializeLaZTaunt()
    if isInitialized then return end

    if not table.insert or not table.concat or not table.sort then
        -- print(ADDON_NAME .. ": Critical error - Lua table functions missing post-init! Please report to Blizzard (11.1 bug).")
        return
    end

    -- Known Taunt Spell IDs - Added Follower Dungeon taunts
    local knownTauntSpellIDs = {
        [355] = true,   -- Warrior: Taunt
        [62124] = true, -- Paladin: Hand of Reckoning
        [56222] = true, -- Death Knight: Dark Command
        [185245] = true,-- Demon Hunter: Torment
        [115546] = true,-- Monk: Provoke
        [5209] = true,  -- Druid: Growl (Bear Form)
        [2649] = true,  -- Hunter Pet: Growl
        [119905] = true, -- Warlock Pet: Threatening Presence
        [420090] = true, -- Follower Dungeon: Captain Garrick's Taunt
        
    }

    -- Frame Creation with Custom UI (Damage Meter Style)
    LaZTaunt.frame = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent, "BackdropTemplate")
    local mainFrame = LaZTaunt.frame
    mainFrame:SetSize(LaZTauntDB.frameWidth or defaults.frameWidth, LaZTauntDB.frameHeight or defaults.frameHeight)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        LaZTauntDB.pos = { point, "UIParent", relativePoint, xOfs, yOfs }
    end)

    -- Dark background with thin border using BackdropTemplate
    local backdropInfo = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }
    mainFrame:SetBackdrop(backdropInfo)
    mainFrame:SetBackdropColor(0, 0, 0, 0.8)
    mainFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Title
    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mainFrame.title:SetPoint("TOP", mainFrame, "TOP", 0, -5)
    mainFrame.title:SetText(ADDON_NAME)

    -- Scroll Frame (Custom, no Blizzard template) - Set to 600px wide
    LaZTaunt.scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "ScrollFrame", mainFrame)
    LaZTaunt.scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 5, -20)
    LaZTaunt.scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 5)
    LaZTaunt.scrollFrame:SetSize(600, 500) -- 600px wide, 500px tall
    -- print(ADDON_NAME .. ": ScrollFrame size set to: " .. LaZTaunt.scrollFrame:GetWidth() .. "x" .. LaZTaunt.scrollFrame:GetHeight())

    LaZTaunt.scrollChild = CreateFrame("Frame", ADDON_NAME .. "ScrollChild", LaZTaunt.scrollFrame)
    LaZTaunt.scrollChild:SetWidth(LaZTaunt.scrollFrame:GetWidth())
    LaZTaunt.scrollChild:SetHeight(1)
    LaZTaunt.scrollFrame:SetScrollChild(LaZTaunt.scrollChild)

    -- Scrollbar (Custom)
    LaZTaunt.scrollBar = CreateFrame("Slider", ADDON_NAME .. "ScrollBar", LaZTaunt.scrollFrame, "UIPanelScrollBarTemplate")
    LaZTaunt.scrollBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -20)
    LaZTaunt.scrollBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -5, 5)
    LaZTaunt.scrollBar:SetMinMaxValues(0, 0)
    LaZTaunt.scrollBar:SetValueStep(1)
    LaZTaunt.scrollBar:SetValue(0)
    LaZTaunt.scrollBar:SetWidth(16)
    LaZTaunt.scrollBar:SetScript("OnValueChanged", function(self, value)
        LaZTaunt.scrollFrame:SetVerticalScroll(value)
    end)

    -- Functions
    function LaZTaunt:ApplyPosition()
        local pos = LaZTauntDB.pos or defaults.pos
        if pos and type(pos) == "table" and #pos == 5 and _G[pos[2]] then
            local relativeFrame = _G[pos[2]]
            if relativeFrame and relativeFrame:IsObjectType("Frame") then
                self.frame:ClearAllPoints()
                self.frame:SetPoint(pos[1], relativeFrame, pos[3], pos[4], pos[5])
            else
                self.frame:ClearAllPoints()
                self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                LaZTauntDB.pos = defaults.pos
            end
        else
            self.frame:ClearAllPoints()
            self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            LaZTauntDB.pos = defaults.pos
        end
    end

    function LaZTaunt:UpdateDisplay()
        local rowHeight = defaults.rowHeight
        local maxEntries = LaZTauntDB.maxEntries or defaults.maxEntries
        local rowSpacing = 2 -- 2px gap between rows

        -- print(ADDON_NAME .. ": UpdateDisplay - Total entries in tauntHistory: " .. #tauntHistory)
        for _, row in ipairs(tauntRows) do
            row:Hide()
        end

        local currentY = 0
        local displayCount = 0
        for i = #tauntHistory, math.max(1, #tauntHistory - maxEntries + 1), -1 do
            -- print(ADDON_NAME .. ": Processing entry " .. i .. " of " .. #tauntHistory)
            local entry = tauntHistory[i]
            -- print(ADDON_NAME .. ": Entry - Timestamp: " .. entry.timestamp .. ", Caster: " .. entry.casterName .. ", Spell: " .. entry.spellName)
            local row = tauntRows[displayCount + 1]
            if not row then
                -- print(ADDON_NAME .. ": Creating new row " .. (displayCount + 1))
                row = CreateFrame("Button", ADDON_NAME .. "Row" .. (displayCount + 1), self.scrollChild)
                row:SetSize(self.scrollFrame:GetWidth() - 10, rowHeight)

                -- Colored bar background (class color) - Enclose icon and text
                row.bar = row:CreateTexture(nil, "BACKGROUND")
                row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.bar:SetSize(self.scrollFrame:GetWidth() - 10, rowHeight)

                -- Spell icon - Larger to match row height
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(32, 32) -- 32x32 to match 43px row height
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0) -- Centered vertically

                -- Text (timestamp, caster, spell name) - Two lines, larger font
                row.textTop = row:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 18pt
                row.textTop:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -4) -- Adjusted to center vertically with 2px padding above
                row.textTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -4)
                row.textTop:SetJustifyH("LEFT")
                row.textTop:SetTextColor(1, 1, 1) -- White
                row.textTop:SetShadowOffset(1, -1)
                row.textTop:SetShadowColor(0, 0, 0, 1)

                row.textBottom = row:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 18pt
                row.textBottom:SetPoint("TOPLEFT", row.textTop, "BOTTOMLEFT", 0, -3) -- 3px gap between lines to fit 43px height
                row.textBottom:SetPoint("TOPRIGHT", row.textTop, "BOTTOMRIGHT", 0, -3)
                row.textBottom:SetJustifyH("LEFT")
                row.textBottom:SetTextColor(1, 1, 1) -- White
                row.textBottom:SetShadowOffset(1, -1)
                row.textBottom:SetShadowColor(0, 0, 0, 1)

                row:SetScript("OnClick", function(self)
                    local chatMessage = string.format("%s taunted (%s) at %s",
                        self.casterName, self.spellName, date("%H:%M:%S", self.timestamp))
                    local channel = "SAY"
                    if IsInRaid() then channel = "RAID"
                    elseif IsInGroup() then
                        channel = "INSTANCE_CHAT"
                        if GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE) == 0 then channel = "PARTY" end
                    end
                    SendChatMessage(chatMessage, channel)
                    print(ADDON_NAME .. ": Announced - " .. chatMessage)
                end)

                tauntRows[displayCount + 1] = row
            end

            row.timestamp = entry.timestamp
            row.spellId = entry.spellId
            row.casterName = entry.casterName
            row.spellIcon = entry.spellIcon
            row.spellName = entry.spellName
            row.casterGUID = entry.casterGUID

            -- Set class color for the bar
            local r, g, b = GetClassColor(entry.casterGUID)
            row.bar:SetColorTexture(r, g, b, 0.5)

            row.icon:SetTexture(entry.spellIcon or "Interface/Icons/INV_Misc_QuestionMark")
            row.textTop:SetText(string.format("%s - %s", 
                date("%H:%M:%S", entry.timestamp), 
                entry.casterName))
            row.textBottom:SetText(string.format("[%s]", entry.spellName))
            -- print(ADDON_NAME .. ": Row " .. (displayCount + 1) .. " updated - Top Text: " .. row.textTop:GetText() .. ", Bottom Text: " .. row.textBottom:GetText())

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, currentY)
            row:Show()
            -- print(ADDON_NAME .. ": Row " .. (displayCount + 1) .. " positioned at Y: " .. currentY .. ", Visible: " .. tostring(row:IsVisible()))

            currentY = currentY - (rowHeight + rowSpacing) -- Add 2px gap
            displayCount = displayCount + 1
        end

        self.scrollChild:SetHeight(displayCount * (rowHeight + rowSpacing))
        -- print(ADDON_NAME .. ": ScrollChild height set to: " .. self.scrollChild:GetHeight())
        -- Update scrollbar range
        local maxScroll = math.max(0, (displayCount * (rowHeight + rowSpacing)) - self.scrollFrame:GetHeight())
        self.scrollBar:SetMinMaxValues(0, maxScroll)
        self.scrollBar:SetValue(math.min(self.scrollBar:GetValue(), maxScroll))
        -- print(ADDON_NAME .. ": Scrollbar range set - Min: 0, Max: " .. maxScroll)
    end

    function LaZTaunt:AddTaunt(timestamp, spellId, casterGUID, casterName)
        -- print(ADDON_NAME .. ": AddTaunt called - SpellID: " .. spellId .. ", Caster: " .. casterName .. ", GUID: " .. casterGUID)
        if not knownTauntSpellIDs[spellId] then
            -- print(ADDON_NAME .. ": SpellID " .. spellId .. " not in knownTauntSpellIDs")
            return
        end

        local playerGUID = UnitGUID("player")
        local petGUID = UnitGUID("pet")
        -- print(ADDON_NAME .. ": PlayerGUID: " .. (playerGUID or "nil") .. ", PetGUID: " .. (petGUID or "nil"))

        if not IsInGroup() and not IsInRaid() then
            -- print(ADDON_NAME .. ": Solo mode check")
            if casterGUID ~= playerGUID and casterGUID ~= petGUID then
                -- print(ADDON_NAME .. ": Failed solo check - CasterGUID does not match player or pet")
                return
            end
        elseif IsInGroup() or IsInRaid() then
            -- print(ADDON_NAME .. ": Group/Raid mode check")
            local isGroupMemberOrPet = casterGUID == playerGUID or casterGUID == petGUID
            if not isGroupMemberOrPet then
                local numMembers = GetNumGroupMembers()
                local unitPrefix = IsInRaid() and "raid" or "party"
                for i = 1, numMembers do
                    local unit = (i == numMembers and unitPrefix == "party") and "player" or (unitPrefix .. i)
                    local unitGUID = UnitGUID(unit)
                    local unitPetGUID = UnitGUID(unit .. "pet")
                    -- print(ADDON_NAME .. ": Checking " .. unit .. " - UnitGUID: " .. (unitGUID or "nil") .. ", UnitPetGUID: " .. (unitPetGUID or "nil"))
                    if casterGUID == unitGUID or (unitPetGUID and casterGUID == unitPetGUID) then
                        isGroupMemberOrPet = true
                        break
                    end
                end
            end
            if not isGroupMemberOrPet then
                -- print(ADDON_NAME .. ": Failed group/raid check - CasterGUID not in group/raid")
                return
            end
        end

        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local spellName = spellInfo and spellInfo.name or "Unknown Spell (" .. spellId .. ")"
        local spellIcon = spellInfo and spellInfo.iconID or "Interface/Icons/INV_Misc_QuestionMark"
        -- print(ADDON_NAME .. ": SpellInfo - Name: " .. spellName .. ", Icon: " .. spellIcon)

        local entry = {
            timestamp = timestamp,
            spellId = spellId,
            casterName = casterName,
            spellIcon = spellIcon,
            spellName = spellName,
            casterGUID = casterGUID, -- Store for class color
        }

        if #tauntHistory >= (LaZTauntDB.maxEntries or defaults.maxEntries) then
            table.remove(tauntHistory, 1)
        end
        table.insert(tauntHistory, entry)
        -- print(ADDON_NAME .. ": Added taunt to history - Total entries: " .. #tauntHistory)

        if not self.updatePending then
            self.updatePending = true
            C_Timer.After(0.1, function()
                -- print(ADDON_NAME .. ": Updating display...")
                LaZTaunt:UpdateDisplay()
                LaZTaunt.updatePending = false
            end)
        end
    end

    -- Event Frame
    LaZTaunt.eventFrame = CreateFrame("Frame", ADDON_NAME .. "EventFrame")
    local eventFrame = LaZTaunt.eventFrame
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local timestamp, subEvent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()
            -- print(ADDON_NAME .. ": Combat Log Event - SubEvent: " .. (subEvent or "nil") .. ", SpellID: " .. (spellId or "nil") .. ", Source: " .. (sourceName or "nil"))
            if subEvent == "SPELL_CAST_SUCCESS" then
                LaZTaunt:AddTaunt(timestamp, spellId, sourceGUID, sourceName)
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            LaZTaunt:UpdateDisplay()
        end
    end)

    -- Initial setup
    LaZTaunt:ApplyPosition()
    LaZTaunt:UpdateDisplay()
    isInitialized = true
    print(ADDON_NAME .. ": Initialized manually for The War Within 11.1!")
end

-- Slash Command to Trigger Initialization
SLASH_LAZTAUNT1 = "/ltz"
SlashCmdList["LAZTAUNT"] = function(msg)
    if not isInitialized then
        InitializeLaZTaunt()
    end
    local cmd = strlower(msg or "")
    if cmd == "test" then
        LaZTaunt:AddTaunt(GetTime(), 355, UnitGUID("player") or "Player-123-ABC", UnitName("player") or "TestPlayer")
        print(ADDON_NAME .. ": Added test entry.")
    elseif cmd == "clear" then
        wipe(tauntHistory)
        LaZTaunt:UpdateDisplay()
        print(ADDON_NAME .. ": History cleared.")
    elseif cmd == "resetpos" then
        LaZTauntDB.pos = defaults.pos
        LaZTaunt:ApplyPosition()
        print(ADDON_NAME .. ": Position reset.")
    else
        print(ADDON_NAME .. " Commands:")
        print("/ltz - Initializes the addon")
        print("/ltz test - Adds a test entry")
        print("/ltz clear - Clears the history")
        print("/ltz resetpos - Resets frame position")
    end
end

print(ADDON_NAME .. ": Waiting for /ltz to initialize (The War Within 11.1)...")