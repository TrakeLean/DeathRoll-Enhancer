# DeathRoll Enhancer - Changelog

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