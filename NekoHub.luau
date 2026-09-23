local SRC = {}
SRC["Library/UI_Library"] = function(...)
--[[
    NekoHub — single-file executor UI template

    Platforms : PC (mouse/keyboard), mobile (touch), gamepad (Selectable + GuiService focus)
    Widgets   : Label, Image, Button, DualButton, Switch, Dropdown (multi flag), DropList, List
    Tabs      : win:Tab("Name") -> tab object with the same widget methods
    Themes    : UI.Themes[name]        — UI.SetTheme(name) recolors everything live
    Images    : cfg.icon sets both the title-bar icon and the floating toggle button

    Load:
        local UI = loadstring(game:HttpGet("your/url/NekoHub.lua"))()
        -- or paste this file above your script and use `UI` directly

    Example at the bottom.
]]

local UIS          = game:GetService("UserInputService")
local GuiService   = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local HttpService  = game:GetService("HttpService")

local TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local UI = {}
UI.__index = UI

UI.Theme = "Dark"
UI._hooks = {}   -- theme re-apply callbacks

UI.Themes = {
    Dark = {
        bg     = Color3.fromRGB(30, 32, 42),
        panel  = Color3.fromRGB(46, 50, 64),
        accent = Color3.fromRGB(88, 176, 255),
        text   = Color3.fromRGB(240, 240, 246),
        dim    = Color3.fromRGB(200, 202, 216),
        border = Color3.fromRGB(74, 80, 100),
    },
    Light = {
        bg     = Color3.fromRGB(238, 238, 242),
        panel  = Color3.fromRGB(255, 255, 255),
        accent = Color3.fromRGB(56, 160, 235),
        text   = Color3.fromRGB(30, 30, 34),
        dim    = Color3.fromRGB(88, 88, 100),
        border = Color3.fromRGB(205, 205, 215),
    },
}

-- ---------------------------------------------------------------- helpers

local function skin(inst, map)
    local function apply()
        local th = UI.Themes[UI.Theme]
        for prop, key in pairs(map) do inst[prop] = th[key] end
    end
    apply()
    table.insert(UI._hooks, apply)
end

local function bind(inst, str, prop, fmt)
    prop = prop or "Text"
    inst[prop] = fmt and fmt:format(str) or str
end

local function round(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
end

local function stroke(inst, key, tr)
    local s = Instance.new("UIStroke")
    s.Thickness = 1
    s.Transparency = tr or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    skin(s, { Color = key or "border" })
    s.Parent = inst
    return s
end

-- vertical gradient, follows theme (fn: theme -> ColorSequence)
local function grad(inst, fn)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    local function apply() g.Color = fn(UI.Themes[UI.Theme]) end
    apply()
    table.insert(UI._hooks, apply)
    g.Parent = inst
    return g
end

-- subtle accent-tinted hover on neutral-panel widgets
local function hover(inst)
    inst.MouseEnter:Connect(function()
        local th = UI.Themes[UI.Theme]
        TweenService:Create(inst, TWEEN, { BackgroundColor3 = th.panel:Lerp(th.accent, 0.18) }):Play()
    end)
    inst.MouseLeave:Connect(function()
        TweenService:Create(inst, TWEEN, { BackgroundColor3 = UI.Themes[UI.Theme].panel }):Play()
    end)
end

local function mount(gui)
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then gui.Parent = h return end
    end
    if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function draggable(handle, target, onEnd)
    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local start, orig, moved = input.Position, target.Position, false
        local dead = false
        local conn
        conn = UIS.InputChanged:Connect(function(m)
            if dead then return end
            if m.UserInputType ~= Enum.UserInputType.MouseMovement
                and m.UserInputType ~= Enum.UserInputType.Touch then return end
            local d = m.Position - start
            moved = moved or d.Magnitude > 4
            target.Position = UDim2.new(orig.X.Scale, orig.X.Offset + d.X,
                                        orig.Y.Scale, orig.Y.Offset + d.Y)
        end)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dead = true
                conn:Disconnect()
                if onEnd then onEnd(moved) end
            end
        end)
    end)
end

local function mkPage()
    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.fromScale(1, 1)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.CanvasSize = UDim2.new()
    sf.ScrollBarThickness = 4
    skin(sf, { ScrollBarImageColor3 = "accent" })
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sf
    local p = Instance.new("UIPadding")
    p.PaddingTop, p.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
    p.PaddingLeft, p.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
    p.Parent = sf
    return sf
end

-- widget parent: tab page, or an auto-created default tab on the window
local function curPage(self)
    if not self._body then self:Tab("Main") end
    return self._body
end

-- ---------------------------------------------------------------- config
-- persists widget state to executor workspace (NekoHub/*.json); no-op without file api

local CFG_DIR = "NekoHub"

local function cfgRead(path)
    if not (isfile and readfile and isfile(path)) then return {} end
    local ok, d = pcall(HttpService.JSONDecode, HttpService, readfile(path))
    return (ok and type(d) == "table") and d or {}
end

local function cfgWrite(path, data)
    if not writefile then return end
    pcall(function()
        if makefolder then pcall(makefolder, CFG_DIR) end
        writefile(path, HttpService:JSONEncode(data))
    end)
end

local function cfgId(self, kind, key)
    return (self._name or "") .. "|" .. kind .. "|" .. tostring(key)
end

-- returns saved value, or nil; invalid values are removed from the store
local function cfgGet(self, kind, key, valid)
    local w = self._win or self
    local id = cfgId(self, kind, key)
    local v = w._save[id]
    if v ~= nil and valid and not valid(v) then
        w._save[id] = nil
        cfgWrite(w._cfgName, w._save)
        v = nil
    end
    return v
end

local function cfgSet(self, kind, key, v)
    local w = self._win or self
    w._save[cfgId(self, kind, key)] = v
    cfgWrite(w._cfgName, w._save)
end

-- ---------------------------------------------------------------- window

function UI.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({}, UI)

    local gui = Instance.new("ScreenGui")
    gui.Name = cfg.name or "NekoHub"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    -- re-execute safe: replace the old window instead of stacking a second one
    do
        local roots = {}
        if gethui then local ok, h = pcall(gethui) if ok and h then table.insert(roots, h) end end
        pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
        local lp = Players.LocalPlayer
        local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
        if pg then table.insert(roots, pg) end
        for _, r in ipairs(roots) do
            for _, d in ipairs(r:GetChildren()) do
                if d:IsA("ScreenGui") and d.Name == gui.Name then pcall(function() d:Destroy() end) end
            end
        end
    end
    mount(gui)

    -- floating toggle (draggable; click toggles, drag doesn't)
    local float = Instance.new("ImageButton")
    float.Name = "Float"
    float.Size = UDim2.fromOffset(48, 48)
    float.Position = UDim2.new(0, 16, 0.5, -24)
    float.Selectable = true
    float.Image = cfg.icon or ""
    skin(float, { BackgroundColor3 = "accent" })
    round(float, 24)
    stroke(float, "border", 0.3)
    if not cfg.icon then
        local t = Instance.new("TextLabel")
        t.Size = UDim2.fromScale(1, 1)
        t.BackgroundTransparency = 1
        t.Text = "☰"
        t.Font = Enum.Font.GothamBold
        t.TextSize = 20
        skin(t, { TextColor3 = "bg" })
        t.Parent = float
    end
    float.Parent = gui
    self._float = float

    -- menu (CanvasGroup so open/close can fade)
    local msz = cfg.size or UDim2.fromOffset(520, 380)
    local menu = Instance.new("CanvasGroup")
    menu.Size = msz
    menu.AnchorPoint = Vector2.new(0.5, 0.5) -- center for any size (custom cfg.size too)
    menu.Position = UDim2.new(0.5, 0, 0.5, 0)
    menu.Visible = cfg.open ~= false
    menu.ClipsDescendants = true
    menu.BackgroundTransparency = 1 -- gradient lives on the bg frame; CanvasGroup gradients dim children
    round(menu, 10)
    stroke(menu)
    local menubg = Instance.new("Frame")
    menubg.Size = UDim2.fromScale(1, 1)
    menubg.BorderSizePixel = 0
    menubg.ZIndex = -1
    skin(menubg, { BackgroundColor3 = "bg" })
    round(menubg, 10)
    grad(menubg, function(th) return ColorSequence.new(th.panel, th.bg) end)
    menubg.Parent = menu
    local scale = Instance.new("UIScale")
    scale.Parent = menu
    menu.Parent = gui

    -- title bar (drag handle)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 36)
    skin(bar, { BackgroundColor3 = "panel" })
    round(bar, 10)
    bar.Parent = menu
    grad(bar, function(th) return ColorSequence.new(th.panel:Lerp(th.accent, 0.14), th.panel) end)
    -- accent hairline under the title bar
    local barline = Instance.new("Frame")
    barline.Size = UDim2.new(1, -20, 0, 1)
    barline.Position = UDim2.new(0, 10, 1, -1)
    barline.BorderSizePixel = 0
    skin(barline, { BackgroundColor3 = "accent" })
    barline.BackgroundTransparency = 0.4
    barline.Parent = bar

    local tx = 10
    if cfg.icon then
        local ic = Instance.new("ImageLabel")
        ic.Size = UDim2.fromOffset(22, 22)
        ic.Position = UDim2.new(0, 8, 0.5, -11)
        ic.BackgroundTransparency = 1
        ic.Image = cfg.icon
        ic.Parent = bar
        tx = 38
    end

    local title = Instance.new("TextLabel")
    title.Position = UDim2.new(0, tx, 0, 0)
    title.Size = UDim2.new(1, -tx - 40, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    skin(title, { TextColor3 = "text" })
    bind(title, cfg.title or "NekoHub")
    title.Parent = bar

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(26, 26)
    close.Position = UDim2.new(1, -31, 0.5, -13)
    close.Text = "✕"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 13
    close.Selectable = true
    skin(close, { BackgroundColor3 = "bg", TextColor3 = "dim" })
    round(close, 13)
    stroke(close)
    close.Parent = bar

    -- sidebar (tab buttons) + pages
    local side = Instance.new("Frame")
    side.Position = UDim2.new(0, 0, 0, 36)
    side.Size = UDim2.new(0, 104, 1, -36)
    side.BackgroundTransparency = 1
    side.Visible = false
    local sl = Instance.new("UIListLayout")
    sl.Padding = UDim.new(0, 6)
    sl.SortOrder = Enum.SortOrder.LayoutOrder
    sl.Parent = side
    local sp = Instance.new("UIPadding")
    sp.PaddingTop, sp.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
    sp.PaddingLeft, sp.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
    sp.Parent = side
    side.Parent = menu

    local pages = Instance.new("Frame")
    pages.Position = UDim2.new(0, 0, 0, 36)
    pages.Size = UDim2.new(1, 0, 1, -36)
    pages.BackgroundTransparency = 1
    pages.Parent = menu

    self._gui, self._menu, self._side, self._pages = gui, menu, side, pages
    self._scale = scale
    self._tabs = {}
    self._name = ""
    self._cfgName = CFG_DIR .. "/" .. (cfg.name or "NekoHub") .. ".json"
    self._save = cfgRead(self._cfgName)
    self._first = close -- gamepad focus falls back to close button

    -- auto-scale UI to viewport
    local vp = workspace.CurrentCamera.ViewportSize
    local s = math.min(1, (vp.X - 40) / math.max(msz.X.Offset, 1),
                        (vp.Y - 40) / math.max(msz.Y.Offset, 1))
    scale.Scale = s
    self._s = s
    local fs = Instance.new("UIScale")
    fs.Scale = s
    fs.Parent = float

    -- toast holder (bottom center, stacks upward)
    local toasts = Instance.new("Frame")
    toasts.Name = "Toasts"
    toasts.AnchorPoint = Vector2.new(0.5, 1)
    toasts.Position = UDim2.new(0.5, 0, 1, -12)
    toasts.Size = UDim2.new(0, 280, 1, -60)
    toasts.BackgroundTransparency = 1
    local tl = Instance.new("UIListLayout")
    tl.Padding = UDim.new(0, 6)
    tl.SortOrder = Enum.SortOrder.LayoutOrder
    tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
    tl.Parent = toasts
    local tsc = Instance.new("UIScale")
    tsc.Scale = s
    tsc.Parent = toasts
    toasts.Parent = gui
    self._toasts = toasts

    -- resize grip (bottom-right corner)
    local grip = Instance.new("TextButton")
    grip.Size = UDim2.fromOffset(16, 16)
    grip.Position = UDim2.new(1, -14, 1, -14)
    grip.Text = ""
    grip.Selectable = false
    skin(grip, { BackgroundColor3 = "accent" })
    grip.BackgroundTransparency = 0.6
    round(grip, 4)
    grip.Parent = menu
    grip.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local start, orig = input.Position, menu.AbsoluteSize
        local dead = false
        local conn
        conn = UIS.InputChanged:Connect(function(m)
            if dead or (m.UserInputType ~= Enum.UserInputType.MouseMovement
                and m.UserInputType ~= Enum.UserInputType.Touch) then return end
            local d = m.Position - start
            menu.Size = UDim2.fromOffset(
                math.clamp(orig.X + d.X, 320, vp.X - 16),
                math.clamp(orig.Y + d.Y, 240, vp.Y - 16))
        end)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dead = true
                conn:Disconnect()
            end
        end)
    end)

    draggable(bar, menu)
    local floatMoved = false
    draggable(float, float, function(m) floatMoved = m end)
    float.Activated:Connect(function()
        if floatMoved then floatMoved = false return end
        self:Toggle()
    end)
    close.Activated:Connect(function() self:Close() end)

    UIS.InputBegan:Connect(function(i, gpe)
        if gpe then return end
        if i.KeyCode == (cfg.toggleKey or Enum.KeyCode.RightShift)
            or i.KeyCode == Enum.KeyCode.ButtonSelect then
            self:Toggle()
        end
    end)

    if menu.Visible then -- intro animation when starting open
        menu.GroupTransparency = 1
        scale.Scale = s * 0.92
        TweenService:Create(menu, TWEEN, { GroupTransparency = 0 }):Play()
        TweenService:Create(scale, TWEEN, { Scale = s }):Play()
    end

    return self
end

function UI:Toggle()
    local menu = self._menu
    if not menu.Visible then -- open: fade + scale in
        menu.Visible = true
        menu.GroupTransparency = 1
        self._scale.Scale = self._s * 0.92
        TweenService:Create(menu, TWEEN, { GroupTransparency = 0 }):Play()
        TweenService:Create(self._scale, TWEEN, { Scale = self._s }):Play()
        if UIS:GetLastInputType().Name:match("Gamepad") then
            GuiService.SelectedObject = self._first
        end
    else -- close: fade + scale out, then hide
        TweenService:Create(self._scale, TWEEN, { Scale = self._s * 0.92 }):Play()
        local tw = TweenService:Create(menu, TWEEN, { GroupTransparency = 1 })
        tw:Play()
        tw.Completed:Connect(function(s)
            if s == Enum.PlaybackState.Completed then menu.Visible = false end
        end)
        if GuiService.SelectedObject
            and GuiService.SelectedObject:IsDescendantOf(menu) then
            GuiService.SelectedObject = nil
        end
    end
end

function UI:Open()  if not self._menu.Visible then self:Toggle() end end
function UI:Close() if self._menu.Visible then self:Toggle() end end
function UI:Destroy() self._gui:Destroy() end
function UI:SetFloatVisible(v)
    local w = self._win or self
    if w._float then w._float.Visible = v ~= false end
end

-- ---------------------------------------------------------------- toasts

function UI:Notify(text, dur)
    self._toastN = (self._toastN or 0) + 1
    local t = Instance.new("CanvasGroup")
    t.Size = UDim2.new(1, 0, 0, 34)
    t.GroupTransparency = 1
    t.LayoutOrder = self._toastN
    skin(t, { BackgroundColor3 = "panel" })
    round(t, 8)
    stroke(t)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 1, 0)
    skin(bar, { BackgroundColor3 = "accent" })
    bar.Parent = t
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 1, 0)
    l.Position = UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    skin(l, { TextColor3 = "text" })
    bind(l, text)
    l.Parent = t
    t.Parent = self._toasts
    TweenService:Create(t, TWEEN, { GroupTransparency = 0 }):Play()
    task.delay(dur or 3, function()
        local tw = TweenService:Create(t, TWEEN, { GroupTransparency = 1 })
        tw.Completed:Connect(function() t:Destroy() end)
        tw:Play()
    end)
    return t
end

-- ---------------------------------------------------------------- tabs

function UI:Tab(name)
    if #self._tabs == 0 then -- first tab: reveal sidebar, shrink page area
        self._side.Visible = true
        self._pages.Position = UDim2.new(0, 104, 0, 36)
        self._pages.Size = UDim2.new(1, -104, 1, -36)
    end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Selectable = true
    bind(btn, name)
    round(btn, 6)
    btn.Parent = self._side

    local page = mkPage()
    page.Visible = #self._tabs == 0
    page.Parent = self._pages

    local tab = setmetatable({ _body = page, _win = self, _name = name }, UI)
    table.insert(self._tabs, tab)
    self._body = self._body or page
    self._cur = self._cur or tab

    local function paint()
        local th = UI.Themes[UI.Theme]
        local on = self._cur == tab
        btn.BackgroundColor3 = on and th.accent or th.panel
        btn.TextColor3 = on and th.bg or th.text
    end
    tab._paint = paint
    skin(btn, { BackgroundColor3 = "panel", TextColor3 = "text" })
    table.insert(UI._hooks, paint) -- runs after skin's hook, so active state wins
    paint()

    btn.Activated:Connect(function()
        self._cur = tab
        for _, t in ipairs(self._tabs) do
            t._body.Visible = t == tab
            t._paint()
        end
        page.Position = UDim2.fromOffset(18, 0) -- slide-in
        TweenService:Create(page, TWEEN, { Position = UDim2.new() }):Play()
        if UIS:GetLastInputType().Name:match("Gamepad") then
            GuiService.SelectedObject = tab._first or self._first
        end
    end)
    return tab
end

-- ---------------------------------------------------------------- widgets

local function optBtn(parent, key, cb)
    local o = Instance.new("TextButton")
    o.Size = UDim2.new(1, 0, 0, 26)
    o.Font = Enum.Font.Gotham
    o.TextSize = 13
    o.Selectable = true
    skin(o, { BackgroundColor3 = "bg", TextColor3 = "dim" })
    bind(o, key)
    round(o, 6)
    stroke(o, "border", 0.5)
    o.Parent = parent
    o.Activated:Connect(function() cb(key) end)
    return o
end

function UI:Label(text, center)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 20)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextXAlignment = center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
    skin(l, { TextColor3 = "dim" })
    bind(l, text)
    l.Parent = curPage(self)
    return l
end

function UI:Image(id, h)
    h = h or 72
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, h)
    row.BackgroundTransparency = 1
    row.Parent = curPage(self)
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.fromOffset(h, h)
    img.Position = UDim2.new(0.5, -h / 2, 0, 0)
    img.BackgroundTransparency = 1
    img.Image = id
    round(img, h / 2)
    img.Parent = row
    return img
end

function UI:Button(text, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.Selectable = true
    skin(b, { BackgroundColor3 = "panel", TextColor3 = "text" })
    bind(b, text)
    round(b, 6)
    stroke(b)
    hover(b)
    b.Parent = curPage(self)
    self._first = self._first or b
    if cb then b.Activated:Connect(cb) end
    return b
end

function UI:DualButton(leftText, rightText, onLeft, onRight)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundTransparency = 1
    row.Parent = curPage(self)
    local function mk(text, cb, left)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -3, 1, 0)
        b.Position = left and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, 3, 0, 0)
        b.Font = Enum.Font.Gotham
        b.TextSize = 14
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Selectable = true
        skin(b, { BackgroundColor3 = "panel", TextColor3 = "text" })
        bind(b, text)
        round(b, 6)
        stroke(b)
        hover(b)
        b.Parent = row
        self._first = self._first or b
        if cb then b.Activated:Connect(cb) end
        return b
    end
    return { left = mk(leftText, onLeft, true), right = mk(rightText, onRight, false) }
end

function UI:Switch(text, default, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.Text = ""
    b.Selectable = true
    skin(b, { BackgroundColor3 = "panel" })
    round(b, 6)
    stroke(b)
    hover(b)
    b.Parent = curPage(self)
    self._first = self._first or b

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -52, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    skin(lbl, { TextColor3 = "text" })
    bind(lbl, text)
    lbl.Parent = b

    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(36, 18)
    pill.Position = UDim2.new(1, -44, 0.5, -9)
    round(pill, 9)
    stroke(pill, "border", 0.4)
    pill.Parent = b

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    round(knob, 7)
    skin(knob, { BackgroundColor3 = "text" })
    knob.Parent = pill

    local saved = cfgGet(self, "Switch", text, function(v) return type(v) == "boolean" end)
    local on = saved ~= nil and saved or default == true
    local function render(anim)
        local th = UI.Themes[UI.Theme]
        local col = on and th.accent or th.bg
        local pos = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if anim then
            TweenService:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = col }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = pos }):Play()
        else
            pill.BackgroundColor3 = col
            knob.Position = pos
        end
    end
    render(false)
    table.insert(UI._hooks, function() render(false) end)

    b.Activated:Connect(function()
        on = not on
        render(true)
        cfgSet(self, "Switch", text, on)
        if cb then cb(on) end
    end)
    if saved ~= nil and cb then task.defer(cb, on) end -- restore saved state
    return { -- programmatic control without firing cb (UI sync)
        Set = function(v)
            v = v == true
            if v == on then return end
            on = v
            render(true)
            cfgSet(self, "Switch", text, on)
        end,
        Get = function() return on end,
    }
end

-- multi: options toggle instead of select; cb(opt, on, selectedSet); box stays open
function UI:Dropdown(text, options, cb, multi)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 30)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = curPage(self)
    local hl = Instance.new("UIListLayout")
    hl.Padding = UDim.new(0, 4)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Parent = holder

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 30)
    head.Font = Enum.Font.Gotham
    head.TextSize = 14
    head.Selectable = true
    skin(head, { BackgroundColor3 = "panel", TextColor3 = "text" })
    bind(head, text, "Text", "%s  ▾")
    round(head, 6)
    stroke(head)
    hover(head)
    head.Parent = holder
    self._first = self._first or head

    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.BackgroundTransparency = 1
    box.Visible = false
    local bl = Instance.new("UIListLayout")
    bl.Padding = UDim.new(0, 4)
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Parent = box
    box.Parent = holder

    head.Activated:Connect(function()
        box.Visible = not box.Visible
        if box.Visible then -- stagger-fade options in
            local i = 0
            for _, o in ipairs(box:GetChildren()) do
                if o:IsA("TextButton") then
                    i = i + 1
                    o.TextTransparency = 1
                    o.BackgroundTransparency = 1
                    TweenService:Create(o, TweenInfo.new(0.08 + i * 0.03, Enum.EasingStyle.Quad),
                        { TextTransparency = 0, BackgroundTransparency = 0 }):Play()
                end
            end
        end
    end)

    local sel = {}
    for _, opt in ipairs(options) do
        local o
        o = optBtn(box, opt, function(v)
            if multi then
                sel[v] = not sel[v] or nil
                o.Text = (sel[v] and "✓  " or "") .. v
                if cb then cb(v, sel[v] == true, sel) end
            else
                head.Text = ("%s  ▾"):format(v) -- header follows selection
                box.Visible = false
                cfgSet(self, "Dropdown", text, v)
                if cb then cb(v) end
            end
        end)
    end
    if not multi then -- restore saved selection (invalid values auto-dropped by cfgGet)
        local saved = cfgGet(self, "Dropdown", text, function(v) return table.find(options, v) ~= nil end)
        if saved ~= nil then
            head.Text = ("%s  ▾"):format(saved)
            if cb then task.defer(cb, saved) end
        end
    end
    return head
end

-- collapsible multi-select listbox: rows toggle, cb(opt, on, selectedSet)
-- returns { Get = fn -> set, Set = fn(opt, on) }
function UI:DropList(text, options, cb, height)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 30)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = curPage(self)
    local hl = Instance.new("UIListLayout")
    hl.Padding = UDim.new(0, 4)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Parent = holder

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 30)
    head.Font = Enum.Font.Gotham
    head.TextSize = 14
    head.Selectable = true
    skin(head, { BackgroundColor3 = "panel", TextColor3 = "text" })
    bind(head, text, "Text", "%s  ▾")
    round(head, 6)
    stroke(head)
    hover(head)
    head.Parent = holder
    self._first = self._first or head

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, 0, 0, height or 110)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.CanvasSize = UDim2.new()
    sf.ScrollBarThickness = 4
    sf.BorderSizePixel = 0
    skin(sf, { BackgroundColor3 = "panel", ScrollBarImageColor3 = "accent" })
    round(sf, 6)
    stroke(sf)
    local sl = Instance.new("UIListLayout")
    sl.Padding = UDim.new(0, 4)
    sl.SortOrder = Enum.SortOrder.LayoutOrder
    sl.Parent = sf
    local sp = Instance.new("UIPadding")
    sp.PaddingTop, sp.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
    sp.PaddingLeft, sp.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
    sp.Parent = sf
    sf.Visible = false
    sf.Parent = holder
    head.Activated:Connect(function()
        sf.Visible = not sf.Visible
        if sf.Visible then -- stagger-fade rows in
            local i = 0
            for _, o in ipairs(sf:GetChildren()) do
                if o:IsA("TextButton") then
                    i = i + 1
                    o.TextTransparency = 1
                    o.BackgroundTransparency = 1
                    TweenService:Create(o, TweenInfo.new(0.08 + i * 0.03, Enum.EasingStyle.Quad),
                        { TextTransparency = 0, BackgroundTransparency = 0 }):Play()
                end
            end
        end
    end)

    local sel, paints = {}, {}

    local function syncHead() -- header shows the selection instead of the label
        local on = {}
        for _, o in ipairs(options) do
            if sel[o] then table.insert(on, o) end
        end
        head.Text = #on > 0 and (table.concat(on, ", ") .. "  ▾")
            or ("%s  ▾"):format(text)
    end

    local function commit()
        local arr = {}
        for _, o in ipairs(options) do if sel[o] then table.insert(arr, o) end end
        cfgSet(self, "DropList", text, arr)
        syncHead()
    end

    -- restore saved selection; options that no longer exist are dropped + written back
    local restored = {}
    local saved = cfgGet(self, "DropList", text, function(v) return type(v) == "table" end)
    if saved then
        for _, v in ipairs(saved) do
            if table.find(options, v) then
                sel[v] = true
                table.insert(restored, v)
            end
        end
        if #restored ~= #saved then cfgSet(self, "DropList", text, restored) end
    end

    for _, opt in ipairs(options) do
        local o = optBtn(sf, opt, function() end)
        local function paint()
            local th = UI.Themes[UI.Theme]
            local on = sel[opt] == true
            o.BackgroundColor3 = on and th.accent or th.panel
            o.TextColor3 = on and th.bg or th.text
        end
        paints[opt] = paint
        table.insert(UI._hooks, paint) -- after optBtn's skin hook, state wins
        paint()
        o.Activated:Connect(function()
            sel[opt] = not sel[opt] or nil
            paint()
            commit()
            if cb then cb(opt, sel[opt] == true, sel) end
        end)
    end
    syncHead()
    for _, v in ipairs(restored) do -- fire restored selections
        if cb then task.defer(cb, v, true, sel) end
    end

    return {
        Get = function() return sel end,
        Set = function(v, on)
            sel[v] = on or nil
            if paints[v] then paints[v]() end
            commit()
        end,
    }
end

-- horizontal drag slider: UI:Slider("Perfect Rate", 0, 100, 0, function(v) end)
-- integer steps; persists on release; returns { Get = fn -> number, Set = fn(n) }
function UI:Slider(text, min, max, default, cb)
    min, max = min or 0, max or 100
    if max < min then min, max = max, min end
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 46)
    holder.BackgroundTransparency = 1
    holder.Parent = curPage(self)
    local hl = Instance.new("UIListLayout")
    hl.Padding = UDim.new(0, 4)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Parent = holder

    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, 0, 0, 20)
    top.BackgroundTransparency = 1
    top.Parent = holder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    skin(lbl, { TextColor3 = "text" })
    bind(lbl, text)
    lbl.Parent = top

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0, 50, 1, 0)
    val.Position = UDim2.new(1, -50, 0, 0)
    val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold
    val.TextSize = 14
    val.TextXAlignment = Enum.TextXAlignment.Right
    skin(val, { TextColor3 = "text" })
    val.Parent = top

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, 0, 0, 14)
    track.Text = ""
    track.AutoButtonColor = false
    skin(track, { BackgroundColor3 = "bg" })
    round(track, 7)
    track.Parent = holder
    self._first = self._first or track

    local fill = Instance.new("Frame")
    skin(fill, { BackgroundColor3 = "accent" })
    round(fill, 7)
    fill.Parent = track

    local v = default or min
    local function paint()
        val.Text = tostring(v)
        fill.Size = UDim2.new(max > min and (v - min) / (max - min) or 0, 0, 1, 0)
    end

    local function setV(px)
        v = math.clamp(math.floor((px - track.AbsolutePosition.X)
            / math.max(track.AbsoluteSize.X, 1) * (max - min) + 0.5) + min, min, max)
        paint()
        if cb then cb(v) end
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        setV(input.Position.X)
        local dead = false
        local conn
        conn = UIS.InputChanged:Connect(function(m)
            if not dead and (m.UserInputType == Enum.UserInputType.MouseMovement
                or m.UserInputType == Enum.UserInputType.Touch) then
                setV(m.Position.X)
            end
        end)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dead = true
                conn:Disconnect()
                cfgSet(self, "Slider", text, v) -- persist on release, like ColorPicker
            end
        end)
    end)
    paint()

    -- restore saved value (invalid values auto-dropped by cfgGet)
    local saved = cfgGet(self, "Slider", text, function(sv)
        return type(sv) == "number" and sv >= min and sv <= max
    end)
    if saved ~= nil then
        v = math.floor(saved + 0.5)
        paint()
        if cb then task.defer(cb, v) end
    end

    return {
        Get = function() return v end,
        Set = function(n)
            v = math.clamp(math.floor((tonumber(n) or min) + 0.5), min, max)
            paint()
            cfgSet(self, "Slider", text, v)
        end,
    }
end

-- collapsible label group: sec:Switch/Button/... put widgets inside; head click hides them
-- side-by-side column hosts: local cols = vis:Columns(2); cols[1]:Section(...)
-- same _name path as the parent, so persisted keys don't change
function UI:Columns(n)
    n = (type(n) == "number" and n >= 1) and math.floor(n) or 2
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1
    row.Parent = curPage(self)
    local lay = Instance.new("UIListLayout")
    lay.FillDirection = Enum.FillDirection.Horizontal
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = row
    local cols = {}
    for i = 1, n do
        local col = Instance.new("Frame")
        col.Size = UDim2.new(1 / n, -(6 * (n - 1) / n), 0, 0)
        col.AutomaticSize = Enum.AutomaticSize.Y
        col.BackgroundTransparency = 1
        col.LayoutOrder = i
        local lay2 = Instance.new("UIListLayout")
        lay2.Padding = UDim.new(0, 6)
        lay2.SortOrder = Enum.SortOrder.LayoutOrder
        lay2.Parent = col
        col.Parent = row
        cols[i] = setmetatable({ _body = col, _win = self._win or self, _name = self._name or "" }, UI)
    end
    return cols
end

function UI:Section(text, sub)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 22)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = curPage(self)
    local hl = Instance.new("UIListLayout")
    hl.Padding = UDim.new(0, 4)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Parent = holder

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 22)
    head.BackgroundTransparency = 1
    head.Font = Enum.Font.GothamBold
    head.TextSize = 13
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.Selectable = true
    skin(head, { TextColor3 = "text" })
    head.Parent = holder
    self._first = self._first or head

    local secbar = Instance.new("Frame") -- accent tick left of the label
    secbar.Size = UDim2.fromOffset(3, 12)
    secbar.Position = UDim2.new(0, 0, 0.5, -6)
    secbar.BorderSizePixel = 0
    round(secbar, 2)
    skin(secbar, { BackgroundColor3 = "accent" })
    secbar.Parent = head
    head.TextXAlignment = Enum.TextXAlignment.Left
    local hpad = Instance.new("UIPadding")
    hpad.PaddingLeft = UDim.new(0, 10)
    hpad.Parent = head
    head.LayoutOrder = 0

    if sub and sub ~= "" then -- dim one-liner under the header (stays visible when collapsed)
        local subLbl = Instance.new("TextLabel")
        subLbl.Size = UDim2.new(1, 0, 0, 16)
        subLbl.BackgroundTransparency = 1
        subLbl.Font = Enum.Font.Gotham
        subLbl.TextSize = 12
        subLbl.TextXAlignment = Enum.TextXAlignment.Left
        subLbl.TextTruncate = Enum.TextTruncate.AtEnd
        subLbl.LayoutOrder = 1
        skin(subLbl, { TextColor3 = "dim" })
        bind(subLbl, sub)
        local spad = Instance.new("UIPadding")
        spad.PaddingLeft = UDim.new(0, 10)
        spad.Parent = subLbl
        subLbl.Parent = holder
    end

    local body = Instance.new("Frame")
    body.LayoutOrder = 2
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    local bl = Instance.new("UIListLayout")
    bl.Padding = UDim.new(0, 6)
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Parent = body
    local bp = Instance.new("UIPadding")
    bp.PaddingLeft = UDim.new(0, 10)
    bp.Parent = body
    body.Parent = holder

    local open = cfgGet(self, "Section", text, function(v) return type(v) == "boolean" end)
    if open == nil then open = true end
    local function render()
        head.Text = ((open and "▾  " or "▸  ") .. "%s"):format(text)
        body.Visible = open
    end
    render()
    head.Activated:Connect(function()
        open = not open
        render()
        cfgSet(self, "Section", text, open)
    end)

    return setmetatable({
        _body = body,
        _win  = self._win or self,
        _name = (self._name and self._name ~= "") and (self._name .. "/" .. text) or text,
        Show  = function(v) holder.Visible = v ~= false end,
    }, UI)
end

-- sRGB color picker: swatch row expands to R/G/B drag sliders + preview; cb(Color3)
function UI:ColorPicker(text, default, cb)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 30)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = curPage(self)
    local hl = Instance.new("UIListLayout")
    hl.Padding = UDim.new(0, 4)
    hl.SortOrder = Enum.SortOrder.LayoutOrder
    hl.Parent = holder

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 30)
    head.Text = ""
    head.Selectable = true
    skin(head, { BackgroundColor3 = "panel" })
    round(head, 6)
    stroke(head)
    hover(head)
    head.Parent = holder
    self._first = self._first or head

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    skin(lbl, { TextColor3 = "text" })
    bind(lbl, text)
    lbl.Parent = head

    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.fromOffset(30, 16)
    swatch.Position = UDim2.new(1, -40, 0.5, -8)
    round(swatch, 4)
    stroke(swatch)
    swatch.Parent = head

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.fromOffset(14, 14)
    arrow.Position = UDim2.new(1, -20, 0.5, -7)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▾"
    arrow.Font = Enum.Font.Gotham
    arrow.TextSize = 12
    skin(arrow, { TextColor3 = "dim" })
    arrow.Parent = head

    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.BackgroundTransparency = 1
    box.Visible = false
    local bl = Instance.new("UIListLayout")
    bl.Padding = UDim.new(0, 4)
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Parent = box
    box.Parent = holder

    local preview = Instance.new("Frame")
    preview.Size = UDim2.new(1, 0, 0, 18)
    round(preview, 5)
    preview.Parent = box

    head.Activated:Connect(function() box.Visible = not box.Visible end)

    local rgb = { 255, 255, 255 }
    if typeof(default) == "Color3" then
        rgb = { math.floor(default.R * 255 + 0.5), math.floor(default.G * 255 + 0.5),
                math.floor(default.B * 255 + 0.5) }
    end

    local function cur() return Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end
    local function paint()
        local c = cur()
        swatch.BackgroundColor3 = c
        preview.BackgroundColor3 = c
    end

    local rows = {}
    for i, ch in ipairs({ "R", "G", "B" }) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BackgroundTransparency = 1
        row.Parent = box

        local lab = Instance.new("TextLabel")
        lab.Size = UDim2.fromOffset(14, 20)
        lab.BackgroundTransparency = 1
        lab.Text = ch
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 12
        skin(lab, { TextColor3 = "dim" })
        lab.Parent = row

        local val = Instance.new("TextLabel")
        val.Size = UDim2.fromOffset(30, 20)
        val.Position = UDim2.new(1, -30, 0, 0)
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.Gotham
        val.TextSize = 12
        skin(val, { TextColor3 = "text" })
        val.Parent = row

        local track = Instance.new("TextButton")
        track.Size = UDim2.new(1, -52, 0, 10)
        track.Position = UDim2.new(0, 20, 0.5, -5)
        track.Text = ""
        track.AutoButtonColor = false
        skin(track, { BackgroundColor3 = "bg" })
        round(track, 5)
        track.Parent = row

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(rgb[i] / 255, 0, 1, 0)
        skin(fill, { BackgroundColor3 = "accent" })
        round(fill, 5)
        fill.Parent = track

        local function setV(px) -- px = absolute mouse x
            rgb[i] = math.clamp(math.floor(
                (px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1) * 255 + 0.5), 0, 255)
            fill.Size = UDim2.new(rgb[i] / 255, 0, 1, 0)
            val.Text = tostring(rgb[i])
            paint()
            if cb then cb(cur()) end
        end
        track.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then return end
            setV(input.Position.X)
            local dead = false
            local conn
            conn = UIS.InputChanged:Connect(function(m)
                if not dead and (m.UserInputType == Enum.UserInputType.MouseMovement
                    or m.UserInputType == Enum.UserInputType.Touch) then
                    setV(m.Position.X)
                end
            end)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dead = true
                    conn:Disconnect()
                    cfgSet(self, "ColorPicker", text, { rgb[1], rgb[2], rgb[3] })
                end
            end)
        end)
        val.Text = tostring(rgb[i])
        rows[i] = { val = val, fill = fill }
    end

    -- restore saved {r,g,b}
    local saved = cfgGet(self, "ColorPicker", text, function(v)
        return type(v) == "table" and #v == 3
            and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
    end)
    if saved then
        for i = 1, 3 do rgb[i] = math.clamp(math.floor(saved[i]), 0, 255) end
        for i = 1, 3 do
            rows[i].fill.Size = UDim2.new(rgb[i] / 255, 0, 1, 0)
            rows[i].val.Text = tostring(rgb[i])
        end
        if cb then task.defer(cb, cur()) end
    end
    paint()

    return {
        Get = function() return cur() end,
        Set = function(c)
            rgb = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
                    math.floor(c.B * 255 + 0.5) }
            for i = 1, 3 do
                rows[i].fill.Size = UDim2.new(rgb[i] / 255, 0, 1, 0)
                rows[i].val.Text = tostring(rgb[i])
            end
            paint()
            cfgSet(self, "ColorPicker", text, rgb)
        end,
        Show = function(v) holder.Visible = v ~= false end,
    }
end

function UI:List(items, cb, height)
    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, 0, 0, height or 110)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.CanvasSize = UDim2.new()
    sf.ScrollBarThickness = 4
    sf.BorderSizePixel = 0
    skin(sf, { BackgroundColor3 = "panel", ScrollBarImageColor3 = "accent" })
    round(sf, 6)
    stroke(sf)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 4)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = sf
    local p = Instance.new("UIPadding")
    p.PaddingTop, p.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
    p.PaddingLeft, p.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
    p.Parent = sf
    sf.Parent = curPage(self)
    for _, it in ipairs(items) do
        optBtn(sf, it, function(v) if cb then cb(v) end end)
    end
    return sf
end

-- ---------------------------------------------------------------- config

function UI.SetTheme(name)
    if not UI.Themes[name] then return end
    UI.Theme = name
    cfgWrite(CFG_DIR .. "/global.json", { _theme = UI.Theme })
    for _, f in ipairs(UI._hooks) do f() end
end

--[[ ============================ EXAMPLE ============================

local UI = loadstring(game:HttpGet("your/url/NekoHub.lua"))()

local win = UI.new{
    title  = "NekoHub",
    icon   = "rbxassetid://1234567890",   -- menu icon + floating button image
    -- size = UDim2.fromOffset(500, 380),
    -- toggleKey = Enum.KeyCode.RightShift,  -- ButtonSelect (gamepad) always works
}

win:Label("Speed")
win:Button("Speed", function() print("clicked") end)
win:Switch("Fly", false, function(on) print("fly:", on) end)
win:Dropdown("Theme", {"Dark", "Light"}, function(v) UI.SetTheme(v) end)

local names = {}
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    table.insert(names, p.Name)
end
win:List(names, function(name) print("picked", name) end)

================================================================== ]]

-- persisted theme (invalid theme names are ignored)
do
    local g = cfgRead(CFG_DIR .. "/global.json")
    if type(g._theme) == "string" and UI.Themes[g._theme] then UI.Theme = g._theme end
end

return UI

end
SRC["main"] = function(...)
-- main.luau — shared hub, loaded by games/*.luau (or directly)

local cfg = getgenv().NekoHubConfig or {}
getgenv().NEKOHUB_BASE = getgenv().NEKOHUB_BASE
    or "https://raw.githubusercontent.com/USER/REPO/refs/heads/main/" -- standalone fallback (no loader)
local import = getgenv().import or function(p)
    return loadstring(game:HttpGet(getgenv().NEKOHUB_BASE .. p .. ".luau"))()
end
local UI = import("Library/UI_Library")

local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local api     = getgenv().GameAPI

local win = UI.new{
    title = cfg.title or "NekoHub",
    icon  = cfg.icon,
    size  = cfg.size,
}

local enSw -- ESP master switch; re-synced when SetCat auto-enables (see Visuals)
local detSw -- Player Details master switch; same re-sync pattern
local genSw -- Generator Details master switch; independent from Player
local sk -- Skeleton switch; lives in Player section

-- ---- Home (first menu) --------------------------------------------------------

local home = win:Tab("Home")

local ok, thumb = pcall(Players.GetUserThumbnailAsync, Players, player.UserId,
    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
if ok then home:Image(thumb, 72) end

home:Label(("%s (@%s)"):format(player.DisplayName, player.Name), true)

if api and api.TeamName then
    local tl = home:Label("Team: " .. api.TeamName(), true)
    player:GetPropertyChangedSignal("Team"):Connect(function()
        tl.Text = "Team: " .. api.TeamName()
    end)
end

for _, attr in ipairs(api and api.Currencies or {}) do
    local lbl = home:Label(("%s: %s"):format(attr, player:GetAttribute(attr) or 0), true)
    player:GetAttributeChangedSignal(attr):Connect(function()
        lbl.Text = ("%s: %s"):format(attr, player:GetAttribute(attr) or 0)
    end)
end

-- ---- Visuals ---------------------------------------------------------------

if api and api.ESP then
    local vis = win:Tab("Visuals")
    local ov = vis:Section("Overlay")
    if api.Overlay then
        -- skeleton covers Killer + Survivor automatically (no target select)
        if api.Overlay.SetFPS then -- skeleton draw rate cap (120 = ~uncapped)
            ov:Slider("FPS", 30, 120, 120, function(v)
                api.Overlay.SetFPS(v)
            end)
        end
    end
    if api.Details then -- overhead labels live under Overlay, side-by-side
        local cols = ov:Columns(2) -- Player Details left, Generator Details right
        local pdt = cols[1]:Section("Player", "Name, distance and skeleton")
        detSw = pdt:Switch("Enabled", api.Details.on == true, function(on) api.Details.Set(on) end)
        if api.Overlay then -- skeleton lines switch lives with the other player visuals
            sk = pdt:Switch("Skeleton", api.Overlay.on == true, function(on) api.Overlay.Set(on) end)
        end
        for _, flag in ipairs({ "Name", "Distance" }) do
            pdt:Switch(flag, api.Details.cats[flag] == true, function(on)
                api.Details.SetCat(flag, on)
                detSw.Set(api.Details.on == true) -- SetCat auto-enables: keep the switch in sync
            end)
        end
        local gdt = cols[2]:Section("Generator Details", "Progress, kicks and repairers")
        if api.Details.SetGen then -- independent generator master (not linked to Player)
            genSw = gdt:Switch("Enabled", api.Details.gen == true, function(on) api.Details.SetGen(on) end)
        end
        for _, flag in ipairs({ "Gen Distance", "Gen %", "Repairers", "Kick" }) do
            gdt:Switch(flag, api.Details.cats[flag] == true, function(on)
                api.Details.SetCat(flag, on)
                if genSw then
                    genSw.Set(api.Details.gen == true)
                else
                    detSw.Set(api.Details.on == true) -- legacy single-master games
                end
            end)
        end
    end
    local hlsec = vis:Section("Highlight")
    enSw = hlsec:Switch("Enabled", api.ESP.on == true, function(on) api.ESP.Set(on) end)
    local dl = hlsec:DropList("Targets", { "Killer", "Survivor", "Hook", "Generator", "Vault", "Pallet" },
        function(v, on)
            api.ESP.SetCat(v, on)
            enSw.Set(api.ESP.on == true) -- SetCat auto-enables: keep the switch in sync
        end, 110)
    for cat in pairs(api.ESP.cats) do dl.Set(cat, true) end -- sync with current state
    if api.Camera then
        local camsec = vis:Section("Camera")
        camsec:Switch("DBD Camera", api.Camera.on == true, function(on) api.Camera.Set(on) end)
        camsec:Slider("Sensitivity", 2, 30, (api.Camera.sens or 0.009) * 1000, function(v)
            api.Camera.SetSens(v)
        end)
    end
end

-- ---- Auto ------------------------------------------------------------------

if api and api.Auto then
    local au = win:Tab("Auto")
    au:Switch("Skill Check", api.Auto.SkillCheck == true, function(on) api.Auto.Set("SkillCheck", on) end)
    au:Slider("Perfect Rate", 0, 100, 0, function(v)
        api.Auto.Set("PerfectRate", v)
    end)
    if api.Auto.SlashCrouch ~= nil then -- game-specific: Abysswalker slash dodge
        au:Switch("Auto Crouch (Slash)", false, function(on) api.Auto.Set("SlashCrouch", on) end)
    end
    if api.Auto.AutoParry ~= nil then -- game-specific: Parrying Dagger counter
        au:Switch("Auto Parry (Dagger)", false, function(on) api.Auto.Set("AutoParry", on) end)
        au:Slider("Lunge Parry Lead (ms)", 0, 400, api.Auto.ParryLead or 150, function(v)
            api.Auto.Set("ParryLead", v)
        end)
        au:Slider("Parry Range (studs)", 4, 16, api.Auto.ParryRange or 10, function(v)
            api.Auto.Set("ParryRange", v)
        end)
    end
end

-- ---- Settings --------------------------------------------------------------

if api and api.ESP then
    -- user highlight color preferences (persisted per category)
    local set = win:Tab("Settings")
    local matched = {} -- game-sourced pickers, hidden while Match Game Color is on
    local function syncMatch()
        local show = api.ESP.useGameColor == false
        for _, p in pairs(matched) do p.Show(show) end
    end
    set:Switch("Match Game Color", api.ESP.useGameColor ~= false, function(on)
        api.ESP.SetMatchGame(on)
        syncMatch()
    end)
    local colsSec = set:Section("Highlight Color")
    for _, cat in ipairs({ "Killer", "Survivor", "Hook", "Vault", "Pallet" }) do
        local p = colsSec:ColorPicker(cat, api.ESP.GetColor(cat), function(c) api.ESP.SetColor(cat, c) end)
        if cat == "Killer" or cat == "Survivor" or cat == "Hook" then matched[cat] = p end
    end
    syncMatch()
end

win:Notify("NekoHub") -- toast on load

end
SRC["games/ViolenceDistrict"] = function(...)
-- games/ViolenceDistrict.luau — PlaceId 93978595733734

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer

-- re-execute safe: kill previous ESP loop + highlights from an earlier run
do
    local old = getgenv().GameAPI
    if old and old.ESP then pcall(old.ESP.Set, false) end
    if old and old.Details then pcall(old.Details.Set, false) end
    if old and old.Details and old.Details.SetGen then pcall(old.Details.SetGen, false) end
    if old and old.Camera then pcall(old.Camera.Set, false) end
end

-- team API — teams in this game: Survivors / Killer / Spectator (lobby = Spectator)
local function teamName(p)
    p = p or localPlayer
    return p.Team and p.Team.Name or ""
end

local function charsOf(pred)
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and p.Character and pred(p) then
            table.insert(out, p.Character)
        end
    end
    return out
end

-- prop instances are static map geometry: they never spawn mid-match, and
-- destroyed ones are pruned on read below. So the Map snapshot is taken once
-- per map (re-scanned on map swap or every 60s as a safety net) and shared by
-- all four finders; generators re-list from their own folder every 2s (cheap:
-- ~7 children) in case they change mid-match. Character finders stay live.
local DUMMY = Instance.new("Part") -- placeholder; never parented, excludes nothing
-- LOS exclude list, rebuilt by the Map scan: [1]=target [2]=self (mutated per
-- check), then invisible-but-queryable trigger boxes (pallet vault zones, ...)
-- so a visible target reads green instead of false-red
local losExclude = { DUMMY, DUMMY }
local propLists = {}
local mapInst, genFolder, mapScanAt, genListAt = nil, nil, -60, -10
local function ensureMap()
    local map = workspace:FindFirstChild("Map")
    local gf = map and map:FindFirstChild("new Generators")
    local now = os.clock()
    if map == mapInst and gf == genFolder and now - mapScanAt <= 60 then return end
    mapInst, genFolder, mapScanAt = map, gf, now
    if not map then
        propLists = { Hook = {}, Generator = {}, Vault = {}, Pallet = {} }
        losExclude = { DUMMY, DUMMY }
        return
    end
    local hooks, gens, triggers, pals = {}, {}, {}, {}
    local ex = { DUMMY, DUMMY }
    for _, d in ipairs(map:GetDescendants()) do
        local n = d.Name
        if n == "Hook" and d:IsA("Model") then
            hooks[#hooks + 1] = d
        elseif n == "Generator" and d:IsA("Model") then
            gens[#gens + 1] = d
        elseif n == "VaultTrigger" and d:IsA("BasePart") then
            triggers[#triggers + 1] = d
        elseif n == "Palletwrong" and d:IsA("Model") then
            pals[#pals + 1] = d
        end
        if d:IsA("BasePart") and d.Transparency >= 1 and d.CanQuery then
            ex[#ex + 1] = d -- never a visual occluder (VaultTriggers included)
        end
    end
    -- vault marker per window: the Bottom sill, else the trigger itself
    local seen, vaults = {}, {}
    for _, d in ipairs(triggers) do
        local m = d:FindFirstAncestorOfClass("Model")
        if m then
            if not seen[m] then
                seen[m] = true
                vaults[#vaults + 1] = m:FindFirstChild("Bottom") or d
            end
        else
            vaults[#vaults + 1] = d
        end
    end
    propLists = { Hook = hooks, Generator = gens, Vault = vaults, Pallet = pals }
    losExclude = ex
end

-- espTick parents a Highlight into every returned instance, so dead entries
-- (destroyed pallets) must be pruned in place before handing the list out
local function prune(list)
    for i = #list, 1, -1 do
        if list[i].Parent == nil then table.remove(list, i) end
    end
    return list
end

local function props(key)
    ensureMap()
    if key == "Generator" then
        if genFolder then -- live folder listing, refreshed every 2s
            local now = os.clock()
            if now - genListAt > 2 then
                genListAt = now
                local gens = {}
                for _, d in ipairs(genFolder:GetChildren()) do
                    if d.Name == "Generator" and d:IsA("Model") then
                        gens[#gens + 1] = d
                    end
                end
                propLists.Generator = gens
            end
        end
        return prune(propLists.Generator or {})
    end
    return prune(propLists[key] or {})
end

-- highlight ESP (run token kills loops orphaned by re-execution)
local RUN = (getgenv().NEKOHUB_ESP_RUN or 0) + 1
getgenv().NEKOHUB_ESP_RUN = RUN
local ESP = { on = false, cats = {}, custom = {}, useGameColor = true }
local hl = {} -- inst -> {obj, cat}
local COLORS = {
    Killer    = Color3.fromRGB(255, 60, 60),
    Survivor  = Color3.fromRGB(80, 200, 255),
    Hook      = Color3.fromRGB(255, 210, 60),
    Vault     = Color3.fromRGB(190, 120, 255),
    Pallet    = Color3.fromRGB(255, 150, 50),
}
function ESP.SetColor(cat, c) ESP.custom[cat] = c end
-- base colors follow the game's aura settings (LocalPlayer attributes);
-- Neko Settings pickers override both
local AURA_ATTR = { Killer = "killeraura", Survivor = "survaura", Hook = "spikeaura" }
local function baseColor(cat)
    local attr = AURA_ATTR[cat]
    if attr and ESP.useGameColor ~= false then
        local v = localPlayer:GetAttribute(attr)
        if typeof(v) == "Color3" then return v end
    end
    return ESP.custom[cat] or COLORS[cat]
end
function ESP.GetColor(cat) return baseColor(cat) end
function ESP.SetMatchGame(on) ESP.useGameColor = on ~= false end

local GEN_LOW = Color3.fromRGB(255, 210, 60) -- 0% repair
local GEN_HIGH = Color3.fromRGB(120, 255, 140) -- 100% (then hidden)

local function paintEsp(h, c)
    if h:IsA("Highlight") then
        h.FillColor = c
        h.OutlineColor = c
    else
        h.Color3 = c
    end
end

local function espTick()
    if getgenv().GameAPI.IsLobby() then -- no ESP while waiting in lobby
        for inst, e in pairs(hl) do e.obj:Destroy() hl[inst] = nil end
        return
    end
    for cat, on in pairs(ESP.cats) do
        if on then
            for _, inst in ipairs(getgenv().GameAPI.Targets[cat]()) do
                local h = inst:FindFirstChild("NekoESP") -- dedupe by instance, not cache
                if not h then
                    if inst:IsA("BasePart") then
                        h = Instance.new("BoxHandleAdornment") -- renders even on transparent parts
                        h.Adornee = inst
                        h.Size = Vector3.new(inst.Size.X, inst.Size.Y, math.min(inst.Size.Z, 1.5))
                        h.AlwaysOnTop = true
                        h.Transparency = 0.65
                        h.ZIndex = 1
                    else -- Model: Highlight renders even when parts are translucent
                        h = Instance.new("Highlight")
                        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        h.FillTransparency = 1 -- outline only
                    end
                    h.Name = "NekoESP"
                    h.Parent = inst
                end
                if cat == "Generator" then -- fixed progress tint: yellow -> green, done = no highlight
                    local p = inst:GetAttribute("RepairProgress") or 0
                    if p >= 100 then
                        h:Destroy()
                        hl[inst] = nil
                    else
                        paintEsp(h, GEN_LOW:Lerp(GEN_HIGH, math.clamp(p / 100, 0, 1)))
                        hl[inst] = { obj = h, cat = cat }
                    end
                else
                    paintEsp(h, baseColor(cat))
                    hl[inst] = { obj = h, cat = cat }
                end
            end
        end
    end
    for inst, e in pairs(hl) do
        if not inst.Parent then hl[inst] = nil end -- prune dead targets
    end
end

function ESP.Set(on)
    if ESP.on == on then return end
    ESP.on = on
    if on then
        task.spawn(function()
            while ESP.on and getgenv().NEKOHUB_ESP_RUN == RUN do
                espTick()
                task.wait(1)
            end
        end)
    else
        for inst, e in pairs(hl) do e.obj:Destroy() hl[inst] = nil end
        for _, d in ipairs(workspace:GetDescendants()) do -- sweep strays from dead loops
            if d.Name == "NekoESP" then d:Destroy() end
        end
    end
end

function ESP.SetCat(cat, on)
    ESP.cats[cat] = on or nil
    if on then
        if ESP.on then espTick() else ESP.Set(true) end -- selecting auto-enables
    else
        for inst, e in pairs(hl) do
            if e.cat == cat then e.obj:Destroy() hl[inst] = nil end
        end
    end
end

-- ---------------------------------------------------------------- skeleton overlay (Drawing API, R15)

-- skeleton covers all players; fps 0 = uncapped (every frame)
local OV = { on = false, cats = { Killer = true, Survivor = true }, fps = 0 }
local hasDrawing = type(Drawing) == "table" and Drawing.new ~= nil
local lastOv = 0 -- last skeleton draw time, for the FPS gate
function OV.SetFPS(n) OV.fps = tonumber(n) or 0 end

local SKELS = getgenv().NEKOHUB_SKELS
if SKELS then -- destroy lines left by a previous run
    for _, s in pairs(SKELS) do
        for _, e in ipairs(s.lines or {}) do
            pcall(function() e:Destroy() end)
            pcall(function() e[1]:Destroy() end)
        end
    end
end
SKELS = {}
getgenv().NEKOHUB_SKELS = SKELS

local LOS_GREEN = Color3.fromRGB(120, 255, 140)
local LOS_RED   = Color3.fromRGB(255, 60, 60)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- skeleton = segments per Motor6D joint (socket→center→tip): tracks whatever
-- actually animates, works for R6/R15/custom rigs
local TIPLESS = { Torso = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true }
local R6_LIMB = { ["Left Leg"] = true, ["Right Leg"] = true, ["Left Arm"] = true, ["Right Arm"] = true }

-- rescan animated Motor6D joints (rigs change as meshes/hats load); cached 0.25s.
local function rescanMotors(char, s, now, r6)
    if now - s.at <= 0.25 then return s.motors end
    s.at = now
    local first = r6 and not s.warmed -- R6 bones are fixed: show all from frame one
    -- keep only motors whose Transform animates: the visible body may be a
    -- skinned mesh driven by its own joints while base rig parts sit static
    local motors, lastT = {}, {}
    local function bodyPart(p) -- skip props: accessory handles, weapon/prop models
        if not p:IsDescendantOf(char) then return false end
        if p:FindFirstAncestorOfClass("Accessory") then return false end
        local m = p:FindFirstAncestorOfClass("Model")
        return m == nil or m == char
    end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") then
            local p0, p1 = d.Part0, d.Part1
            if p0 and p1 and bodyPart(p0) and bodyPart(p1) then
                local t = d.Transform
                if s.lastT[d] and s.lastT[d] ~= t then s.anim[d] = true end
                lastT[d] = t
                if s.anim[d] or first then motors[#motors + 1] = d end
            end
        end
    end
    s.lastT = lastT
    s.motors = motors
    if first then s.warmed = true end
    return motors
end

-- line-of-sight: blocked = red, clear = green. Invisible trigger boxes ride in
-- the exclude list (they never occlude vision); a failed ray reads green.
local function losColor(char, cam, s)
    local now = os.clock()
    if s.losCol ~= nil and now - s.losAt < 0.1 then -- 10 Hz: colors only flip on transitions
        return s.losCol
    end
    local torso = s.torso
    if not (torso and torso.Parent) then -- resolved once per character
        torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
        s.torso = torso
    end
    if torso then
        ensureMap() -- no-op once the map snapshot is fresh
        losExclude[1] = char
        losExclude[2] = localPlayer.Character or char
        rayParams.FilterDescendantsInstances = losExclude
        local ok, hit = pcall(workspace.Raycast, workspace,
            cam.CFrame.Position, torso.Position - cam.CFrame.Position, rayParams)
        if ok and hit then s.losAt, s.losCol = now, LOS_RED return LOS_RED end
    end
    s.losAt, s.losCol = now, LOS_GREEN
    return LOS_GREEN
end

-- segment endpoints per animated joint (parent->socket, socket->center, [center->tip])
local function motorSegs(m, char, r6)
    local p0, p1 = m.Part0, m.Part1
    if not (p0 and p1 and p0:IsDescendantOf(char) and p1:IsDescendantOf(char)) then return nil end
    local j = (p1.CFrame * m.C1).Position -- joint point on the animated child
    local b = p1.Position
    -- R6 limbs are single rigid pieces, but their sockets sit outboard of the
    -- limb axis: routing through the socket zigzags (crooked legs). Draw one
    -- straight root->tip segment instead. (R15+/custom keep joint segments.)
    if r6 and R6_LIMB[p1.Name] then
        local c1 = m.C1.Position
        if math.abs(c1.X) > 0.2 or math.abs(c1.Z) > 0.2 then
            local edge = p0.Size.Y / 2
            if p1.Name:find("Leg") then edge = -edge end
            local root = p0.CFrame * Vector3.new(0, edge, 0)
            local tip = b - p1.CFrame.UpVector * (p1.Size.Y / 2)
            return root, tip, nil, nil, nil, nil
        end
    end
    if TIPLESS[p1.Name] then return p0.Position, j, j, b, nil, nil end
    return p0.Position, j, j, b, b, b + (b - j) -- extend through the far end
end

local function drawSeg(s, i, cam, a, b)
    local l = s.lines[i]
    if (a - b).Magnitude > 6 then -- stray attach (downed/carry welds): skip
        l.Visible = false
        return i + 1
    end
    local pa, pb = cam:WorldToViewportPoint(a), cam:WorldToViewportPoint(b)
    if pa.Z > 0 and pb.Z > 0 then
        local c = s.xy[i] -- rewrite endpoints only when they moved
        if c == nil then
            c = { 0, 0, 0, 0 }
            s.xy[i] = c
        end
        if c[1] ~= pa.X or c[2] ~= pa.Y or c[3] ~= pb.X or c[4] ~= pb.Y then
            c[1], c[2], c[3], c[4] = pa.X, pa.Y, pb.X, pb.Y
            l.From = Vector2.new(pa.X, pa.Y)
            l.To = Vector2.new(pb.X, pb.Y)
        end
        l.Visible = true
    else
        l.Visible = false
    end
    return i + 1
end

local function drawSkel(char)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local s = SKELS[char]
    if not s then
        s = { lines = {}, motors = {}, at = 0, anim = {}, lastT = {}, xy = {} }
        SKELS[char] = s
    end
    if s.r6 == nil then -- cached per character; rig type never changes on it
        local hum = char:FindFirstChildOfClass("Humanoid")
        s.r6 = hum ~= nil and hum.RigType == Enum.HumanoidRigType.R6 or false
    end
    local motors = rescanMotors(char, s, os.clock(), s.r6)
    do -- frozen char + static camera: every line is already correct, skip the draw
        local lastF = s.lastF
        if lastF == nil or s.lastM ~= motors then
            lastF = {}
            s.lastF, s.lastM = lastF, motors
        end
        local same = true
        for _, m in ipairs(motors) do
            local t = m.Transform
            if lastF[m] ~= t then same = false end
            lastF[m] = t
        end
        local torso = s.torso
        if same and torso ~= nil and torso.Parent ~= nil
            and torso.CFrame == s.lastRoot and cam.CFrame == s.lastCam then
            return
        end
        s.lastRoot = (torso ~= nil and torso.Parent ~= nil) and torso.CFrame or nil
        s.lastCam = cam.CFrame
    end
    local col = losColor(char, cam, s)
    if s.col ~= col then -- rewrite line colors only on LOS flips
        s.col = col
        for _, l in ipairs(s.lines) do l.Color = col end
    end
    while #s.lines < #motors * 3 do -- grow line pool (parent->socket->center->tip)
        local l = Drawing.new("Line")
        l.Thickness = 1.5
        l.Visible = false -- new lines start hidden; drawn ones are shown below
        l.Color = col -- born with the current color (the flip-guard would skip them)
        s.lines[#s.lines + 1] = l
    end
    -- anchor on the CHILD-side joint (p1.CFrame*C1): it rides with the animated
    -- part, so bones stay glued to skinned-mesh rigs instead of the static hitbox
    local li = 1
    for _, m in ipairs(motors) do
        local a1, b1, a2, b2, a3, b3 = motorSegs(m, char, s.r6)
        if a1 then
            li = drawSeg(s, li, cam, a1, b1)
            if a2 then li = drawSeg(s, li, cam, a2, b2) end
            if a3 then li = drawSeg(s, li, cam, a3, b3) end
        end
    end
    if s.used and li < s.used then -- fewer segments: hide the newly-unused tail
        for i = li, s.used - 1 do s.lines[i].Visible = false end
    end
    s.used = li
end

do -- render loop; latest priority samples positions closest to the frame
    pcall(function() RunService:UnbindFromRenderStep("NekoSkel") end)
    RunService:BindToRenderStep("NekoSkel", Enum.RenderPriority.Last.Value, function()
        if getgenv().NEKOHUB_ESP_RUN ~= RUN then
            pcall(function() RunService:UnbindFromRenderStep("NekoSkel") end)
            return
        end
        if not (OV.on and hasDrawing) then return end
        if OV.fps > 0 then -- draw at most fps times per second (0 = every frame)
            local nowF = os.clock()
            if nowF - lastOv < 1 / OV.fps then return end
            lastOv = nowF
        end
        local seen = {}
        if not getgenv().GameAPI.IsLobby() then
            for cat, on in pairs(OV.cats) do
                local find = on and getgenv().GameAPI.Targets[cat]
                if find then
                    for _, char in ipairs(find()) do
                        seen[char] = true
                        drawSkel(char)
                    end
                end
            end
        end
        for char, s in pairs(SKELS) do
            if not char.Parent or not seen[char] then
                s.lastF = {} -- force a full redraw when the char is seen again
                for _, l in ipairs(s.lines) do l.Visible = false end
                if not char.Parent then -- char gone: drop its lines
                    for _, l in ipairs(s.lines) do pcall(function() l:Destroy() end) end
                    SKELS[char] = nil
                end
            end
        end
    end)
end

function OV.Set(on)
    OV.on = on
    if not on then
        for _, s in pairs(SKELS) do
            s.lastF = {} -- force a full redraw (lines may un-hide) on re-enable
            for _, l in ipairs(s.lines) do l.Visible = false end
        end
    end
end
function OV.SetCat(cat, on)
    OV.cats[cat] = on or nil
    if on then OV.on = true end -- selecting auto-enables
end

-- ------------------------------------------------- details labels (BillboardGui text)
-- Single-line Name / Distance / Gen % / Kick text on all Targets (independent of ESP).
-- Flags live in DT.cats (Details switches); DT.Text builds one instance's text.

local DT = { on = false, gen = false, cats = {} } -- split masters: on = players, gen = generators
-- inst -> {part, gui, tl, text, col}: anchor + label refs resolved once, text
-- size + property writes only when the value actually changes (prune dead)
local dtAdorn = {}
-- Details labels: players + generators only (hooks/vaults/pallets never labeled)
local LABEL_CATS = { Killer = true, Survivor = true, Generator = true }
local TextService = game:GetService("TextService")

local function pivotOf(inst)
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then return inst:GetPivot().Position end
    return nil
end

local function distTo(inst)
    local char = localPlayer.Character
    if not char then return nil end
    local a, b = pivotOf(char), pivotOf(inst)
    if not (a and b) then return nil end
    return math.floor((a - b).Magnitude + 0.5)
end

local function adornPart(inst)
    if inst:IsA("BasePart") then return inst end
    if not inst:IsA("Model") then return nil end
    local head = inst:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    local hrp = inst:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    -- props: bulkiest visible part (skips invisible hitboxes/markers that sit
    -- off-center or inflate the bounding box)
    local best, bestVol, anyBest, anyVol = nil, 0, nil, 0
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            local s = d.Size
            local vol = s.X * s.Y * s.Z
            if vol > anyVol then anyBest, anyVol = d, vol end
            if d.Transparency < 1 and vol > bestVol then best, bestVol = d, vol end
        end
    end
    return best or anyBest
end

-- kicked gen draining with nobody repairing it
local function isRegressing(inst)
    local kc = inst:GetAttribute("kickcount") or 0
    if kc == 0 then return false end
    local prog = inst:GetAttribute("RepairProgress") or 0
    local repairing = inst:GetAttribute("PlayersRepairingCount") or 0
    return prog > 0 and prog < 100 and repairing == 0
end

function DT.Text(inst, cat)
    local done = inst:GetAttribute("RepairProgress")
    if done ~= nil and done >= 100 then return "" end -- finished gen: no label, like ESP
    local lines = {}
    local flags = DT.cats
    local owner = Players:GetPlayerFromCharacter(inst)
    if owner and not DT.on then return "" end -- player master off
    if not owner and not DT.gen then return "" end -- generator master off
    if flags.Name then
        if owner then lines[#lines + 1] = owner.Name end
    end
    if (owner ~= nil and flags.Distance) or (owner == nil and flags["Gen Distance"]) then
        local d = distTo(inst)
        if d then lines[#lines + 1] = ("%dm"):format(d) end
    end
    if flags["Gen %"] then
        local p = inst:GetAttribute("RepairProgress")
        if p ~= nil then lines[#lines + 1] = ("%d%%"):format(math.floor(p)) end
    end
    if flags.Repairers then
        local rc = inst:GetAttribute("PlayersRepairingCount") or 0
        if rc > 0 then lines[#lines + 1] = ("player: %d"):format(rc) end
    end
    if flags.Kick then
        local kc = inst:GetAttribute("kickcount")
        if kc ~= nil then -- gens always show it (even 0); others lack the attribute
            local line = ("Kick:%d"):format(kc)
            if isRegressing(inst) then line = line .. " (regressing)" end
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, " • ")
end

-- label text color follows generator state: lime while repaired, red while
-- regressing, white otherwise (chars/props have no repair state)
function DT.TextColor(inst)
    local repairing = inst:GetAttribute("PlayersRepairingCount") or 0
    if repairing > 0 then return Color3.new(0, 1, 0) end
    if isRegressing(inst) then return Color3.new(1, 0, 0) end
    return Color3.new(1, 1, 1)
end

local function updateLabel(inst, cat)
    if not inst.Parent then return end
    local st = dtAdorn[inst]
    local part = st and st.part
    if not (part and part.Parent) then -- anchor resolved once; billboard follows it
        part = adornPart(inst)
        if not part then return end
        st = { part = part }
        dtAdorn[inst] = st
    end
    local text = DT.Text(inst, cat)
    if text == "" then -- nothing to show: disable any label, create none
        local g = st.gui
        if g and g.Parent and g.Enabled then g.Enabled = false end
        st.text = ""
        return
    end
    local tsize = Players:GetPlayerFromCharacter(inst) == nil and 10 or 12
    local gui = st.gui
    if not (gui and gui.Parent) then
        gui = part:FindFirstChild("NekoDetails")
        if gui then
            st.tl = gui:FindFirstChild("Label")
        else
            gui = Instance.new("BillboardGui")
            gui.Name = "NekoDetails"
            gui.AlwaysOnTop = true
            gui.Adornee = part
            -- label center just above the adornee part's top (the adornee is the
            -- visual mass, so this lands on top of the visible target)
            gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 0.5, 0)
            local tl = Instance.new("TextLabel")
            tl.Name = "Label"
            tl.BackgroundTransparency = 1
            tl.Size = UDim2.fromScale(1, 1)
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = tsize
            tl.TextColor3 = Color3.new(1, 1, 1)
            tl.TextStrokeTransparency = 0
            tl.Parent = gui
            gui.Parent = part
            st.tl = tl
        end
        st.gui, st.text, st.col = gui, nil, nil -- force first draw
    end
    local col = DT.TextColor(inst)
    if st.text ~= text then -- same text: skip measure + writes entirely
        local tw = TextService:GetTextSize(text, tsize, Enum.Font.GothamBold, Vector2.new(2000, 22))
        gui.Size = UDim2.fromOffset(math.min(math.ceil(tw.X) + 16, 600), 22)
        if st.tl then st.tl.Text, st.tl.TextSize = text, tsize end
        st.text = text
    end
    if st.col ~= col then
        if st.tl then st.tl.TextColor3 = col end
        st.col = col
    end
    if not gui.Enabled then gui.Enabled = true end -- back from lobby / hidden
end

local function dtTick()
    if getgenv().GameAPI.IsLobby() then -- no labels while waiting in lobby
        for _, st in pairs(dtAdorn) do
            local g = st.gui
            if g and g.Parent and g.Enabled then g.Enabled = false end
        end
        return
    end
    -- Details is independent of ESP boxes: iterate every Targets category so
    -- labels follow Details switches alone (re-exec safe, no ESP row needed)
    for cat, find in pairs(getgenv().GameAPI.Targets) do
        if type(find) == "function" and LABEL_CATS[cat] then
            for _, inst in ipairs(find()) do
                updateLabel(inst, cat)
            end
        end
    end
    for inst, _ in pairs(dtAdorn) do
        if not inst.Parent then dtAdorn[inst] = nil end -- prune dead targets
    end
end

local dtRunning = false
local function dtStart() -- shared 0.25s loop; runs while either master is on
    if dtRunning then return end
    dtRunning = true
    task.spawn(function()
        while (DT.on or DT.gen) and getgenv().NEKOHUB_ESP_RUN == RUN do
            dtTick()
            task.wait(0.25) -- text tracks movement live; ESP boxes stay on 1s
        end
        dtRunning = false
    end)
end
local function dtHideGroup(player) -- instantly hide one group's labels
    for inst, st in pairs(dtAdorn) do
        local g = st.gui
        if g and g.Parent and g.Enabled then
            local isChar = Players:GetPlayerFromCharacter(inst) ~= nil
            if isChar == player then g.Enabled = false end
        end
    end
end
local function dtDestroyAll()
    for inst, st in pairs(dtAdorn) do
        local g = st.gui
        if g and g.Parent then g:Destroy() end
        dtAdorn[inst] = nil
    end
    for _, d in ipairs(workspace:GetDescendants()) do -- sweep strays from dead loops
        if d.Name == "NekoDetails" then d:Destroy() end
    end
end
function DT.Set(on) -- player labels master
    if DT.on == on then return end
    DT.on = on
    if on then
        dtStart()
    elseif DT.gen then
        dtHideGroup(true)
    else
        dtDestroyAll()
    end
end
function DT.SetGen(on) -- generator labels master
    if DT.gen == on then return end
    DT.gen = on
    if on then
        dtStart()
    elseif DT.on then
        dtHideGroup(false)
    else
        dtDestroyAll()
    end
end

local GEN_FLAGS = { ["Gen Distance"] = true, ["Gen %"] = true, Repairers = true, Kick = true }
function DT.SetCat(flag, on)
    DT.cats[flag] = on or nil
    if on then -- selecting auto-enables its own group's master
        if GEN_FLAGS[flag] then
            if DT.gen then dtTick() else DT.SetGen(true) end
        else
            if DT.on then dtTick() else DT.Set(true) end
        end
    elseif DT.on or DT.gen then
        dtTick() -- refresh: drop lines for the removed flag
    end
end

-- ------------------------------------------------- auto skill check (legit only)
-- tracks the needle as an offset from the goal and presses once it enters
-- (or jumps past) the target zone; one press per goal, FPS-independent

local AUTO: { [string]: any } = {
    SkillCheck = false, PerfectRate = 0, SlashCrouch = false, AutoParry = false,
    ParryLead = 150, -- ms before a held lunge's forced swing (maxHold) to parry
    ParryRange = 10, -- studs; killer reach is server-side only, tune from [NekoParry] dist logs
}
function AUTO.Set(name: string, val: any)
    if name == "PerfectRate" or name == "ParryLead" or name == "ParryRange" then AUTO[name] = tonumber(val) or 0 return end
    AUTO[name] = val == true or nil
end

local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local pg = localPlayer:WaitForChild("PlayerGui")

-- tap a mobile control where a real finger would land
local function tapGui(btn: GuiObject, id: number)
    local inset = GuiService:GetGuiInset() -- read at press time: topbar toggles shift it
    local p, s = btn.AbsolutePosition, btn.AbsoluteSize
    local x, y = p.X + s.X / 2 + inset.X, p.Y + s.Y / 2 + inset.Y
    VIM:SendTouchEvent(id, 0, x, y)
    VIM:SendTouchEvent(id, 2, x, y)
end

do
    local TOUCH_ID = 8822
    local ACTION_PATH = "Survivor-mob.Controls.action.check"
    -- zones (needle offset = line - goal): perfect 104°..108° pressed at once
    -- (lands center); normal 109°..112° pressed at once (lands far-edge Good, no delay)
    local ZN0, ZP1, ZG0, ZG1 = 104, 108, 109, 112

    local prevOff: number? = nil -- last needle offset; nil = prompt hidden / goal moved
    local goal: number? = nil    -- goal rotation the current arm belongs to; nil = new prompt
    local clicked, perfect = false, false

    local function angDelta(from: number, to: number)
        local d = to - from
        if d > 180 then d = d - 360 end
        if d < -180 then d = d + 360 end
        return d
    end

    -- gamepad client uses SkillCheckPromptGui-con; only returns a visible prompt
    local function getPrompt(): (GuiObject?, GuiObject?, GuiObject?)
        for _, n in ipairs({ "SkillCheckPromptGui", "SkillCheckPromptGui-con" }) do
            local g = pg:FindFirstChild(n)
            local c = g and g:FindFirstChild("Check", true)
            if c and c:IsA("GuiObject") and c.Visible then
                local l = c:FindFirstChild("Line", true)
                local go = c:FindFirstChild("Goal", true)
                if l and l:IsA("GuiObject") and go and go:IsA("GuiObject") then
                    return c, l, go
                end
            end
        end
        return nil, nil, nil
    end

    local function trigger()
        -- touch: tap the .check button (its handler owns the skill check);
        -- elsewhere send the same Space press a real player would
        local btn: Instance? = pg
        for s in ACTION_PATH:gmatch("[^%.]+") do btn = btn and btn:FindFirstChild(s) end
        if UIS.TouchEnabled and btn and btn:IsA("GuiObject") then
            tapGui(btn, TOUCH_ID)
            return
        end
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        if firesignal then -- fallback for executors where VIM skips Lua handlers
            pcall(firesignal, UIS.InputBegan, {
                KeyCode = Enum.KeyCode.Space,
                UserInputType = Enum.UserInputType.Keyboard,
                UserInputState = Enum.UserInputState.Begin,
            }, false)
        end
    end

    -- persistent loop, gated by flag; run-token kills it after re-execution
    -- (two-statement form: assign the connection before the callback can run)
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if getgenv().NEKOHUB_ESP_RUN ~= RUN then conn:Disconnect() return end
        local _, ln, gl
        if AUTO.SkillCheck and getgenv().GameAPI.IsSurvivor() then _, ln, gl = getPrompt() end
        if not (ln and gl) then -- off / not survivor / prompt hidden: reset
            prevOff, goal, clicked = nil, nil, false
            return
        end
        local gr = gl.Rotation % 360
        if goal == nil then -- new prompt: roll mode once per sweep
            perfect = math.random(100) <= (AUTO.PerfectRate or 0)
        end
        if goal == nil or math.abs(angDelta(goal, gr)) > 5 then -- new goal: re-arm
            goal, prevOff, clicked = gr, nil, false
        end
        local off = (ln.Rotation - gr) % 360
        if not clicked then
            local z0, z1 = ZG0, ZG1
            if perfect then z0, z1 = ZN0, ZP1 end
            -- ponytail: forward-only sweep; in-zone or jumped past it since last frame
            if off >= z0 and (off <= z1 or (prevOff ~= nil and prevOff < z0)) then
                clicked = true
                AUTO.lastOff = off
                trigger()
            end
        end
        prevOff = off
    end)
end

-- ------------------------------------------------- auto crouch vs Abysswalker slash
-- slash = 0.8s windup dash (WalkSpeed 35, ~28 studs) then the hit. Crouch while
-- it's aimed at us, stand back up once the swing is over.
do
    local SLASH_ID = "80411309607666" -- Abysswalker "slash" (only killer that has it)
    -- ponytail: fixed range/cone guess from the dash math; tune from real matches
    local RANGE, CONE = 40, math.cos(math.rad(45))
    -- hit fires 0.8s into the slash (its anim runs 3s, so don't wait for it); stand 0.2s after
    local HOLD = 0.8 + 0.2
    local FLAT = Vector3.new(1, 0, 1)
    -- strong keys: Instance proxies in a weak table get collected, which re-hooked the
    -- same animator every few seconds (61 handlers seen -> one attack fired 12 parries)
    local hooked = {}
    local keyHeld = false
    local warmAt = -5 -- last warm attempt; throttled: a miss is a 43ms getgc scan

    local function crouching()
        local c = localPlayer.Character
        return c ~= nil and c:GetAttribute("Crouching") == true
    end

    local function targeted(kchar: Model, range: number, cone: number?)
        local me = localPlayer.Character
        local a = kchar:FindFirstChild("HumanoidRootPart")
        local b = me and me:FindFirstChild("HumanoidRootPart")
        if not (a and b) then return false end
        local d = (b.Position - a.Position) * FLAT
        if d.Magnitude > range then return false end
        if d.Magnitude < 2 then return true end
        local look = a.CFrame.LookVector * FLAT
        return look.Magnitude > 0 and look.Unit:Dot(d.Unit) >= (cone or CONE)
    end

    -- per-killer parry anims; add a killer here. Ids are unique per killer, so the
    -- playing anim id identifies the killer (SelectedKiller attr isn't always set)
    -- maxHold / speed (lungeWalkSpeed) come from each killer's Animations script
    local KILLERS = {
        Abysswalker = { hold = "118907603246885", attack = { "78432063483146", "77081789642514" }, maxHold = 0.5, speed = 25 },
        Slasher     = { hold = "110355011987939", attack = { "139369275981139" }, maxHold = 0.6, speed = 27 },
        Veil        = { hold = "122812055447896", attack = { "78935059863801" }, maxHold = 0.6, speed = 23 }, -- knife only
        Killer      = { hold = "129784271201071", attack = { "132817836308238", "82666958311998" }, maxHold = 0.6, speed = 27 }, -- attackfr = Frenzy
        Cure        = { hold = "135002183282873", attack = { "121216847022485" }, maxHold = 0.6, speed = 27, threshold = 0.2 }, -- no flask
        Hidden      = { hold = "113255068724446", attack = { "74968262036854" }, maxHold = 0.6, speed = 27, -- attackfr shared w/ Killer
            charges = { { id = "98163597193511", maxHold = 1, range = 50 } } }, -- M2 charge→50-stud dash; ponytail: maxHold guess
        Stalker     = { hold = "117042998468241", attack = { "133963973694098" }, maxHold = 0.6, speed = 27 }, -- Stage 3 ids excluded per request
        Masked      = { hold = "105374834496520", attack = { "111920872708571", "130593238885843", "138720291317243" }, maxHold = 0.6, speed = 27,
            charges = { { id = "115244153053858", maxHold = 0.8 }, -- Cobra hold
                { id = "117070354890871", maxHold = 1.7 },          -- Alex chainsaw rev
                { id = "106871536134254", maxHold = 3 } } },        -- Alex saw-dash: parry when close; ponytail: maxHold guess
    }
    local LUNGE_THRESHOLD = 0.45 -- game default: a hold this long is sent as a lunge (per-killer `threshold` overrides)
    local PARRY_IDS, PARRY_HOLD_IDS, HOLD_OV = {}, {}, {} -- anim id -> killer / hold id -> overrides
    for name, k in pairs(KILLERS) do
        PARRY_HOLD_IDS[k.hold] = name
        for _, c in ipairs(k.charges or {}) do
            PARRY_HOLD_IDS[c.id] = name
            HOLD_OV[c.id] = c
        end
        for _, a in ipairs(k.attack) do PARRY_IDS[a] = name end
    end

    -- the game's ParryClient controller (owns parryEvent); cached per dagger model
    local pCtrl, pDagger, parryWarmAt = nil, nil, -5
    local function parryCtrl()
        local dg = localPlayer.Character and localPlayer.Character:FindFirstChild("Parrying Dagger")
        if not dg then return nil end
        if pCtrl and pDagger == dg then return pCtrl end
        pCtrl, pDagger = nil, dg
        for _, t in ipairs(getgc and getgc(true) or {}) do
            if type(t) == "table" and rawget(t, "parryEvent") ~= nil and rawget(t, "tool") == dg then
                pCtrl = t
                break
            end
        end
        return pCtrl
    end

    -- the game's SurvivorAnimationsController (owns crouchButton); cached per button
    local ctrl, ctrlBtn
    local function survivorCtrl(btn)
        if ctrl and ctrlBtn == btn then return ctrl end
        ctrl, ctrlBtn = nil, btn
        for _, t in ipairs(getgc and getgc(true) or {}) do
            if type(t) == "table" and rawget(t, "crouchButton") == btn and type(t._setCrouching) == "function" then
                ctrl = t
                break
            end
        end
        return ctrl
    end

    local function crouchBtn()
        local btn = pg:FindFirstChild("Survivor-mob")
        btn = btn and btn:FindFirstChild("Controls")
        return btn and btn:FindFirstChild("crouch")
    end

    -- mobile button is a toggle; PC C is hold unless the game's crouchtoggle is on
    local function setCrouch(on: boolean)
        local btn = crouchBtn()
        if UIS.TouchEnabled and btn and btn:IsA("GuiButton") and btn.Visible then
            if crouching() == on then return end
            -- VIM touch is ignored on some executors (Arceus X): run the button's own handler.
            -- Standing up via the button doesn't take, so that goes straight to the controller.
            if on then
                if firesignal then firesignal(btn.MouseButton1Click) else tapGui(btn, 8823) end
                task.wait(0.15)
                survivorCtrl(btn) -- warm the cache now so standing up doesn't pay the GC scan
            end
            if crouching() ~= on then -- handler refused/missed: drive the controller directly
                local c = survivorCtrl(btn)
                if c then
                    c:_setCrouching(on)
                    pcall(c._refreshMobileButtons, c)
                end
            end
            print("[NekoCrouch] set", on, "->", crouching())
        elseif localPlayer:GetAttribute("crouchtoggle") then
            if crouching() ~= on then
                VIM:SendKeyEvent(true, Enum.KeyCode.C, false, game)
                VIM:SendKeyEvent(false, Enum.KeyCode.C, false, game)
            end
        elseif keyHeld ~= on then -- always release a key we pressed
            keyHeld = on
            VIM:SendKeyEvent(on, Enum.KeyCode.C, false, game)
        end
    end

    local function onTrack(kchar: Model, track: AnimationTrack)
        if getgenv().NEKOHUB_ESP_RUN ~= RUN then return end
        local anim = track.Animation
        local id = anim and anim.AnimationId:match("%d+")
        if not id then return end
        -- ponytail: parry reach is the UI slider (server hitbox isn't visible to clients)
        local PARRY_RANGE = AUTO.ParryRange or 10
        -- within 7 studs facing is ignored: the killer's replicated facing lags their real
        -- turn, and 4/4 swings at 4.8 studs showing 76-96° off still hit us
        -- ponytail: 7 studs from logged hits (hits seen at 4.2-6.3); a swing at a teammate this close burns the dagger
        -- the killer we see is ~one ping old: extrapolate their position (replicated
        -- velocity) and facing (yaw rate from our own frame-to-frame samples) forward by
        -- ping, so checks use where they are/aim now, not where they were
        -- ponytail: linear extrapolation, lag capped 0.2s and turn capped 60°; jerky
        -- flicks overshoot (the FACE_HOLD debounce below absorbs that)
        local lastLook, lastT, yawRate = nil, 0, 0
        local function now()
            local a = kchar:FindFirstChild("HumanoidRootPart")
            local b = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not (a and b) then return nil end
            local look = a.CFrame.LookVector * FLAT
            if look.Magnitude == 0 then return nil end
            look = look.Unit
            local t = os.clock()
            if lastLook and t - lastT > 0.01 then -- one sample per frame, not per call
                yawRate = math.atan2(lastLook:Cross(look).Y, lastLook:Dot(look)) / (t - lastT)
            end
            if not lastLook or t - lastT > 0.01 then lastLook, lastT = look, t end
            local lag = math.min(localPlayer:GetNetworkPing(), 0.2)
            local turn = math.clamp(yawRate * lag, -math.rad(60), math.rad(60))
            local pos = a.Position + a.AssemblyLinearVelocity * FLAT * lag
            return (b.Position - pos) * FLAT, CFrame.Angles(0, turn, 0):VectorToWorldSpace(look)
        end
        local function close(range)
            local d = now()
            return d ~= nil and d.Magnitude <= math.min(range, 7)
        end
        -- beyond the close zone: we must be ahead of the killer and within PATH_HALF of
        -- their facing line (a cone lets far/wide swings through: 6.3 studs at 41° passed
        -- 4 studs beside us and burned the dagger)
        -- ponytail: 3.5 = guessed hitbox half-width + our body; tune from [NekoParry] logs
        local PATH_HALF = 3.5
        local function inPath(range)
            local d, look = now()
            if not d or d.Magnitude > range then return false end
            local fwd = d:Dot(look)
            return fwd > 0 and math.sqrt(math.max(d.Magnitude ^ 2 - fwd ^ 2, 0)) <= PATH_HALF
        end
        local function aimed(range) return close(range) or inPath(range) end
        -- auto parry: any known attack anim aimed at us inside dagger reach;
        -- Parry() yields on its anim, so it always goes through task.spawn
        -- dist/angle of us from the killer's facing, for the logs
        local function geo()
            local a = kchar:FindFirstChild("HumanoidRootPart")
            local b = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not (a and b) then return "no root" end
            local d, look = (b.Position - a.Position) * FLAT, a.CFrame.LookVector * FLAT
            local ang = d.Magnitude > 0 and look.Magnitude > 0 and math.deg(math.acos(math.clamp(look.Unit:Dot(d.Unit), -1, 1))) or 0
            local fwd = look.Magnitude > 0 and d:Dot(look.Unit) or 0
            return ("dist=%.1f ang=%d side=%.1f"):format(d.Magnitude, ang, math.sqrt(math.max(d.Magnitude ^ 2 - fwd ^ 2, 0)))
        end
        local function log(what, why) print("[NekoParry]", what, "vs", kchar.Name, PARRY_IDS[id] or PARRY_HOLD_IDS[id], why, geo()) end
        local function tryParry(why, range)
            if not (getgenv().GameAPI.IsSurvivor() and aimed(range)) then return log("skip", why .. " (not targeted)") end
            local c = parryCtrl()
            if not (c and c:CanUse()) then
                return log("skip", why .. (c and " (CanUse=false: cooldown/hp<50/busy)" or " (no parry controller)"))
            end
            task.spawn(c.Parry, c)
            log("parry", why)
        end
        -- attack ids arrive after the server already has the hit (killer plays anim +
        -- fires BasicAttack together), so they're a late fallback; lungehold is the
        -- early signal (plays on press, before every swing)
        -- re-checked every frame: a killer can swing facing away and turn back onto us
        -- ponytail: 0.8s turn-back window (= the game's parry lockDuration); tune from matches
        if AUTO.AutoParry and PARRY_IDS[id] then
            task.spawn(function()
                local t0 = os.clock()
                while track.IsPlaying and AUTO.AutoParry and os.clock() - t0 < 0.8 do
                    if aimed(PARRY_RANGE) then return tryParry("attack", PARRY_RANGE) end
                    task.wait()
                end
                if AUTO.AutoParry and getgenv().GameAPI.IsSurvivor() then log("skip", "attack (never faced us in range)") end
            end)
        end
        -- wind-up, re-checked every frame (killer may turn or walk in mid-hold). The game
        -- force-swings at maxHold * lungeboost and moves the killer at lungeWalkSpeed while
        -- holding, so: already in reach -> parry now (can release any moment); can still
        -- reach us before the forced swing and it's ParryLead away -> parry; released
        -- first -> parry at release (held >= lungeThreshold = the game's lunge)
        -- ponytail: t0 is when the anim reaches us, not the killer's press; ParryLead absorbs it
        local k = KILLERS[PARRY_HOLD_IDS[id]]
        if AUTO.AutoParry and k then
            task.spawn(function()
                local t0 = os.clock()
                local ov = HOLD_OV[id] or {}
                local fire = (ov.maxHold or k.maxHold) * (kchar:GetAttribute("lungeboost") or 1)
                local speed = ov.speed or k.speed
                local range = ov.range or PARRY_RANGE -- M2 dash can strike from 50 studs out
                local lead = (AUTO.ParryLead or 150) / 1000
                -- anti-fake: a quick camera flick onto us mid-hold must not burn the dagger,
                -- so beyond 7 studs facing has to hold FACE_HOLD before a wind-up parry
                -- (inside 7 there's no time to wait: parry immediately)
                -- ponytail: 0.15s guess; longer resists slower fakes but delays real turns
                local FACE_HOLD, faceSince = 0.15, nil
                local function steady(range)
                    if close(range) then return true end
                    return aimed(range) and faceSince ~= nil and os.clock() - faceSince >= FACE_HOLD
                end
                while track.IsPlaying and AUTO.AutoParry do
                    if aimed(math.huge) then faceSince = faceSince or os.clock() else faceSince = nil end
                    if steady(PARRY_RANGE) then return tryParry("close wind-up", PARRY_RANGE) end
                    local left = math.max(fire - (os.clock() - t0), 0)
                    local reach = range + speed * left
                    if left <= lead and steady(reach) then return tryParry("lunge", reach) end
                    task.wait()
                end
                if AUTO.AutoParry then
                    tryParry(os.clock() - t0 >= (k.threshold or LUNGE_THRESHOLD) and "lunge release" or "quick attack", range)
                end
            end)
        end
        if not (AUTO.SlashCrouch and anim.AnimationId:find(SLASH_ID, 1, true)) then return end
        local t0, mine = os.clock(), false
        print("[NekoCrouch] slash seen; targeted:", targeted(kchar, RANGE), "crouching:", crouching())
        repeat
            local dt = os.clock() - t0
            if not mine and not crouching() and getgenv().GameAPI.IsSurvivor() and targeted(kchar, RANGE) then
                setCrouch(true)
                mine = true -- only undo a crouch we started
            end
            task.wait()
        until not track.IsPlaying or dt >= HOLD
        if mine then setCrouch(false) end
    end

    task.spawn(function() -- hook killer animators; re-scan picks up respawns
        while getgenv().NEKOHUB_ESP_RUN == RUN do
            task.wait(1) -- first: GameAPI is assigned below this block
            for _, kchar in ipairs(getgenv().GameAPI.Targets.Killer()) do
                local hum = kchar:FindFirstChildOfClass("Humanoid")
                local an = hum and hum:FindFirstChildOfClass("Animator")
                if an and not hooked[an] then
                    local conn
                    conn = an.AnimationPlayed:Connect(function(track)
                        if getgenv().NEKOHUB_ESP_RUN ~= RUN then return conn:Disconnect() end
                        onTrack(kchar, track)
                    end)
                    hooked[an] = conn
                end
            end
            -- warm the controller cache between slashes; the controller isn't
            -- loaded during the round-start cutscene, so a miss retries in 5s
            if AUTO.SlashCrouch and UIS.TouchEnabled and getgenv().GameAPI.IsSurvivor()
                and os.clock() - warmAt > 5 then
                local btn = crouchBtn()
                if btn and not (ctrl and ctrlBtn == btn) then
                    warmAt = os.clock()
                    survivorCtrl(btn)
                end
            end
            -- same warm for the parry controller (exists on every platform;
            -- only the dagger model gates it)
            if AUTO.AutoParry and getgenv().GameAPI.IsSurvivor()
                and os.clock() - parryWarmAt > 5 then
                local dg = localPlayer.Character and localPlayer.Character:FindFirstChild("Parrying Dagger")
                if dg and not (pCtrl and pDagger == dg) then
                    parryWarmAt = os.clock()
                    parryCtrl()
                end
            end
        end
    end)
end

-- DBD-style custom camera: damped free-look orbit, trailing pivot, right shoulder
local CAM = { on = false, FOV = 80, sens = 0.009 }
local camConn, camInput, camSaved
local tYaw, tPitch, cYaw, cPitch, cPivot -- target + smoothed look + smoothed pivot
local CAM_DIST, CAM_UP, CAM_SIDE = 7, 2.2, 1.75
local CAM_POS_S, CAM_ROT_S, CAM_MOVE_SLOW = 10, 18, 0.5
local function camEnable(char)
    local cam, hrp = workspace.CurrentCamera, char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if camInput then camInput:Disconnect() camInput = nil end -- respawn re-entry
    local look = cam.CFrame.LookVector
    tYaw, cYaw = math.atan2(-look.X, -look.Z), math.atan2(-look.X, -look.Z)
    tPitch, cPitch = -0.12, -0.12
    cPivot = hrp.Position + Vector3.new(0, CAM_UP, 0)
    -- remember prior state so Set(false) restores exactly what the game had
    -- (FOV excluded: the game rewrites it every frame, ours only holds while enabled)
    camSaved = { cam.CameraType, cam.CameraSubject,
        localPlayer.CameraMinZoomDistance, localPlayer.CameraMaxZoomDistance, UIS.MouseBehavior }
    cam.CameraType = Enum.CameraType.Scriptable
    camInput = UIS.InputChanged:Connect(function(i, gpe)
        if gpe then return end
        -- slower sensitivity while the character is moving (DBD feel)
        local sens = CAM.sens
        if hrp and hrp.Parent and hrp.AssemblyLinearVelocity.Magnitude > 2 then sens *= CAM_MOVE_SLOW end
        if i.UserInputType == Enum.UserInputType.MouseMovement then
            tYaw -= i.Delta.X * sens
            tPitch = math.clamp(tPitch - i.Delta.Y * sens, -1.2, 1.2)
        elseif i.UserInputType == Enum.UserInputType.Touch
            and i.UserInputState == Enum.UserInputState.Change then
            tYaw -= i.Delta.X * sens * 0.7
            tPitch = math.clamp(tPitch - i.Delta.Y * sens * 0.7, -1.2, 1.2)
        end
    end)
    if UIS.MouseEnabled then UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end
    camConn = RunService:BindToRenderStep("nekoCam", Enum.RenderPriority.Camera.Value, function(dt)
        local hrp2 = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
        if not hrp2 then return end
        local a = math.min(1, dt * CAM_POS_S)
        cPivot = cPivot:Lerp(hrp2.Position + Vector3.new(0, CAM_UP, 0), a)
        local b = math.min(1, dt * CAM_ROT_S)
        cYaw += (tYaw - cYaw) * b
        cPitch += (tPitch - cPitch) * b
        cam.CFrame = CFrame.new(cPivot) * CFrame.Angles(0, cYaw, 0) * CFrame.Angles(cPitch, 0, 0)
            * CFrame.new(CAM_SIDE, 0, CAM_DIST)
        cam.FieldOfView = CAM.FOV
    end)
end
function CAM.Set(on)
    on = on ~= false
    if on == CAM.on then return end
    CAM.on = on
    if camConn then RunService:UnbindFromRenderStep("nekoCam") camConn = nil end
    if camInput then camInput:Disconnect() camInput = nil end
    local cam = workspace.CurrentCamera
    if on then
        camEnable(localPlayer.Character)
    else
        local s = camSaved
        if s then
            cam.CameraSubject = s[2]
            cam.CameraType = s[1]
            localPlayer.CameraMaxZoomDistance = s[4]
            localPlayer.CameraMinZoomDistance = s[3]
            if UIS.MouseEnabled then UIS.MouseBehavior = s[5] end
            camSaved = nil
        else
            cam.CameraType = Enum.CameraType.Custom
            local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
            localPlayer.CameraMaxZoomDistance = 400
            localPlayer.CameraMinZoomDistance = 0.5
            if UIS.MouseEnabled then UIS.MouseBehavior = Enum.MouseBehavior.Default end
        end
    end
end
function CAM.SetSens(v) CAM.sens = (tonumber(v) or 9) / 1000 end
localPlayer.CharacterAdded:Connect(function(char) if CAM.on then camEnable(char) end end)

getgenv().GameAPI = {
    IsLobby    = function(p) return teamName(p) == "Spectator" end,
    IsSurvivor = function(p) return teamName(p) == "Survivors" end,
    IsKiller   = function(p) return teamName(p) == "Killer"    end,
    TeamName   = teamName,
    -- currency attribute names on LocalPlayer (Screws is the main one)
    Currencies = { "Screws", "Gears" },
    -- ESP target finders (used by the Visuals tab)
    Targets = {
        Killer    = function() return charsOf(function(p) return teamName(p) == "Killer" end) end,
        Survivor  = function() return charsOf(function(p) return teamName(p) == "Survivors" end) end,
        Hook      = function() return props("Hook") end,
        Generator = function() return props("Generator") end,
        Vault     = function() return props("Vault") end,
        -- pallets are vaultable until broken (broken pallets get destroyed -> auto-pruned)
        Pallet    = function() return props("Pallet") end,
    },
    ESP = ESP,
    Overlay = OV,
    Auto = AUTO,
    Details = DT,
    Camera = CAM,
}

getgenv().NekoHubConfig = {
    title = "NekoHub",
    icon  = "rbxassetid://0", -- menu icon + floating button image
}

getgenv().import("main")

end
local cache = {}
getgenv().import = function(p) if cache[p] == nil then cache[p] = SRC[p]() end return cache[p] end
getgenv().import("games/ViolenceDistrict")
