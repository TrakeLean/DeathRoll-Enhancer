# Verification and client smoke tests

Run the host-side regression suite with Python 3.11+ and Lua 5.1 through Lupa:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/build_release.py --version 2.4.1 --output dist/DeathRollEnhancer-2.4.1.zip
```

The tests execute the actual addon modules with mocked WoW/Ace boundaries. They cover trusted roll events, turn order, self-duels, localized/positional roll formats, full player identities, challenge expiry and terms, popup lifecycle, stable record IDs, safe legacy migration, trade settlement, stale timers, widget reuse, and package references. They also compile all active and embedded Lua files under Lua 5.1. Locale fixture strings exercise parser behavior; they do not certify every client's translations.

These checks cannot reproduce WoW's secure execution, actual secret-value enforcement, chat restrictions, server event ordering, or rendering. A passing host suite is not an in-game compatibility certification.

## Client version matrix

Reviewed 2026-11-04. All families share the same runtime and generic multi-interface TOC; Forever also has its existing dedicated manifests. Interface numbers identify package targets, not proof of in-game success.

| Client family | Source version | Interface |
| --- | --- | --- |
| Retail | 12.1.5 | 120105 |
| Classic Era / Hardcore | 1.15.9 | 11509 |
| TBC Anniversary | 2.5.6 | 20506 |
| Wrath Classic | 3.4.5 | 30405 |
| Cataclysm Classic | 4.4.2 | 40402 |
| Mists Classic | 5.5.4 | 50504 |
| Titan Reforged (China) | 3.80.2 | 38002 |
| Forever | 1.60.1 | 16001 |

Current build evidence comes from the [Retail](https://github.com/Gethe/wow-ui-source/commit/297d7aaaa736f346b3e036f38ee088eaf7f8c07f), [Era](https://github.com/Gethe/wow-ui-source/commit/4192ac60067fc55566182291bc67c85dd9b6794d), [TBC Anniversary](https://github.com/Gethe/wow-ui-source/commit/68e0a2ec559d9761dfc4e7f864c3944f9d758a49), [Mists](https://github.com/Gethe/wow-ui-source/commit/e5d9b3a22c3f0f6f41ebac0e454f4969594261cf), and [Titan](https://github.com/Gethe/wow-ui-source/commit/7014c309a25338905c41dc3799a93f9719ebb533) UI source snapshots. Historical Wrath/Cataclysm and Forever targets also appear in the [pinned Ace3 manifest](https://github.com/WoWUIDev/Ace3/blob/ac3d1225037e0dc74e025a72342c0f7824aae147/Ace3.toc). Wrath and Cataclysm entries retain older Classic compatibility; they do not imply currently available public realms. [Blizzard identifies Titan Reforged as a China offering](https://worldofwarcraft.blizzard.com/en-us/news/24250385/).

`tests/test_clients.py` exercises actual addon flows with modern namespaced APIs, legacy global APIs, absent Settings/secret APIs, and Forever surname APIs. It also executes the actual bundled Heading widget with an already registered upstream widget. These feature profiles are simulations, not eight installed WoW clients. Run the acceptance checks below on each intended client. Original 1.12, 2.4.3, and 3.3.5 clients and arbitrary private-server patches are not covered.

### Compatibility research

- [Blizzard's deprecated emote wrapper](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_DeprecatedChatInfo/Deprecated_ChatInfo.lua) maps `DoEmote` to `C_ChatInfo.PerformEmote` only when compatibility aliases are enabled. DRE now prefers the modern function and isolates cosmetic failures after result persistence.
- [Blizzard's unit API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) marks `UnitIsUnit` comparisons as potentially secret. Challenge buttons compare accessible canonical names instead.
- [DBM's Say/Yell handling](https://github.com/DeadlyBossMods/DeadlyBossMods/blob/master/DBM-Core/modules/objects/Yell.lua) avoids automatic outdoor messages. DRE conservatively defers all event-driven group Say announcements to an explicit click/slash action; grouped channels remain automatic.
- [Campkeeper's chat handling](https://github.com/Vikquick/Campkeeper/blob/main/Campkeeper/Comm/Comm.lua) documents Forever's continuously asserted addon-message restriction flag despite successful sends. DRE no longer applies that flag to ordinary chat, while retaining actual lockdown checks and protected calls.
- [Legacy Wrath options](https://github.com/Gethe/wow-ui-source/blob/3.4.3/Interface/FrameXML/InterfaceOptionsFrame.lua) predate the modern Settings integration required by bundled AceConfig. DRE skips only the Blizzard Settings registration when those APIs are absent; `/dr config` and the in-window Settings tab remain available.
- [BigWigs packaging](https://github.com/BigWigsMods/packager#building-for-multiple-game-versions) supports multiple interface versions in one TOC/ZIP. Package tests check every listed target and all manifest load orders.

## Forever client

Dedicated Forever and Camelot TOCs and the generic TOC include official Forever's `16001` interface, based on the inspected 1.60.1.70755 client source. Name handling uses `RegionalUniqueNamesEnabled()` and the client's surname formatter rather than assuming that a second unit-name return is a realm. Required Ace3 modules are embedded at the revision documented in `Libs/SOURCES.txt`, including upstream Forever saved-profile fixes.

A server using a modified or older client still needs its exact build checked. Record the output of `/dump GetBuildInfo()` and the client locale before testing. Do not change metadata to imply compatibility with an untested build.

## In-game acceptance checks

1. Back up `WTF` SavedVariables before testing migration. Install the ZIP's `DeathRollEnhancer` folder in the target client's `Interface/AddOns`. Enable Lua errors (`/console scriptErrors 1`) and test without a separately installed Ace3. Optional minimap/media libraries remain optional.
2. Open `/dr`, all five tabs, `/dr config`, `/drh`, `/dr edit`, and Export. Close/reopen each; resize the main window. Switch tabs during your turn, the opponent's turn, and a pending roll.
3. Play both challenge directions with two clients. Check initial maximum, wager, opener=1, normal wins/losses, and self-duels. Out-of-turn rolls and crafted emotes must not alter outcomes; wrong ranges on the expected turn must be rejected.
4. Test a full surname, a UTF-8 name, and—where the client supports realms—a remote realm-qualified name. Compare actual target, whisper sender, and system-roll identities. On a non-English client verify its `RANDOM_ROLL_RESULT` format.
5. Send/accept/decline/expire challenges, including zero wager after a nonzero wager. Test dialog replacement, expiry during combat, close/Escape/controller B, and accept after leaving combat. Enable the native controller UI and check for blocked actions. During restricted chat states the addon should ignore inaccessible values, not try to decode them.
6. Keep an editor open, finish another game, then save/delete the original selection. Verify merge and dedupe preserve distinct identical-looking games and aggregate-only legacy history. Use quoted full names when merging, e.g. `/dr merge "Alice Smith" "Alice Jones"`.
7. Finish a tracked game, reload, and settle within five minutes. Check unrelated partners and same-first-name characters cannot settle it. If multiple games match one payment, the addon refuses to guess; assign that payment once through `/dr edit`. A subsequent separate trade can settle the remaining game. Test incoming wins and outgoing losses, cancel/reopen, changed offers including zero, and gold on both sides (manual assignment required).
8. Cancel an abandoned game with the button and `/dr cancel`, including while a roll is pending and from another tab. Confirm there is no outcome or new pending payment, earlier unpaid games remain, and a new opponent can be challenged. Check the action row at narrow and normal window sizes.
9. Enter letters, commas, fractions, and out-of-range amounts in `/dr edit`: Save must leave data and pending payments unchanged and keep the editor open. Valid edits and deletions must refresh History without switching tabs; delete the final player and finish the first game with History open.
10. With LibDBIcon installed, lock and unlock the minimap icon and verify dragging resumes.
11. Enable automatic win/loss emotes and finish games with the API available and during a restricted state; results must save regardless of whether an emote plays. Broadcast stats through available channels. Failures/restrictions must not falsely report success. Re-enable the addon and verify controls and minimap registration recover.

Legacy rows without reliable chronology are preserved. Their relative cross-player ordering cannot be recovered. When older releases retained totals but discarded detailed rows, a migration checkpoint preserves known streak history; outcome edits/deletions to pre-checkpoint records invalidate the current-streak checkpoint and replay the retained rows while preserving historical maxima. Missing older outcomes still cannot be reconstructed. `/dr dedupe` removes only duplicate records with proven matching IDs and content, not merely matching dates/results/wagers.

## Group round acceptance checks

1. Use three nearby players; install the addon only on the host. Open `/dr group`, add full names in order, select the channel and start at 100. Complete a full rotation, then a losing roll of 1. Confirm exactly one loser, no 1v1 result, and no new pending trade wager.
2. Mix client languages and test same-first-name/different-surname participants. Wrong players, wrong ranges, forged emotes, and repeated rolls out of turn must not advance the round. A valid roll equal to the current maximum must still advance the turn.
3. Switch tabs and close/reopen the window mid-round. Verify the correct turn/range and disabled roster controls. Test host roll failure/timeout, then cancel and restart. Restart must display and use the original roster/order/range even after editing the next-round draft.
4. With Say selected, each accepted roll must update the local turn/result without sending chat automatically. Click Announce (or `/dr group announce`) to send that latest state. Repeat with Party/Raid/Instance and verify automatic announcements. Leave chat range/group or trigger chat restrictions. The local round must remain usable with a visible announcement error where the client reports one; retry with Announce. Say delivery and actual roll visibility still depend on range. Party selection must not silently send to Raid/Instance. Cancel if a participant disconnects or leaves; do not skip them or declare a result automatically.
5. Start with an earlier unpaid 1v1 game involving a participant. Finish the group round and trade its payout: the old record must remain unchanged, with instructions to assign any earlier payment through `/dr edit`. Check this again after reload. Trades for unrelated pending opponents should still settle normally. Settle group payouts before starting new trade-tracked 1v1 games: the trade API cannot distinguish a delayed group payout from a new 1v1 payment.
6. Verify at narrow/normal window sizes and with the controller. Disable/reload during a round: no result is recorded, and the host must start a fresh round. The group log is deliberately session-only.

## Forever research sources

Reviewed 2026-11-04 against primary maintainer reports and patches:

- [Questie #7970](https://github.com/Questie/Questie/issues/7970) and [popup isolation fix](https://github.com/Questie/Questie/commit/b7cd18f791cfcaa8696b8e580c1798b7ddc86016): Blizzard StaticPopup can enter blocked-action loops with Forever's controller UI. DeathRoll used the same API; its challenge/reset/delete dialogs now use a retained, addon-owned AceGUI window. Applicability is inferred from the shared API path; the original hang has not been reproduced with DeathRoll in-game.
- [ShamanPower chat fix](https://github.com/taubut/ShamanPower/commit/c1a9ec450d5eccd05f2fbf9449078e214fd2fdb7) and [FrontierScout restriction handling](https://github.com/xsansebastian/FrontierScout/commit/fda5e044e7d3e2b4fbe228865dbd3e05f4354e18): check `C_ChatInfo.InChatMessagingLockdown` before sending. DeathRoll checks actual messaging lockdown and reports failed challenge whispers. The addon-message-only flag is excluded from ordinary chat as described above.
- [Questie's dual manifests](https://github.com/Questie/Questie/commit/c32cb8825c79cc4d85a0b9056372d7f4a891339c): ship both `_Forever.toc` and `_Camelot.toc`; DeathRoll now packages both with the same runtime load order.
- [Ace3 Forever surname fix](https://github.com/WoWUIDev/Ace3/commit/5e2e0d3b3fd125ef1518744c6a9dd21f68f6e773), [regional character keys](https://github.com/WoWUIDev/Ace3/commit/afabc91e780eac94c291616d8b24dbba55134e4d), and [RP-PVP support](https://github.com/WoWUIDev/Ace3/commit/ac3d1225037e0dc74e025a72342c0f7824aae147): already included in the pinned library. DeathRoll uses `UnitNameUnmodified` and regional surname formatting too.

Questie's quest-objective, gossip, and instance aura fixes do not apply to this addon's features. No workaround for an unrelated subsystem is included. Research does not certify a private server's modified client or replace the smoke tests above.

## Trade gold research

The trade review on 2026-11-04 checked these primary sources:

- [Gargul TradeWindow](https://github.com/papa-smurf/Gargul/blob/e3b8d0f3da577a8dcacd84d6f2f277f62bd405f0/Classes/TradeWindow.lua#L355): reads `GetPlayerTradeMoney`/`GetTargetTradeMoney`, keeps the snapshot through `TRADE_CLOSED`, and records success from `UI_INFO_MESSAGE == ERR_TRADE_COMPLETE`. DeathRoll uses the same success signal and now also ignores updates when the trade is closed/hidden. This guard is defensive; no live Forever trace has been collected to establish that late zeroing occurs on this client.
- [Gargul Forever identity fix](https://github.com/papa-smurf/Gargul/commit/b451ec2cf630e8f34dc0d9de4cf67e7901332dab): surnames must not be treated as realm names. DeathRoll already preserves full regional names and now tests them through the complete trade event sequence.
- [GBankClassic trade handlers](https://github.com/GrumpyPlayer/GBankClassic/blob/1d2c12153fb7e745691a4af9e46b09e7c0e5c56f/Modules/Events.lua#L906): separately tracks offered money and discards the snapshot on `TRADE_REQUEST_CANCEL`. DeathRoll now clears cancelled snapshots too; this is a lifecycle comparison, not a claim that GBankClassic certifies Forever compatibility.
- [Forever client trade frame](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/TradeFrame.lua) and [trade API declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeInfoDocumentation.lua): retain the trade events, NPC partner unit, and readable money interfaces used here. The money-setting UI is restricted; DeathRoll only observes the player's manually completed trade.

The verified accounting defect was independent of client version: receiving 1 gold while paying 2 gold could incorrectly settle a pending win as 1 gold. Two-sided offers now require manual assignment. The new tests execute actual handlers with simulated client events; they are not a substitute for two-player in-game validation.
