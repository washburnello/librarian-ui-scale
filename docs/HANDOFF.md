# Handoff — librarian-ui-scale

State of the project for whoever picks this up next. Read this top to bottom.

## Goal

A mod for **Librarian: Tidy Up the Arcane Library!** (Steam app `4197610`, Unreal
Engine **5.5**) that adds a **UI Scale** setting so the game is readable when
played on a TV (Steam Deck docked). The owner's primary directive: **read the
book names and button prompts on a TV**. UI Scale of **2.0×** was accepted as
"looks okay".

## Where things stand

Working and verified on both the dev PC (Linux/Proton) and the Steam Deck:

- A **UI Scale** row is injected into **Settings → Game Settings**.
- Value range **0.25×–2.00× in 0.25 steps**; the row shows the current value
  (label `UI Scale: 1.50x` and the numeric box).
- Moving the slider only **previews** the value. Pressing the game's **Apply**
  button commits it (this avoids a feedback loop where scaling during a drag
  moves the mouse target). **Reset** sets 1.0, **Cancel** discards.
- The chosen value persists to `Scripts/scale.txt` and is re-applied on launch.
- While the **Settings menu** is open the applied scale is **capped at 1.25×**
  (config `menu_cap`) so the menu itself stays on-screen and reachable; the
  chosen scale applies in-game.
- The row re-injects after Settings is closed and reopened.
- Deployed to the Deck and confirmed by the owner to appear in the menu.

**The one blocker:** the row is **not reachable with a controller**. Owner tested
on the Deck; the cursor stops before it. Diagnostics below explain why.

## Open problem — controller navigation to the injected row

### What we measured (via hooks on the Deck)

- The panel's `SelectedIdx` cycles **0..6** (7 options) and never reaches our
  row. `OptionWidgetArray` reads **8** (our row is in it), so the navigation
  limit does **not** come from that array.
- `USettingWidget:ChangeSelectOption` fires on every move (native hook) — so the
  game uses **index-based selection**, not Slate focus.
- `SettingsMenuBP:ListScroll(delta=±1)` routes to
  `USettingWidget:ScrollOptionList(delta)`; this only **scrolls**, it did not
  change `SelectedIdx` when invoked.
- Calling `ourRow:SetKeyboardFocus()` (Slate focus) did **not** change
  `SelectedIdx` — selection is not focus-driven, so UMG navigation rules will
  not help.
- The navigation count appears to come from the panel's **`CategoryValueArray`
  data** (flattened = 7 options). Extending it at runtime is unsafe (next).

### What does NOT work / crashed us

- **Appending to `CategoryValueArray[...].OptionValueArray`** (to make the count
  8): `table.insert` on that nested `TArray<FOptionData>` **hangs the mod**
  (Lua thread stops; game keeps running). Removed.
- **Scanning the game's widget children** (`GetChildrenCount`/`GetChildAt` +
  `GetText`) crashed the game (`EXCEPTION_ACCESS_VIOLATION`) when Settings
  opened. Removed.
- **Front-insert experiment (UNTESTED, reverted):** the idea was to insert our
  row at the **front** of both the visual list (`OptionsBox:InsertChildAt(0,row)`)
  and `OptionWidgetArray` (index 1), so it falls inside the game's fixed 0..6
  range. `InsertChildAt` and front-insertion into `OptionWidgetArray` were
  suspected in an earlier crash, so this was reverted before testing. Trade-off
  if it works: the **last built-in option (Display HUD) becomes
  controller-unreachable** (still clickable). See `main.lua` `registerFocus` /
  `attachRow` to re-apply.

### Next experiments to try (in order)

1. **Front-insert** as above, tested carefully on the PC first (open Settings,
   navigate, check for crash), then the Deck.
2. **Hook `USettingWidget:ChangeSelectOption`**: when `self.SelectedIdx == 6` and
   the player moves down again, call `self:ChangeSelectOption(_G.LibrarianUIScale_row)`
   yourself. Needs the input edge; combine with the `ListScroll`/`ScrollOptionList`
   hooks (which fire on nav). This is likely the cleanest fix if the edge can be
   detected.
3. **Asset mod**: add a real option to the game's settings data with a companion
   `.pak` via UE4SS `BPModLoaderMod` (`Content/Paks/LogicMods/`). This is the
   "correct" fix and would make the row a first-class navigable option. Needs
   FModel/retoc and realistically the Unreal Editor for widget work. See
   `docs/DISTRIBUTION_AND_TOOLS.md`.
4. **Fallbacks for controller users** (no code): use the Deck's **right trackpad**
   as a mouse to click the slider (the row is scrolled into view when Settings
   opens), or map **F8/F9 (scale −/+ 0.25)** and **F10 (reset)** to controller
   buttons via **Steam Input**. The hotkeys already exist in the mod.

## Repo layout

```
mod/LibrarianUIScale/Scripts/main.lua   the whole mod (Lua)
mod/LibrarianUIScale/Scripts/config.lua scale/min/max/step/menu_cap/focus
mod/LibrarianUIScale/enabled.txt
tools/fetch-ue4ss.sh        pinned UE4SS -> ./ue4ss (gitignored)
tools/install-dev.sh        install into local game
tools/run-game.sh           launch via Proton with the DLL override
tools/deploy-deck.sh        install onto the Deck over SSH
tools/set-deck-launch-option.py  set the Steam launch option (app 4197610)
docs/REVERSE_ENGINEERING.md game internals + crash hazards (READ THIS)
docs/DISTRIBUTION_AND_TOOLS.md  Workshop is unsupported; tool ecosystem
```

GitHub: `https://github.com/washburnello/librarian-ui-scale` (public). The local
clone is `/home/washburnello/Work/librarian-ui-scale`.

## How the mod works (short version)

1. `UUserInterfaceSettings.ApplicationScale` (CDO) scales the whole UI. Set via
   `StaticFindObject("/Script/Engine.Default__UserInterfaceSettings")`.
2. A **float option row** (`OptionUMG_Float_C`) is created with
   `WidgetBlueprintLibrary::Create` and added to the Game Settings panel's
   `OptionsBox`. It is the only runtime row type that renders with the correct
   (bright) style. Enum/Text rows render dim/disabled and their label array
   cannot be set from Lua.
3. The slider is polled (200 ms); its raw value is mapped directly to the
   0.25-step table (its `MinValue/MaxValue` getters are unreadable via UE4SS).
4. Apply/Reset/Cancel button handlers are hooked on `SettingsMenuBP_C`.
5. `SettingsMenuBP_C:IsVisible()` drives the menu cap.

## Crash hazards (do not repeat)

Full list in `docs/REVERSE_ENGINEERING.md`. Summary: never iterate the game's
widget children / read child widget text; never add the row to the panel's
`CategoryValueArray` or mutate its nested arrays; never call `RefreshSettings` /
`ActiveInit` after changing data. Safe: `WidgetBlueprintLibrary::Create`,
writing the row's own properties/children, `OptionsBox:AddChild`,
`OptionsBox:ScrollWidgetIntoView`, appending to `OptionWidgetArray`/`OptionList`.

## Steam Deck

- SSH: `deck@steamdeck` (key-based works from this PC).
- Game: `/home/deck/.steam/steam/steamapps/common/Librarian Tidy Up the Arcane
  Library!/Librarian/Binaries/Win64` (`S:` in Proton maps to
  `/home/deck/.local/share/Steam`).
- UE4SS + the mod are installed at
  `.../Win64/ue4ss/Mods/LibrarianUIScale` and enabled.
- **Launch option is required** or UE4SS never injects (Steam → game →
  Properties → Launch Options):
  ```
  WINEDLLOVERRIDES="dwmapi=n,b" %command%
  ```
  Gotchas: it was once entered as `WINEDLLOVERIDES` (one R) and silently did
  nothing. **Steam overwrites `localconfig.vdf` while running**, so
  `deploy-deck.sh --launch-option` only works with Steam closed; otherwise set
  it in the UI. Backups are named `localconfig.vdf.bak-librarian-uiscale`.
- Redeploy after code changes: `tools/deploy-deck.sh` (skip `--launch-option`).
- Verify injection: `.../Win64/ue4ss/UE4SS.log` exists and contains
  `[Lua] [LibrarianUIScale] ...` lines.

## Testing / diagnostics

The mod exposes a **file-driven command channel**: write a line to
`<Win64>/ue4ss/Mods/LibrarianUIScale/Scripts/cmd.txt` (on the Deck via SSH) and
it runs on the game thread. Useful commands:
`uiscale_status`, `uiscale_focusinfo`, `uiscale_watchnav <secs>`,
`uiscale_focusrow`, `uiscale_sliderinfo`, `uiscale_set <n>`, `uiscale_scrollto`,
`funcs <substr>`, `invoke <class> <func>`, `live <substr>`, `props <substr>`.

On the PC: `tools/install-dev.sh` then `tools/run-game.sh` (Steam launch option
not needed for `run-game.sh`). On the PC the game only starts via direct Proton
run; controller input isn't available there (the owner tests controller behavior
on the Deck). The PC can drive the UI by `invoke`-ing the title Options handler:
`invoke WBP_Title BndEvt__WBP_Title_Button_Options_K2Node_ComponentBoundEvent_1_OnButtonPressedEvent__DelegateSignature`.

## Uncommitted-now-committed state / notes

- The controller-nav **diagnostic hooks** are currently left in `main.lua`
  (they log `nav ...` lines on navigation). They are harmless but can be removed
  once nav is solved.
- `registerFocus`/`attachRow` are reverted to the **stable append + AddChild**
  behavior that matches what is deployed on the Deck.
- The **pause menu is not capped**, so the play-timer can drift under global
  scaling (a known layout artifact of `ApplicationScale`; see
  `docs/REVERSE_ENGINEERING.md`). Next after controller nav: extend the cap to
  `WBP_PauseMenu` and/or re-anchor the timer.

## Config reference (`mod/LibrarianUIScale/Scripts/config.lua`)

```lua
scale = 1.0      -- starting value first run; then scale.txt wins
min = 0.25
max = 2.0
step = 0.25
menu_cap = 1.25  -- applied while a full-screen menu is open
focus = true     -- register the row in the game's focus arrays
```
