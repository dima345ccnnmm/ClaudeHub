# ClaudeHub

Roblox client scripts built with [ObsidianUltra](https://github.com/joustingmatch/ObsidianUltra).

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dima345ccnnmm/ClaudeHub/main/Loader.luau"))()
```

Requires an environment that supports `loadstring` and `game:HttpGet`. Not a standard Roblox LocalScript installer.

- DOORS universe (`2440500124`): opens `Doors.luau`.
- Other experiences: opens the existing `ClaudeHub.luau` universal module (v2.16.0).
- Re-running while the loaded window is active will not create another copy.
- Unload from UI Settings before loading again. Failed loads can be retried.
- Re-run the loader after teleporting between places. No teleport auto-execution is installed.

## DOORS v0.1.0 — first playable-test build

- Home: avatar, changelog, Game / Games / Info tabs, floor, latest-room value, population and debug info.
- Fullbright, local flashlight and custom FOV, with restoration on disable/unload.
- Loaded exit-door, key/book/lever/fuse/keycard and hiding-spot markers.
- Entity-model markers and spawn notifications for an initial name allowlist.
- Mouse/touch-draggable session HUD: timer, room/floor, health and population.
- Inline rebindable toggle badges, RightControl menu key, themes and separate DOORS configs.
- All feature toggles start OFF; saved configurations are not automatically loaded in this release.

### Scope and limitations

This is an initial client-assist module, not an anti-cheat bypass. It does not provide invulnerability, auto-completion or server-side changes. Use responsibly and follow the experience's rules.

Rooms, markers and entity alerts depend on objects replicated to your client. Unloaded rooms cannot be shown. Object names are an initial allowlist, not a promise of every floor/item/entity being supported. A marker does not prove that a hiding spot is available or safe. The `LatestRoom` value represents server progress, not necessarily your location. The timer measures time since script load/reset, not official run time.

Syntax and deterministic mock regressions were checked locally. Actual Roblox gameplay and executor compatibility still require in-game testing. DOORS updates may change object names or layout.

## Files

| File | Purpose |
| --- | --- |
| `Loader.luau` | Universe-aware entry point |
| `Doors.luau` | DOORS-specific initial module |
| `ClaudeHub.luau` | Existing universal module, unchanged by this release |

The repository is public. Executable source is visible to anyone who downloads it. The loader and UI fetch remote Lua; only execute code from sources you trust.
