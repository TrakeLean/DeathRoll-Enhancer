# DeathRoll Enhancer

DeathRoll Enhancer is a World of Warcraft addon for running DeathRoll games with better tracking, cleaner UI, and safer game flow. It focuses on fast play, clear game state, and long-term stats.

![image](https://media.forgecdn.net/attachments/1311/246/img1.png)

## Core Features

### Interface
- Resizable, moveable main window
- Tabbed layout: DeathRoll, Statistics, History, and Settings
- Minimap icon for quick open/config access
- Live roll history and game-state feedback during active games

### Game Flow
- Automatic roll detection from chat events
- Whisper-based challenge flow for addon users
- Self-duel support for practice
- Wager inputs (gold/silver/copper) with optional trade-based wager tracking
- Invalid roll-range detection (flags suspicious rolls during active games)

### Data and Stats
- Per-player win/loss and gold history
- Global profit/loss and streak tracking
- Fun stats (nemesis, best/worst matchup, high roller, and more)
- "Most Likely to Cheat" fun stat based on flagged invalid roll ranges
- Edit/delete recent game records
- Merge renamed player records into one history entry
- Deduplicate repeated history rows and recalculate totals after bad merges/imports

## Commands

- `/dr` or `/deathroll` - Open the main window
- `/dr config` - Open configuration options
- `/dr accept` - Accept a pending challenge
- `/dr decline` - Decline a pending challenge
- `/dr edit` - Edit recent game records
- `/dr merge <oldName> <newName>` - Merge player history after a rename
- `/dr dedupe` - Remove duplicate game rows and recalculate stats/totals
- `/dr suspicious` or `/dr cheaters` - Show flagged invalid roll ranges
- `/dr setsuspicious <player> <count>` - Manually set a player's suspicious-roll count
- `/dr clearsuspicious <player>` - Clear a player's suspicious-roll entry
- `/dr fixgold` - Recalculate gold totals and streak data
- `/dr size` - Print current window size details
- `/drh [player]` - Show history for a specific player

## Configuration

Available via `/dr config` and the in-window Settings tab:

- Challenge behavior (whispers, minimum roll threshold)
- UI scale and window reset helpers
- Chat/debug output toggles
- Trade-based wager tracking
- Fun stat visibility toggles
- Data cleanup, export, and repair tools

## Compatibility and Dependencies

- Works across modern WoW flavors (Classic and Retail interface ranges listed in the TOC)
- Uses Ace3 with LibSharedMedia and LibDBIcon
- Lightweight saved-variable storage for persistent history/stat tracking

## Best For

- Players who run frequent DeathRoll games
- Guild/community events
- Players who want long-term stats and wager tracking
- Anyone who wants less manual bookkeeping during DeathRoll sessions
