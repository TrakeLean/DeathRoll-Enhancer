# DeathRoll Enhancer v2.3.2 - SKEM Edition

![Available on CurseForge](https://img.shields.io/badge/Available_on-CurseForge-6441A4?style=flat&logo=curseforge)
![Version](https://img.shields.io/badge/Version-2.3.2-brightgreen)
![WoW Compatibility](https://img.shields.io/badge/WoW-Classic%20|%20TBC%20|%20Wrath%20|%20Cata%20|%20Retail-blue)

**The ultimate DeathRoll addon for World of Warcraft!** Transform your gambling experience with professional-grade statistics tracking, intuitive UI, comprehensive game management, and now **whisper-based challenge notifications**! Built with the reliable Ace3 framework for maximum stability and performance across all WoW versions.

Available for download at [CurseForge](https://www.curseforge.com/wow/addons/deathroll-enhancer).

## What's New in Version 2.3.2

- **SKEM Edition UI polish** - Added a built-in Settings tab, stretched main tabs, and tightened the default window to 400x311
- **Embedded full roll history** - Main DeathRoll log now keeps all rolls inside the window with mouse-wheel scrolling instead of truncating at three lines
- **History scrollbar refresh fix** - Switching to players with longer histories now shows the scrollbar immediately
- **Use My Gold button** - Replaced the old auto-roll setting with a one-click roll helper beside the roll input
- **Trade-based wager tracking** - Added an option to hide manual wager inputs and record wagers from completed gold trades instead
- **Perspective-based roll odds** - The roll log now shows your chance of winning after your roll and your chance of losing after your opponent's roll

## 🆕 What's New in Version 2.3.0

### **💬 Whisper-Based Challenge System**
- **Seamless challenge notifications** - Addon users automatically notify opponents via whisper
- **Popup dialog** - Clean WoW-style popup shows challenger name, roll, and wager
- **One-click accept** - Opens UI and pre-fills all challenge values
- **Configurable thresholds** - Set minimum roll value to filter spam (default: 100)
- **Fully toggleable** - Enable/disable sending and receiving challenges independently
- **Works alongside manual play** - Still functions normally with players who don't have the addon

### **📊 Improved Fun Statistics**
- **Organized sections** - Stats now grouped into "Player Relationships", "Gold & Money", and "Luck & Streaks"
- **Matches settings layout** - Same order and structure as the settings tab
- **Cleaner display** - Easier to scan and understand your gambling stats

### **🐛 Bug Fixes**
- **Starting roll field fix** - Fixed starting rolls showing as 0 in edit game records
- **Field name consistency** - Unified `initialRoll` field across all operations

![image](https://media.forgecdn.net/attachments/1311/246/img1.png)

## 🎲 Core Features

### **Professional Interface**
- **Modern AceGUI design** with clean, scalable interface
- **Resizable & moveable window** with persistent positioning
- **Tabbed interface** - DeathRoll, Statistics, History, and Settings tabs
- **Smart challenge detection** - Automatically detects opponent rolls and shows "PlayerName rolled 56 from 1000 - Accept challenge!"
- **Real-time game progress** with colored player names and win probability

### **Advanced Statistics & Tracking**
- **Comprehensive player history** - Win/loss records per opponent
- **Gold tracking** - Track winnings, losses, and net profit with detailed breakdowns
- **Streak tracking** - Current and best winning/losing streaks
- **Fun statistics** - Most frequent opponent, biggest win/loss, win rates, and more
- **Recent game history** - View last 15 games with each player
- **Game record editing** - Fix mistakes with full edit/delete capabilities

### **Smart Game Management**
- **Automatic roll detection** - Recognizes opponent rolls in chat
- **Challenge acceptance** - One-click accept with pre-filled roll values
- **Flexible wager system** - Gold/Silver/Copper inputs or trade-based wager tracking
- **Self-duel mode** - Practice against yourself
- **Cross-version compatibility** - Works on Classic Era, TBC, Wrath, Cata, and Retail

## 🚀 Quick Start

1. Type `/dr` or `/deathroll` to open the interface
2. Target your opponent (or yourself for practice)
3. Set your starting roll and optional wager
4. Click "Challenge to DeathRoll!" and start playing

## 📋 Commands

- **`/dr`** or **`/deathroll`** - Open main interface
- **`/dr config`** - Open configuration panel
- **`/dr accept`** - Accept pending whisper-based challenge
- **`/dr decline`** - Decline pending whisper-based challenge
- **`/dr edit`** - Edit recent game records to fix mistakes
- **`/dr fixgold`** - Recalculate gold tracking totals
- **`/dr size`** - Show current window size and scale details
- **`/drh [player]`** - View history with specific player

## 🎨 Interface Navigation

- **DeathRoll Tab** - Start games and view live progress
- **Statistics Tab** - Review your performance and fun stats
- **History Tab** - Browse detailed game history per player
- **Settings Tab** - Adjust gameplay, challenge, UI, data, and fun stat options in-window
- **Minimap Icon** - Quick access and customizable positioning

## ⚙️ Configuration Options

Access via `/dr config` or the in-window `Settings` tab for extensive customization:
- **UI scaling and positioning** with reset functions
- **Auto-emote settings** for win/loss reactions
- **Sound notifications** for game events
- **Chat message control** - Toggle informational messages
- **Debug mode** - Enable detailed logging for troubleshooting
- **Trade-based wager tracking** - Capture wager amounts from completed gold trades
- **Fun statistics toggles** - Show only the stats you want
- **Minimap icon** show/hide and positioning
- **Data management** - Edit games, clean old data, export statistics

## 🔧 Technical Details

- **Built with Ace3** for rock-solid stability and performance
- **LibSharedMedia integration** for consistent UI theming
- **Persistent data storage** with automatic backup/restore
- **Comprehensive error handling** with debug system
- **Memory efficient** with smart data management
- **TBC compatible** with automatic fallback for older APIs

## 🎭 Emote System

- **Winning reactions** - CHEER, LAUGH, VICTORY, and more
- **Losing reactions** - CRY, SIGH, SURRENDER, and others
- **Fully customizable** - Enable/disable or choose specific emotes
- **Context-aware** - Different emotes for different situations

## 💰 Advanced Gold Tracking

- **Real-time calculations** - See your profit/loss as you play
- **Per-player breakdowns** - Know exactly how much you've won/lost against each opponent
- **Streak monitoring** - Track hot and cold streaks
- **Historical analysis** - View trends over time
- **Repair function** - `/dr fixgold` to fix any data inconsistencies

## 📊 Statistics Dashboard

View detailed analytics including:
- Total games played and win percentage
- Gold won, lost, and net profit
- Current and best streaks
- Most/least profitable opponents
- Biggest single wins and losses
- Average wager amounts
- Nemesis and favorite opponent tracking

## 🏆 Perfect For

- **TBC Classic players** looking for the best DeathRoll addon
- **Serious DeathRoll players** who want comprehensive tracking
- **Gold-making enthusiasts** monitoring their gambling profits
- **Statistics lovers** who enjoy detailed performance analytics
- **Casual players** who want a better DeathRoll experience
- **Guild events** and organized DeathRoll tournaments

## 🛠️ Developer Information

**Author:** 0xTrk
**Framework:** Ace3
**Dependencies:** LibSharedMedia-3.0, LibDBIcon-1.0
**License:** GPL v3

## 📖 Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and all changes.

### Recent Updates

**v2.2.0** - TBC Compatibility & Bug Fix Edition
- Full TBC Classic support with C_Timer shim
- 20+ bug fixes including race conditions and UI crashes
- Enhanced stability and error handling

**v2.1.x** - Gold Tracking & Edit Features
- Game record editing system
- Gold tracking repair function
- Database integrity improvements

---

*Experience DeathRoll like never before with professional-grade tracking, statistics, and management tools - now with full TBC Classic support!*
