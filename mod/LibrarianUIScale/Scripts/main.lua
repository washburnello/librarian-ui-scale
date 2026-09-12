--[[
    LibrarianUIScale - Phase 0 probe + scale driver
    Game: Librarian: Tidy Up the Arcane Library! (Unreal Engine 5.5)
    Loader: UE4SS (Lua)

    Drives the global UMG/Slate scale via UUserInterfaceSettings.ApplicationScale
    and provides discovery helpers used to locate the game's Settings widget so a
    native slider can be injected there.

    Console commands (open the UE console):
      uis_dump             - print the current UserInterfaceSettings values
      uis_scale <number>   - set ApplicationScale (0.5 - 3.0)
      uis_classes [substr] - list loaded UClass names containing substr (default "Setting")
      uis_widgets [substr] - list live UUserWidget instances containing substr
      uis_props <substr>   - list reflected properties of the first matching widget

    Hotkeys:
      F8  - scale down one step
      F9  - scale up one step
      F10 - reset to 1.0
]]

local MOD = "LibrarianUIScale"

local function log(msg)
    print("[" .. MOD .. "] " .. tostring(msg) .. "\n")
end

local function safe(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log("ERROR in " .. tostring(label) .. ": " .. tostring(err))
    end
    return ok
end

--- Run a function on the game thread when possible. Property writes from a
--- background thread are not safe, so route them through ExecuteInGameThread.
local function onGameThread(fn)
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(fn)
    else
        fn()
    end
end

local function shortName(obj)
    local ok, n = pcall(function() return obj:GetFName():ToString() end)
    return ok and n or "<?>"
end

local function fullName(obj)
    local ok, n = pcall(function() return obj:GetFullName() end)
    return ok and n or "<?>"
end

local function isValid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v
end

local function isCdo(obj)
    return shortName(obj):sub(1, 9) == "Default__"
end

local function className(obj)
    local ok, c = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and c or ""
end

--- Match a UObject against a case-insensitive substring, testing both the
--- object's own name and its class name. UMG widgets usually carry the variable
--- name (e.g. "TitleUMG") as their object name while the class is "WBP_Title_C",
--- so searching either is necessary.
local function matches(obj, needle)
    if needle == "" then return true end
    if shortName(obj):lower():find(needle, 1, true) then return true end
    return className(obj):lower():find(needle, 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- Config / persistence
-- ---------------------------------------------------------------------------

local scriptDir = (debug.getinfo(1, "S").source:match("@(.*[\\/])")) or ""
local scaleTxt = scriptDir .. "scale.txt"

local okConfig, config = pcall(require, "config")
if not okConfig or type(config) ~= "table" then
    config = { scale = 1.0, min = 1.0, max = 2.5, step = 0.1 }
    log("config.lua not found or invalid, using defaults")
end

local currentScale = tonumber(config.scale) or 1.0

local function loadPersistedScale()
    local f = io.open(scaleTxt, "r")
    if f then
        local v = tonumber(f:read("*a"))
        f:close()
        if v then return v end
    end
    return nil
end

local function persistScale(v)
    local f = io.open(scaleTxt, "w")
    if f then
        f:write(string.format("%.2f", v))
        f:close()
    end
end

local persisted = loadPersistedScale()
if persisted then currentScale = persisted end

-- ---------------------------------------------------------------------------
-- UserInterfaceSettings
-- ---------------------------------------------------------------------------

local function getUISettings()
    local cdo = StaticFindObject("/Script/Engine.Default__UserInterfaceSettings")
    if isValid(cdo) then return cdo end
    cdo = FindFirstOf("UserInterfaceSettings")
    if isValid(cdo) then return cdo end
    return nil
end

local function readScale()
    local s = getUISettings()
    if not s then return nil end
    local ok, v = pcall(function() return s.ApplicationScale end)
    return ok and v or nil
end

local function dumpUISettings()
    local s = getUISettings()
    if not s then
        log("UserInterfaceSettings: NOT FOUND")
        return
    end
    log("UserInterfaceSettings: " .. fullName(s))
    for _, prop in ipairs({ "ApplicationScale", "UIScaleRule", "bAllowHighDPIInGameMode" }) do
        local ok, v = pcall(function() return s[prop] end)
        log("  " .. prop .. " = " .. (ok and tostring(v) or "<unreadable>"))
    end
end

local function clamp(v)
    v = tonumber(v) or 1.0
    if v < (config.min or 1.0) then v = config.min or 1.0 end
    if v > (config.max or 2.5) then v = config.max or 2.5 end
    return v
end

local lastApplied = nil

local function applyScale(v, persist, inline)
    v = clamp(v)
    currentScale = v
    lastApplied = v
    local function set()
        local s = getUISettings()
        if not s then
            log("applyScale: UserInterfaceSettings not found")
            return
        end
        safe("set ApplicationScale", function() s.ApplicationScale = v end)
        log(string.format("applyScale -> %.2f (read back %s)", v, tostring(readScale())))
    end
    if inline then set() else onGameThread(set) end
    -- Keep the injected slider in sync when the scale changes from elsewhere.
    local row = _G.LibrarianUIScale_row
    if isValid(row) then
        pcall(function() row.Slider_Value:SetValue(v) end)
        pcall(function() row.Option.OptionValue.FloatValue = v end)
    end
    if persist ~= false then persistScale(v) end
end

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

local function probeClasses(substr)
    substr = substr or "Setting"
    log("probeClasses matching '" .. substr .. "' ...")
    local classClass = StaticFindObject("/Script/CoreUObject.Class")
    if not isValid(classClass) then
        log("probeClasses: CoreUObject.Class not found")
        return
    end
    local needle = substr:lower()
    local count = 0
    ForEachUObject(function(obj)
        if isValid(obj) then
            local ok, isClass = pcall(function() return obj:IsA(classClass) end)
            if ok and isClass then
                local n = shortName(obj)
                if n:lower():find(needle, 1, true) then
                    count = count + 1
                    log("  class " .. fullName(obj))
                end
            end
        end
    end)
    log("probeClasses done (" .. count .. " classes)")
end

local function probeWidgets(substr)
    substr = substr or ""
    log("probeWidgets matching '" .. substr .. "' ...")
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    if not isValid(widgetClass) then
        log("probeWidgets: UMG.UserWidget not found (open a menu first?)")
        return
    end
    local needle = substr:lower()
    local total, shown = 0, 0
    ForEachUObject(function(obj)
        if isValid(obj) and not isCdo(obj) then
            local ok, isWidget = pcall(function() return obj:IsA(widgetClass) end)
            if ok and isWidget then
                total = total + 1
                if matches(obj, needle) then
                    shown = shown + 1
                    log(string.format("  widget %s  [%s]", fullName(obj), className(obj)))
                end
            end
        end
    end)
    log(string.format("probeWidgets done (%d widgets total, %d shown)", total, shown))
end

local function dumpObjectProperties(obj)
    if not isValid(obj) then
        log("dumpObjectProperties: invalid object")
        return
    end
    log("properties of " .. fullName(obj))
    -- ForEachProperty only walks the class's own PropertyLink, so walk the
    -- inheritance chain to include C++ base-class properties too.
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    local depth = 0
    while isValid(cls) and depth < 16 do
        pcall(function()
            cls:ForEachProperty(function(prop)
                local okp, val = pcall(function() return obj[prop:GetFName():ToString()] end)
                log(string.format("  %-40s = %s", prop:GetFName():ToString(),
                    okp and tostring(val) or "<unreadable>"))
            end)
        end)
        local parent = nil
        pcall(function() parent = cls.SuperStruct end)
        cls = parent
        depth = depth + 1
    end
end

--- Find the first live object matching a substring, skipping class and package
--- objects and optionally requiring a base class.
local function firstLiveObject(substr, requiredClassPath)
    local needle = (substr or ""):lower()
    local classClass = StaticFindObject("/Script/CoreUObject.Class")
    local required = nil
    if requiredClassPath then
        required = StaticFindObject(requiredClassPath)
    end
    local found = nil
    ForEachUObject(function(obj)
        if not found and isValid(obj) and not isCdo(obj) and matches(obj, needle) then
            local ok = true
            if isValid(classClass) then
                local isClass = false
                pcall(function() isClass = obj:IsA(classClass) end)
                if isClass then ok = false end
            end
            if ok and className(obj) == "Package" then ok = false end
            if ok and className(obj) == "Function" then ok = false end
            if ok and isValid(required) then
                local isReq = false
                pcall(function() isReq = obj:IsA(required) end)
                if not isReq then ok = false end
            end
            if ok then found = obj end
        end
    end)
    return found
end

--- Read a dotted/indexed property path from the first live object matching a
--- class substring. e.g. "get GameSettingsOptionsUMG CategoryValueArray"
local function getPropPath(classSubstr, path)
    if not classSubstr or not path then
        log("get: need <classSubstr> <path>")
        return
    end
    local target = firstLiveObject(classSubstr, nil)
    if not target then
        log("get: no live object matched '" .. classSubstr .. "'")
        return
    end
    log("get " .. path .. " on " .. fullName(target))
    local cur = target
    for part in path:gmatch("[^%.]+") do
        local idx = tonumber(part)
        local ok, nxt = pcall(function()
            if idx then return cur[idx] else return cur[part] end
        end)
        if not ok then
            log("  " .. part .. " -> ERROR " .. tostring(nxt))
            return
        end
        cur = nxt
        local len = nil
        pcall(function() len = #cur end)
        log(string.format("  %s -> %s%s", part, tostring(cur),
            len and (" (len " .. len .. ")") or ""))
    end
    -- If the path resolved to an object, show its properties too.
    local isObj = false
    pcall(function() isObj = (cur.GetFullName ~= nil) end)
    if isObj then
        dumpObjectProperties(cur)
    end
end

local UI_SCALE_NAME = "UI Scale"
local UI_SCALE_MIN = 1.0
local UI_SCALE_MAX = 2.0
local UI_SCALE_STEP = 0.1

local function makeText(s)
    local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    if isValid(lib) then
        local ok, t = pcall(function() return lib:Conv_StringToText(s) end)
        if ok and t ~= nil then return t end
    end
    return s
end

local function textToString(t)
    local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    if isValid(lib) and t ~= nil then
        local ok, s = pcall(function() return lib:Conv_TextToString(t) end)
        if ok then return s end
    end
    return nil
end

--- Add a "UI Scale" float row to the game's own Game Settings panel by
--- extending its CategoryValueArray and rebuilding the list. EXPERIMENTAL:
--- calling the panel's ActiveInit/RefreshSettings has crashed the game before.
local function installOption()
    local panel = firstLiveObject("GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget")
    if not panel then
        log("install: Game Settings panel not live (open Settings first)")
        return
    end
    local opts = panel.CategoryValueArray[1].OptionValueArray
    local n = nil
    pcall(function() n = #opts end)
    if not n or n < 1 then
        log("install: could not read Game Settings option array")
        return
    end

    -- Reuse the last float option (Field Of View) as a structural template.
    table.insert(opts, opts[n])
    local revised = opts[#opts]
    pcall(function() revised.Name = makeText(UI_SCALE_NAME) end)
    pcall(function() revised.ValueMinMax.X = UI_SCALE_MIN end)
    pcall(function() revised.ValueMinMax.Y = UI_SCALE_MAX end)
    pcall(function() revised.DefaultFltValue = currentScale end)
    pcall(function() revised.OffsetValue = UI_SCALE_STEP end)
    pcall(function() revised.OptionValue.FloatValue = currentScale end)
    pcall(function() revised.CanDirectEdit = false end)
    local okAssign, errAssign = pcall(function() opts[#opts] = revised end)
    log("install: assign back ok=" .. tostring(okAssign) .. " err=" .. tostring(errAssign))

    local ok, err = pcall(function() panel:RefreshSettings() end)
    log("install: RefreshSettings ok=" .. tostring(ok) .. " err=" .. tostring(err))
    -- The actual row construction lives in the panel's Blueprint ActiveInit event.
    local okA, errA = pcall(function() panel:ActiveInit() end)
    log("install: ActiveInit ok=" .. tostring(okA) .. " err=" .. tostring(errA))
end

--- Create and configure a fresh UI Scale row (does NOT attach it).
local function createScaleRow(panel)
    local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not isValid(lib) then
        log("addrow: UWidgetBlueprintLibrary not found")
        return nil
    end
    local rowClass = StaticFindObject("/Game/Librarian/UI/Options/OptionUMG_Float.OptionUMG_Float_C")
    local pc = FindFirstOf("PlayerController")
    local row = nil
    local ok, err = pcall(function() row = lib:Create(panel, rowClass, pc) end)
    log("addrow: create ok=" .. tostring(ok) .. " err=" .. tostring(err))
    if not isValid(row) then return nil end

    pcall(function() row.ParentWidget = panel end)
    local option = nil
    pcall(function() option = row.Option end)
    pcall(function()
        option.Name = makeText(UI_SCALE_NAME)
        option.ValueMinMax.X = UI_SCALE_MIN
        option.ValueMinMax.Y = UI_SCALE_MAX
        option.DefaultFltValue = currentScale
        option.OptionValue.FloatValue = currentScale
        row.Option = option
    end)
    pcall(function() row:CreateContentBP(row.Option) end)

    if isValid(row.Text_OptionName) then
        pcall(function() row.Text_OptionName:SetText(makeText(UI_SCALE_NAME)) end)
    end
    if isValid(row.Text_OptionValue) then
        pcall(function() row.Text_OptionValue:SetText(makeText(string.format("%.1fx", currentScale))) end)
    end
    if isValid(row.Slider_Value) then
        pcall(function()
            row.Slider_Value:SetMinValue(UI_SCALE_MIN)
            row.Slider_Value:SetMaxValue(UI_SCALE_MAX)
            row.Slider_Value:SetStepSize(UI_SCALE_STEP)
            row.Slider_Value:SetValue(currentScale)
        end)
    end

    if isValid(row.EditableText_Value) then
        pcall(function() row.EditableText_Value:SetText(makeText(string.format("%.1f", currentScale))) end)
    end
    if isValid(row.ProgressBar_Value) then
        local pct = (currentScale - UI_SCALE_MIN) / (UI_SCALE_MAX - UI_SCALE_MIN)
        pcall(function() row.ProgressBar_Value:SetPercent(pct) end)
    end
    return row
end

local function arrayHas(arr, row)
    local n = 0
    pcall(function() n = #arr end)
    local target = fullName(row)
    for i = 1, n do
        local e = arr[i]
        if isValid(e) and fullName(e) == target then return true end
    end
    return false
end

--- Register the row in the game's controller-focus lists. Append-only (never
--- insert at the front, which shifted indices and crashed the game) and guarded
--- against duplicates so re-attaching on reopen does not add it twice.
local function registerFocus(panel, row)
    if config.focus == false then return end
    local widgetArr, listArr = nil, nil
    local okW = pcall(function() widgetArr = panel.OptionWidgetArray end)
    local okL = pcall(function() listArr = panel.OptionList end)
    local addedW, addedL = false, false
    if okW and widgetArr ~= nil and not arrayHas(widgetArr, row) then
        addedW = pcall(function() table.insert(widgetArr, row) end)
    end
    if okL and listArr ~= nil and not arrayHas(listArr, row) then
        addedL = pcall(function() table.insert(listArr, row) end)
    end
    log(string.format("focus: OptionWidgetArray=%s(+%s) OptionList=%s(+%s)",
        tostring(okW), tostring(addedW), tostring(okL), tostring(addedL)))
end

--- Ensure our row exists and is attached to the panel. Reuses the existing row
--- object when possible so focus-list membership stays valid across a
--- close/reopen (the row survives but is orphaned).
local function attachRow(panel)
    if not isValid(panel) then return end
    local box = nil
    pcall(function() box = panel.OptionsBox end)
    if not isValid(box) then
        log("addrow: OptionsBox not found")
        return
    end
    local row = _G.LibrarianUIScale_row
    if isValid(row) then
        pcall(function() box:AddChild(row) end)
    else
        row = createScaleRow(panel)
        if not isValid(row) then return end
        pcall(function() box:AddChild(row) end)
        _G.LibrarianUIScale_row = row
        _G.LibrarianUIScale_panel = panel
    end
    pcall(function() box:ScrollWidgetIntoView(row, false, 0) end)
    registerFocus(panel, row)
end

local function addRow()
    attachRow(firstLiveObject("GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget"))
end

--- Drive the injected row's slider programmatically (simulates the player
--- dragging it) so the whole change path can be tested without input.
local function setSlider(value)
    value = tonumber(value)
    if not value then
        log("uiscale_set: need a number")
        return
    end
    local row = _G.LibrarianUIScale_row
    if not isValid(row) then
        row = firstLiveObject(UI_SCALE_NAME, "/Script/Librarian.OptionWidgetBase_Float")
    end
    if not isValid(row) then
        log("uiscale_set: UI Scale row not found (run uiscale_addrow with Settings open)")
        return
    end
    -- Moving the slider is what a real drag does; the poll applies the change.
    local ok, err = pcall(function() row.Slider_Value:SetValue(value) end)
    pcall(function() row.Option.OptionValue.FloatValue = value end)
    local sliderVal = "?"
    pcall(function() sliderVal = tostring(row.Slider_Value:GetValue()) end)
    log(string.format("uiscale_set %.2f ok=%s err=%s sliderVal=%s", value, tostring(ok), tostring(err), sliderVal))
end

--- Report injection/visibility state (diagnostics).
local function uiscaleStatus()
    local panel = firstLiveObject("GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget")
    local row = _G.LibrarianUIScale_row
    local pvis, pname, rvis, rparent = "?", "none", "?", "none"
    if isValid(panel) then
        pname = fullName(panel)
        pcall(function() pvis = tostring(panel:IsVisible()) end)
    end
    if isValid(row) then
        pcall(function() rvis = tostring(row:IsVisible()) end)
        pcall(function() local p = row:GetParent(); if isValid(p) then rparent = fullName(p) end end)
    end
    log("status: panelValid=" .. tostring(isValid(panel)) .. " panelVisible=" .. pvis)
    log("  panelName=" .. pname)
    log("  rowValid=" .. tostring(isValid(row)) .. " rowVisible=" .. rvis .. " rowParent=" .. rparent)
end

--- Test the controller-focus path: ask the game to select our row.
local function selectRow()
    local panel = _G.LibrarianUIScale_panel
    local row = _G.LibrarianUIScale_row
    if not isValid(panel) or not isValid(row) then
        log("select: no row/panel")
        return
    end
    local ok, err = pcall(function() panel:ChangeSelectOption(row) end)
    local idx = "?"
    pcall(function() idx = tostring(panel.SelectOptionIdx) end)
    log("select: ChangeSelectOption ok=" .. tostring(ok) .. " err=" .. tostring(err)
        .. " SelectOptionIdx=" .. idx)
end

--- Diagnostics: dump the game's focus arrays.
local function focusInfo()
    local panel = _G.LibrarianUIScale_panel
    local row = _G.LibrarianUIScale_row
    if not isValid(panel) then
        log("focusinfo: no panel")
        return
    end
    local wa, ol = nil, nil
    pcall(function() wa = panel.OptionWidgetArray end)
    pcall(function() ol = panel.OptionList end)
    local nwa, nol = -1, -1
    if wa ~= nil then pcall(function() nwa = #wa end) end
    if ol ~= nil then pcall(function() nol = #ol end) end
    log("focusinfo: OptionWidgetArray=" .. nwa .. " OptionList=" .. nol)
    for i = 1, (nwa > 0 and nwa or 0) do
        local e = wa[i]
        if isValid(e) then log("  WA[" .. i .. "]=" .. fullName(e)) end
    end
    if isValid(row) then
        log("  ourRow inWA=" .. tostring(wa ~= nil and arrayHas(wa, row))
            .. " inOL=" .. tostring(ol ~= nil and arrayHas(ol, row)))
    end
    local si, sel = "?", "?"
    pcall(function() si = tostring(panel.SelectOptionIdx) end)
    pcall(function() sel = tostring(panel.SelectedIdx) end)
    log("  SelectOptionIdx=" .. si .. " SelectedIdx=" .. sel)
end

--- Diagnostics: select a game row by index in OptionWidgetArray.
local function selectIndex(i)
    i = tonumber(i)
    local panel = _G.LibrarianUIScale_panel
    local wa = nil
    pcall(function() wa = panel.OptionWidgetArray end)
    local e = nil
    pcall(function() e = wa[i] end)
    if not isValid(panel) or not i or not isValid(e) then
        log("selectindex: invalid (" .. tostring(i) .. ")")
        return
    end
    local ok, err = pcall(function() panel:ChangeSelectOption(e) end)
    local si = "?"
    pcall(function() si = tostring(panel.SelectOptionIdx) end)
    log("selectindex " .. i .. " (" .. fullName(e) .. ") ok=" .. tostring(ok)
        .. " err=" .. tostring(err) .. " SelectOptionIdx=" .. si)
end

--- Scroll the injected row into view and make the scroll bar visible.
local function scrollToRow()
    local row = _G.LibrarianUIScale_row
    local panel = _G.LibrarianUIScale_panel
    if not isValid(row) or not isValid(panel) then
        log("scrollto: no injected row/panel")
        return
    end
    local box = nil
    pcall(function() box = panel.OptionsBox end)
    if not isValid(box) then
        log("scrollto: no OptionsBox")
        return
    end
    local ok, err = pcall(function() box:ScrollWidgetIntoView(row, false, 0) end)
    log("scrollto ok=" .. tostring(ok) .. " err=" .. tostring(err))
end

--- Probe the settings data model: enumerate categories and option rows.
local function probeSettingData(classSubstr)
    local panel = firstLiveObject(classSubstr or "GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget")
    if not panel then
        log("settingdata: no live setting panel matched '" .. tostring(classSubstr) .. "' (open Settings first)")
        return
    end
    log("settingdata on " .. fullName(panel))
    local cats = nil
    pcall(function() cats = panel.CategoryValueArray end)
    if cats == nil then
        log("  CategoryValueArray not readable")
        return
    end
    local ncats = nil
    if not pcall(function() ncats = #cats end) then
        log("  CategoryValueArray is not an indexable array: " .. tostring(cats))
        return
    end
    log("  categories = " .. tostring(ncats))
    for i = 1, ncats do
        local cat = cats[i]
        local opts = nil
        pcall(function() opts = cat.OptionValueArray end)
        local nopts = -1
        if opts ~= nil then pcall(function() nopts = #opts end) end
        local subtitle = "?"
        pcall(function() subtitle = tostring(cat.SubtitleName) end)
        log(string.format("  [%d] %s (%d options)", i, subtitle, nopts))
        for j = 1, (nopts > 0 and nopts or 0) do
            local o = opts[j]
            local name, cls, minmax, def, cur = "?", "?", "?", "?", "?"
            pcall(function() name = tostring(o.Name) end)
            pcall(function() cls = tostring(o.OptionWidgetClass) end)
            pcall(function() minmax = tostring(o.ValueMinMax) end)
            pcall(function() def = tostring(o.DefaultFltValue) end)
            pcall(function() cur = tostring(o.OptionValue) end)
            log(string.format("      - %-32s cls=%s minmax=%s def=%s", name, cls, minmax, def))
        end
    end
end

local function probeProps(substr)
    substr = substr or ""
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    if not isValid(widgetClass) then
        log("probeProps: UMG.UserWidget not found")
        return
    end
    local needle = substr:lower()
    local found = false
    ForEachUObject(function(obj)
        if not found and isValid(obj) and not isCdo(obj) then
            local ok, isWidget = pcall(function() return obj:IsA(widgetClass) end)
            if ok and isWidget and matches(obj, needle) then
                found = true
                dumpObjectProperties(obj)
            end
        end
    end)
    if not found then
        log("probeProps: no live widget matched '" .. substr .. "'")
    end
end

--- Dump reflected properties of the first live non-widget UObject matching a
--- substring (e.g. a GameInstance). Useful for finding references like OptionsUMG.
local function probeAnyProps(substr)
    substr = substr or ""
    local needle = substr:lower()
    local classClass = StaticFindObject("/Script/CoreUObject.Class")
    local found = false
    ForEachUObject(function(obj)
        if not found and isValid(obj) and not isCdo(obj) and matches(obj, needle) then
            local isClass = false
            if isValid(classClass) then
                pcall(function() isClass = obj:IsA(classClass) end)
            end
            if not isClass then
                found = true
                dumpObjectProperties(obj)
            end
        end
    end)
    if not found then
        log("objprops: no live object matched '" .. tostring(substr) .. "'")
    end
end

--- List reflected UFunction objects (including Blueprint-generated ones such as
--- the BndEvt__ button handlers) whose name matches a substring.
local function probeFunctions(substr)
    substr = substr or ""
    local fnClass = StaticFindObject("/Script/CoreUObject.Function")
    if not isValid(fnClass) then
        log("funcs: Function class not found")
        return
    end
    local needle = substr:lower()
    local n = 0
    ForEachUObject(function(obj)
        if isValid(obj) then
            local ok, isFn = pcall(function() return obj:IsA(fnClass) end)
            if ok and isFn and matches(obj, needle) then
                n = n + 1
                log("  func " .. fullName(obj))
            end
        end
    end)
    log("funcs done (" .. n .. ")")
end

--- Call a UFunction by name on the first live object whose class matches.
local function invokeFunction(classSubstr, funcName, arg1, arg2)
    if not classSubstr or not funcName then
        log("invoke: need <classSubstr> <funcName> [arg1] [arg2]")
        return
    end
    local needle = classSubstr:lower()
    local classClass = StaticFindObject("/Script/CoreUObject.Class")
    local candidates = {}
    ForEachUObject(function(obj)
        if isValid(obj) and not isCdo(obj) and matches(obj, needle) then
            local isClass = false
            if isValid(classClass) then
                pcall(function() isClass = obj:IsA(classClass) end)
            end
            if not isClass then
                candidates[#candidates + 1] = obj
            end
        end
    end)
    if #candidates == 0 then
        log("invoke: no live object matched '" .. classSubstr .. "'")
        return
    end
    for _, target in ipairs(candidates) do
        local fn = nil
        pcall(function() fn = target[funcName] end)
        if fn then
            log("invoke: " .. funcName .. " on " .. fullName(target))
            local args = { target }
            if arg1 ~= nil and arg1 ~= "" then args[#args + 1] = tonumber(arg1) or arg1 end
            if arg2 ~= nil and arg2 ~= "" then args[#args + 1] = tonumber(arg2) or arg2 end
            local ok, err = pcall(function() return target[funcName](table.unpack(args)) end)
            log("invoke result ok=" .. tostring(ok) .. " err=" .. tostring(err))
            if ok then return end
        end
    end
    log("invoke: no candidate exposed function '" .. funcName .. "'")
end

--- Simulate pressing a named UMG button by finding the first live widget that
--- exposes a property with that name, then trying the usual delegate entry
--- points. Lets us open menus (e.g. Button_Options) without real input.
local function pressButton(propname)
    if not propname or propname == "" then
        log("press: need a property name, e.g. 'press Button_Options'")
        return
    end
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    local target, owner = nil, nil
    ForEachUObject(function(obj)
        if not target and isValid(obj) and not isCdo(obj) then
            local ok, isWidget = pcall(function() return obj:IsA(widgetClass) end)
            if ok and isWidget then
                local p = nil
                pcall(function() p = obj[propname] end)
                if isValid(p) then
                    target, owner = p, obj
                end
            end
        end
    end)
    if not target then
        log("press: no live widget exposes property '" .. propname .. "'")
        return
    end
    log(string.format("press: %s on %s -> %s", propname, fullName(owner), className(target)))
    local attempts = {
        function() target.OnClicked:Broadcast() end,
        function() target:BroadcastOnClicked() end,
        function() target:OnClicked() end,
        function() target:Click() end,
        function() target:K2_Click() end,
    }
    for i, fn in ipairs(attempts) do
        local ok, err = pcall(fn)
        log(string.format("  attempt %d ok=%s err=%s", i, tostring(ok), tostring(err)))
        if ok then break end
    end
end

local function findFirstWidget(substr)
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    if not isValid(widgetClass) then return nil end
    local needle = (substr or ""):lower()
    local fallback, withTree = nil, nil
    ForEachUObject(function(obj)
        if isValid(obj) and not isCdo(obj) then
            local ok, isWidget = pcall(function() return obj:IsA(widgetClass) end)
            if ok and isWidget and matches(obj, needle) then
                if not fallback then fallback = obj end
                local treeOk = false
                pcall(function() treeOk = isValid(obj.WidgetTree) end)
                if treeOk and not withTree then withTree = obj end
            end
        end
    end)
    return withTree or fallback
end

--- List only non-CDO (live) UserWidget instances.
local function probeLiveWidgets(substr)
    substr = substr or ""
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    if not isValid(widgetClass) then
        log("live: UMG.UserWidget not found")
        return
    end
    local needle = substr:lower()
    local n = 0
    ForEachUObject(function(obj)
        if isValid(obj) and not isCdo(obj) then
            local ok, isWidget = pcall(function() return obj:IsA(widgetClass) end)
            if ok and isWidget and matches(obj, needle) then
                n = n + 1
                log(string.format("  live %s  [%s]", fullName(obj), className(obj)))
            end
        end
    end)
    log("live done (" .. n .. " widgets)")
end

--- Print every named widget inside a live UUserWidget's WidgetTree. This is the
--- map we need to find the Settings panel and a row to clone for the slider.
local function dumpWidgetTree(substr)
    local w = findFirstWidget(substr)
    if not w then
        log("tree: no live widget matched '" .. tostring(substr) .. "'")
        return
    end
    log("tree of " .. fullName(w))
    local tree = nil
    pcall(function() tree = w.WidgetTree end)
    if not isValid(tree) then
        log("  no WidgetTree")
        return
    end
    local all = nil
    pcall(function() all = tree.AllWidgets end)
    if type(all) ~= "table" then
        log("  no AllWidgets")
        return
    end
    for i = 1, #all do
        local c = all[i]
        if isValid(c) then
            log(string.format("  [%d] %-36s %s", i, shortName(c), fullName(c:GetClass())))
        end
    end
    log("tree done (" .. #all .. " widgets)")
end

--- File-driven command channel: write a line to cmd.txt next to this script and
--- it is executed on the game thread. Lets us drive discovery without keyboard
--- input (handy under Proton and for automated testing).
local function runCommand(line)
    line = tostring(line or ""):gsub("#.*$", "")
    local parts = {}
    for word in line:gmatch("%S+") do parts[#parts + 1] = word end
    local c = (parts[1] or ""):lower()
    if c == "" then return end
    log("command: " .. line)
    if c == "dump" then
        dumpUISettings()
    elseif c == "scale" then
        applyScale(parts[2])
    elseif c == "classes" then
        probeClasses(parts[2])
    elseif c == "widgets" then
        probeWidgets(parts[2])
    elseif c == "live" then
        probeLiveWidgets(parts[2])
    elseif c == "props" then
        probeProps(parts[2])
    elseif c == "tree" then
        dumpWidgetTree(parts[2])
    elseif c == "objprops" then
        probeAnyProps(parts[2])
    elseif c == "get" then
        getPropPath(parts[2], parts[3])
    elseif c == "settingdata" then
        probeSettingData(parts[2])
    elseif c == "uiscale_install" then
        installOption()
    elseif c == "uiscale_addrow" then
        addRow()
    elseif c == "uiscale_set" then
        setSlider(parts[2])
    elseif c == "uiscale_scrollto" then
        scrollToRow()
    elseif c == "uiscale_status" then
        uiscaleStatus()
    elseif c == "uiscale_select" then
        selectRow()
    elseif c == "uiscale_focusinfo" then
        focusInfo()
    elseif c == "uiscale_selectindex" then
        selectIndex(parts[2])

    elseif c == "press" then
        pressButton(parts[2])
    elseif c == "funcs" then
        probeFunctions(parts[2])
    elseif c == "invoke" then
        invokeFunction(parts[2], parts[3], parts[4], parts[5])
    elseif c == "sdk" then
        local ok, err = pcall(function() GenerateSDK() end)
        log("GenerateSDK ok=" .. tostring(ok) .. " err=" .. tostring(err))
    elseif c == "uht" then
        local ok, err = pcall(function() GenerateUHTCompatibleHeaders() end)
        log("GenerateUHTCompatibleHeaders ok=" .. tostring(ok) .. " err=" .. tostring(err))
    elseif c == "objdump" then
        local ok, err = pcall(function() DumpAllObjects() end)
        log("DumpAllObjects ok=" .. tostring(ok) .. " err=" .. tostring(err))
    else
        log("unknown command: " .. c)
    end
end

-- ---------------------------------------------------------------------------
-- Console commands
-- ---------------------------------------------------------------------------

safe("register uis_dump", function()
    RegisterConsoleCommandHandler("uis_dump", function()
        onGameThread(dumpUISettings)
        return true
    end)
end)

safe("register uis_scale", function()
    RegisterConsoleCommandHandler("uis_scale", function(_, params)
        applyScale(params and params[1])
        return true
    end)
end)

safe("register uis_classes", function()
    RegisterConsoleCommandHandler("uis_classes", function(_, params)
        onGameThread(function() probeClasses(params and params[1]) end)
        return true
    end)
end)

safe("register uis_widgets", function()
    RegisterConsoleCommandHandler("uis_widgets", function(_, params)
        onGameThread(function() probeWidgets(params and params[1]) end)
        return true
    end)
end)

safe("register uis_props", function()
    RegisterConsoleCommandHandler("uis_props", function(_, params)
        onGameThread(function() probeProps(params and params[1]) end)
        return true
    end)
end)

-- ---------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------

safe("register F8/F9/F10", function()
    local step = tonumber(config.step) or 0.1
    RegisterKeyBind(Key.F8, function() applyScale(currentScale - step) end)
    RegisterKeyBind(Key.F9, function() applyScale(currentScale + step) end)
    RegisterKeyBind(Key.F10, function() applyScale(1.0) end)
end)

-- Intercept the game's by-name option apply so our injected "UI Scale" row
-- actually drives ApplicationScale. The game's own C++ has no UI Scale case.
safe("hook SettingWidget:ChangeOptionFlt", function()
    RegisterHook("/Script/Librarian.SettingWidget:ChangeOptionFlt",
        function(self, optionName, delta, returnValue)
            local name = optionName
            if type(name) ~= "string" then
                local ok, s = pcall(function() return name:ToString() end)
                if ok then name = s end
            end
            if tostring(name) == UI_SCALE_NAME then
                local d = tonumber(delta) or 0
                log(string.format("hook ChangeOptionFlt '%s' delta=%s", tostring(name), tostring(delta)))
                applyScale(currentScale + d, false, true)
                pcall(function() returnValue.FloatValue = currentScale end)
            end
        end)
    log("hook ChangeOptionFlt registered")
end)

-- Inject the UI Scale row whenever the Game Settings panel initialises.
safe("hook SettingWidget:RefreshSettings", function()
    RegisterHook("/Script/Librarian.SettingWidget:RefreshSettings",
        function(self) end,
        function(self)
            pcall(function()
                if isValid(self) and className(self) == "GameSettingsOptionsUMG_C" then
                    attachRow(self)
                end
            end)
        end)
    log("hook RefreshSettings registered")
end)

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

LoopAsync(3000, function()
    local s = getUISettings()
    if not s then
        log("UserInterfaceSettings not loaded yet; retrying...")
        return false
    end
    log("ready. F8/F9 scale -/+, F10 reset.")
    log("console: uis_dump | uis_scale <n> | uis_classes [s] | uis_widgets [s] | uis_props [s]")
    log("file channel: write e.g. 'classes WBP_' to Scripts/cmd.txt")
    dumpUISettings()
    log(string.format("applying startup scale %.2f", currentScale))
    applyScale(currentScale, false)
    return true
end)

-- Watch the scale file so the value can be changed without restarting the
-- game (useful during development, and a fallback if the UI cannot be used).
local scaleWatch = LoopAsync(1000, function()
    local v = loadPersistedScale()
    if v and (lastApplied == nil or math.abs(v - lastApplied) > 0.001) then
        log(string.format("scale file changed -> %.2f", v))
        applyScale(v, false)
    end
    return false
end)

local cmdTxt = scriptDir .. "cmd.txt"
local lastCmd = nil
local cmdWatch = LoopAsync(1200, function()
    local f = io.open(cmdTxt, "r")
    if f then
        local content = (f:read("*a") or ""):gsub("%s+$", "")
        f:close()
        if content ~= "" and content ~= lastCmd then
            lastCmd = content
            onGameThread(function() runCommand(content) end)
        end
    end
    return false
end)

-- Inject the UI Scale row as soon as the Game Settings panel exists, and again
-- if the panel is rebuilt (closing and reopening Settings).
--- Is our row currently attached to this panel's scroll box? After the menu is
--- cancelled and reopened the row survives as an object but is orphaned
--- (GetParent() returns none), so IsValid alone is not enough.
local function rowAttachedTo(panel)
    local row = _G.LibrarianUIScale_row
    if not isValid(row) then return false end
    local parent, box = nil, nil
    pcall(function() parent = row:GetParent() end)
    pcall(function() box = panel.OptionsBox end)
    if not isValid(parent) or not isValid(box) then return false end
    return fullName(parent) == fullName(box)
end

-- Inject almost immediately after the player opens Settings (title or pause
-- menu), so the row does not visibly pop in. The fast poll below is the
-- fallback for any other way the menu can be opened.
local function scheduleInject(delayMs)
    LoopAsync(delayMs or 50, function()
        local panel = firstLiveObject("GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget")
        if isValid(panel) and not rowAttachedTo(panel) then
            attachRow(panel)
        end
        return true
    end)
end

-- Blueprint functions are not loaded when the mod starts, so register these
-- lazily (once the game classes exist) and isolate each one.
local hookedPaths = {}
local function registerOpenHooks()
    local handlers = {
        "/Game/Librarian/UI/Title/WBP_Title.WBP_Title_C:BndEvt__WBP_Title_Button_Options_K2Node_ComponentBoundEvent_1_OnButtonPressedEvent__DelegateSignature",
        "/Game/Librarian/UI/Title/WBP_PauseMenu.WBP_PauseMenu_C:BndEvt__WBP_PauseMenu_Button_Option_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature",
    }
    for _, path in ipairs(handlers) do
        if not hookedPaths[path] then
            local ok, err = pcall(function()
                RegisterHook(path, function(self) end, function(self) scheduleInject(50) end)
            end)
            if ok then
                hookedPaths[path] = true
                log("hooked open handler: " .. path)
            else
                log("could not hook " .. path .. ": " .. tostring(err))
            end
        end
    end
end

-- Fast poll. The Settings panel is cached so this only costs a couple of cheap
-- method calls per tick; a full object scan happens only if the cached panel
-- goes away (e.g. a new game session).
local cachedPanel = nil
local openHooksTried = false
LoopAsync(150, function()
    local panel = cachedPanel
    if not isValid(panel) then
        panel = firstLiveObject("GameSettingsOptionsUMG", "/Script/Librarian.SettingWidget")
        cachedPanel = panel
    end
    if not isValid(panel) then return false end
    if not openHooksTried then
        openHooksTried = true
        registerOpenHooks()
    end
    local visible = false
    pcall(function() visible = panel:IsVisible() end)
    if not visible then return false end
    if not rowAttachedTo(panel) then
        attachRow(panel)
    end
    return false
end)

-- Apply changes the player makes by dragging the injected UI Scale slider.
LoopAsync(200, function()
    local row = _G.LibrarianUIScale_row
    if isValid(row) and isValid(row.Slider_Value) then
        local v = nil
        pcall(function() v = row.Slider_Value:GetValue() end)
        if v and math.abs(v - currentScale) > 0.001 then
            applyScale(v, true, false)
            pcall(function() row.Option.OptionValue.FloatValue = v end)
        end
    end
    return false
end)
