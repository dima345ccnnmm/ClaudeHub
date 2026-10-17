# ClaudeHub DOORS v0.4.4

- Removed Fast Interact, Instant Prompts, Prompt Clip, Prompt Reach Multiplier and their old controls/handlers.
- Removed the entire Exploits tab, including hazard bypasses, future module-removal switches, audio-removal
  controls and their background scanning/mutation handlers. Character/Visuals controls outside that tab remain.
- Renamed Speed Boost to Legit Speed Boost. Removed the adjustable slider; boost is always base WalkSpeed +4,
  without compounding. Turning it off/unloading restores the current game-owned baseline.
- Removed explanatory UI paragraphs beneath controls and the empty Read First panel. Home author/license
  information and functional status labels remain.
- Auto Closet accepts only Rush, Ambush, Blitz, A-60, A-120, Frozen Ambush, GlitchRush and GlitchAmbush aliases.
  Eyes, Seek, Screech, Lookman, Jeff, Sally, Monument and Gloombat Swarm do not trigger it. Its ignore list
  includes only allowed Rush-like labels. Empty-spot, prompt reach/LOS and current-room checks remain.
- Auto Interact fully uses the supplied Abysall source's blacklist, TriggerPrompt function, debounce and
  Heartbeat loop. These blocks are byte-for-byte source matches, using local dependency/control mappings.
  Source FirePrompt/ForceFirePrompt fallback queue and visibility/hold retries are included with unload
  instrumentation. The previous ClaudeHub interaction worker, extra filters, range cap and cooldown logic
  are removed. Source-style ParentRoom preparation is retained/restored, so the copied room filter works.
- Native Auto Interact therefore follows the original behavior, including no extra ClaudeHub menu/focus gate,
  no native-call error-to-fallback substitution, and the source's disabled LongPushPrompt/BigPropPrompt exceptions.
  These are intentional consequences of the requested full copy, not additional overrides.
- Preserved room-based ESP, entity identity, Scriptable Third Person and TweenService notification animation.
- Config folder changed to configs-v044; no automatic saved-config loading.
- Loader v1.1.0 and standalone lobby v0.4.1 are unchanged.

Validation: all three scripts compile. Deterministic tests pass for removed UI/handler absence,
fixed +4/noncompounding/external-baseline/restore, full source native interactions and ignore filters,
ParentRoom preparation, source LongPush exception, original fallback visibility/hold/restore,
pending fallback unload/thread cleanup, allowed/disallowed Auto Closet entity lists, retained ESP,
TweenService lifecycle, standalone lobby and loader routing/errors. The copied source block is checked
by exact string comparison and SHA256. These are local mocks, NOT a live Roblox/DOORS/executor test.
