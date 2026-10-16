# Third-party notices — ClaudeHub DOORS v0.4.3

## Abysall

Original author: **FireBacon (bocaj111004)**  
Source: https://github.com/bocaj111004/Abysall  
Earlier reviewed revision: `66d4192d00d9b824a304b654bc2d2eb89c3b372b`  
Additional reference: user-supplied `Main.luau`, `Lobby.luau`, `Loader.luau` and screenshots. The uploaded files are not asserted to match that Git revision.

Adapted portions include entity/objective/item/hiding/chest aliases; entity registration and highlight preparation; UI grouping and feature-control patterns; camera and visual-effect adapters; local hazard/audio switches; interaction, character, library-code, padlock, anchor, breaker and hiding automation patterns; notification filters and styles.

ClaudeHub keeps its own bounded BillboardGui/Highlight renderer, notification layouts and lifecycle. Abysall/Doors/STX notification styles are local visual recreations; no notification component or upstream root loader is downloaded/executed. The original source analytics, health-kill handlers and persistent anti-cheat hooks are not included. FireBacon's MIT copyright is retained here and in Doors.luau.

Door ESP targets leaf parts only, never the wall-containing parent. ESP supports at most 240 labels/tracers and 24 active Highlights. New gameplay features are opt-in. Fast Interact and Auto Interact share one worker; optional reach/clip overrides are separate, explicit settings. Auto Closet respects occupancy, prompt reach/line-of-sight and never automatically exits when a threat disappears.

Selected game remotes are used only after explicit user action/feature enable: public chat notifications, known-code padlock/anchor, breaker instructions, hiding exit, door opening, Play Again, Lobby and Revive. Revive is double-click confirmed and may consume the user's revive; no purchase API is invoked.

Not ported: Anticheat Bypass, Velocity Manipulation, Position/Crouch Spoof, Infinite Items, No Damage hooks, Eyes/Lookman remote spoof, Auto Heartbeat and random-code guessing. These have no pretend-enabled placeholder toggles. Client-local hazard and visual suppression are NOT server-side invulnerability; cached modules or server checks can defeat them.

Compile and deterministic local mock checks passed. This is not a live Roblox/DOORS/executor test. Archives/Stairwell-specific compatibility is not claimed. Unknown layouts and unavailable game adapters are skipped or reported instead of waiting forever for old object paths.

## v0.4.1 additions

A standalone DoorsLobby.luau adapts the supplied Lobby.luau's elevator join/creation,
quick-play, unlocked-achievement and code-request patterns. It does not execute Abysall's root loader
or analytics, does not load run-only camera/ESP adapters, and does not promise access to locked destinations.
Old sample codes may be expired. Revive/server-damage bypasses are not present in the lobby module.

Third-person now supports DOORS Scriptable cameras, uses a late render binding, and restores owned
avatar transparency and camera offset. Strict Dupe mode requires a Hidden BasePart with a replicated
TouchTransmitter; unknown shapes are omitted rather than labeled from a decorative name alone.
Compatibility mode is optional and less precise. Loader v1.1 routes lobby Place ID 6516141723 to
DoorsLobby.luau, DOORS run places to Doors.luau, other universes to the unchanged ClaudeHub.luau.
Direct execution of Doors.luau in the lobby delegates to DoorsLobby.luau too.

## UI

ObsidianUltra: https://github.com/joustingmatch/ObsidianUltra  
Original Obsidian documentation: https://docs.mspaint.cc/obsidian  
The existing external UI dependency remains unchanged; ClaudeHub does not claim authorship of that library.

MIT License

Copyright (c) 2026 FireBacon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## v0.4.2 local changes

Whole-rig Seek/Screech/Eyes identity, current-room ESP lifecycle, separate Auto Interact filters, model-pivot/furniture LOS handling and notification card layouts are ClaudeHub adaptations of the supplied reference patterns. Global unowned threats remain visible across room changes. Native DOORS achievement UI is not cloned.

## v0.4.3 copied interaction routines

TriggerPrompt filter logic was copied from the user-supplied Abysall Main.luau, with local control/dependency
names and optional UI guards adapted. The fallback follows that source's temporary camera-adjacent prompt
reparenting, hold-input and field-restoration technique; ClaudeHub adds bounded, cancellable lifecycle and
room/range checks. Auto Interact scans all eligible prompts at 1/60 s; the previous unrelated distance cap is
removed. Reach uses source-style base-distance multiplication with immediate callbacks and extra current-room
scoping. Notification animation uses TweenService rather than 5Hz manual interpolation. Full original MIT
copyright remains in this file and Doors.luau. No source analytics or external root loader is executed.
