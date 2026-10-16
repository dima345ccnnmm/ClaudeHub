# ClaudeHub DOORS v0.4.3

## Interaction port

- Copied TriggerPrompt's blacklist, inventory/durability, consumable, lock, shop, dropped-item,
  currency, minecart and closed-drawer filters from the user-supplied Abysall Main.luau (MIT).
  Dependencies are renamed to ClaudeHub controls, optional UI paths are guarded, and ancestor
  checks additionally support prompts attached to Handle/Attachment descendants.
- Auto Interact now scans all enabled eligible nearby prompts using each prompt's own
  MaxActivationDistance, as the reference does. Removed the unrelated 8-stud cap and nearest-only
  arbitration. Activation cadence is 1/60 s with per-prompt cooldown / duplicate queue prevention.
- Native fireproximityprompt is used when available. Otherwise the source's camera-anchor
  technique is ported: temporarily move the selected prompt onto a tiny local camera-adjacent
  part, wait for visibility / bounded retry, InputHoldBegin + InputHoldEnd, then restore its parent,
  enabled state, distance, hold time and line of sight. Original 99999 fallback distance is only
  temporary after the original distance/room/Enabled checks. No game remotes are invented.
- Fallback is cancellable on menu/text/focus/room/feature change, bounded by a timeout, and
  restored on unload/errors. Native API failure falls back too. No analytics/root loader executed.
- Fast Interact is activated by its checkbox OR inline F key, rather than requiring both together.
  Auto Interact is checkbox OR R. Both use the same source-derived firing backend and queue.
- Reach updates immediately on setting changes and prompt registration. Base distance does not
  compound. Game-authored distance changes are tracked. Multiplier range is 1..2 like the source.
  Only the current room gets extended reach; while multiplier >1, other-room prompts are temporarily
  disabled, restored on room entry or multiplier reset. CurrentRoom is the local player's attribute.
  Missing room metadata remains a limitation. Prompt Clip and Instant Prompts are separate controls.

## Notifications and UI

- Replaced 5Hz manual position/progress interpolation with TweenService, following Abysall's
  native-tween approach. Layout tweens run only on stack changes; lifetime tweens run once per card.
  Closing, expiry, replacement and unload cancel owned tweens. Styles remain local layouts;
  native achievement widgets and third-party STX notification loaders are not loaded.
- Abysall layout matches the source's 420x50 dimensions, .4 background transparency and compact
  icon/title/body arrangement. Doors and STX retain their separate locally recreated layouts.
- Removed explanatory UI paragraphs below controls. Functional status labels, Home author credit
  and the complete source MIT license remain. Settings folder is configs-v043; no automatic config load.
- Retained v0.4.2 whole-rig entity classification/current-room ESP and earlier camera/Dupe fixes.
- Loader v1.1.0 and standalone lobby v0.4.1 are unchanged.

## Validation

All three scripts compile. Local deterministic tests pass for the existing run/ESP/camera/lifecycle
features, source filters, all-nearby interaction beyond 8 studs, F activation, native success/error/nil
API fallback, fallback hold events/restoration/timeouts/menu/focus/room/unload, immediate/scoped and
noncompounding reach, TweenService creation/cancellation without 5Hz restarts, lobby and loader.
Tween mock records parameters/endpoints; it does not prove actual animation smoothness.
No live Roblox/DOORS/executor test has been performed. Server/game/executor differences may still
prevent an interaction; a successful client-side request is not proof of a server-side result.
