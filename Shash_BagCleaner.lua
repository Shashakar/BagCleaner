
local frame = CreateFrame("Frame")

-- Config
local DELETE_LIMIT = 5 * 100 -- 5 silver in copper
local pendingItems = {}
local selectedQualities = {
    [0] = true,  -- Junk
    [1] = false, -- Common
    [2] = false, -- Uncommon
    [3] = false, -- Rare
    [4] = false, -- Epic
    [5] = false, -- Legendary
}
local ignoredItems = {} -- [itemID] = true

-- Tooltip scanner for soulbound detection
local scanner = CreateFrame("GameTooltip", "ShashScannerTooltip", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
for i = 1, 6 do
    _G["ShashScannerTooltipTextLeft" .. i] = _G["ShashScannerTooltipTextLeft" .. i] or scanner:CreateFontString()
end

local function isSoulbound(bag, slot)
    scanner:ClearLines()
    scanner:SetBagItem(bag, slot)
    for i = 1, scanner:NumLines() do
        local text = _G["ShashScannerTooltipTextLeft" .. i]:GetText()
        if text and text:find("Soulbound") then
            return true
        end
    end
    return false
end

local function getItemID(itemLink)
    return tonumber(string.match(itemLink, "item:(%d+):"))
end

local function shouldDeleteItem(quality, vendorValue, itemID)
    return selectedQualities[quality] and not ignoredItems[itemID] and vendorValue > 0 and vendorValue <= DELETE_LIMIT
end

local function scanBags()
    wipe(pendingItems)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
                local itemID = getItemID(itemLink)
                local _, _, quality = GetItemInfo(itemLink)
                local _, itemCount = GetContainerItemInfo(bag, slot)
                local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)

                vendorPrice = tonumber(vendorPrice or 0)
                itemCount = itemCount or 1
                local totalValue = vendorPrice * itemCount

                if quality and vendorPrice and not isSoulbound(bag, slot) and shouldDeleteItem(quality, totalValue, itemID) then
                    table.insert(pendingItems, {
                        bag = bag,
                        slot = slot,
                        link = itemLink,
                        count = itemCount,
                        totalValue = totalValue,
                        quality = quality
                    })
                end
            end
        end
    end
end

local function listItems()
    if #pendingItems == 0 then
        print("|cffffd000[Shash_BagCleaner]|r No items to delete.")
        return
    end
    print("|cffffd000[Shash_BagCleaner]|r Items marked for deletion:")
    for _, item in ipairs(pendingItems) do
        print(string.format(" - %sx%d (worth %d copper, quality %d)", item.link, item.count, item.totalValue, item.quality or -1))
    end
end

local function deleteItems()
    for _, item in ipairs(pendingItems) do
        PickupContainerItem(item.bag, item.slot)
        DeleteCursorItem()
        print("|cffff0000[Shash_BagCleaner]|r Deleted:", item.link)
    end
    wipe(pendingItems)
end

StaticPopupDialogs["SHASH_BAGCLEANER_CONFIRM"] = {
    text = "Are you sure you want to delete %d item(s)?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = deleteItems,
    OnCancel = function() print("|cff00ff00[Shash_BagCleaner]|r Deletion cancelled.") end,
    hasEditBox = false,
    whileDead = true,
    hideOnEscape = true,
    timeout = 0,
    preferredIndex = 3,
    OnShow = function(self)
        if not self.extraButton then
            local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
            b:SetSize(80, 22)
            b:SetText("List Items")
            b:SetPoint("TOP", self, "BOTTOM", 0, -2)
            b:SetScript("OnClick", listItems)
            self.extraButton = b
        end
        self.extraButton:Show()
    end,
    OnHide = function(self)
        if self.extraButton then
            self.extraButton:Hide()
        end
    end,
}

local function startCleanup()
    scanBags()
    if #pendingItems > 0 then
        StaticPopup_Show("SHASH_BAGCLEANER_CONFIRM", tostring(#pendingItems))
    else
        print("|cff00ff00[Shash_BagCleaner]|r Nothing to delete.")
    end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Settings UI
local optionsFrame = CreateFrame("Frame", "ShashBagCleanerOptions", UIParent)
optionsFrame:SetSize(260, 240)
optionsFrame:SetPoint("CENTER")
optionsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
optionsFrame:Hide()
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)

optionsFrame.title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
optionsFrame.title:SetPoint("TOP", 0, -10)
optionsFrame.title:SetText("Shash_BagCleaner Settings")

local silverLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
silverLabel:SetPoint("TOPLEFT", 16, -40)
silverLabel:SetText("Delete items worth ≤ this many silver:")

local silverInput = CreateFrame("EditBox", nil, optionsFrame, "InputBoxTemplate")
silverInput:SetSize(60, 20)
silverInput:SetPoint("TOPLEFT", silverLabel, "BOTTOMLEFT", 0, -4)
silverInput:SetAutoFocus(false)
silverInput:SetNumeric(true)
silverInput:SetMaxLetters(5)

-- Quality checkboxes
local qualityLabels = { "Junk", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
for i = 0, 5 do
    local cb = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 16 + (i % 3) * 80, -100 - math.floor(i / 3) * 28)
    cb:SetChecked(selectedQualities[i])
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(qualityLabels[i + 1] or tostring(i))
    cb:SetScript("OnClick", function(self)
        selectedQualities[i] = self:GetChecked()
    end)
end

local saveButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
saveButton:SetSize(80, 22)
saveButton:SetPoint("BOTTOM", 0, 12)
saveButton:SetText("Save")

saveButton:SetScript("OnClick", function()
    local silver = tonumber(silverInput:GetText())
    if silver and silver > 0 then
        DELETE_LIMIT = silver * 100
        print(string.format("|cff00ff00[Shash_BagCleaner]|r Delete limit updated to %d silver (%d copper)", silver, DELETE_LIMIT))
        optionsFrame:Hide()
    else
        print("|cffff0000[Shash_BagCleaner]|r Invalid input. Enter a number > 0.")
        PlaySound(89)
    end
end)

-- Slash Commands
SLASH_BAGCLEAN1 = "/bagclean"
SLASH_BAGCLEAN2 = "/bc"

SlashCmdList["BAGCLEAN"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end
    local command = args[1]
    local param = args[2]

    if command == "options" then
        silverInput:SetText(tostring(math.floor(DELETE_LIMIT / 100)))
        optionsFrame:Show()
    elseif command == "clean" then
        startCleanup()
    elseif command == "ignore" and param then
        local id = tonumber(param) or getItemID(param)
        if id then
            ignoredItems[id] = true
            print(string.format("|cffff8800[Shash_BagCleaner]|r Item %d added to ignore list.", id))
        end
    elseif command == "unignore" and param then
        local id = tonumber(param) or getItemID(param)
        if id and ignoredItems[id] then
            ignoredItems[id] = nil
            print(string.format("|cff88ff88[Shash_BagCleaner]|r Item %d removed from ignore list.", id))
        end
    else
        print("|cffffd000[Shash_BagCleaner]|r Commands:")
        print("  /bagclean clean          - Scan and confirm item deletion")
        print("  /bagclean options        - Open settings UI")
        print("  /bagclean ignore <item>  - Add item to ignore list")
        print("  /bagclean unignore <item>- Remove item from ignore list")
    end
end
