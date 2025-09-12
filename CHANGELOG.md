# DeathRoll Enhancer - Changelog

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