# Third-party notices — ClaudeHub DOORS v0.3.0

## Abysall

Original author: **FireBacon (bocaj111004)**  
Source: https://github.com/bocaj111004/Abysall  
Reviewed revision: `66d4192d00d9b824a304b654bc2d2eb89c3b372b`  
Adapted source: `Games/Doors/Main.luau`.

Adapted portions include entity/objective/item/hiding/chest aliases; entity registration and rusher highlight preparation; ESP category patterns; InstantPrompts/AutoInteract behavior; speed, CanJump/CanSlide, infinite-jump and physical-property patterns; fog and occupied-hiding transparency; item, oxygen and Haste notifications.

ClaudeHub uses its own bounded BillboardGui/Highlight renderer and lifecycle. Door highlights target only explicitly named leaf parts, never the outer wall-containing model. Fast Interact has a rebindable hold key, preserves the prompt's own range/line-of-sight and restores hold duration after activation, failure or unload. New toggles start OFF.

The upstream analytics, destructive entity handlers, anti-cheat hooks, server remote actions, collision changes and entire upstream ESP renderer are not included. Adaptations have local compile/mock tests but are not yet verified in live Roblox gameplay. Archives/Stairwell-specific compatibility is not claimed.

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
