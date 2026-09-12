# Reverse-engineering notes

Target: **Librarian: Tidy Up the Arcane Library!** (Steam app `4197610`),
Unreal Engine **5.5**, Windows build run through Proton.

## Environment facts

- Engine version string found in the save file: `++UE5+Release-5.5`.
- IoStore TOC version 8 (`.utoc`), game content in
  `Librarian/Content/Paks/Librarian-Windows.{pak,ucas,utoc}`.
- Game settings live in a save-game object, not `.ini`:
  `<Proton prefix>/.../AppData/Local/Librarian/Saved/SaveGames/SystemSetting.sav`
  (`/Script/Librarian.SystemSaveGame`, structs `GeneralSettingsData`,
  `GameSettingsData`, `AudioSettingsData`, properties `BGMVolume`,
  `MotionBlur`, `SettingsQuality`, `SkyMode`, `VSync`, ...).
- There is **no native UI scale option**.

## Mod loader

UE4SS `v3.0.1-946` (experimental) loads the Lua mod. Under Proton, the
`dwmapi.dll` proxy requires a Wine DLL override or UE4SS silently fails to
inject:

```
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Layout after install (matches current UE4SS convention):

```
Librarian/Binaries/Win64/
  dwmapi.dll
  ue4ss/
    UE4SS.dll
    UE4SS-settings.ini
    Mods/
      LibrarianUIScale/
        enabled.txt
        Scripts/{main.lua,config.lua,scale.txt}
    UE4SS.log
```

## How UI scaling works

`UUserInterfaceSettings::ApplicationScale` (a `UDeveloperSettings` CDO) is
multiplied into the game-layer DPI scale, scaling the entire UMG/Slate UI.
It is live-editable and takes effect immediately.

```lua
local s = StaticFindObject("/Script/Engine.Default__UserInterfaceSettings")
s.ApplicationScale = 1.5
```

Confirmed by screenshot A/B at `1.0` vs `2.0`: menu text roughly doubles,
the 3D world is untouched. The title logo overflows at high values, so the
mod caps at 2.0.

## Settings menu architecture (the interesting part)

The Options screen is data-driven. Relevant classes (all under
`/Game/Librarian/UI/Options/` unless noted):

| Class | Role |
|---|---|
| `SettingsMenuBP_C` | Whole Options screen; `MenuBar`, `MenuSwitcher`, `SubMenuData` |
| `GameSettingsOptionsUMG_C` | The "Game Settings" tab panel (derives from `USettingWidget`) |
| `GraphicsOptionsUMG_C`, `AudioOptionsUMG_C`, `ControlOptionsUMG_C`, `GamepadControlOptionsUMG_C`, `LanguageOptionsUMG_C`, `InputOptionsUMG_C`, `TutorialOptionsUMG_C` | Other tabs |
| `OptionUMG_Float_C` | A float setting row = label + slider + progress bar |
| `OptionUMG_Enum_C`, `OptionUMG_Text_C`, ... | Other row types |
| `SubTitleOptionUMG_C` | Section subtitle ("Basic Settings", "HUD", ...) |

C++ base classes (from UE4SS's UHT header dump):

- `USettingWidget` has `TArray<FOptionCategory> CategoryValueArray`,
  `UScrollBox* OptionsBox`, `TArray<UOptionWidgetBase*> OptionWidgetArray`,
  and `RefreshSettings()` / `ChangeOptionFlt(optionName, delta, out)`.
- `FOptionCategory` = `{ FText SubtitleName; TArray<FOptionData> OptionValueArray; }`
- `FOptionData` = `{ FText Name; FName EnumName; TSubclassOf<UOptionWidgetBase>
  OptionWidgetClass; int DefaultIntValue; float DefaultFltValue; FVector2D
  ValueMinMax; float OffsetValue; bool CanDirectEdit; TArray<FText>
  ExtraTextArray; FOptionValue OptionValue; }`
- `UOptionWidgetBase_Float` has `USlider* Slider_Value`,
  `UProgressBar* ProgressBar_Value`, `UEditableTextBox* EditableText_Value`,
  and `ChangeValueBySlider(float)`.

Option rows are created by the Blueprint from the panel's `CategoryValueArray`
and each row's slider ultimately calls `USettingWidget::ChangeOptionFlt` with
the option's display name.

### Injection method used by this mod

1. Create a new row from the game's float row class (`OptionUMG_Float`):

   ```lua
   local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
   local rowClass = StaticFindObject("/Game/Librarian/UI/Options/OptionUMG_Float.OptionUMG_Float_C")
   local row = lib:Create(panel, rowClass, FindFirstOf("PlayerController"))
   ```

   `OptionUMG_Float` is the only row type that renders with the correct (bright)
   style when created at runtime. The arrow rows (`OptionUMG_Text`,
   `OptionUMG_Enum`) stay dimmed/disabled because the game initialises their
   state from data it builds itself; populating their `ExtraTextArray` from Lua
   also freezes the game (see crash hazards).

2. Configure `row.Option` (`Name`, `ValueMinMax`, `DefaultFltValue`,
   `OptionValue.FloatValue`), set the slider min/max/step/value, and set the
   label to include the current scale
   (`row.Text_OptionName:SetText("UI Scale: 1.50x")`) plus the numeric box
   (`row.EditableText_Value`). The slider is snapped to 0.25 steps by the poll.
3. Add it: `panel.OptionsBox:AddChild(row)`.
4. The game's own change path does not know a "UI Scale" setting. Both paths are
   intercepted: `USettingWidget:ChangeOptionFlt` (float rows) and
   `USettingWidget:ChangeOption` (arrow rows, called with a `±1` delta). A short
   poll also watches `row.Option.OptionValue.IntValue` as a fallback. This
   avoids relying on UMG delegate binding from Lua.
5. Persist the value in `Scripts/scale.txt`; re-apply on startup.

**Do not** populate `Option.ExtraTextArray` (the enum value labels) from Lua.
`table.insert`/assignment on that nested `TArray<FText>` corrupts memory and
freezes the game; the scale indicator is carried by the row label instead.

**Controller focus:** the game drives controller navigation over its own
`UBasicWidget` lists (`OptionWidgetArray`, `OptionList`) and BP events
(`SelectOptionBP(oldIdx,newIdx)`). To be reachable, the injected row is
**appended** to `OptionWidgetArray` (and `OptionList`) — never inserted at the
front, which shifted indices and crashed the game. The row is then the last
entry (index 8 in Game Settings) and is reachable by pressing Down past the
last built-in option. Re-attaching on reopen reuses the same row object so the
list entry stays valid, and a duplicate check keeps it from being added twice.

**Timing:** opening the menu is detected by post-hooks on the title and pause
"Options" button handlers (registered lazily, because Blueprint UFunctions are
not loaded at mod start). A 150 ms poll is the fallback. An earlier 700 ms poll
was visible as the row "popping in" a moment after the menu opened.

### Useful game symbols

- Options button handler:
  `/Game/Librarian/UI/Title/WBP_Title.WBP_Title_C:BndEvt__WBP_Title_Button_Options_K2Node_ComponentBoundEvent_1_OnButtonPressedEvent__DelegateSignature`
- Pause menu option handler:
  `.../WBP_PauseMenu.WBP_PauseMenu_C:BndEvt__WBP_PauseMenu_Button_Option_...`
- `WBP_Title_C` is instanced as `BP_LibrarianGameInstance_C.TitleUMG`;
  the in-game HUD is `BP_LibrarianGameInstance_C.MainUMG`.

## Development helpers built into the mod

Because keyboard/mouse injection into a Proton window is awkward, `main.lua`
exposes a file-driven command channel: write a line to
`Scripts/cmd.txt` and it runs on the game thread. Commands:
`dump`, `scale <n>`, `classes <s>`, `widgets <s>`, `live <s>`, `props <s>`,
`objprops <s>`, `get <class> <path>`, `settingdata <class>`, `tree <s>`,
`press <button>`, `funcs <s>`, `invoke <class> <func>`, `uiscale_addrow`,
`uiscale_install`, `uiscale_set <n>`, `sdk`, `uht`, `objdump`.

## Crash hazards (important)

Do **not** do any of the following from Lua — each was observed to crash the
game with `EXCEPTION_ACCESS_VIOLATION` (C0000005) when the Settings menu
opened or rebuilt:

- Iterating the panel's widget children (`OptionsBox:GetChildrenCount/GetChildAt`)
  and reading `Text_OptionName` / calling `GetText()` on them. Reading a child's
  text (e.g. `row.EditableText_Value:GetText()`) also froze the game even inside
  `pcall`, so the mod never reads its row's child widgets — it only writes to
  them, guarded by `IsValid`.
- Adding the injected row to the game's `OptionWidgetArray` / `OptionList`
  (the game dereferences those assuming its own managed widgets).
- Calling the panel's `RefreshSettings` / `ActiveInit` after modifying
  `CategoryValueArray`.

Safe operations used by the mod: `WidgetBlueprintLibrary::Create` for the row,
setting the row's own properties/children, `OptionsBox:AddChild`, and
`OptionsBox:ScrollWidgetIntoView`.

Two more runtime quirks discovered while fixing the reopen bug:

- `UUserWidget:IsInViewport()` returns **false** for the Settings panel even
  when it is open. Use `IsVisible()` instead (correctly false/true on
  close/open).
- When the menu is cancelled and reopened, the panel object is **reused** and
  our row object survives but becomes **orphaned** (`row:GetParent()` returns
  none) while `IsValid(row)` stays true. Re-injection is therefore gated on
  `row:GetParent()` matching the panel's `OptionsBox`, not on `IsValid` alone.

## Known limitations / next work

- The injected row is added at the end of the scroll box and is not yet part
  of the game's controller focus list (`OptionWidgetArray` / `OptionList`),
  so gamepad navigation may not reach it. Mouse dragging and the poll work.
- The row's value text is not shown (`Text_OptionValue` is not bound in this
  row's Blueprint).
- Visual polish: position the row under "Basic Settings" and match styling.
