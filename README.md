# DeathRoll Enhancer v2.4.2 - 2SChoppy Edition

![Available on CurseForge](https://img.shields.io/badge/Available_on-CurseForge-6441A4?style=flat&logo=curseforge)
![Version](https://img.shields.io/badge/Version-2.4.2-brightgreen)
![WoW Compatibility](https://img.shields.io/badge/WoW-Classic%20|%20TBC%20|%20Wrath%20|%20Cata%20|%20Retail-blue)

**The ultimate DeathRoll addon for World of Warcraft!** Transform your gambling experience with professional-grade statistics tracking, intuitive UI, comprehensive game management, and now **whisper-based challenge notifications**! Built with Ace3 and feature-detected compatibility paths; target-client validation is described below.

Available for download at [CurseForge](https://www.curseforge.com/wow/addons/deathroll-enhancer).

## Version 2.4.1: client compatibility

One ZIP targets Retail, Classic Era/Hardcore, TBC Anniversary, Wrath Classic, Cataclysm Classic, Mists Classic, Titan Reforged (China), and Forever. See the [client version matrix and validation limits](TESTING.md#client-version-matrix). This covers modern client families, not original 1.12/2.4.3/3.3.5 installations.

Finished games now save even when optional emotes are unavailable or restricted. Older clients can still open settings with `/dr config`; the Blizzard Settings entry is added only when that API exists. Target challenges avoid restricted unit comparisons, and ordinary chat no longer inherits an addon-message-only restriction.

Group rounds start with **Announce to → None**. Turns and results appear on the host’s table. Choosing a different destination saves it for future rounds and reloads. With **Say**, click **Announce** after each roll to send the current turn or result. Party, Raid, and Instance channels announce automatically. Full Forever surnames remain supported.

### Shared tables in the Forever dev addon

1. The host opens **Group → Host table**. Add players by their full names. Anyone on the roster or in the host's party or raid can join the view.
2. On another character with the updated dev addon, target the host and click **Group → Join target**. You can also type `/dr group join Full Host Name`. Joining lets party members watch. The host adds them to the roster to give them a turn.
3. The host controls the mode, starting roll, teams, roster, shuffle, and round. Joined players see the changes, including turns, scores, lives, and results, even with **Announce to → None**. On your turn, use **Roll Your Turn** or the displayed `/roll` range. Stay near the host so their client receives the roll.

The table reconnects after a brief reload. Wait for the host to return before rolling. Guests can **Leave table** at any time. The host can close sharing with `/dr group leave` and continue locally. Players without the addon can still participate using ordinary rolls.

## Version 2.4.0: host-controlled group DeathRolls

Open **Group** or `/dr group`. Add 2–40 players in turn order using **Add Target**, **Add Me**, or their exact full names. Choose the mode, starting roll and announcement channel, then click **Start Round**. Only the host needs the addon. Everyone must stay nearby so the host can see their rolls.

- **Classic** ends when someone rolls 1. That player loses.
- **Elimination** knocks out whoever rolls 1. The next remaining player clockwise starts again at the original maximum. The last player standing wins.
- **Hot Potato** passes each safe roll to a randomly chosen different player. That player rolls with the new maximum. The first 1 ends the game.
- **Two Lives** gives everyone two lives. Each 1 costs the roller a life and resets the maximum for the next player. The last player with a life wins.
- **Teams** splits the roster between Gold and Crimson. On the Forever table, each portrait has a team-colored background and a thin matching border. The current roller gets a green ring. Left-click a portrait before starting to switch that player's team. **Shuffle order** changes who rolls first and keeps those assignments. The teams alternate, each cycling through its remaining players. A 1 knocks the roller out and resets the maximum. When one side runs out of players, everyone on the other team wins.

**Play again** restores the full roster in the same order and mode, with all lives and team members back in play.

The roster locks during play. **Cancel Round** or `/dr cancel` ends a stuck round; **Restart Round** reuses the previous roster/order/maximum. Cancel before changing participants. **Roll Your Turn** rolls only for the host when eligible; everyone can use ordinary `/roll`. **Announce** sends the current turn/result for Say and retries other channels if chat was blocked. Slash shortcuts: `/dr group roll`, `/dr group announce`, `/dr group cancel`, `/dr group restart`.

Payouts are manual. Settle them before starting new trade-tracked 1v1 games. Group results stay separate from 1v1 statistics. Earlier unpaid 1v1 games with group participants require `/dr edit` payment assignment. Reloading ends a local-only round. A Forever dev host can resume an explicitly shared round after a brief reload, including the last 20 log entries.

## Version 2.3.13: game recovery and safer editing

Use **Cancel** beside the game button or `/dr cancel` to leave an abandoned game locally. Cancellation records no result or payment and leaves earlier unpaid games intact. History edits now reject invalid amounts instead of silently replacing them with zero, and the History tab refreshes immediately after data changes. Minimap unlocking and release preparation are repaired too.

## Version 2.3.11: trade gold capture

Enable **Settings → Challenge System → Track Wager From Completed Trade** before starting a game. After the result, complete a gold trade with that opponent within five minutes. The addon records incoming gold for a win or outgoing gold for a loss only after the server confirms completion. Full Forever surnames are preserved.

Cancelled trades and late window events cannot reuse a payment. If both players offer gold, or several pending games match, assign the payment using `/dr edit`; the addon does not guess. This update has host-side regression coverage; an in-game test on your server/client is still needed.

## Version 2.3.10: correctness and Forever compatibility

This version fixes roll impersonation, turn enforcement, challenge acceptance, stale UI callbacks, and history edits targeting the wrong game. Required Ace3 modules are bundled, including upstream Forever name/profile support. Full surnames, UTF-8 names, and remote realm identities are preserved; roll parsing uses the client's localized format.

History records now have stable IDs. Migration preserves old rows and lifetime totals; deduplication no longer guesses from minute/second timestamps. Trade-wager settlements survive reload for five minutes. If several unpaid games match one trade, use `/dr edit` to assign that payment explicitly.

For commands taking two full names, quote each one: `/dr merge "Alice Smith" "Alice Jones"`. `/dr sendstats Alice Smith party` supports full names too.

The official Forever interface is included, but this build still needs in-game testing on the intended server/client. See [verification and client smoke tests](TESTING.md). The minimap libraries are bundled; only the optional media integration requires LibSharedMedia.

Challenge and data confirmations use addon-owned dialogs to avoid the Forever controller popup issue reported by Questie. Chat sends honor temporary client lockdown. The package includes both Forever and Camelot manifests. See [research sources and applicability](TESTING.md#forever-research-sources).

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
- **Live roll history** with colored player names and the next player's chance to roll a 1

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
- **Cross-version compatibility** - Current Retail and Classic families, plus Forever; see the tested API profiles and client matrix below

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
- **Persistent data storage** with exportable backups and conservative legacy migration
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
**Bundled libraries:** Ace3, LibDataBroker-1.1, LibDBIcon-1.0
**Optional integration:** LibSharedMedia-3.0
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
