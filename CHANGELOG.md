# DeathRoll Enhancer Changelog

## Version 2.1.0

### 🎉 Major New Features

#### Game Record Editing System
- **NEW**: Edit game records after completion to fix mistakes (wager amounts, results, etc.)
- Access via `/dr edit` command or Data Management tab in settings
- Color-coded dropdown: Green for wins, Red for losses
- Proper display format: "MyPlayer vs OpponentPlayer - Result - Amount - Date"
- Edit result (Won/Lost), initial roll, and separate Gold/Silver/Copper inputs
- Real-time validation with automatic statistics recalculation

#### Settings Reorganization
- **NEW**: Dedicated "Data Management" tab for all data operations
- Moved statistics, cleanup, reset, and export functions to organized location
- Cleaner settings interface with better UX organization

### 🔧 Major Bug Fixes & Improvements

#### Settings System Fixes
- **FIXED**: Debug messages setting now properly controls debug output
- **FIXED**: Auto-roll from money setting updates immediately when changed
- **FIXED**: Chat messages setting now properly controls all addon messages
- Converted key game messages to respect chat settings toggle

#### Post-Duel Challenge Bug
- **FIXED**: Critical bug where challenging the same person within 60 seconds after a duel would use their last roll instead of manual input
- Added proper cleanup of opponent roll data when games end

#### Code Quality & Performance
- Removed duplicate `ShowChallengeNotification` function definition
- Removed unused functions: `CusRound`, `FindRecentTargetRoll`, `AcceptIncomingChallenge`, `DenyIncomingChallenge`
- Added comprehensive game record editing infrastructure
- Enhanced auto-roll setting with proper UI state management

### 🎨 UI/UX Improvements

#### History Tab Enhancements
- **IMPROVED**: Limited recent games display to last 5 games to prevent UI overflow
- Shows "... and X more games" when additional history exists
- Better content fitting within UI bounds

#### Edit Dialog Interface
- Clean popup interface with intuitive layout
- Games dropdown → Result dropdown → Roll input → Gold/Silver/Copper inputs
- Proper input validation and user feedback
- No emoji characters (WoW compatibility)

### 🛠️ Technical Enhancements

#### Database & Storage
- Enhanced game records with proper timestamp tracking
- Improved data retrieval functions for editing system
- Better error handling and data validation
- Complete statistics recalculation when records are modified

#### Settings Infrastructure  
- Added AceConfigRegistry import for dynamic settings updates
- Improved settings callbacks with immediate UI reflection
- Better organization of configuration options

### 📝 Developer Notes

#### Chat System Improvements
- Created `SetRollInput()` helper function for consistent roll input handling
- Converted `Print()` calls to `ChatPrint()` for settings-respecting messages
- Better separation between debug messages and user notifications

#### Data Management
- Enhanced `GetRecentGamesForEditing()` with proper sorting and limits
- Added `EditGameRecord()` function with comprehensive validation
- Improved gold tracking with proper undo/redo of statistical changes

---

### 🚀 Getting Started with New Features

1. **Edit Game Records**: Use `/dr edit` or go to Settings → Data Management → Edit Game Records
2. **Manage Your Data**: All data operations now in Settings → Data Management tab  
3. **Better History**: View recent games in the History tab with improved formatting

### 💡 Tips
- The edit dialog shows your recent games with color coding for easy identification
- All edits immediately update your statistics and gold tracking
- Use the Data Management tab for a centralized data control experience

---

*This update represents a significant enhancement to DeathRoll Enhancer with improved reliability, new features, and better user experience. Special thanks to all users who provided feedback and bug reports!*