# Third-party notices — ClaudeHub DOORS v0.4.4

## Abysall

Original author: **FireBacon (bocaj111004)**
Source: https://github.com/bocaj111004/Abysall
Reference used for this release: user-supplied Main.luau (195949 bytes), Lobby.luau,
Loader.luau and screenshots. The earlier reviewed repository revision was
66d4192d00d9b824a304b654bc2d2eb89c3b372b; uploaded files are not asserted to match it.

The full AutoInteractBlacklist, TriggerPrompt, TriggerDebounce and AutoInteract Heartbeat block
is copied verbatim from that Main.luau, not rewritten into ClaudeHub's previous interaction worker.
Exact copied block SHA256: a4752443af4bc72e1016141bb2b68460376441631fc3839653f5d9b157a20bfa.

Functions.FirePrompt / ForceFirePrompt and the camera-anchor fallback are also included from the
source. Lifecycle instrumentation stores a worker handle and temporary prompt state for unload
cancellation/restoration. ClaudeHub supplies local dependency/control mappings, prompt registration,
source-style ParentRoom metadata, current character/camera/inventory context and ready/alive guards.
The source's 1/60 interval, item/lock/durability filters, LongPushPrompt/BigPropPrompt exceptions,
per-prompt fallback queue and hold/visibility retries are retained. Removed Instant Prompts, Fast
Interact, Prompt Clip and reach-multiplier controls are not reintroduced by this port. Temporary
fallback changes are internal to one interaction and restored afterwards, as in the source.

Other adapted portions include entity/objective/item/hiding/chest aliases, entity highlighting,
UI grouping, camera/effect controls, character/library/padlock/anchor/breaker/hiding workflows,
notification filters and standalone lobby elevator/achievement/code-request patterns.
The old Exploits tab and all of its hazard-bypass, module-removal and audio-removal handlers are
removed in this release. No source root loader, analytics, anti-cheat hooks or infinite-item module
is executed. MIT authorship/license are retained in this file and Doors.luau.

ClaudeHub keeps its bounded BillboardGui/Highlight renderer and TweenService notification layouts.
Abysall/Doors/STX styles are local layouts; native achievement UI and external STX scripts are not loaded.
Auto Closet uses an explicit Rush/Ambush/Blitz/A-60/A-120/variant allowlist, respects nearby empty-spot
metadata and does not auto-exit. Legit Speed Boost is a name for a fixed +4 local adjustment, not an
anti-cheat-safety guarantee. Server/game/executor compatibility is not guaranteed.

## UI dependency

ObsidianUltra: https://github.com/joustingmatch/ObsidianUltra
Original Obsidian documentation: https://docs.mspaint.cc/obsidian
ClaudeHub does not claim authorship of the external UI library.

## Abysall license

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
