-- ============================================================================
-- Addon Setup
-- ============================================================================
local ADDON_NAME = "LaZTaunt"
local LaZTaunt = CreateFrame("Frame", ADDON_NAME .. "Frame") -- Main addon frame

-- Default settings
local defaults = {
    pos = { "CENTER", "CENTER", 0, 0 }, -- Default position
    maxEntries = 15, -- Maximum number of taunts to show
    frameWidth = 250,
    frameHeight = 200,
    rowHeight = 20,
    iconSize = 18,
}

-- Database for saved settings (position, etc.)
LaZTauntDB = LaZTauntDB or defaults -- Load saved settings or use defaults

-- Local references for performance
local _G = _G
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove
local date = date
local time = time
local GetTime = GetTime
local GetSpellInfo = GetSpellInfo
local SendChatMessage = SendChatMessage
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitIsPlayer = UnitIsPlayer
local CreateFrame = CreateFrame
local UIParent = UIParent

-- Data storage
local tauntHistory = {} -- Stores { timestamp, spellId, casterName, spellIcon, spellName }
local tauntRows = {} -- Stores the UI row frames

-- ============================================================================
-- Known Taunt Spell IDs (Expand this list!)
-- ============================================================================
-- This is NOT exhaustive. Add more IDs from Wowhead/other sources for different specs/expansions.
local knownTauntSpellIDs = {
    -- Warrior
    [355] = true,   -- Taunt
    -- Paladin
    [32700] = true, -- Hand of Reckoning
    -- Death Knight
    [56222] = true, -- Dark Command
    -- Demon Hunter
    [185245] = true,-- Torment
    -- Monk
    [115546] = true,-- Provoke
    -- Druid
    [5209] = true,  -- Growl (Bear Form)
    -- Hunter Pets (May need different handling if you only want player taunts)
    [2649] = true,  -- Growl (Pet) - Example, might want to filter non-player source later
    -- Warlock Pets
    [119905] = true, -- Threatening Presence (Voidwalker) - Example
}

-- ============================================================================
-- Frame Creation and Management
-- ============================================================================
local mainFrame = LaZTaunt
mainFrame:SetSize(LaZTauntDB.frameWidth or defaults.frameWidth, LaZTauntDB.frameHeight or defaults.frameHeight)
mainFrame:SetClampedToScreen(true)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    LaZTauntDB.pos = { point, relativeTo:GetName(), relativePoint, xOfs, yOfs }
    print(ADDON_NAME .. ": Position saved.")
end)

-- Backdrop
mainFrame:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
mainFrame:SetBackdropColor(0, 0, 0, 0.8)
mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- Title Text
local title = mainFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", mainFrame, "TOP", 0, -8)
title:SetText(ADDON_NAME)

-- Scroll Frame Setup
local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "ScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -28, 8) -- -28 accounts for scrollbar

-- Scroll Child Frame (holds the actual content rows)
local scrollChild = CreateFrame("Frame", ADDON_NAME .. "ScrollChild", scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetSize(scrollFrame:GetWidth(), 1) -- Width matches scroll frame, height starts small

-- Function to apply saved or default position
function LaZTaunt:ApplyPosition()
    local pos = LaZTauntDB.pos
    if pos and type(pos) == "table" and #pos == 5 and _G[pos[2]] then
        mainFrame:ClearAllPoints()
        -- Ensure relativeTo is a valid frame name that exists
        local relativeFrame = _G[pos[2]] or UIParent
        mainFrame:SetPoint(pos[1], relativeFrame, pos[3], pos[4], pos[5])
    else
        -- Apply default position if saved data is invalid or missing
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(defaults.pos[1], defaults.pos[2], defaults.pos[3], defaults.pos[4], defaults.pos[5])
        LaZTauntDB.pos = defaults.pos -- Save the default back if it was bad
    end
end

-- ============================================================================
-- Update Display Function
-- ============================================================================
function LaZTaunt:UpdateDisplay()
    local currentY = 0
    local rowHeight = LaZTauntDB.rowHeight or defaults.rowHeight
    local iconSize = LaZTauntDB.iconSize or defaults.iconSize
    local frameWidth = (LaZTauntDB.frameWidth or defaults.frameWidth) - 10 -- Usable width inside scroll child

    -- Clear or hide old rows
    for i = 1, #tauntRows do
        tauntRows[i]:Hide()
    end

    local displayIndex = 1
    for i = #tauntHistory, 1, -1 do -- Iterate backwards to show newest first
        local entry = tauntHistory[i]
        if not entry then break end

        local row = tauntRows[displayIndex]
        if not row then
            -- Create a new row if needed
            row = CreateFrame("Button", ADDON_NAME .. "Row" .. displayIndex, scrollChild)
            row:SetSize(frameWidth, rowHeight)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(iconSize, iconSize)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row:SetScript("OnClick", function(self)
                local chatMessage = string.format("|T%s:%d|t %s taunted (%s) at %s",
                    self.spellIcon, 16, self.casterName, self.spellName, date("%H:%M:%S", self.timestamp))

                local channel = "SAY" -- Default
                if IsInRaid() then
                    channel = "RAID"
                elseif IsInGroup() then
                    channel = "INSTANCE_CHAT" -- Use INSTANCE_CHAT in dungeons/scenarios
                    if GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE) == 0 then -- Check if actually in instance group
                      channel = "PARTY" -- Fallback to PARTY if not in instance group but still grouped
                    end
                end
                SendChatMessage(chatMessage, channel)
                print(ADDON_NAME .. ": Announced - " .. chatMessage)
            end)

            tauntRows[displayIndex] = row
        end

        -- Populate row data
        row.timestamp = entry.timestamp
        row.spellId = entry.spellId
        row.casterName = entry.casterName
        row.spellIcon = entry.spellIcon
        row.spellName = entry.spellName

        -- Set UI elements
        row.icon:SetTexture(entry.spellIcon or "Interface/Icons/INV_Misc_QuestionMark")
        row.text:SetText(string.format("%s - %s [%s]", date("%H:%M:%S", entry.timestamp), entry.casterName, entry.spellName))

        -- Position and show row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentY)
        row:Show()

        currentY = currentY - rowHeight
        displayIndex = displayIndex + 1

        if displayIndex > (LaZTauntDB.maxEntries or defaults.maxEntries) then
            break -- Stop processing if we've hit the max display limit
        end
    end

    -- Update scroll child height
    local totalHeight = math.abs(currentY)
    scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight())) -- Ensure it's at least as tall as the scroll frame view
end

-- ============================================================================
-- Add Taunt Entry Function
-- ============================================================================
function LaZTaunt:AddTaunt(timestamp, spellId, casterGUID, casterName)
    -- Basic filtering (ignore if caster is not a player, unless we specifically want pet taunts later)
    if not UnitIsPlayer(casterName) then
        -- You might want to add logic here to check if the casterGUID belongs to a player's pet
        -- For now, we only track direct player taunts for simplicity
         -- Check if it's a known pet taunt ID (optional)
        if not (knownTauntSpellIDs[spellId] and string.find(casterGUID, "Pet")) then
             return
        end
        -- If allowing pets, might want to format name like "PlayerName's Pet"
        -- local ownerName = -- Need logic to get pet owner if desired
        -- casterName = ownerName .. "'s Pet"
    end

    local spellName, _, spellIcon = GetSpellInfo(spellId)
    if not spellName then
        spellName = "Unknown Spell (" .. spellId .. ")"
        spellIcon = "Interface/Icons/INV_Misc_QuestionMark"
    end

    local entry = {
        timestamp = timestamp,
        spellId = spellId,
        casterName = casterName,
        spellIcon = spellIcon,
        spellName = spellName,
    }

    tinsert(tauntHistory, entry)

    -- Limit history size
    local maxEntries = LaZTauntDB.maxEntries or defaults.maxEntries
    if #tauntHistory > maxEntries then
        tremove(tauntHistory, 1) -- Remove the oldest entry
    end

    LaZTaunt:UpdateDisplay()
end

-- ============================================================================
-- Event Handling
-- ============================================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            print(ADDON_NAME .. " Loaded!")
            -- Apply position only after the addon is fully loaded
            LaZTaunt:ApplyPosition()
            -- Populate display if there's any saved history (unlikely, but possible if modified)
            LaZTaunt:UpdateDisplay()
            -- Unregister ADDON_LOADED after first load if not needed further
            -- self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId = CombatLogGetCurrentEventInfo()

        -- Check for successful spell casts that are in our known taunt list
        if subEvent == "SPELL_CAST_SUCCESS" and knownTauntSpellIDs[spellId] then
            -- We have a taunt!
             -- Filter out self-taunts if desired (unlikely for most taunts but possible)
             -- if sourceGUID == destGUID then return end
            LaZTaunt:AddTaunt(timestamp, spellId, sourceGUID, sourceName)
        end
        -- Could also listen for SPELL_AURA_APPLIED for taunt debuffs if needed,
        -- but CAST_SUCCESS is usually sufficient for tracking the action itself.
    end
end)

-- ============================================================================
-- Slash Commands (Optional: for testing/debugging)
-- ============================================================================
SLASH_LAZTAUNT1 = "/ltz"
SlashCmdList["LAZTAUNT"] = function(msg)
    local cmd = strlower(msg or "")
    if cmd == "test" then
        -- Add a dummy entry for testing layout/click
        local testSpellId = 355 -- Warrior Taunt
        LaZTaunt:AddTaunt(GetTime(), testSpellId, UnitGUID("player") or "Player-123-ABC", UnitName("player") or "TestPlayer")
        print(ADDON_NAME .. ": Added test entry.")
    elseif cmd == "clear" then
        tauntHistory = {}
        LaZTaunt:UpdateDisplay()
        print(ADDON_NAME .. ": History cleared.")
    elseif cmd == "resetpos" then
        LaZTauntDB.pos = defaults.pos
        LaZTaunt:ApplyPosition()
        print(ADDON_NAME .. ": Position reset.")
    else
        print(ADDON_NAME .. " Commands:")
        print("/ltz test - Adds a test entry")
        print("/ltz clear - Clears the history")
        print("/ltz resetpos - Resets frame position")
    end
end

print(ADDON_NAME .. ": Initializing...")