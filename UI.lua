-- UI.lua
-- AceGUI-based user interface components

local addonName, addonTable = ...
local DRE = _G.DeathRollEnhancer
if not DRE then return end

local AceGUI = LibStub("AceGUI-3.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- UI Manager
DRE.UI = {}
local UI = DRE.UI

-- UI state
UI.mainWindow = nil
UI.isGameActive = false
UI.playerRoll = nil
UI.opponentRoll = nil
UI.gameState = "WAITING" -- WAITING, ROLLING, FINISHED

-- Initialize UI system
function DRE:InitializeUI()
    self.UI = self.UI or {}
end


-- Create main DeathRoll window using AceGUI
function DRE:ShowMainWindow()
    if not AceGUI then
        self:Print("AceGUI-3.0 not available. Please install Ace3.")
        return
    end
    
    if UI.mainWindow then
        UI.mainWindow:Show()
        return
    end
    
    -- Create main window frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("DeathRoll Enhancer v" .. self.version)
    frame:SetStatusText("Ready to roll!")
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    frame:SetLayout("Fill")
    frame:SetWidth(450)
    frame:SetHeight(550)
    
    -- Apply scaling from settings
    if self.db and self.db.profile.ui.scale then
        frame.frame:SetScale(self.db.profile.ui.scale)
    else
        frame.frame:SetScale(0.9) -- Default scale
    end
    
    UI.mainWindow = frame
    
    -- Create TabGroup
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Fill")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetTabs({
        {text="DeathRoll", value="deathroll"},
        {text="Statistics", value="statistics"}, 
        {text="History", value="history"}
    })
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        container:ReleaseChildren()
        if group == "deathroll" then
            self:CreateGameSection(container)
        elseif group == "statistics" then
            self:CreateStatsSection(container)
        elseif group == "history" then
            self:CreateHistorySection(container)
        end
    end)
    tabGroup:SelectTab("deathroll") -- Default to DeathRoll tab
    
    frame:AddChild(tabGroup)
    UI.tabGroup = tabGroup
    
    frame:Show()
end

-- Create game control section
function DRE:CreateGameSection(container)
    local gameGroup = AceGUI:Create("ScrollFrame")
    gameGroup:SetFullWidth(true)
    gameGroup:SetFullHeight(true)
    gameGroup:SetLayout("Flow")
    container:AddChild(gameGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Start DeathRoll")
    header:SetFullWidth(true)
    gameGroup:AddChild(header)
    
    -- Target info display
    local targetInfo = AceGUI:Create("Label")
    targetInfo:SetText("Target someone in-game, then click Challenge!")
    targetInfo:SetFullWidth(true)
    targetInfo:SetColor(0.8, 0.8, 0.8)
    gameGroup:AddChild(targetInfo)
    
    -- Roll amount section
    local rollGroup = AceGUI:Create("SimpleGroup")
    rollGroup:SetFullWidth(true)
    rollGroup:SetLayout("Flow")
    gameGroup:AddChild(rollGroup)
    
    local rollLabel = AceGUI:Create("Label")
    rollLabel:SetText("Roll:")
    rollLabel:SetWidth(80)
    rollGroup:AddChild(rollLabel)
    
    local rollEdit = AceGUI:Create("EditBox")
    rollEdit:SetLabel("")
    rollEdit:SetWidth(120)
    
    -- Set initial roll value based on auto-roll setting
    local initialRoll = "100"
    if self.db and self.db.profile.gameplay.autoRollFromMoney then
        initialRoll = tostring(self:CalculateAutoRoll())
    end
    rollEdit:SetText(initialRoll)
    
    rollEdit:SetMaxLetters(6) -- Limit to 6 digits
    rollEdit:SetCallback("OnTextChanged", function(widget, event, text)
        -- Only allow numbers
        local numericText = text:gsub("[^0-9]", "")
        if numericText ~= text then
            widget:SetText(numericText)
        end
        -- Ensure it doesn't exceed 6 digits
        if #numericText > 6 then
            widget:SetText(numericText:sub(1, 6))
        end
    end)
    rollGroup:AddChild(rollEdit)
    
    -- Store reference for auto-roll updates
    UI.rollEdit = rollEdit
    
    -- Wager section
    local wagerGroup = AceGUI:Create("SimpleGroup")
    wagerGroup:SetFullWidth(true)
    wagerGroup:SetLayout("Flow")
    gameGroup:AddChild(wagerGroup)
    
    local wagerLabel = AceGUI:Create("Label")
    wagerLabel:SetText("Wager:")
    wagerLabel:SetWidth(80)
    wagerGroup:AddChild(wagerLabel)
    
    local goldEdit = AceGUI:Create("EditBox")
    goldEdit:SetLabel("Gold")
    goldEdit:SetWidth(60)
    goldEdit:SetText("") -- Start empty
    goldEdit:SetMaxLetters(6) -- Reasonable gold limit
    goldEdit:DisableButton(true) -- Remove the "Okay" button
    
    -- Set placeholder text
    goldEdit.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
    goldEdit:SetText("0")
    goldEdit.isPlaceholder = true
    
    goldEdit:SetCallback("OnEditFocusGained", function(widget)
        if widget.isPlaceholder then
            widget:SetText("")
            widget.editbox:SetTextColor(1, 1, 1) -- White normal text
            widget.isPlaceholder = false
        end
    end)
    
    goldEdit:SetCallback("OnEditFocusLost", function(widget)
        if widget:GetText() == "" then
            widget:SetText("0")
            widget.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
            widget.isPlaceholder = true
        end
    end)
    
    goldEdit:SetCallback("OnTextChanged", function(widget, event, text)
        if widget.isPlaceholder then return end -- Don't process placeholder text
        
        local numericText = text:gsub("[^0-9]", "")
        if numericText ~= text then
            widget:SetText(numericText)
        end
    end)
    
    wagerGroup:AddChild(goldEdit)
    
    local silverEdit = AceGUI:Create("EditBox")
    silverEdit:SetLabel("Silver")
    silverEdit:SetWidth(60)
    silverEdit:SetText("") -- Start empty
    silverEdit:SetMaxLetters(2) -- Silver max 99
    silverEdit:DisableButton(true) -- Remove the "Okay" button
    
    -- Set placeholder text
    silverEdit.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
    silverEdit:SetText("0")
    silverEdit.isPlaceholder = true
    
    silverEdit:SetCallback("OnEditFocusGained", function(widget)
        if widget.isPlaceholder then
            widget:SetText("")
            widget.editbox:SetTextColor(1, 1, 1) -- White normal text
            widget.isPlaceholder = false
        end
    end)
    
    silverEdit:SetCallback("OnEditFocusLost", function(widget)
        if widget:GetText() == "" then
            widget:SetText("0")
            widget.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
            widget.isPlaceholder = true
        end
    end)
    
    silverEdit:SetCallback("OnTextChanged", function(widget, event, text)
        if widget.isPlaceholder then return end -- Don't process placeholder text
        
        local numericText = text:gsub("[^0-9]", "")
        if numericText ~= text then
            widget:SetText(numericText)
        end
        -- Limit silver to 99
        local num = tonumber(numericText)
        if num and num > 99 then
            widget:SetText("99")
        end
    end)
    
    wagerGroup:AddChild(silverEdit)
    
    local copperEdit = AceGUI:Create("EditBox")
    copperEdit:SetLabel("Copper")
    copperEdit:SetWidth(60)
    copperEdit:SetText("") -- Start empty
    copperEdit:SetMaxLetters(2) -- Copper max 99
    copperEdit:DisableButton(true) -- Remove the "Okay" button
    
    -- Set placeholder text
    copperEdit.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
    copperEdit:SetText("0")
    copperEdit.isPlaceholder = true
    
    copperEdit:SetCallback("OnEditFocusGained", function(widget)
        if widget.isPlaceholder then
            widget:SetText("")
            widget.editbox:SetTextColor(1, 1, 1) -- White normal text
            widget.isPlaceholder = false
        end
    end)
    
    copperEdit:SetCallback("OnEditFocusLost", function(widget)
        if widget:GetText() == "" then
            widget:SetText("0")
            widget.editbox:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder color
            widget.isPlaceholder = true
        end
    end)
    
    copperEdit:SetCallback("OnTextChanged", function(widget, event, text)
        if widget.isPlaceholder then return end -- Don't process placeholder text
        
        local numericText = text:gsub("[^0-9]", "")
        if numericText ~= text then
            widget:SetText(numericText)
        end
        -- Limit copper to 99
        local num = tonumber(numericText)
        if num and num > 99 then
            widget:SetText("99")
        end
    end)
    
    wagerGroup:AddChild(copperEdit)
    
    -- Start game button
    local startButton = AceGUI:Create("Button")
    startButton:SetText("Challenge to DeathRoll!")
    startButton:SetFullWidth(true)
    startButton:SetCallback("OnClick", function()
        local target = UnitName("target")
        local roll = tonumber(rollEdit:GetText())
        
        -- Calculate wager in copper, treating placeholders as 0
        local gold = (goldEdit.isPlaceholder and 0) or (tonumber(goldEdit:GetText()) or 0)
        local silver = (silverEdit.isPlaceholder and 0) or (tonumber(silverEdit:GetText()) or 0)
        local copper = (copperEdit.isPlaceholder and 0) or (tonumber(copperEdit:GetText()) or 0)
        local totalWager = (gold * 10000) + (silver * 100) + copper
        
        if not target or target == "" then
            self:Print("Please target a player first!")
            return
        end
        
        if not roll or roll < 2 then
            self:Print("Roll must be at least 2!")
            return
        end
        
        if roll > 999999 then
            self:Print("Roll cannot exceed 999,999 (6 digits maximum)!")
            return
        end
        
        if gold < 0 or silver < 0 or copper < 0 then
            self:Print("Wager amounts cannot be negative!")
            return
        end
        
        self:StartDeathRoll(target, roll, totalWager)
    end)
    gameGroup:AddChild(startButton)
    
    -- Game status
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText("")
    statusLabel:SetFullWidth(true)
    statusLabel:SetColor(1, 1, 0) -- Yellow text
    gameGroup:AddChild(statusLabel)
    
    UI.statusLabel = statusLabel
end

-- Create stats section
function DRE:CreateStatsSection(container)
    local statsGroup = AceGUI:Create("ScrollFrame")
    statsGroup:SetFullWidth(true)
    statsGroup:SetFullHeight(true)
    statsGroup:SetLayout("Flow")
    container:AddChild(statsGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("DeathRoll Statistics")
    header:SetFullWidth(true)
    statsGroup:AddChild(header)
    
    if not self.db or not self.db.profile.goldTracking then
        local noDataLabel = AceGUI:Create("Label")
        noDataLabel:SetText("No statistics available yet. Play some DeathRoll games to see your stats here!")
        noDataLabel:SetFullWidth(true)
        statsGroup:AddChild(noDataLabel)
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Overall statistics
    local overallGroup = AceGUI:Create("InlineGroup")
    overallGroup:SetTitle("Overall Performance")
    overallGroup:SetFullWidth(true)
    overallGroup:SetLayout("Flow")
    statsGroup:AddChild(overallGroup)
    
    -- Calculate total games and win rate
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    if self.db.profile.history then
        for playerName, playerData in pairs(self.db.profile.history) do
            totalWins = totalWins + (playerData.wins or 0)
            totalLosses = totalLosses + (playerData.losses or 0)
        end
    end
    totalGames = totalWins + totalLosses
    local winRate = totalGames > 0 and (totalWins / totalGames * 100) or 0
    
    -- Stats display with better formatting
    local statsText = string.format(
        "Total Games Played: %d\nGames Won: %d\nGames Lost: %d\nWin Rate: %.1f%%\n\nGold Won: %s\nGold Lost: %s\nNet Profit: %s",
        totalGames,
        totalWins,
        totalLosses,
        winRate,
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        self:FormatGold((stats.totalWon or 0) - (stats.totalLost or 0))
    )
    
    local statsLabel = AceGUI:Create("Label")
    statsLabel:SetText(statsText)
    statsLabel:SetFullWidth(true)
    overallGroup:AddChild(statsLabel)
    
    -- Streak information
    local streakGroup = AceGUI:Create("InlineGroup")
    streakGroup:SetTitle("Streaks")
    streakGroup:SetFullWidth(true)
    streakGroup:SetLayout("Flow")
    statsGroup:AddChild(streakGroup)
    
    local streakText = string.format(
        "Current Streak: %s%d\nBest Win Streak: %d\nWorst Loss Streak: %d",
        (stats.currentStreak or 0) >= 0 and "+" or "",
        stats.currentStreak or 0,
        stats.bestWinStreak or 0,
        stats.worstLossStreak or 0
    )
    
    local streakLabel = AceGUI:Create("Label")
    streakLabel:SetText(streakText)
    streakLabel:SetFullWidth(true)
    streakGroup:AddChild(streakLabel)
    
    -- Fun Statistics section
    self:CreateFunStatsSection(statsGroup)
    
    UI.statsLabel = statsLabel
    UI.streakLabel = streakLabel
end

-- Create fun statistics section
function DRE:CreateFunStatsSection(container)
    if not self.db or not self.db.profile.funStats then
        return
    end
    
    -- Calculate fun stats
    local funStats = self:CalculateFunStats()
    local settings = self.db.profile.funStats
    
    -- Check if any fun stats are enabled
    local hasEnabledStats = false
    for key, enabled in pairs(settings) do
        if enabled then
            hasEnabledStats = true
            break
        end
    end
    
    if not hasEnabledStats then
        return
    end
    
    local funStatsGroup = AceGUI:Create("InlineGroup")
    funStatsGroup:SetTitle("Fun Statistics")
    funStatsGroup:SetFullWidth(true)
    funStatsGroup:SetLayout("Flow")
    container:AddChild(funStatsGroup)
    
    -- Create a text string with all enabled fun stats
    local funStatsText = ""
    local statsToShow = {}
    
    -- Map settings to stat keys and check if they should be shown
    local statMappings = {
        showMostPlayedWith = "mostPlayedWith",
        showMostWinsAgainst = "mostWinsAgainst", 
        showMostLossesAgainst = "mostLossesAgainst",
        showMostMoneyWonFrom = "mostMoneyWonFrom",
        showMostMoneyLostTo = "mostMoneyLostTo",
        showBiggestWin = "biggestWin",
        showBiggestLoss = "biggestLoss",
        showNemesis = "nemesis",
        showVictim = "victim",
        showHighRoller = "highRoller",
        showCheapskate = "cheapskate",
        showLuckyPlayer = "luckyPlayer",
        showUnluckyPlayer = "unluckyPlayer", 
        showDaredevil = "daredevil",
        showConservative = "conservative",
    }
    
    -- Collect enabled stats
    for settingKey, statKey in pairs(statMappings) do
        if settings[settingKey] then
            local statText = self:FormatFunStat(statKey, funStats[statKey])
            if statText then
                table.insert(statsToShow, statText)
            end
        end
    end
    
    -- Display the stats
    if #statsToShow > 0 then
        funStatsText = table.concat(statsToShow, "\n")
    else
        funStatsText = "No fun statistics available yet.\nPlay more games to unlock interesting insights!"
    end
    
    local funStatsLabel = AceGUI:Create("Label")
    funStatsLabel:SetText(funStatsText)
    funStatsLabel:SetFullWidth(true)
    funStatsLabel:SetColor(0.9, 0.9, 0.5) -- Light yellow color for fun stats
    funStatsGroup:AddChild(funStatsLabel)
    
    -- Add settings hint
    local settingsHint = AceGUI:Create("Label")
    settingsHint:SetText("\nTip: Use /dr config → Fun Statistics to customize which stats are shown!")
    settingsHint:SetFullWidth(true)
    settingsHint:SetColor(0.7, 0.7, 0.7)
    funStatsGroup:AddChild(settingsHint)
    
    UI.funStatsLabel = funStatsLabel
end

-- Create history section
function DRE:CreateHistorySection(container)
    local historyGroup = AceGUI:Create("ScrollFrame")
    historyGroup:SetFullWidth(true)
    historyGroup:SetFullHeight(true)
    historyGroup:SetLayout("Flow")
    container:AddChild(historyGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Game History")
    header:SetFullWidth(true)
    historyGroup:AddChild(header)
    
    if not self.db or not self.db.profile.history then
        local noDataLabel = AceGUI:Create("Label")
        noDataLabel:SetText("No game history yet. Start playing DeathRoll games to see your history here!")
        noDataLabel:SetFullWidth(true)
        historyGroup:AddChild(noDataLabel)
        return
    end
    
    -- Player selector dropdown
    local playerGroup = AceGUI:Create("SimpleGroup")
    playerGroup:SetFullWidth(true)
    playerGroup:SetLayout("Flow")
    historyGroup:AddChild(playerGroup)
    
    local playerLabel = AceGUI:Create("Label")
    playerLabel:SetText("Player:")
    playerLabel:SetWidth(60)
    playerGroup:AddChild(playerLabel)
    
    -- Create dropdown with all players
    local playerNames = {}
    local playerDropdown = {}
    for playerName, _ in pairs(self.db.profile.history) do
        table.insert(playerNames, playerName)
        playerDropdown[playerName] = playerName
    end
    table.sort(playerNames)
    
    if #playerNames == 0 then
        local noPlayersLabel = AceGUI:Create("Label")
        noPlayersLabel:SetText("No players in history yet!")
        noPlayersLabel:SetFullWidth(true)
        historyGroup:AddChild(noPlayersLabel)
        return
    end
    
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetList(playerDropdown)
    dropdown:SetValue(playerNames[1])
    dropdown:SetWidth(200)
    dropdown:SetCallback("OnValueChanged", function(widget, event, key)
        self:UpdateHistoryDisplay(key)
    end)
    playerGroup:AddChild(dropdown)
    
    -- History display area
    local historyDisplayGroup = AceGUI:Create("InlineGroup")
    historyDisplayGroup:SetTitle("Player Statistics & Recent Games")
    historyDisplayGroup:SetFullWidth(true)
    historyDisplayGroup:SetLayout("Fill")
    historyGroup:AddChild(historyDisplayGroup)
    
    local historyBox = AceGUI:Create("MultiLineEditBox")
    historyBox:SetNumLines(15)
    historyBox:DisableButton(true)
    historyBox:SetFullWidth(true)
    historyBox:SetFullHeight(true)
    historyDisplayGroup:AddChild(historyBox)
    
    -- Store references for updates
    UI.historyBox = historyBox
    UI.historyDropdown = dropdown
    
    -- Show first player's history by default
    self:UpdateHistoryDisplay(playerNames[1])
end

-- Start a DeathRoll game
function DRE:StartDeathRoll(target, initialRoll, wagerAmount)
    if not target or target == "" then
        self:Print("Invalid target!")
        return
    end
    
    UI.isGameActive = true
    UI.gameState = "ROLLING"
    wagerAmount = wagerAmount or 0
    
    -- Create challenge message with wager information
    local message
    if wagerAmount > 0 then
        local wagerText = self:FormatGold(wagerAmount)
        message = string.format("DEATHROLL_CHALLENGE:%d:%d:%s", initialRoll, wagerAmount, "I challenge you to a DeathRoll! Starting at " .. initialRoll .. " for " .. wagerText .. "!")
    else
        message = string.format("DEATHROLL_CHALLENGE:%d:0:%s", initialRoll, "I challenge you to a DeathRoll! Starting at " .. initialRoll .. " (no wager)")
    end
    
    -- Send challenge message as whisper
    SendChatMessage(message, "WHISPER", nil, target)
    
    if UI.statusLabel then
        local statusText = wagerAmount > 0 and 
            string.format("Challenging %s: %d starting roll, %s wager", target, initialRoll, self:FormatGold(wagerAmount)) or
            string.format("Challenging %s: %d starting roll, no wager", target, initialRoll)
        UI.statusLabel:SetText(statusText)
    end
    
    local printText = wagerAmount > 0 and
        string.format("Challenged %s to DeathRoll starting at %d for %s", target, initialRoll, self:FormatGold(wagerAmount)) or
        string.format("Challenged %s to DeathRoll starting at %d (no wager)", target, initialRoll)
    self:Print(printText)
end

-- Update UI scale
function DRE:UpdateUIScale()
    if UI.mainWindow and UI.mainWindow.frame then
        local scale = self.db.profile.ui.scale or 1.0
        UI.mainWindow.frame:SetScale(scale)
    end
end

-- Format gold amount for display
function DRE:FormatGold(amount)
    if amount == 0 then
        return "0g"
    end
    
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    
    local result = ""
    if gold > 0 then
        result = gold .. "g"
    end
    if silver > 0 then
        result = result .. (result ~= "" and " " or "") .. silver .. "s"
    end
    if copper > 0 then
        result = result .. (result ~= "" and " " or "") .. copper .. "c"
    end
    
    return result ~= "" and result or "0c"
end

-- Show player history
function DRE:ShowHistory(playerName)
    if not self.db or not self.db.profile.history then
        self:Print("No history data available")
        return
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData then
        self:Print("No history found for " .. playerName)
        return
    end
    
    -- Create history window
    local histFrame = AceGUI:Create("Frame")
    histFrame:SetTitle("History with " .. playerName)
    histFrame:SetLayout("Fill")
    histFrame:SetWidth(500)
    histFrame:SetHeight(400)
    
    local histText = AceGUI:Create("MultiLineEditBox")
    histText:SetText(self:FormatPlayerHistory(playerData))
    histText:DisableButton(true)
    histText:SetFullWidth(true)
    histText:SetFullHeight(true)
    histFrame:AddChild(histText)
    
    histFrame:Show()
end

-- Format player history for display
function DRE:FormatPlayerHistory(playerData)
    if not playerData then
        return "No data available"
    end
    
    local text = string.format("Games Played: %d\n", playerData.gamesPlayed or 0)
    text = text .. string.format("Wins: %d\n", playerData.wins or 0)
    text = text .. string.format("Losses: %d\n", playerData.losses or 0)
    text = text .. string.format("Gold Won: %s\n", self:FormatGold(playerData.goldWon or 0))
    text = text .. string.format("Gold Lost: %s\n", self:FormatGold(playerData.goldLost or 0))
    
    if playerData.recentGames then
        text = text .. "\nRecent Games:\n"
        for i, game in ipairs(playerData.recentGames) do
            if i > 10 then break end -- Show only last 10 games
            text = text .. string.format("%s - %s (%s)\n", 
                game.date or "Unknown", 
                game.result or "Unknown",
                self:FormatGold(game.goldAmount or 0))
        end
    end
    
    return text
end

-- Update stats display
function DRE:UpdateStatsDisplay()
    if not UI.statsLabel or not self.db or not self.db.profile.goldTracking then
        return
    end
    
    local stats = self.db.profile.goldTracking
    
    -- Recalculate total games and win rate
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    if self.db.profile.history then
        for playerName, playerData in pairs(self.db.profile.history) do
            totalWins = totalWins + (playerData.wins or 0)
            totalLosses = totalLosses + (playerData.losses or 0)
        end
    end
    totalGames = totalWins + totalLosses
    local winRate = totalGames > 0 and (totalWins / totalGames * 100) or 0
    
    local statsText = string.format(
        "Total Games Played: %d\nGames Won: %d\nGames Lost: %d\nWin Rate: %.1f%%\n\nGold Won: %s\nGold Lost: %s\nNet Profit: %s",
        totalGames,
        totalWins,
        totalLosses,
        winRate,
        self:FormatGold(stats.totalWon or 0),
        self:FormatGold(stats.totalLost or 0),
        self:FormatGold((stats.totalWon or 0) - (stats.totalLost or 0))
    )
    
    UI.statsLabel:SetText(statsText)
    
    if UI.streakLabel then
        local streakText = string.format(
            "Current Streak: %s%d\nBest Win Streak: %d\nWorst Loss Streak: %d",
            (stats.currentStreak or 0) >= 0 and "+" or "",
            stats.currentStreak or 0,
            stats.bestWinStreak or 0,
            stats.worstLossStreak or 0
        )
        UI.streakLabel:SetText(streakText)
    end
    
    -- Update fun stats if they exist
    if UI.funStatsLabel and self.db and self.db.profile.funStats then
        local funStats = self:CalculateFunStats()
        local settings = self.db.profile.funStats
        local statsToShow = {}
        
        local statMappings = {
            showMostPlayedWith = "mostPlayedWith",
            showMostWinsAgainst = "mostWinsAgainst", 
            showMostLossesAgainst = "mostLossesAgainst",
            showMostMoneyWonFrom = "mostMoneyWonFrom",
            showMostMoneyLostTo = "mostMoneyLostTo",
            showBiggestWin = "biggestWin",
            showBiggestLoss = "biggestLoss",
            showNemesis = "nemesis",
            showVictim = "victim",
            showHighRoller = "highRoller",
            showCheapskate = "cheapskate",
            showLuckyPlayer = "luckyPlayer",
            showUnluckyPlayer = "unluckyPlayer", 
            showDaredevil = "daredevil",
            showConservative = "conservative",
        }
        
        for settingKey, statKey in pairs(statMappings) do
            if settings[settingKey] then
                local statText = self:FormatFunStat(statKey, funStats[statKey])
                if statText then
                    table.insert(statsToShow, statText)
                end
            end
        end
        
        local funStatsText = #statsToShow > 0 and 
            table.concat(statsToShow, "\n") or
            "No fun statistics available yet.\nPlay more games to unlock interesting insights!"
            
        UI.funStatsLabel:SetText(funStatsText)
    end
end

-- Update history display for selected player
function DRE:UpdateHistoryDisplay(playerName)
    if not UI.historyBox or not self.db or not self.db.profile.history then
        return
    end
    
    local playerData = self.db.profile.history[playerName]
    if not playerData then
        UI.historyBox:SetText("No data available for " .. (playerName or "Unknown"))
        return
    end
    
    -- Enhanced player history formatting
    local text = string.format("=== HISTORY WITH %s ===\n\n", string.upper(playerName))
    text = text .. string.format("Games Played: %d\n", (playerData.wins or 0) + (playerData.losses or 0))
    text = text .. string.format("Wins: %d\n", playerData.wins or 0)
    text = text .. string.format("Losses: %d\n", playerData.losses or 0)
    
    local totalGames = (playerData.wins or 0) + (playerData.losses or 0)
    if totalGames > 0 then
        local winRate = (playerData.wins or 0) / totalGames * 100
        text = text .. string.format("Win Rate: %.1f%%\n", winRate)
    end
    
    text = text .. string.format("Gold Won: %s\n", self:FormatGold(playerData.goldWon or 0))
    text = text .. string.format("Gold Lost: %s\n", self:FormatGold(playerData.goldLost or 0))
    text = text .. string.format("Net Profit: %s\n", self:FormatGold((playerData.goldWon or 0) - (playerData.goldLost or 0)))
    
    if playerData.recentGames and #playerData.recentGames > 0 then
        text = text .. "\n=== RECENT GAMES ===\n"
        local displayCount = math.min(#playerData.recentGames, 15) -- Show last 15 games
        for i = 1, displayCount do
            local game = playerData.recentGames[i]
            if game then
                local resultIcon = (game.result == "Won") and "✓" or "✗"
                local goldDisplay = (game.goldAmount and game.goldAmount > 0) and 
                    (" (" .. self:FormatGold(game.goldAmount) .. ")") or ""
                text = text .. string.format("%s %s - %s%s\n", 
                    resultIcon,
                    game.date or "Unknown Date",
                    game.result or "Unknown",
                    goldDisplay)
            end
        end
        
        if #playerData.recentGames > 15 then
            text = text .. string.format("\n... and %d more games\n", #playerData.recentGames - 15)
        end
    else
        text = text .. "\n=== RECENT GAMES ===\nNo games recorded yet."
    end
    
    UI.historyBox:SetText(text)
end

-- Clean up UI
function DRE:CleanupUI()
    if UI.mainWindow then
        UI.mainWindow:Hide()
        UI.mainWindow = nil
    end
end