# Verification and client smoke tests

Run the host-side regression suite with Python 3.11+ and Lua 5.1 through Lupa:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/build_release.py --version 2.3.10 --output dist/DeathRollEnhancer-2.3.10.zip
```

The tests execute the actual addon modules with mocked WoW/Ace boundaries. They cover trusted roll events, turn order, self-duels, localized/positional roll formats, full player identities, challenge expiry and terms, popup lifecycle, stable record IDs, safe legacy migration, trade settlement, stale timers, widget reuse, and package references. They also compile all active and embedded Lua files under Lua 5.1. Locale fixture strings exercise parser behavior; they do not certify every client's translations.

These checks cannot reproduce WoW's secure execution, actual secret-value enforcement, chat restrictions, server event ordering, or rendering. A passing host suite is not an in-game compatibility certification.

## Target client

Dedicated Forever and Camelot TOCs and the generic TOC include official Forever's `16001` interface, based on the inspected 1.60.1.70755 client source. Name handling uses `RegionalUniqueNamesEnabled()` and the client's surname formatter rather than assuming that a second unit-name return is a realm. Required Ace3 modules are embedded at the revision documented in `Libs/SOURCES.txt`, including upstream Forever saved-profile fixes.

A server using a modified or older client still needs its exact build checked. Record the output of `/dump GetBuildInfo()` and the client locale before testing. Do not change metadata to imply compatibility with an untested build.

## In-game acceptance checks

1. Back up `WTF` SavedVariables before testing migration. Install the ZIP's `DeathRollEnhancer` folder in the target client's `Interface/AddOns`. Enable Lua errors (`/console scriptErrors 1`) and test without a separately installed Ace3. Optional minimap/media libraries remain optional.
2. Open `/dr`, all four tabs, `/dr config`, `/drh`, `/dr edit`, and Export. Close/reopen each; resize the main window. Switch tabs during your turn, the opponent's turn, and a pending roll.
3. Play both challenge directions with two clients. Check initial maximum, wager, opener=1, normal wins/losses, and self-duels. Out-of-turn rolls and crafted emotes must not alter outcomes; wrong ranges on the expected turn must be rejected.
4. Test a full surname, a UTF-8 name, and—where the client supports realms—a remote realm-qualified name. Compare actual target, whisper sender, and system-roll identities. On a non-English client verify its `RANDOM_ROLL_RESULT` format.
5. Send/accept/decline/expire challenges, including zero wager after a nonzero wager. Test dialog replacement, expiry during combat, close/Escape/controller B, and accept after leaving combat. Enable the native controller UI and check for blocked actions. During restricted chat states the addon should ignore inaccessible values, not try to decode them.
6. Keep an editor open, finish another game, then save/delete the original selection. Verify merge and dedupe preserve distinct identical-looking games and aggregate-only legacy history. Use quoted full names when merging, e.g. `/dr merge "Alice Smith" "Alice Jones"`.
7. Finish a tracked game, reload, and settle within five minutes. Check unrelated partners and same-first-name characters cannot settle it. If multiple games match one payment, the addon refuses to guess; assign that payment once through `/dr edit`. A subsequent separate trade can settle the remaining game.
8. Broadcast stats through available channels. Failures/restrictions must not falsely report success. Re-enable the addon and verify controls and minimap registration recover.

Legacy rows without reliable chronology are preserved. Their relative cross-player ordering cannot be recovered. When older releases retained totals but discarded detailed rows, a migration checkpoint preserves known streak history; outcome edits/deletions to pre-checkpoint records invalidate the current-streak checkpoint and replay the retained rows while preserving historical maxima. Missing older outcomes still cannot be reconstructed. `/dr dedupe` removes only duplicate records with proven matching IDs and content, not merely matching dates/results/wagers.

## Forever research sources

Reviewed 2026-11-04 against primary maintainer reports and patches:

- [Questie #7970](https://github.com/Questie/Questie/issues/7970) and [popup isolation fix](https://github.com/Questie/Questie/commit/b7cd18f791cfcaa8696b8e580c1798b7ddc86016): Blizzard StaticPopup can enter blocked-action loops with Forever's controller UI. DeathRoll used the same API; its challenge/reset/delete dialogs now use a retained, addon-owned AceGUI window. Applicability is inferred from the shared API path; the original hang has not been reproduced with DeathRoll in-game.
- [ShamanPower chat fix](https://github.com/taubut/ShamanPower/commit/c1a9ec450d5eccd05f2fbf9449078e214fd2fdb7) and [FrontierScout restriction handling](https://github.com/xsansebastian/FrontierScout/commit/fda5e044e7d3e2b4fbe228865dbd3e05f4354e18): check `C_ChatInfo.InChatMessagingLockdown` before sending. DeathRoll now checks it alongside existing realm restrictions and reports failed challenge whispers.
- [Questie's dual manifests](https://github.com/Questie/Questie/commit/c32cb8825c79cc4d85a0b9056372d7f4a891339c): ship both `_Forever.toc` and `_Camelot.toc`; DeathRoll now packages both with the same runtime load order.
- [Ace3 Forever surname fix](https://github.com/WoWUIDev/Ace3/commit/5e2e0d3b3fd125ef1518744c6a9dd21f68f6e773), [regional character keys](https://github.com/WoWUIDev/Ace3/commit/afabc91e780eac94c291616d8b24dbba55134e4d), and [RP-PVP support](https://github.com/WoWUIDev/Ace3/commit/ac3d1225037e0dc74e025a72342c0f7824aae147): already included in the pinned library. DeathRoll uses `UnitNameUnmodified` and regional surname formatting too.

Questie's quest-objective, gossip, and instance aura fixes do not apply to this addon's features. No workaround for an unrelated subsystem is included. Research does not certify a private server's modified client or replace the smoke tests above.
