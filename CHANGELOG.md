# DOORS v0.3.0

## Requested fixes

- Exit ESP targets only named Door leaf parts, with separate outlines for double doors. Wall-containing outer models are never highlighted as a fallback.
- Visuals > Entity ESP now groups the toggle, multi-type filter, quick single-type selector and Select all / Clear actions together.
- Main > Fast Interact: enable the checkbox, close the menu and hold F. Rebind via the inline badge; Hold/Toggle modes are available. Uses normal prompt range and line-of-sight. Locks/purchases, hiding/exit, dropped items and fake-door/hazard prompts are ignored by default.

## Fifteen additional functions adapted from Abysall

1. Loot / consumables ESP.
2. Chest ESP.
3. Gold / stardust ESP.
4. Ladder ESP.
5. Player ESP.
6. Speed boost.
7. Enable jumping.
8. Enable sliding.
9. Infinite jumps.
10. No acceleration (physical-properties adaptation).
11. Remove fog.
12. Transparent occupied hiding spot.
13. Item spawn notifications.
14. Low oxygen warning.
15. Haste timer display / warning.

Objective labels and hiding-spot names are also expanded. All gameplay toggles start OFF. Existing inline keybinds, HUD dragging and cleanup are retained.

## Updating

Replace Doors.luau in the repository, add/update THIRD_PARTY_NOTICES.md, unload the old DOORS window and run the existing Loader.luau again. Loader.luau and the universal ClaudeHub.luau do not need changing.

Credit: FireBacon (bocaj111004), Abysall, MIT. The full license is embedded in Doors.luau and included in THIRD_PARTY_NOTICES.md. No upstream analytics is included.

Syntax and deterministic client/UI mock tests passed. Real Roblox behavior, server validation and executor compatibility still require live testing. No blanket Archives/Stairwell support is claimed.
