# ClaudeHub DOORS v0.4.2

Run module update. Loader v1.1.0 and standalone Lobby v0.4.1 are unchanged.

- Entity identity: SeekMovingNewClone / SeekMoving / SeekRig / Seek, Screech and GlitchScreech
  use their own selectable labels and notification filters. Whole entity ancestors suppress
  child FigureRig / Eyes aliases, so Seek no longer creates a child Figure marker and
  Screech no longer creates an Eyes marker/alert.
- Eyes detection is conservative: a world-level Model is required. Parts, room decorations,
  camera decorations, Tools and Accessories named Eyes are not treated as the Eyes entity.
  Unknown nested Eyes variants are deliberately omitted rather than guessed.
- Room ESP defaults to Current room, using the local player's CurrentRoom (not LatestRoom).
  Switching rooms hides previous room objects immediately; returning restores markers from
  retained candidates. Global entities/players/drops without a room owner remain visible.
  Missing CurrentRoom falls back to loaded-room visibility. All loaded rooms is optional.
- Auto Interact: toggle for continuous operation OR hold the rebindable R key temporarily;
  Fast Interact retains its separate master + F key behavior. Both share one activation worker.
- Independent Auto Interact Ignore List: Glitch Fragments, Jeff Items, Dropped Items, Currency,
  Minecarts, Locks. First three selected by default, matching the supplied source/screenshots.
  Hiding/exit/shop-dialogue/fake-door/hazard actions and closing drawers are guarded separately.
  Lock prompts additionally require an inventory key; disabled prompts remain disabled.
- Drawer/chest prompts: model-owned prompts use model pivots; line of sight accepts their own
  immediate furniture geometry, never an entire room or an unrelated wall. Activation still
  respects prompt range, local room, enabled state, focus, menu state and cooldowns.
- Notifications: distinct locally recreated Abysall, Doors and STX layouts, separate title/body,
  warning icon where applicable, lifetime strip, slide-in, close button and draggable stack.
  These are local recreations, not a claim of pixel-perfect screenshots or native game UI cloning.
- Prior strict Dupe/door-leaf ESP, Scriptable Third Person, initialization guards and lobby
  routing regressions retained. Abysall attribution and full MIT license retained. No analytics.

Validation: all three modules compile with Luau. Deterministic tests cover reported entity
mislabels/deduplication, room switch/return and missing room data, model pivots and drawer LOS,
wall rejection, continuous/temporary input, all ignore categories/locks, card styles/expiry/close,
previous run features, lobby workflow and loader routing/failures. NOT live Roblox/DOORS testing.
