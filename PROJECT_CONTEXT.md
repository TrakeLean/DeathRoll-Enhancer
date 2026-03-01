# Project Context

## Overview

DeathRollEnhancer is a single World of Warcraft addon focused on DeathRoll games, stats tracking, wager tracking, history browsing, and challenge handling. The current version in the repo is `2.3.2`.

The addon uses:

- Ace3 (`AceAddon`, `AceConsole`, `AceEvent`, `AceConfig`, `AceConfigDialog`, `AceDB`, `AceGUI`)
- `LibSharedMedia-3.0`
- `LibDBIcon-1.0`
- `LibDataBroker-1.1` when available

Saved variables:

- `DeathRollEnhancerDB`
- `DeathRollEnhancer_DebugExport`

## Load Order

The addon manifest is `DeathRollEnhancer.toc`, which loads modules in this order:

1. `Core.lua`
2. `Database.lua`
3. `UI.lua`
4. `Events.lua`
5. `Minimap.lua`

This load order matters. `Core.lua` defines placeholder methods that later files replace with full implementations.

## Core Architecture

`Core.lua` is the main runtime hub.

Primary responsibilities:

- create the Ace3 addon object
- define the default AceDB profile structure
- register slash commands
- register addon options
- register and handle chat and target events
- run challenge whisper logic
- detect and deduplicate rolls
- manage active game state
- manage debug buffering and debug export
- define popup dialogs for challenge acceptance and record deletion

Lifecycle:

- `OnInitialize()`: creates the database, initializes caches, registers commands and options
- `OnEnable()`: registers events and initializes UI/minimap/shared media
- `OnDisable()`: clears active game state, spicy duel state, and UI references

Compatibility:

- Includes a `C_Timer.After()` shim for clients where `C_Timer` is missing

## Runtime State Models

There are several major state containers:

- `self.db.profile`: persistent config and history
- `self.gameState`: current DeathRoll game state
- `self.spicyDuel`: current Spicy Duel state
- `self.recentRolls`: short-term observed roll cache
- `self.processedRolls`: short-term dedupe cache
- `self.pendingChallenge`: active whisper-based incoming challenge
- `self.UI`: live UI references and transient UI state

### `gameState`

Typical fields:

- `isActive`
- `target`
- `initialRoll`
- `currentRoll`
- `wager`
- `playerTurn`
- `rollCount` (used for self-duels)

### `spicyDuel`

Typical fields:

- `isActive`
- `target`
- `myHP`
- `opponentHP`
- `round`
- `myStance`
- `myRoll`
- `opponentStance`
- `opponentRoll`

## Slash Commands

Main commands:

- `/dr` or `/deathroll`: open main window
- `/dr config` or `/dr options`: open options
- `/dr accept`: accept the current pending whisper-based challenge
- `/dr decline`: decline the current pending whisper-based challenge
- `/dr debug`: dump debug buffer and export it to saved variables
- `/dr edit`: open edit recent game records dialog
- `/dr fixgold`: rebuild global gold totals and streaks from history
- `/dr size` or `/dr windowsize`: print the current live and saved window size
- `/drh [player]` or `/deathrollhistory [player]`: show history for a player

## UI System

`UI.lua` builds the visible AceGUI interface.

Main window:

- AceGUI `Frame`
- persisted size/position through AceGUI status table
- user-configurable scale
- default size of `400 x 311`

Visible tabs:

1. `DeathRoll`
2. `Statistics`
3. `History`
4. `Settings`

### DeathRoll Tab

Contains:

- roll input
- `Use My Gold` helper button beside the roll input
- wager inputs (`gold`, `silver`, `copper`) when manual wager mode is active
- a trade-tracking notice instead of wager inputs when `trackWagerByTrade` is enabled
- one main action button
- an embedded `Roll History` panel under the controls

Roll history behavior:

- keeps the full roll log instead of truncating
- uses mouse-wheel scrolling with no visible scrollbar
- appends new entries at the bottom and auto-scrolls down
- phrases roll odds from the player's perspective, showing your chance of winning after your roll and your chance of losing after the opponent's roll
- is explicitly hidden on tab switches to prevent leaking into other tabs

The action button is driven by a state machine:

- `WAITING`
- `ROLLING`
- `WAITING_FOR_OPPONENT`
- `WAITING_FOR_ROLL_RESULT`
- `GAME_OVER`

The same button is reused to:

- start a challenge
- accept a recently observed target roll
- roll during an active game

### Statistics Tab

Shows:

- total games
- wins / losses
- win rate
- gold won / lost
- net profit
- streaks
- optional "fun statistics"

Fun statistics are grouped into:

- Player Relationships
- Gold and Money
- Luck and Streaks

### History Tab

Shows:

- a dropdown of players in history
- a scrollable `Statistics & Recent Games` panel for the selected player
- aggregate stats for the selected player
- recent games for that player

The history content panel has explicit resize-aware height logic so it refreshes correctly when switching players and when the main window changes size.

### Settings Tab

Shows an in-window mirror of the most-used addon settings:

- gameplay toggles
- challenge system toggles
- UI scale and reset actions
- data management actions
- fun-stat toggles

There is also a separate popup history window available through `/drh`.

## Roll Detection System

Roll processing is centralized in `Core.lua`.

Event sources:

- `CHAT_MSG_SYSTEM`
- `CHAT_MSG_TEXT_EMOTE`
- `CHAT_MSG_EMOTE`

Flow:

1. a chat message is captured
2. the code attempts to parse known roll formats
3. `You` is normalized to the current player name
4. a unique roll id is generated
5. the roll is ignored if already processed recently
6. the roll is passed into `HandleDetectedRoll()`

Deduplication:

- `processedRolls` stores recent roll ids
- expiry window is short (default 5 seconds)

Recent roll cache:

- non-self rolls are stored in `recentRolls`
- entries expire after 60 seconds
- cache size is capped

This cache drives the UI's "Accept challenge" behavior when your current target recently rolled.

## Challenge Systems

There are two separate challenge paths.

### 1. Structured whisper-based addon challenge

This is the explicit addon-to-addon system.

Outgoing format:

- `DEATHROLL_CHALLENGE:roll:wager:version`

Incoming behaviors:

- receive whisper
- parse challenge payload
- validate minimum roll threshold
- store `pendingChallenge`
- show a `StaticPopup` accept/decline dialog

Accept path:

- sends `DEATHROLL_ACCEPT`
- targets the challenger
- opens the main window
- pre-fills roll and wager fields

Decline path:

- sends `DEATHROLL_DECLINE`

### 2. Passive chat-observed challenge

This is the "target rolled recently" system.

If the current target has a recent roll in cache:

- the button text changes to indicate the target rolled
- the UI stores that roll in `UI.recentTargetRoll`
- clicking the main button can accept that observed roll as the starting point

This path works even if the other player does not have the addon.

## DeathRoll Gameplay Flow

Main functions:

- `StartChallengeFlow()`
- `StartDeathRoll()`
- `StartActualGame()`
- `PerformRoll()`
- `HandleGameRoll()`
- `HandleGameEnd()`

Normal duel:

1. user targets a player
2. user enters roll and optional wager
3. `StartChallengeFlow()` validates the target and inputs
4. optional structured challenge whisper is sent
5. `StartDeathRoll()` validates again and starts the game
6. `StartActualGame()` seeds `self.gameState`
7. the addon triggers `RandomRoll(1, currentRoll)`
8. observed rolls advance turns until someone rolls `1`
9. `HandleGameEnd()` records the result and clears the active game

Self-duel:

- starts immediately against the player's own character
- every roll alternates between "you" and "opponent-self"
- odd/even `rollCount` is used to determine winner when `1` is rolled

## Database And Persistence

`Database.lua` manages persistent history and derived aggregate maintenance.

### Per-player history

Each player record in `db.profile.history[playerName]` typically stores:

- `gamesPlayed`
- `wins`
- `losses`
- `goldWon`
- `goldLost`
- `recentGames`

### Per-game record

Each `recentGames` entry stores:

- `date`
- `result`
- `goldAmount`
- `initialRoll`
- `timestamp`

Important detail:

- new game records store both a formatted date string and a numeric timestamp
- older records may still be missing `timestamp`
- later functions use `game.timestamp` when present and fall back to parsing `date` for older data

### Global tracking

`db.profile.goldTracking` stores:

- `totalWon`
- `totalLost`
- `currentStreak`
- `bestWinStreak`
- `worstLossStreak`

These values are updated incrementally during normal writes and can be repaired from history.

## Edit / Delete / Repair Systems

The addon includes built-in data maintenance tools.

### Edit records

The edit dialog:

- collects recent games across all players
- sorts them newest first
- lets the user change result, wager, and starting roll
- updates per-player counters
- updates global gold totals

### Delete records

Delete flow:

- user confirms deletion in a popup
- the game is removed from `recentGames`
- per-player counters are decremented
- global gold totals are decremented
- empty player records can be removed entirely

### Repair

`RecalculateGoldTracking()`:

- rebuilds `totalWon` and `totalLost` from all player records
- calls `RecalculateStreaks()`

`RecalculateStreaks()`:

- flattens all games
- sorts oldest first
- replays results to compute current and best/worst streaks

## Fun Statistics System

Fun stats are derived from all player histories and recent games.

Computed examples:

- most played with
- most wins against
- most losses against
- biggest gold mine
- biggest money sink
- nemesis
- victim
- lucky player
- unlucky player
- high roller
- cheapskate
- daredevil
- conservative
- biggest single win
- biggest single loss

These are not stored separately. They are recalculated when needed.

The options UI allows each stat to be toggled individually.

## Minimap System

`Minimap.lua` integrates with `LibDBIcon`.

Features:

- left click opens the main window
- right click opens options
- tooltip shows version and quick gold/streak stats
- supports hide/show and position persistence

Related profile fields:

- `profile.minimap.hide`
- `profile.minimap.minimapPos`
- `profile.minimap.lock`

## Debug System

The addon keeps a rolling in-memory debug buffer:

- `DRE.debugChatBuffer`
- capped by `DRE.maxDebugMessages`

Two output paths:

- `ChatPrint()`: user-facing informational messages, gated by `profile.gameplay.chatMessages`
- `DebugPrint()`: diagnostic messages, always buffered, only shown in chat when `profile.gameplay.debugMessages` is enabled

`/dr debug`:

- prints the buffer contents
- stores a structured export into `DeathRollEnhancer_DebugExport`
- uses saved variables as a persistence mechanism for later inspection

## Options System

The AceConfig options panel includes controls for:

- auto emotes
- sound effects toggle
- gold tracking toggle
- chat messages
- debug messages
- challenge popup enablement
- sending challenge whispers
- trade-based wager tracking
- minimum roll threshold
- UI scale
- resetting window position and size
- minimap icon visibility
- showing summary stats in chat
- cleaning old data
- resetting all data
- exporting data
- editing game records
- toggling each fun statistic

There is also an in-window `Settings` tab that mirrors the same main controls so the user can stay inside the addon window for most common configuration changes.

## Release And Packaging

Release process is documented in `RELEASE_PROCESS.md`.

Supporting scripts:

- `update-version.ps1`
- `update-version.sh`

The `versions/` directory contains:

- previous release zip files
- a `v2.3.1` packaged folder snapshot

The repo currently has no automated test suite.

## Important Quirks And Risks

These are the main codebase quirks to remember before editing.

### Placeholder methods in `Core.lua`

`Core.lua` defines simple placeholder versions of methods that are later replaced by other files.

Impact:

- the load order in the `.toc` must not change carelessly

### Duplicate `UpdateUIScale()` definitions

`UpdateUIScale()` exists in both `Core.lua` and `UI.lua`.

Impact:

- the later `UI.lua` definition wins at runtime because of load order
- both paths should stay behaviorally aligned when scale handling changes

### Mixed AceGUI and raw frame layout

The main UI uses AceGUI widgets for most layout, but the embedded roll history panel uses raw WoW frames created with `CreateFrame()`.

Impact:

- tab cleanup must explicitly hide those raw frames before AceGUI releases tab content
- size and scale changes require manual relayout code in addition to normal AceGUI layout calls

### Dormant Spicy Duel system

The Spicy Duel engine exists in code and has a UI builder function, but it is not wired into the visible tab set.

Impact:

- feature looks partially implemented / hidden rather than fully shipped

### Version surfaces need to stay in sync

Version and edition labels appear in multiple places:

- `Core.lua`
- `UI.lua`
- `DeathRollEnhancer.toc`
- `README.md`
- `CHANGELOG.md`

Impact:

- version and release branding can drift if only one surface is updated

## Recommended Starting Points For Future Work

If returning later, the highest-value files to read first are:

1. `DeathRollEnhancer.toc`
2. `Core.lua`
3. `UI.lua`
4. `Database.lua`
5. `CHANGELOG.md`

If making behavior changes:

- gameplay flow changes usually touch `Core.lua` and `UI.lua`
- data integrity changes usually touch `Database.lua`
- UI wording and controls usually touch `UI.lua` and the options section in `Core.lua`
- release/version changes usually touch `Core.lua`, `DeathRollEnhancer.toc`, `README.md`, and `CHANGELOG.md`
