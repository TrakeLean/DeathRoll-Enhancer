# DeathRoll Enhancer v2.3.9 - SKEM Edition

![Available on CurseForge](https://img.shields.io/badge/Available_on-CurseForge-6441A4?style=flat&logo=curseforge)
![Version](https://img.shields.io/badge/Version-2.3.9-brightgreen)
![WoW Compatibility](https://img.shields.io/badge/WoW-Classic%20|%20TBC%20|%20Wrath%20|%20Cata%20|%20Retail-blue)

**The ultimate DeathRoll addon for World of Warcraft!** Transform your gambling experience with professional-grade statistics tracking, intuitive UI, comprehensive game management, and now **whisper-based challenge notifications**! Built with the reliable Ace3 framework for maximum stability and performance across all WoW versions.

Available for download at [CurseForge](https://www.curseforge.com/wow/addons/deathroll-enhancer).

## What's New in Version 2.3.9

- **Invalid escape code hotfix** - Stats broadcasts now sanitize outbound chat text to prevent `SendChatMessage` failures.
- **Channel picker in History tab** - Replaced fixed buttons with a channel dropdown + `Send Stats` button.
- **More broadcast channels** - `/dr sendstats` now supports `party`, `raid`, `guild`, `officer`, `instance`, `say`, and `yell`.
- **Better channel feedback** - Improved channel parsing and validation messages when a channel is unavailable.

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
- **Cheat-flag insights** - Includes a "Most Likely to Cheat" fun stat based on invalid roll-range flags
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
- **`/dr merge <oldName> <newName>`** - Merge player history after a rename
- **`/dr fixgold`** - Recalculate gold tracking totals
- **`/dr dedupe`** - Remove duplicate game entries and recalculate statistics
- **`/dr suspicious`** or **`/dr cheaters`** - Show tracked invalid roll-range attempts
- **`/dr setsuspicious <player> <count>`** - Manually set a player's suspicious-roll count
- **`/dr clearsuspicious <player>`** - Clear a player's suspicious-roll entry
- **`/dr sendstats [player] [party|raid|guild|officer|instance|say|yell]`** - Broadcast main stats against a player
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

**v2.3.9** - Stats Broadcast Hotfix
- Fixed `Invalid escape code in chat message` errors when broadcasting matchup stats
- Added History-tab channel selector + `Send Stats` action
- Expanded `/dr sendstats` to party/raid/guild/officer/instance/say/yell

**v2.3.8** - Matchup Stats Broadcast
- Added `/dr sendstats [player] [party|raid|guild|officer|instance|say|yell]` for in-chat matchup summaries
- Added History-tab quick-send actions for sharing selected matchup stats
- Added automatic player/channel fallback and compact broadcast formatting

**v2.3.7** - Tab Layout and Suspicion Management
- Fixed random tab overlap on DeathRoll/Statistics/History tabs
- Added set/clear suspicion tools in Edit Game Records
- Added `/dr setsuspicious`, `/dr clearsuspicious`, and `/dr forgive` commands

**v2.3.6** - Stats and History Cleanup
- Added `/dr dedupe` to remove duplicate game entries and recalculate totals
- Improved `/dr merge` to dedupe merged data and report duplicate-removal counts
- Reworked fun stat thresholds/tie-breaking to reduce weird duplicate-looking results

**v2.3.5** - Merge and Packaging Hotfixes
- Fixed `/dr merge` runtime crash in WoW Lua environments
- Fixed stale old-name entries in History dropdown after merge
- Fixed local addon version fallback display and CurseForge changelog markdown rendering

**v2.3.3** - Anti-Cheat and Stats Update
- Added strict wrong-roll range detection with suspicious-roll tracking
- Added `/dr suspicious` and `/dr merge` quality-of-life commands
- Added "Most Likely to Cheat" fun stat

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
