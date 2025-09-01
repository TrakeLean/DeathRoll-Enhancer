# DeathRoll Enhancer - Development Context & History

## Project Overview
**DeathRoll Enhancer** is a professional World of Warcraft addon that enhances the DeathRoll gambling experience. Originally a basic addon, it has been completely rewritten using modern Ace3 framework and professional development practices.

## Version History

### Version 1.x (Original)
- Basic DeathRoll functionality
- Simple UI with native WoW frames
- Basic gold tracking
- Monolithic code structure

### Version 2.0.0 (Complete Rewrite)
**MASSIVE ARCHITECTURAL OVERHAUL** - Complete transformation from basic addon to enterprise-level professional addon.

## Current Architecture

### **Core Framework: Ace3**
- **AceAddon-3.0**: Professional addon lifecycle management
- **AceEvent-3.0**: Robust event handling system
- **AceConsole-3.0**: Slash command management
- **AceDB-3.0**: Professional database with profiles and defaults
- **AceGUI-3.0**: Modern, professional UI widgets
- **AceConfig-3.0/AceConfigDialog-3.0**: Comprehensive options system

### **Additional Libraries:**
- **LibSharedMedia-3.0**: Font and theme consistency
- **LibDBIcon-1.0**: Professional minimap integration
- **LibDataBroker-1.1**: Optional (LibDBIcon works independently)

### **Dependency Management:**
- **External Dependencies**: Uses CurseForge dependency management
- **TOC Dependencies**: `## Dependencies: Ace3, LibSharedMedia-3.0, LibDBIcon-1.0`
- **No Embedded Libraries**: Cleaner structure, auto-downloaded via CurseForge

## File Structure

```
DeathRollEnhancer/
├── DeathRollEnhancer.toc     # TOC with Ace3 dependencies
├── Core.lua                  # Main Ace3 addon with options system
├── Database.lua              # AceDB helper functions and data management
├── UI.lua                    # AceGUI-based user interface
├── Events.lua                # Event handling and game logic
├── Minimap.lua              # LibDBIcon minimap integration
└── DEVELOPMENT_CONTEXT.md   # This file
```

## Key Features Implemented

### **1. Professional UI System (AceGUI-3.0)**
- **Main Window**: Modern AceGUI Frame with sections
- **Target Selection**: EditBox + Target button
- **Roll Input**: 6-digit limit, numeric-only validation
- **Wager System**: Gold/Silver/Copper inputs with smart placeholders
- **Statistics Display**: Live stats with formatted gold amounts
- **History View**: Per-player game history

### **2. Advanced Wager System**
- **Individual Inputs**: Separate Gold, Silver, Copper fields
- **Smart Placeholders**: Gray "0" placeholder, no "010" issues
- **Input Validation**: Numeric-only, proper limits (Silver/Copper max 99)
- **Auto-calculation**: Converts to copper for internal storage
- **Visual Feedback**: Clear wager display in challenges

### **3. Challenge System with Popup Dialogs**
- **Whisper-Based**: Private challenges via whispers
- **Structured Messages**: `DEATHROLL_CHALLENGE:roll:wager:message` format
- **Interactive Popups**: Beautiful AceGUI dialog with Accept/Decline buttons
- **Auto-responses**: Instant feedback via whisper
- **Sound Notifications**: Audio alerts for incoming challenges

### **4. Comprehensive Options System**
- **AceConfig Integration**: Professional options panel
- **Blizzard Integration**: Appears in game's settings menu
- **Multiple Categories**: General, Interface, Minimap, Data Management
- **Advanced Features**: Font selection, UI scaling, data export
- **Validation**: Input limits and error handling

### **5. Auto-Roll from Money Feature**
- **Smart Calculation**: `GetMoney() % 999999` with minimum of 2
- **Settings Integration**: Toggle in options panel
- **Refresh Button**: Manual update button with tooltip
- **Strategic Element**: Roll based on actual character wealth

### **6. Professional Database System (AceDB-3.0)**
- **Structured Data**: Profiles, defaults, proper organization
- **Per-Player History**: Detailed game tracking per opponent
- **Statistics Tracking**: Wins, losses, streaks, gold amounts
- **Data Management**: Export, cleanup, reset functionality
- **Migration Safe**: Handles data format changes

### **7. Enhanced Event System**
- **Multi-Channel Support**: Whisper (primary), Say, Yell, Party, Guild
- **Smart Pattern Matching**: Multiple challenge detection patterns
- **Game State Management**: Tracks active games, rolls, wagers
- **Auto-responses**: Seamless challenge acceptance/decline flow

### **8. Input Validation & UX**
- **6-Digit Roll Limit**: Prevents overflow, matches WoW /roll limits
- **Real-time Validation**: Instant feedback, prevents invalid input
- **Smart Placeholders**: True placeholder behavior, no manual deletion
- **Professional Polish**: Removed intrusive "Okay" buttons

## Technical Implementation Details

### **Hybrid Challenge Flow:**
1. **Initiator**: Uses in-game targeting + UI to set roll/wager → Starts hybrid challenge
2. **Addon Detection**: Sends hidden PING message, waits 3 seconds for PONG response
3. **Enhanced Mode** (if target has addon):
   - Sends structured addon message with challenge details
   - Recipient gets popup dialog with Accept/Decline buttons
   - Response sent via addon message (ACCEPT/DECLINE)
4. **Fallback Mode** (if target lacks addon):
   - Sends natural whisper: "I challenge you to a DeathRoll! Starting at 6 for 1g 2s 3c!"
   - Monitors system messages for roll responses
   - 60-second timeout for challenge acceptance

### **Addon Message Formats:**
- **Detection**: `PING:<version>` → `PONG:<version>`
- **Challenge**: `CHALLENGE:<roll>:<wager>:<challengeText>`
- **Responses**: `ACCEPT:<roll>:<wager>` | `DECLINE`

### **Natural Whisper Format:**
- **Fallback Challenge**: `I challenge you to a DeathRoll! Starting at 6 for 1g 2s 3c!`

### **Data Structure:**
```lua
defaults = {
    profile = {
        minimap = { hide, minimapPos, lock },
        ui = { scale, framePos, font },
        gameplay = { autoEmote, soundEnabled, trackGold, autoRollFromMoney },
        history = { [playerName] = { wins, losses, goldWon, goldLost, recentGames } },
        goldTracking = { totalWon, totalLost, currentStreak, bestWinStreak, worstLossStreak }
    }
}
```

### **Key Functions:**
- **`DRE:ShowMainWindow()`**: Creates and displays tabbed AceGUI interface
- **`DRE:StartDeathRoll(target, roll, wager)`**: Main challenge initiation (hybrid system)
- **`DRE:SendChallenge(challenge)`**: Hybrid addon detection and challenge system
- **`DRE:ShowChallengeDialog(sender, roll, wager, text)`**: Popup dialogs for addon users
- **`DRE:StartFallbackMode(challenge)`**: Roll monitoring for non-addon users
- **`DRE:CHAT_MSG_SYSTEM()`**: System message monitoring for fallback mode
- **`DRE:CHAT_MSG_ADDON()`**: Addon message handling (PING/PONG/ACCEPT/DECLINE)
- **`DRE:CalculateAutoRoll()`**: Smart money-based roll calculation
- **`DRE:FormatGold(copper)`**: Converts copper to "5g 25s 10c" display format
- **`DRE:ChatPrint(message)`**: Conditional print that respects chatMessages setting

## Recent Major Improvements

### **Tabbed UI System (AceGUI TabGroup):**
- Complete UI restructure with professional tabbed interface
- **DeathRoll Tab**: Main challenge interface with streamlined controls
- **Statistics Tab**: Comprehensive fun statistics with 20+ customizable metrics
- **History Tab**: Per-player game history and records
- Removed target input field (uses in-game targeting)
- Removed refresh button for cleaner interface

### **Advanced Fun Statistics System:**
- 20+ customizable metrics: "Most Played With", "Your Nemesis", "Biggest Gold Mine"
- Individual toggles in configuration for each statistic
- Player dropdown history for detailed analysis
- Smart calculations for win/loss ratios and gold flow

### **Configuration Consolidation:**
- Reduced from 4 sparse tabs to 2 comprehensive tabs
- **General Tab**: Settings, Interface, Minimap, Data Management
- **Fun Statistics Tab**: Individual toggles for all statistics
- Removed problematic font picker (LSM30_Font dialog control)
- Adjusted UI scale defaults (0.9 becomes new 1.0)

### **Hybrid Addon Communication System:**
- **Addon Detection**: PING/PONG system with 3-second timeout
- **Enhanced Mode**: Popup dialogs for users with DeathRoll Enhancer addon
- **Fallback Mode**: Natural whispers and roll monitoring for non-addon users
- **Seamless Integration**: Automatically detects addon presence and switches modes

### **Message Format Evolution:**
- **Before**: Technical format `DEATHROLL_CHALLENGE:6:1020:3:I challenge you...`
- **After**: Natural messages `I challenge you to a DeathRoll! Starting at 6 for 1g 2s 3c!`
- Hidden addon messages for enhanced user experience
- Clean whisper communication for non-addon users

### **Input System Improvements:**
- Fixed wager placeholder behavior (no more gray "0" showing as real values)
- Removed fake placeholder system entirely
- Clean empty input fields with proper validation
- Real-time input validation with user-friendly feedback

### **Chat Messages Control System:**
- Added `chatMessages` setting (default: **off**) to control informational messages
- Created `ChatPrint()` helper function that respects user preference
- Informational messages now controllable: challenge status, addon detection, game flow
- Error messages and critical notifications still always show
- Reduces chat spam for users who want quieter addon experience

## Development Philosophy

### **Professional Standards:**
- **Ace3 Best Practices**: Following established addon development patterns
- **Modular Architecture**: Clean separation of concerns
- **Error Handling**: Graceful fallbacks and user-friendly messages
- **Cross-Version Support**: Works on all WoW versions

### **User Experience Focus:**
- **Intuitive Interface**: Modern, professional appearance
- **Smart Validation**: Prevents user errors before they happen
- **Clear Feedback**: Always inform user of what's happening
- **Consistent Behavior**: Predictable, reliable functionality

## Future Considerations

### **Potential Enhancements:**
- **Sound Pack Integration**: Custom win/loss sounds via LibSharedMedia
- **Advanced Statistics**: Graphs, win rates, profit analysis
- **Guild Integration**: Guild-wide DeathRoll tournaments
- **Betting Pools**: Multiple-player wagering systems
- **Achievement System**: DeathRoll milestones and badges

### **Technical Debt:**
- Currently minimal due to complete rewrite
- Well-documented, modular code structure
- Professional patterns throughout

## Installation & Dependencies

### **For Users:**
1. Download from CurseForge
2. Required dependencies auto-download: Ace3, LibSharedMedia-3.0, LibDBIcon-1.0
3. `/dr` to open, `/dr config` for options

### **For Developers:**
- Understand Ace3 framework patterns
- AceGUI widget system knowledge helpful
- Event-driven architecture understanding
- WoW addon development basics

### **IMPORTANT FOR NEXT SESSIONS READ THIS**
- The main logic of the rolls are not working, with the correct logic i should be able to challenge myself and play through the game, currently i am not able. 
- We are currently sending challenge whispers TWICE this is not good
- We should implement a setting that allows us to turn of these "Deathrollenhancer:" messages, not everyone wants this kind of "debug" feedback so have this default off.

## Commit History Highlights

- **Version 2.0.0 Complete Rewrite**: Massive architectural transformation
- **Whisper Challenge System**: Privacy-focused challenge implementation
- **Wager System & Popups**: Comprehensive gold wagering with interactive dialogs
- **Auto-Roll from Money**: Strategic wealth-based rolling feature
- **Input Validation Polish**: Professional UX improvements

---

- I have an idea for a spicy deathroll minigame we could add to one of the tabs it goes like this:
# Spicy Deathroll — RPS Dice Duel (Glass Cannon)

## Concept (1-liner)

A best-of-rounds duel where each player secretly chooses a stance (**Attack / Defend / Gamble**), rolls a stance-die, and resolves outcomes via an RPS-style matchup table with simple damage formulas.

---

## Default Numbers (tweak as you like)

* Starting HP: **150** per player
* Dice by stance:

  * **Attack:** d50
  * **Defend:** d50
  * **Gamble:** d50 (swingy by rules, not the die size)
* Win condition: first to reduce the opponent to **0 HP or less**.
* Reveal timing: both players lock a stance, then both roll and reveal.

---

## Stances & Lore (for flavor)

* **Attack (A):** Straightforward strike—consistent pressure.
* **Defend (D):** Shield and parry—blocks and counters.
* **Gamble (G):** Wild lunge—can whiff hard or explode for big damage.

---

## Matchup Table (authoritative)

Below, `Ax`, `Dx`, `Gx` are the actual dice results (1–100). “Damage X→Y” means Y loses that HP.

1. **Attack vs Attack**

   * Higher roll deals **difference** to the other:

     * If `Ax > Ay`: Damage A→B = `Ax - Ay`
     * If `Ay > Ax`: Damage B→A = `Ay - Ax`
     * If tie: no damage.
   * (Optional spice: both take the difference if within ≤5, but default = off.)

2. **Attack vs Defend**

   * **Defend blocks** if `D ≥ A` → **no damage**.
   * If `A > D` → Damage A→D = `A - D` (reduced hit).
   * (Optional counter: if `D ≥ A + 20` → chip counter `floor((D - A)/2)` back to Attacker.)

3. **Attack vs Gamble** (**Glass Cannon**)

   * If `A ≥ G`: **Attack wins**. Damage A→G = **`A`** (full attack value).
   * If `G > A`: **Gamble breaks through**. Damage G→A = **`G`** (full gamble value).
   * Notes: This keeps “Attack generally beats Gamble,” but Gamble can spike huge.

4. **Defend vs Defend**

   * No damage by default.
   * (Optional stamina mode: both recover +5 stamina or +5 HP; default = off.)

5. **Defend vs Gamble**

   * **Gamble beats Defend** if `G > D`: Damage G→D = **`G`** (full).
   * If `D ≥ G`: the Gambler stumbles and takes **recoil**: Damage D→G = **`ceil((D - G)/2)`**.
   * (This preserves the triangle: Gamble > Defend, but not for free.)

6. **Gamble vs Gamble**

   * Higher roll deals **double difference**:

     * If `G1 > G2`: Damage P1→P2 = `2 * (G1 - G2)`
     * If `G2 > G1`: Damage P2→P1 = `2 * (G2 - G1)`
     * Tie: both take **10** (mutual chaos), or 0 if you want it safer.

---

## Ties & Ordering

* When both sides would deal damage simultaneously (e.g., A vs A, G vs G), **apply damage concurrently**. It’s possible to KO each other in the same round.
* On exact ties where the table says “higher deals,” apply **no damage** (unless G vs G tie, where the mutual 10 default kicks in).

---

## Round Flow (algorithm)

1. **Stance lock:** Both players secretly choose **A / D / G**.
2. **Roll:** Each rolls d100 for their chosen stance.
3. **Reveal:** Show stances and results.
4. **Resolve:** Use the matchup table; compute damage numbers.
5. **Apply damage simultaneously.**
6. **Check KO:** If either HP ≤ 0 → end; else next round.

---

## Pseudocode (drop-in for a bot/addon)

```pseudo
HP_A = 100; HP_B = 100

while HP_A > 0 and HP_B > 0:
  stance_A = choose_from({"A","D","G"})  // secretly
  stance_B = choose_from({"A","D","G"})  // secretly

  roll_A = d100()
  roll_B = d100()

  dmg_A_to_B = 0
  dmg_B_to_A = 0

  switch (stance_A, stance_B):
    case ("A","A"):
      if roll_A > roll_B: dmg_A_to_B = roll_A - roll_B
      else if roll_B > roll_A: dmg_B_to_A = roll_B - roll_A
      // tie => 0

    case ("A","D"):
      if roll_B >= roll_A: /* blocked */
      else dmg_A_to_B = roll_A - roll_B
      // optional counter:
      // if roll_B >= roll_A + 20: dmg_B_to_A = floor((roll_B - roll_A)/2)

    case ("A","G"): // Glass Cannon
      if roll_A >= roll_B: dmg_A_to_B = roll_A
      else dmg_B_to_A = roll_B

    case ("D","A"): // symmetric to A vs D
      if roll_A >= roll_B: /* blocked */
      else dmg_B_to_A = roll_B - roll_A
      // optional counter same idea

    case ("D","D"):
      // default: no damage
      // optional: recover
      // HP_A += 5; HP_B += 5

    case ("D","G"):
      if roll_B > roll_A: dmg_B_to_A = roll_B
      else dmg_A_to_B = ceil((roll_A - roll_B)/2)

    case ("G","D"): // symmetric to D vs G
      if roll_A > roll_B: dmg_A_to_B = roll_A
      else dmg_B_to_A = ceil((roll_B - roll_A)/2)

    case ("G","G"):
      if roll_A > roll_B: dmg_A_to_B = 2 * (roll_A - roll_B)
      else if roll_B > roll_A: dmg_B_to_A = 2 * (roll_B - roll_A)
      else { dmg_A_to_B = 10; dmg_B_to_A = 10 } // tie default

  // Criticals / Fails (optional)
  if roll_A == 100: dmg_A_to_B += 10
  if roll_B == 100: dmg_B_to_A += 10
  if roll_A == 1 and (stance_A == "A" or stance_A == "G"): dmg_A_to_A = 5
  if roll_B == 1 and (stance_B == "A" or stance_B == "G"): dmg_B_to_B = 5
  // apply self-damage first or together; default: together with other damage

  // Apply damage simultaneously
  HP_A -= (dmg_B_to_A + (dmg_A_to_A ?? 0))
  HP_B -= (dmg_A_to_B + (dmg_B_to_B ?? 0))

end while

winner = (HP_A > 0) ? "Player A" : (HP_B > 0) ? "Player B" : "Double KO"
```

---

## One-Page Cheat Sheet (for players)

* **Choose:** Attack / Defend / Gamble → roll d100.
* **A vs A:** higher roll deals **difference**.
* **A vs D:** D blocks if `D ≥ A`, else damage = `A - D`.
* **A vs G (Glass Cannon):** if `A ≥ G` → damage = `A`; else Gamble deals `G`.
* **D vs D:** no damage.
* **D vs G:** if `G > D` → damage = `G`; else Gambler takes recoil `ceil((D - G)/2)`.
* **G vs G:** higher roll deals **double difference**; tie → both take 10.
* **Simultaneous damage** applies; KO at **0 HP**.

---


*This addon represents a complete transformation from basic functionality to enterprise-level professional development, showcasing modern WoW addon architecture and best practices.*