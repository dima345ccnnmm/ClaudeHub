# ClaudeHub DOORS v0.4.1 / Loader v1.1.0

- Run callbacks wait for finished UI initialization. Catch-up scans cover objects streamed during UI creation.
- Third Person: normal DOORS Scriptable camera allowed; old CameraSubject gate removed; offset applied at Last+1,
  never accumulated; suspension for known hiding/animation states; camera and head/accessory transparency restored.
- Dupe: strict positive trigger detection (CurrentRooms / FakeDoor or DoorFake / Hidden BasePart / TouchTransmitter).
  Decorative names and Hidden-only models are not enough. Reclassification handles late triggers and filter changes.
  Optional less-precise compatibility mode is available under Visuals > ESP > Dupe detection.
- Independent DoorsLobby.luau: Home/profile/info, selected-player elevator join, Quick Play, configurable elevator
  creation, unlocked badge equip/cycling, manual code entry and cancellable sample-code batch requests.
- Loader v1.1 routes lobby Place ID 6516141723 to DoorsLobby.luau, DOORS runs to Doors.luau,
  other games to unchanged ClaudeHub.luau. Direct Doors.luau launch also delegates to lobby.
- No direct Main_Game.PromptService indexing; optional sounds are discovered and changed only when present.
  Anti-idle checks missing toggle/state safely. No persistent legacy getconnections hooks are installed.
- Old Main.luau is not executed by these modules. Rejoin before testing to stop any legacy callbacks still running.

Checks: compile all three scripts; deterministic yielded-startup, missing-toggle/member, Scriptable camera,
head/camera restoration, strict/late-trigger Dupe, run regression, standalone lobby and loader routing/failure tests.
These are local mocks, not live Roblox/executor/gameplay tests. Strict Dupe can omit unrecognized/unstreamed triggers;
new floor-specific support is not claimed.
