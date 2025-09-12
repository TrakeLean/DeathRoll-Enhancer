-- UI.lua
-- AceGUI-based user interface components

local addonName, addonTable = ...
local DRE = LibStub("AceAddon-3.0"):GetAddon("DeathRollEnhancer")
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
        -- Check for recent rolls when reopening UI
        self:CheckRecentRollsForChallenge()
        return
    end
    
    -- Create main window frame (initially hidden to prevent flash)
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("DeathRoll Enhancer")
    frame:SetStatusText("v" .. self.version .. " - Bintes EDITion")
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    
    -- Hide frame initially to prevent flash during setup
    frame.frame:Hide()
    
    -- Set default dimensions first
    frame:SetWidth(400)
    frame:SetHeight(300)
    frame:SetLayout("Fill")
    
    -- Set up AceGUI status table (this will override defaults if saved values exist)
    if not self.db.profile.ui.frameStatus then
        self.db.profile.ui.frameStatus = {}
    end
    
    frame:SetStatusTable(self.db.profile.ui.frameStatus)
    frame:EnableResize(true)
    
    -- Apply scaling AFTER AceGUI status table is set up
    -- This ensures the scale is applied consistently
    local scaleValue = (self.db and self.db.profile.ui.scale) or 0.9
    frame.frame:SetScale(scaleValue)
    
    -- For first-time users, ensure correct dimensions immediately (no timer)
    if not self.db.profile.ui.frameStatus.width and not self.db.profile.ui.frameStatus.height then
        -- This is likely first time opening - ensure proper sizing immediately
        frame:SetWidth(400)
        frame:SetHeight(300)
        self:DebugPrint("Applied first-time window dimensions immediately after scale")
    end
    
    -- Debug hook - ensure scale is maintained when AceGUI restores status
    local originalApplyStatus = frame.ApplyStatus
    frame.ApplyStatus = function(self_frame)
        originalApplyStatus(self_frame)
        -- Reapply scale after status restoration
        local scaleValue = (self.db and self.db.profile.ui.scale) or 0.9
        self_frame.frame:SetScale(scaleValue)
        self:DebugPrint("Frame status applied (position/size restored) - scale reapplied: " .. scaleValue)
    end
    
    -- Position/size restoration is now handled by AceGUI status table
    
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
        -- Clear UI references when switching tabs to prevent cross-contamination
        UI.statsLabel = nil
        UI.streakLabel = nil
        UI.funStatsLabel = nil
        UI.rollHistoryBox = nil
        UI.rollHistory = {}
        UI.historyBox = nil
        UI.historyDropdown = nil
        -- Clear challenge UI references too
        UI.gameButton = nil
        UI.goldEdit = nil
        UI.silverEdit = nil
        UI.copperEdit = nil
        
        -- Track current tab
        UI.currentTab = group
        
        if group == "deathroll" then
            self:CreateGameSection(container)
            -- Check for recent rolls when switching to deathroll tab
            self:CheckRecentRollsForChallenge()
        elseif group == "statistics" then
            self:CreateStatsSection(container)
        elseif group == "history" then
            self:CreateHistorySection(container)
        end
    end)
    tabGroup:SelectTab("deathroll") -- Default to DeathRoll tab
    
    frame:AddChild(tabGroup)
    UI.tabGroup = tabGroup
    
    -- Show the frame AFTER all setup is complete to prevent flash
    frame:Show()
    
    -- Check for recent rolls when first opening UI
    self:CheckRecentRollsForChallenge()
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
    
    -- Store roll edit reference
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
    
    goldEdit:SetCallback("OnTextChanged", function(widget, event, text)
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
    
    silverEdit:SetCallback("OnTextChanged", function(widget, event, text)
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
    
    copperEdit:SetCallback("OnTextChanged", function(widget, event, text)
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
    
    -- Game action button (changes based on game state)
    local gameButton = AceGUI:Create("Button")
    gameButton:SetText("Challenge Player to DeathRoll!")
    gameButton:SetFullWidth(true)
    gameButton:SetCallback("OnClick", function()
        self:HandleGameButtonClick()
    end)
    gameGroup:AddChild(gameButton)
    
    
    -- Game status (compact, simple display)
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText("Ready to start! Target someone and click Challenge Player to DeathRoll!")
    statusLabel:SetFullWidth(true)
    statusLabel:SetColor(0.9, 0.9, 0.9) -- Light gray text
    gameGroup:AddChild(statusLabel)
    
    -- Store all UI references for later updates
    UI.goldEdit = goldEdit
    UI.silverEdit = silverEdit
    UI.copperEdit = copperEdit
    UI.gameButton = gameButton
    UI.rollHistoryBox = statusLabel -- Simple status label for roll display
    UI.rollHistory = {} -- Array to store roll entries
    
    -- Update button text with current target initially
    self:UpdateChallengeButtonText()
end

-- Add a roll entry to the history display
function DRE:AddRollToHistory(playerName, roll, maxRoll, isSelfDuel, rollCount)
    if not UI.rollHistoryBox or not UI.rollHistory then
        return
    end
    
    local myName = UnitName("player")
    local displayName = playerName
    local isMe = (playerName == myName)
    
    -- For self-duels, alternate the color but keep the same name
    if isSelfDuel then
        displayName = myName
        if (rollCount % 2) == 1 then
            isMe = true
        else
            isMe = false
        end
    end
    
    -- Calculate loss probability (chance of rolling 1)
    local lossChance = (1 / maxRoll) * 100
    
    -- Create colored entry
    local colorCode = isMe and "|cff00ff00" or "|cffff6666" -- Green for player, red for opponent
    local resetColor = "|r"
    
    local entry = string.format("%s%s%s rolled %d (1-%d) - %.3f%% chance of losing", 
        colorCode, displayName, resetColor, roll, maxRoll, lossChance)
    
    -- Add to history array
    table.insert(UI.rollHistory, 1, entry) -- Insert at beginning
    
    -- Keep only last 3 entries for compact display
    if #UI.rollHistory > 3 then
        table.remove(UI.rollHistory, 4)
    end
    
    -- Update display with compact format
    local historyText = table.concat(UI.rollHistory, "\n")
    UI.rollHistoryBox:SetText(historyText)
end

-- Update roll history with game status messages (for non-game states only)
function DRE:UpdateRollHistoryStatus(message, clearHistory)
    if not UI.rollHistoryBox then
        return
    end
    
    -- Only clear history if explicitly requested (for new games/challenges)
    if clearHistory then
        UI.rollHistory = {}
    end
    
    -- For status messages, just replace the content
    UI.rollHistoryBox:SetText(message)
end

-- Clear roll history for new game
function DRE:ClearRollHistory()
    if UI.rollHistory then
        UI.rollHistory = {}
    end
end

-- Add game result to roll history
function DRE:AddGameResultToHistory(result, opponent, wager)
    if not UI.rollHistoryBox or not UI.rollHistory then
        return
    end
    
    local resultText = ""
    local colorCode = ""
    
    if result == "WIN" then
        colorCode = "|cff00ff00" -- Bright green
        resultText = "*** YOU WON! ***"
    elseif result == "LOSS" then
        colorCode = "|cffff0000" -- Bright red
        resultText = "*** YOU LOST! ***"
    end
    
    local resetColor = "|r"
    local wagerText = wager and wager > 0 and (" (" .. self:FormatGold(wager) .. ")") or ""
    
    local entry = string.format("%s%s%s vs %s%s", 
        colorCode, resultText, resetColor, opponent or "Unknown", wagerText)
    
    -- Add result to top of history
    table.insert(UI.rollHistory, 1, entry)
    
    -- Keep only last 3 entries
    if #UI.rollHistory > 3 then
        table.remove(UI.rollHistory, 4)
    end
    
    -- Update display
    local historyText = table.concat(UI.rollHistory, "\n")
    UI.rollHistoryBox:SetText(historyText)
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
    
    -- Force ScrollFrame to recalculate content area
    C_Timer.After(0.1, function()
        if statsGroup and statsGroup.content then
            statsGroup:DoLayout()
        end
    end)
    
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
    funStatsGroup:SetHeight(200) -- Set explicit height to ensure proper scrolling
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
    settingsHint:SetText("\nTip: Use /dr config -> Fun Statistics to customize which stats are shown!")
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
    
    -- Player selector section
    local playerSelectorGroup = AceGUI:Create("SimpleGroup")
    playerSelectorGroup:SetFullWidth(true)
    playerSelectorGroup:SetLayout("Flow")
    historyGroup:AddChild(playerSelectorGroup)
    
    local playerLabel = AceGUI:Create("Label")
    playerLabel:SetText("View history with:")
    playerLabel:SetWidth(120)
    playerSelectorGroup:AddChild(playerLabel)
    
    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetList(playerDropdown)
    dropdown:SetValue(playerNames[1])
    dropdown:SetWidth(180)
    dropdown:SetCallback("OnValueChanged", function(widget, event, key)
        self:UpdateHistoryDisplay(key)
    end)
    playerSelectorGroup:AddChild(dropdown)
    
    -- History display area - with explicit height for proper scrolling
    local historyDisplayGroup = AceGUI:Create("InlineGroup")
    historyDisplayGroup:SetTitle("Statistics & Recent Games")
    historyDisplayGroup:SetFullWidth(true)
    historyDisplayGroup:SetHeight(200) -- Set explicit height to ensure proper scrolling
    historyDisplayGroup:SetLayout("Fill")
    historyGroup:AddChild(historyDisplayGroup)
    
    local historyLabel = AceGUI:Create("Label")
    historyLabel:SetText("Select a player to view history")
    historyLabel:SetFullWidth(true)
    historyLabel:SetJustifyV("TOP")
    historyLabel:SetJustifyH("LEFT")
    historyDisplayGroup:AddChild(historyLabel)
    
    -- Force ScrollFrame to recalculate content area
    C_Timer.After(0.1, function()
        if historyGroup and historyGroup.content then
            historyGroup:DoLayout()
        end
    end)
    
    -- Store references for updates
    UI.historyBox = historyLabel -- Now using Label instead of EditBox
    UI.historyDropdown = dropdown
    
    -- Show first player's history by default
    self:UpdateHistoryDisplay(playerNames[1])
end

-- UI StartDeathRoll function removed - using Core.lua version instead
-- This function just updates the UI state when the game starts

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
    
    -- Handle negative amounts
    local isNegative = amount < 0
    local absAmount = math.abs(amount)
    
    local gold = math.floor(absAmount / 10000)
    local silver = math.floor((absAmount % 10000) / 100)
    local copper = absAmount % 100
    
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
    
    if result == "" then
        result = "0c"
    end
    
    -- Add negative sign for negative amounts
    if isNegative then
        result = "-" .. result
    end
    
    return result
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
    -- Only update stats if we're on the statistics tab
    if UI.currentTab ~= "statistics" then
        return
    end
    
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
                local resultIcon = (game.result == "Won") and "[W]" or "[L]"
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


-- Create Spicy Duel RPS section
function DRE:CreateSpicyDuelSection(container)
    local spicyGroup = AceGUI:Create("ScrollFrame")
    spicyGroup:SetFullWidth(true)
    spicyGroup:SetFullHeight(true)
    spicyGroup:SetLayout("Flow")
    container:AddChild(spicyGroup)
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetText("Spicy DeathRoll - RPS Dice Duel")
    header:SetFullWidth(true)
    spicyGroup:AddChild(header)
    
    -- Description
    local descLabel = AceGUI:Create("Label")
    descLabel:SetText("A best-of-rounds duel where each player secretly chooses a stance (Attack/Defend/Gamble), rolls d50, and resolves outcomes via RPS-style matchups!\n\nStarting HP: 150 each | Win condition: reduce opponent to 0 HP")
    descLabel:SetFullWidth(true)
    descLabel:SetColor(0.9, 0.9, 0.7)
    spicyGroup:AddChild(descLabel)
    
    -- Game state display
    local gameStateGroup = AceGUI:Create("InlineGroup")
    gameStateGroup:SetTitle("Game Status")
    gameStateGroup:SetFullWidth(true)
    gameStateGroup:SetLayout("Flow")
    spicyGroup:AddChild(gameStateGroup)
    
    local gameStateLabel = AceGUI:Create("Label")
    gameStateLabel:SetText("Ready to start a new Spicy Duel!")
    gameStateLabel:SetFullWidth(true)
    gameStateGroup:AddChild(gameStateLabel)
    
    -- Stance selection
    local stanceGroup = AceGUI:Create("InlineGroup")
    stanceGroup:SetTitle("Choose Your Stance")
    stanceGroup:SetFullWidth(true)
    stanceGroup:SetLayout("Flow")
    spicyGroup:AddChild(stanceGroup)
    
    local stanceDropdown = AceGUI:Create("Dropdown")
    stanceDropdown:SetList({
        ["attack"] = "Attack (Straightforward strike)",
        ["defend"] = "Defend (Shield and parry)",
        ["gamble"] = "Gamble (Wild lunge - high risk/reward)"
    })
    stanceDropdown:SetValue("attack")
    stanceDropdown:SetWidth(200)
    stanceGroup:AddChild(stanceDropdown)
    
    local rollButton = AceGUI:Create("Button")
    rollButton:SetText("Roll & Reveal!")
    rollButton:SetWidth(120)
    rollButton:SetCallback("OnClick", function()
        self:HandleSpicyRoll(stanceDropdown:GetValue())
    end)
    stanceGroup:AddChild(rollButton)
    
    -- Challenge section
    local challengeGroup = AceGUI:Create("InlineGroup")
    challengeGroup:SetTitle("Challenge Someone")
    challengeGroup:SetFullWidth(true)
    challengeGroup:SetLayout("Flow")
    spicyGroup:AddChild(challengeGroup)
    
    local challengeButton = AceGUI:Create("Button")
    challengeButton:SetText("Challenge Target to Spicy Duel")
    challengeButton:SetFullWidth(true)
    challengeButton:SetCallback("OnClick", function()
        local target = UnitName("target")
        if not target or target == "" then
            self:Print("Please target a player first!")
            return
        end
        self:StartSpicyDuel(target)
    end)
    challengeGroup:AddChild(challengeButton)
    
    -- Rules section
    local rulesGroup = AceGUI:Create("InlineGroup")
    rulesGroup:SetTitle("Quick Rules")
    rulesGroup:SetFullWidth(true)
    rulesGroup:SetLayout("Fill")
    spicyGroup:AddChild(rulesGroup)
    
    local rulesText = AceGUI:Create("MultiLineEditBox")
    rulesText:SetText([[Attack vs Attack: Higher roll deals difference damage
Attack vs Defend: Defend blocks if D>=A, else A deals (A-D)
Attack vs Gamble: Glass Cannon - if A>=G then A deals full A, else G deals full G
Defend vs Defend: No damage (stalemate)
Defend vs Gamble: If G>D then G deals full G, else recoil (D-G)/2 to Gambler
Gamble vs Gamble: Higher deals double difference, tie = both take 10

Attack = consistent pressure | Defend = blocks & counters | Gamble = swingy chaos]])
    rulesText:SetNumLines(8)
    rulesText:DisableButton(true)
    rulesText:SetFullWidth(true)
    rulesText:SetFullHeight(true)
    rulesGroup:AddChild(rulesText)
    
    -- Store references
    UI.spicyGameState = gameStateLabel
    UI.spicyStance = stanceDropdown
    UI.spicyRollButton = rollButton
end

-- Calculate wager from UI input fields
function DRE:CalculateWagerFromUI()
    local gold = tonumber(UI.goldEdit and UI.goldEdit:GetText() or "0") or 0
    local silver = tonumber(UI.silverEdit and UI.silverEdit:GetText() or "0") or 0  
    local copper = tonumber(UI.copperEdit and UI.copperEdit:GetText() or "0") or 0
    return gold * 10000 + silver * 100 + copper
end

-- Handle game button clicks based on current state
function DRE:HandleGameButtonClick()
    local gameState = UI.gameState or "WAITING"
    
    if gameState == "WAITING" or gameState == "GAME_OVER" then
        -- Initial challenge state or starting new game after previous ended
        if gameState == "GAME_OVER" then
            -- Reset to WAITING state first to clear previous game
            self:UpdateGameUIState("WAITING")
        end
        
        -- Check if we have a recent target roll (challenge to accept)
        if UI.recentTargetRoll then
            -- Accept the challenge - start DeathRoll with their roll result
            local targetName = UnitName("target")
            if targetName and targetName == UI.recentTargetRoll.playerName then
                local wager = self:CalculateWagerFromUI()
                self:DebugPrint("Accepting challenge from " .. targetName .. " with roll " .. UI.recentTargetRoll.roll)
                self:StartDeathRoll(targetName, UI.recentTargetRoll.roll, wager)
            else
                self:Print("Target changed - please target " .. (UI.recentTargetRoll.playerName or "the challenger") .. " to accept their challenge")
            end
        else
            -- Start a new challenge
            self:StartChallengeFlow()
        end
    elseif gameState == "ROLLING" then
        -- Player needs to roll
        self:PerformRoll()
    elseif gameState == "WAITING_FOR_OPPONENT" then
        -- Waiting for opponent, button should be disabled
        self:Print("Waiting for opponent to roll...")
    end
end

-- Accept an incoming challenge from targeted player
function DRE:AcceptIncomingChallenge()
    local challenge = UI.incomingChallenge
    if not challenge then
        self:Print("No incoming challenge to accept!")
        return
    end
    
    local challenger = challenge.player
    local theirRoll = challenge.roll
    local maxRoll = challenge.maxRoll
    local wager = 0 -- Could be made configurable
    
    self:ChatPrint("Accepting " .. challenger .. "'s DeathRoll challenge!")
    self:ChatPrint(challenger .. " rolled " .. theirRoll .. " (1-" .. maxRoll .. ")")
    
    -- Start the game with their roll
    if theirRoll == 1 then
        self:ChatPrint(challenger .. " rolled 1 and lost! You won!")
        self:HandleGameEnd(challenger, "WIN", wager, maxRoll)
    else
        self:ChatPrint("Your turn! Roll 1-" .. theirRoll)
        -- Start the game - they already rolled, now it's your turn
        self:StartActualGame(challenger, maxRoll, wager, theirRoll)
    end
    
    -- Clear the challenge data
    UI.incomingChallenge = nil
    
    -- Update UI to normal state
    self:UpdateChallengeButtonText()
end

-- Deny an incoming challenge
function DRE:DenyIncomingChallenge()
    local challenge = UI.incomingChallenge
    if not challenge then
        return
    end
    
    self:ChatPrint("Denied " .. challenge.player .. "'s DeathRoll challenge.")
    
    -- Clear the challenge data
    UI.incomingChallenge = nil
    
    -- Update UI to normal state
    self:UpdateChallengeButtonText()
end

-- Accept a recent roll detected in chat or use your roll to challenge
function DRE:AcceptRecentRoll()
    local rollData = UI.recentTargetRoll
    if not rollData then
        self:Print("No recent roll found!")
        return
    end
    
    local rollOwner = rollData.player
    local rollResult = rollData.roll
    local maxRoll = rollData.maxRoll
    local currentTarget = UnitName("target")
    local wager = 0 -- Could be made configurable
    
    if rollOwner == UnitName("player") then
        -- You rolled - challenge the current target with your roll
        if not currentTarget then
            self:Print("No target selected to challenge!")
            return
        end
        
        self:ChatPrint("Challenging " .. currentTarget .. " with your roll of " .. rollResult .. " (1-" .. maxRoll .. ")!")
        
        -- Start game with your roll as the starting point
        if rollResult == 1 then
            self:ChatPrint("You rolled 1 and lost! " .. currentTarget .. " wins!")
            self:HandleGameEnd(currentTarget, "LOSS", wager, maxRoll)
        else
            -- Start the game - you already rolled, now target needs to roll
            self:StartActualGame(currentTarget, maxRoll, wager, rollResult)
        end
    else
        -- Someone else rolled - accept their challenge
        self:ChatPrint("Accepting " .. rollOwner .. "'s DeathRoll! They rolled " .. rollResult .. " (1-" .. maxRoll .. ")")
        
        -- Start game with their roll as the starting point
        if rollResult == 1 then
            self:ChatPrint(rollOwner .. " rolled 1 and lost! You won!")
            self:HandleGameEnd(rollOwner, "WIN", wager, maxRoll)
        else
            -- Start the game - they already rolled, now it's your turn
            self:StartActualGame(rollOwner, maxRoll, wager, rollResult)
        end
    end
    
    -- Clear the recent roll data
    UI.recentTargetRoll = nil
end

-- Start the challenge flow
function DRE:StartChallengeFlow()
    local target = UnitName("target")
    
    -- Check if we have a target
    if UnitExists("target") then
        -- Check if target is yourself (self-dueling)
        if UnitIsUnit("target", "player") then
            target = UnitName("player")
            self:Print("Self-duel mode activated!")
        else
            -- Check if target is a player (not NPC)
            if not UnitIsPlayer("target") then
                self:Print("You can only DeathRoll with other players, not NPCs!")
                return
            end
            
            -- Target is a valid player
            target = UnitName("target")
        end
    else
        -- No target selected
        self:Print("Please target a player first (or target yourself for self-duel)!")
        return
    end
    
    local roll = tonumber(UI.rollEdit:GetText())
    
    -- Calculate wager in copper, treating empty fields as 0
    local gold = tonumber(UI.goldEdit:GetText()) or 0
    local silver = tonumber(UI.silverEdit:GetText()) or 0
    local copper = tonumber(UI.copperEdit:GetText()) or 0
    local totalWager = (gold * 10000) + (silver * 100) + copper
    
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
    
    -- Store current target and game info for UI updates
    UI.currentTarget = target
    UI.initialRoll = roll
    UI.currentWager = totalWager
    
    -- Skip rolling state since we auto-roll, go straight to waiting for opponent
    self:UpdateGameUIState("WAITING_FOR_OPPONENT")
    
    -- Start the challenge
    self:StartDeathRoll(target, roll, totalWager)
end

-- Perform a roll in the active game
function DRE:PerformRoll()
    if not self.gameState or not self.gameState.isActive then
        self:Print("No active game!")
        return
    end
    
    local rollRange = self.gameState.currentRoll
    if not rollRange or rollRange < 1 then
        self:Print("Invalid roll range!")
        return
    end
    
    -- Update UI to show we're waiting for the roll result
    self:UpdateGameUIState("WAITING_FOR_ROLL_RESULT")
    
    -- Perform the roll using WoW's built-in roll system with a small delay
    C_Timer.After(0.1, function()
        RandomRoll(1, rollRange)
    end)
    
    -- Fallback timeout to reset UI if roll detection fails (especially for self-duels)
    C_Timer.After(3, function()
        if self.UI and self.UI.gameState == "WAITING_FOR_ROLL_RESULT" then
            self:DebugPrint("Roll detection timeout - resetting UI to ROLLING state")
            self:UpdateGameUIState("ROLLING")
        end
    end)
end

-- UpdateGameUIState function moved to Core.lua to avoid scoping issues


-- Clean up UI
function DRE:CleanupUI()
    if UI.mainWindow then
        UI.mainWindow:Hide()
        UI.mainWindow = nil
    end
end