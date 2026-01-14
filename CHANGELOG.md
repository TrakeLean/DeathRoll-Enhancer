# DeathRoll Enhancer - Changelog

## Version 2.2.0 - TBC Compatibility & Bug Fix Edition

### TBC Compatibility
- **Full TBC Classic Support** - Added C_Timer shim for TBC/Classic compatibility
  - Implements `C_Timer.After()` fallback using frame OnUpdate pattern
  - Zero performance impact on retail (uses native C_Timer when available)
  - Works seamlessly across all WoW versions (Classic Era, TBC, Wrath, Cata, Retail)

### Critical Bug Fixes
- **Race Condition in Roll Detection** - Fixed duplicate roll processing
  - Implemented roll deduplication system with unique roll IDs
  - Added 5-second expiry cache for processed rolls
  - Prevents same roll from being handled multiple times by different event handlers
  - Fixed pattern matching to use anchored regex (prevents partial matches)
- **Game State Validation** - Fixed crashes from invalid game states
  - Added comprehensive validation in `HandleGameRoll()`
  - Validates game state existence and required fields before processing
  - Added player name validation and parameter checking
  - Prevents nil reference errors during game execution
- **Concurrent Game Prevention** - Fixed ability to start multiple games
  - Added active game check at start of `StartDeathRoll()`
  - Returns error message if game already in progress
  - Prevents overlapping game state corruption

### UI & Safety Fixes
- **UI Safety Guards** - Comprehensive nil checks throughout UI code
  - Added validation in `UpdateChallengeButtonText()` before UI access
  - Added `pcall()` wrapper in `AddRollToHistory()` for safe text updates
  - Fixed potential crashes when UI closed during active operations
  - All UI components validated before access
- **Timer Race Condition** - Fixed roll detection timeout
  - Changed timeout from 3.0s to 3.2s to account for 0.1s roll delay
  - Prevents false positive timeout detections
- **UI Scale Desync** - Fixed double-scaling and flickering
  - Scale now applied correctly before AceGUI restoration
  - Added comparison check to prevent redundant scale operations
  - Eliminated scale flickering on window open
- **Target Change During Game** - Fixed UI confusion
  - Added active game check in `PLAYER_TARGET_CHANGED` handler
  - Prevents button updates during active games

### Database & Validation Fixes
- **Database Counter Corruption** - Fixed negative counter values
  - Changed initialization pattern from `(value or 1)` to `(value or 0)`
  - Applied `math.max(0, ...)` before subtraction operations
  - Prevents negative win/loss/gold counters in all scenarios
- **Date Parsing Validation** - Fixed crashes from malformed dates
  - Added complete date validation with `parseDateToNumber()`
  - Validates year (2000-2100), month (1-12), day (1-31), hour/minute ranges
  - Strict regex matching for date format (YYYY-MM-DD HH:MM)
  - Prevents crashes from corrupted date strings
- **Input Sanitization** - Fixed database corruption from invalid input
  - Added validation for gold (0-999,999), silver (0-99), copper (0-99)
  - Added validation for starting roll (0-999,999)
  - Prevents invalid currency values in edit dialog
- **Player Name Validation** - Improved validation logic
  - Added check for pure whitespace/symbol names
  - Prevents names like "---" or "   " from passing validation
  - Enforces reasonable character requirements

### Memory & Performance Fixes
- **Memory Leak Prevention** - Fixed recent rolls memory leak
  - Added `ClearRecentRollsForPlayer()` function
  - Automatic cleanup when games start/end
  - Prevents unbounded growth of recent rolls array
- **Infinite Loop Protection** - Added iteration limits
  - Bounds checking in `StoreRecentRoll()` with max iteration counter
  - Safety fallback if `maxRecentRolls` becomes negative
  - Debug warnings if iteration limits reached

### Cleanup & Error Handling
- **Proper State Cleanup** - Enhanced `OnDisable()` cleanup
  - Clears active game state on logout/disable
  - Cleans up spicy duel state
  - Clears UI references to prevent memory leaks
- **Enhanced Debug Logging** - Improved error visibility
  - Added debug messages for all error conditions
  - More descriptive error messages throughout
  - Better troubleshooting information

### Files Modified
- **Core.lua** - 13 major changes (TBC compat, validation, safety)
- **UI.lua** - 4 major changes (timer fix, validation, scale management)
- **Database.lua** - 3 major changes (counter fixes, date validation)

---

## Version 2.1.6 - Bintes Edition

### Bug Fixes
- [Add your changes here]

### New Features
- [Add your changes here]

---

## Version 2.1.5 - Gold Tracking Fix Edition

### Bug Fixes
- **Critical Gold Tracking Synchronization Bug** - Fixed desynchronization between individual player gold totals and global gold tracking
  - `DeleteGameRecord()` now properly updates global `goldTracking.totalWon` and `goldTracking.totalLost`
  - `EditGameRecord()` now properly synchronizes global tracking for both result changes and gold amount modifications
  - Prevents data corruption when deleting or editing games through the settings menu
- **Data Recovery Function** - Added `RecalculateGoldTracking()` to repair existing corrupted data
  - Recalculates global totals from individual player data
  - Accessible via new `/dr fixgold` command
  - One-time fix for users affected by the synchronization bug
- **Negative Net Profit Display** - Fixed `FormatGold()` function to properly display negative amounts
  - Net Profit now correctly shows negative values (e.g., "-15g 50s") when you have a net loss
  - Applies to all gold displays throughout the addon (main stats, minimap tooltip, player history)
- **Average Wager Decimal Fix** - Rounded down average wager calculations to remove decimal places
  - High Roller and Cheapskate stats now show clean copper amounts without decimals
  - Changed from "1g 66s 55.5555555555c avg wager" to "1g 66s 55c avg wager"

### New Features  
- **Gold Tracking Repair Command** - `/dr fixgold` command to fix corrupted global gold totals
  - Automatically recalculates `totalWon` and `totalLost` from individual player records
  - Provides feedback showing old vs new corrected values
  - Essential for users who experienced the synchronization bug

---

## Version 2.1.4 - Bintes EDITion

### New Features
- **Edit Game Records** - Complete game record editing functionality
  - Modify win/loss results for any previous game
  - Edit gold amounts (separate gold/silver/copper inputs) 
  - Change starting roll values for recorded games
  - Access via `/dr edit` command or settings menu
- **Delete Game Records** - Remove unwanted game entries
  - Safe deletion with confirmation dialog
  - Automatic statistics recalculation after deletion
  - Maintains data integrity by updating win/loss counters
- **Enhanced Game Management Interface**
  - Professional AceGUI dialog with dropdown game selection
  - Real-time dropdown refresh after deletions
  - Improved date sorting (newest games first) 
  - Clear game identification with player, result, gold, and date

### Technical Improvements
- **WoW-Compatible Date Sorting** - Fixed `os.time()` compatibility issue with WoW's restricted Lua environment
- **Database Functions** - Added `GetRecentGamesForEditing()`, `EditGameRecord()`, and `DeleteGameRecord()`
- **UI State Management** - Proper dialog cleanup and refresh after record modifications
- **Statistics Integrity** - Automatic counter updates when records are modified or deleted

### User Experience
- **Slash Command** - `/dr edit` for quick access to game editing
- **Settings Integration** - "Edit Game Records" button in Data Management section
- **Debug Output** - Optional debug information showing game order and timestamps
- **Error Handling** - Comprehensive validation and user-friendly error messages

---

## Version 2.1.3 - Database Fix Edition

### Critical Fix
- **Added missing Database.lua file** - This critical file was accidentally excluded from the addon distribution
  - Contains essential database management functions required for saving game history and statistics
  - Previous downloads from CurseForge were missing this file, causing silent failures in data persistence
  - All database functionality now works correctly (game history, statistics, gold tracking, etc.)
  - Users who experienced issues with data not saving should now have full functionality

### Technical Details
- Database.lua contains helper functions for player history management, statistics calculation, and data export
- The file was incorrectly excluded due to confusion with user data files
- SavedVariables system now functions properly for persistent data storage across game sessions

---

## Version 2.1.2 - Bintes Edition

### Bug Fixes
- Fixed post-game challenge button displaying opponent's last roll after game completion
- Challenge button now properly returns to normal state when games end
- Improved game state cleanup to prevent UI confusion after duels

### Technical Improvements  
- Fixed addon loading order issues that caused `AddGameToHistory` method not found errors
- Updated all module files to use proper Ace3 addon registration instead of global namespace access
- Enhanced game end cleanup to clear opponent roll data from recent rolls array

---

## Version 2.1.1 - Bintes Edition

### Bug Fixes
- Fixed challenge acceptance display to show actual roll value and original range (e.g., "PlayerName rolled 56 from 1000 - Accept challenge!" instead of "PlayerName challenges you to DeathRoll 1-56!")
- Roll input field now correctly populated with the challenger's actual roll value (56) rather than the range maximum (1000)

### UI Improvements
- Updated status bar to display "V2.1.1 - Bintes Edition"
- Enhanced challenge notification clarity by showing both rolled value and original maximum

---

## Version 2.0.0 - Complete Rewrite

### Major Changes
- Complete rewrite using Ace3 libraries for stability and performance
- Professional AceGUI interface with modern styling
- Advanced AceConfig options panel with font selection
- Comprehensive data management and export tools
- Enhanced statistics tracking and display
- LibSharedMedia integration for consistent theming

### Features
- Intuitive AceGUI-based interface for starting games
- Detailed win/loss history tracking per player
- Advanced gold tracking with streaks and statistics
- Smart minimap integration with LibDBIcon
- Automatic emote reactions on wins/losses
- Cross-version compatibility (Classic Era, TBC, Wrath, Cata, Retail)
- Professional options panel with Blizzard integration
- Data export/import functionality

### Commands
- `/dr` or `/deathroll` - Open the main DeathRoll window
- `/dr config` - Open configuration options
- `/drh [player]` - View history with specific player
