if getgenv().Library and getgenv().Library.Unload then
    pcall(getgenv().Library.Unload, getgenv().Library)
end

--> Services (safe references)
local GetService = setmetatable({}, {
    __index = function(_, Name)
        return game:GetService(Name)
    end
})

local Workspace   = GetService["Workspace"]
local Players     = GetService["Players"]
local RunService  = GetService["RunService"]
local HttpService = GetService["HttpService"]

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--> Localized globals for performance
local WorldToViewportPoint  = Camera.WorldToViewportPoint
local FindFirstChildOfClass = game.FindFirstChildOfClass
local FindFirstChild        = game.FindFirstChild

local NewVector3  = Vector3.new
local NewVector2  = Vector2.new
local Dim         = UDim.new
local Dim2        = UDim2.new
local DimOffset   = UDim2.fromOffset
local NumSeq      = NumberSequence.new
local NumKey      = NumberSequenceKeypoint.new

local Format  = string.format
local Clear   = table.clear
local Floor   = math.floor
local Clamp   = math.clamp
local Abs     = math.abs
local Tan     = math.tan
local Rad     = math.rad
local Huge    = math.huge
local Remove  = table.remove

local FRAME_BUDGET = 1 / 60
local ZeroVector3  = NewVector3(0, 0, 0)
local CameraPosition = NewVector3(0, 0, 0)
local CachedFocalLength = 0
local ViewPortY  = 0
local LastUpdate = 0

--> Camera cache — rebuilt on FOV or viewport change
local function RebuildCameraCache()
    ViewPortY           = Camera.ViewportSize.Y
    CachedFocalLength   = ViewPortY / (2 * Tan(Rad(Camera.FieldOfView) * 0.5))
end

RebuildCameraCache()
Camera:GetPropertyChangedSignal("FieldOfView"):Connect(RebuildCameraCache)
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(RebuildCameraCache)

--------------------------------------------------------------------------------
-- Library definition
--------------------------------------------------------------------------------

getgenv().Library = {
    Directory   = "Esp",
    Cache       = {},
    Holder      = nil,
    Threads     = {},
    Connections = {},

    Table = {
        Enabled  = true,
        Distance = 7520,

        Boxes = {
            Enabled = true,

            ["Bounding Box"] = {
                Enabled            = true,
                IncludeAcsessories = false,
                BoxX               = 0,
                BoxY               = 0,
            },

            ["Box Glow"] = {
                Enabled      = true,
                Top          = Color3.fromRGB(255, 255, 255),
                Bot          = Color3.fromRGB(255, 255, 255),
                Transparency = { 0.9, 0.9 },
            },

            Gradients = {
                Top = Color3.fromRGB(255, 255, 255),
                Bot = Color3.fromRGB(255, 255, 255),
            },

            Filled = {
                Enabled      = true,
                Top          = Color3.fromRGB(255, 255, 255),
                Bot          = Color3.fromRGB(255, 255, 255),
                Transparency = { 1, 0.8 },
            },
        },

        Bars = {
            ["Health Bar"] = {
                Enabled = true,
                Top     = Color3.fromRGB(0,   255, 0),
                Mid     = Color3.fromRGB(255, 170, 0),
                Bot     = Color3.fromRGB(255, 0,   0),
            },
            ["Armor Bar"] = {
                Enabled = false,
                Top     = Color3.fromRGB(255, 255, 255),
                Mid     = Color3.fromRGB(220, 220, 220),
                Bot     = Color3.fromRGB(180, 180, 180),
            },
        },

        Texts = {
            Name = {
                Enabled = true,
                Color   = Color3.fromRGB(255, 255, 255),
            },
            Distance = {
                Enabled = true,
                Color   = Color3.fromRGB(255, 255, 255),
            },
            Weapon = {
                Enabled = true,
                Color   = Color3.fromRGB(255, 255, 255),
            },
        },
    },
}

local Library = getgenv().Library
local Cfg     = Library.Table

Library.__index = Library

--------------------------------------------------------------------------------
-- Font registration
--------------------------------------------------------------------------------

local function RegisterFont(name, weight, style, asset)
    if not isfile(asset.Id) then
        writefile(asset.Id, asset.Font)
    end
    local fontFile = name .. ".font"
    if isfile(fontFile) then
        delfile(fontFile)
    end
    local info = {
        name  = name,
        faces = {
            {
                name    = "Normal",
                weight  = weight,
                style   = style,
                assetId = getcustomasset(asset.Id),
            },
        },
    }
    writefile(fontFile, HttpService:JSONEncode(info))
    return getcustomasset(fontFile)
end

do
    local rawTahoma = RegisterFont("Tahoma", 400, "Normal", {
        Id   = "Tahoma.ttf",
        Font = game:HttpGet("https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/fs-tahoma-8px.ttf"),
    })

    local rawXPTahoma = RegisterFont("XPTahoma", 400, "Normal", {
        Id   = "Tahoma8PTBOLD.ttf",
        Font = game:HttpGet("https://github.com/sametexe001/luas/raw/refs/heads/main/fonts/TAHOMA-8PT-BOLD-WINDOWS-XP.TTF"),
    })

    local rawSmallest = RegisterFont("SmallestPixel", 400, "Normal", {
        Id   = "smallest_pixel-7.ttf",
        Font = game:HttpGet("https://raw.githubusercontent.com/sametexe001/luas/main/smallest_pixel-7.ttf"),
    })

    local rawProggyTiny = RegisterFont("ProggyTiny", 400, "Normal", {
        Id   = "ProggyTinyyyy.ttf",
        Font = game:HttpGet("https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/ProggyTiny.ttf"),
    })

    local rawProggyClean = RegisterFont("ProggyClean", 400, "Normal", {
        Id   = "ProggyClean.ttf",
        Font = game:HttpGet("https://github.com/i77lhm/storage/raw/main/fonts/ProggyClean.ttf"),
    })

    Library.ProggyTiny   = Font.new(rawProggyClean, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    Library.TahomaBold   = Font.new(rawXPTahoma,    Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    Library.ProggyClean  = Font.new(rawProggyClean, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    Library.Tahoma       = Font.new(rawTahoma,       Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    Library.SmallestPixel = Font.new(rawSmallest,   Enum.FontWeight.Regular, Enum.FontStyle.Normal)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function Library:Make(class, props)
    local obj = Instance.new(class)
    for k, v in props or {} do
        obj[k] = v
    end
    return obj
end

function Library:Track(name, signal, callback)
    local conn = signal:Connect(callback)
    self.Threads[name] = conn
    return conn
end

Library.Holder = Library:Make("ScreenGui", {
    Name           = "\n",
    Parent         = gethui(),
    ScreenInsets   = Enum.ScreenInsets.DeviceSafeInsets,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    ResetOnSpawn   = false,
    DisplayOrder   = 10000,
    IgnoreGuiInset = true,
})

--------------------------------------------------------------------------------
-- InitEsp — builds all GUI objects for one target
--------------------------------------------------------------------------------

function Library:InitEsp(data)
    local obj = data.Objects

    --> Root holders
    obj.TargetHolder = self:Make("Frame", {
        Parent               = self.Holder,
        Visible              = false,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.TopHolder = self:Make("Frame", {
        Parent               = obj.TargetHolder,
        AutomaticSize        = Enum.AutomaticSize.Y,
        Visible              = true,
        BackgroundTransparency = 1,
        AnchorPoint          = NewVector2(0,1),
        Position             = Dim2(0,-2,0,-5),
        Size                 = Dim2(1,4,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BottomHolder = self:Make("Frame", {
        Parent               = obj.TargetHolder,
        AutomaticSize        = Enum.AutomaticSize.Y,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(0,-2,1,3),
        Size                 = Dim2(1,4,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.LeftHolder = self:Make("Frame", {
        Parent               = obj.TargetHolder,
        AutomaticSize        = Enum.AutomaticSize.X,
        Visible              = true,
        BackgroundTransparency = 1,
        AnchorPoint          = NewVector2(1,0),
        Position             = Dim2(0,-5,0,-2),
        Size                 = Dim2(0,0,1,4),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.RightHolder = self:Make("Frame", {
        Parent               = obj.TargetHolder,
        AutomaticSize        = Enum.AutomaticSize.X,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(1,5,0,-2),
        Size                 = Dim2(0,0,1,4),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    --> Text holders
    obj.TopTextHolder = self:Make("Frame", {
        Parent               = obj.TopHolder,
        AutomaticSize        = Enum.AutomaticSize.Y,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BottomTextHolder = self:Make("Frame", {
        Parent               = obj.BottomHolder,
        LayoutOrder          = 2,
        AutomaticSize        = Enum.AutomaticSize.Y,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.LeftTextHolder = self:Make("Frame", {
        Parent               = obj.LeftHolder,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.RightTextHolder = self:Make("Frame", {
        Parent               = obj.RightHolder,
        LayoutOrder          = 2,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Visible              = true,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    --> Bar holders
    obj.LeftBarHolder = self:Make("Frame", {
        Parent               = obj.LeftHolder,
        AutomaticSize        = Enum.AutomaticSize.X,
        Visible              = false,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,0,1,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BottomBarHolder = self:Make("Frame", {
        Parent               = obj.BottomHolder,
        LayoutOrder          = 0,
        AutomaticSize        = Enum.AutomaticSize.Y,
        Visible              = false,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    --> List layouts
    self:Make("UIListLayout", { Parent = obj.TopTextHolder,    VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = Dim(0,1),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.BottomTextHolder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = Dim(0,-1), SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.LeftTextHolder,   HorizontalAlignment = Enum.HorizontalAlignment.Right,  Padding = Dim(0,0),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.RightTextHolder,  HorizontalAlignment = Enum.HorizontalAlignment.Left,   Padding = Dim(0,0),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.LeftBarHolder,    FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,  Padding = Dim(0,5), SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.BottomBarHolder,  HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = Dim(0,5),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.TopHolder,        VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = Dim(0,1),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.BottomHolder,     Padding = Dim(0,1),  SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.LeftHolder,       FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left,   Padding = Dim(0,1), SortOrder = Enum.SortOrder.LayoutOrder })
    self:Make("UIListLayout", { Parent = obj.RightHolder,      FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left,   Padding = Dim(0,1), SortOrder = Enum.SortOrder.LayoutOrder })

    --> Padding
    self:Make("UIPadding", { Parent = obj.TopTextHolder,    PaddingBottom = Dim(0,0) })
    self:Make("UIPadding", { Parent = obj.BottomTextHolder, PaddingTop    = Dim(0,-1) })
    self:Make("UIPadding", { Parent = obj.LeftTextHolder,   PaddingTop    = Dim(0,-3) })
    self:Make("UIPadding", { Parent = obj.RightTextHolder,  PaddingTop    = Dim(0,-3) })
    self:Make("UIPadding", { Parent = obj.LeftBarHolder,    PaddingRight  = Dim(0,0) })
    self:Make("UIPadding", { Parent = obj.BottomBarHolder,  PaddingTop    = Dim(0,2) })
    self:Make("UIPadding", { Parent = obj.LeftHolder,       PaddingRight  = Dim(0,1) })

    --> Box glow + gradients
    obj.BoxGlow = self:Make("ImageLabel", {
        Parent             = obj.TargetHolder,
        Image              = "rbxassetid://110204605000367",
        ScaleType          = Enum.ScaleType.Slice,
        SliceCenter        = Rect.new(NewVector2(21,21), NewVector2(79,79)),
        AutomaticSize      = Enum.AutomaticSize.XY,
        ImageTransparency  = 0.65,
        ResampleMode       = Enum.ResamplerMode.Pixelated,
        Visible            = true,
        BackgroundTransparency = 1,
        Position           = Dim2(0,-21,0,-21),
        Size               = Dim2(0,0,0,0),
        BorderSizePixel    = 0,
        BorderColor3       = Color3.fromRGB(0,0,0),
        BackgroundColor3   = Color3.fromRGB(255,255,255),
    })

    obj.BoxGlowGradient = self:Make("UIGradient", {
        Parent       = obj.BoxGlow,
        Rotation     = 90,
        Color        = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0)) }),
        Transparency = NumSeq({ NumKey(0,0), NumKey(1,0) }),
    })

    self:Make("UIPadding", {
        Parent        = obj.BoxGlow,
        PaddingTop    = Dim(0,21),
        PaddingBottom = Dim(0,20),
        PaddingLeft   = Dim(0,21),
        PaddingRight  = Dim(0,20),
    })

    obj.BoxOutlineHolder = self:Make("Frame", {
        Parent               = obj.BoxGlow,
        Visible              = false,
        BackgroundTransparency = 1,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BoxOutline = self:Make("UIStroke", {
        Parent      = obj.BoxOutlineHolder,
        Thickness   = 3,
        LineJoinMode = Enum.LineJoinMode.Miter,
    })

    obj.BoxOutlineGradient = self:Make("UIGradient", {
        Parent       = obj.BoxOutline,
        Rotation     = 90,
        Color        = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0)) }),
        Transparency = NumSeq({ NumKey(0,0), NumKey(1,0) }),
    })

    obj.BoxInlineHolder = self:Make("Frame", {
        Parent               = obj.BoxGlow,
        Visible              = false,
        BackgroundTransparency = 1,
        Position             = Dim2(0,-1,0,-1),
        Size                 = Dim2(0,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BoxInline = self:Make("UIStroke", {
        Parent      = obj.BoxInlineHolder,
        Color       = Color3.fromRGB(255,255,255),
        LineJoinMode = Enum.LineJoinMode.Miter,
    })

    obj.BoxInlineGradient = self:Make("UIGradient", {
        Parent       = obj.BoxInline,
        Rotation     = 90,
        Color        = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255,255,255)) }),
        Transparency = NumSeq({ NumKey(0,0), NumKey(1,0) }),
    })

    obj.BoxFill = self:Make("Frame", {
        Parent               = obj.BoxGlow,
        Visible              = false,
        BackgroundTransparency = 0,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,0,0,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.BoxFillGradient = self:Make("UIGradient", {
        Parent       = obj.BoxFill,
        Rotation     = 90,
        Color        = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255,255,255)) }),
        Transparency = NumSeq({ NumKey(0,1), NumKey(1,1) }),
    })

    --> Health bar
    obj.HealthBarOutline = self:Make("Frame", {
        Parent               = obj.LeftBarHolder,
        ZIndex               = 5,
        LayoutOrder          = 0,
        Visible              = false,
        BackgroundTransparency = 0,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(0,1,1,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(0,0,0),
        ClipsDescendants     = false,
    })

    self:Make("UIStroke", { Parent = obj.HealthBarOutline, Thickness = 1, LineJoinMode = Enum.LineJoinMode.Miter })

    obj.HealthBar = self:Make("Frame", {
        Parent               = obj.HealthBarOutline,
        ZIndex               = 6,
        AnchorPoint          = NewVector2(0,1),
        Position             = Dim2(0,0,1,0),
        Size                 = Dim2(1,0,1,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
        ClipsDescendants     = true,
    })

    obj.HealthBarGradient = self:Make("UIGradient", {
        Parent   = obj.HealthBar,
        Rotation = 90,
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Cfg.Bars["Health Bar"].Top),
            ColorSequenceKeypoint.new(0.5, Cfg.Bars["Health Bar"].Mid),
            ColorSequenceKeypoint.new(1,   Cfg.Bars["Health Bar"].Bot),
        }),
        Transparency = NumSeq({ NumKey(0,0), NumKey(1,0) }),
    })

    obj.HealthBarText = self:Make("TextLabel", {
        Parent               = obj.HealthBarOutline,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        ZIndex               = 10,
        TextColor3           = Color3.fromRGB(255,255,255),
        Text                 = "",
        TextXAlignment       = Enum.TextXAlignment.Center,
        TextYAlignment       = Enum.TextYAlignment.Center,
        AnchorPoint          = NewVector2(0.5,0.5),
        Position             = Dim2(0.5,0,1,0),
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.HealthBarText, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    --> Armor bar
    obj.ArmorBarOutline = self:Make("Frame", {
        Parent               = obj.BottomBarHolder,
        ZIndex               = 5,
        LayoutOrder          = 0,
        Visible              = false,
        BackgroundTransparency = 0,
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,0,1),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(0,0,0),
        ClipsDescendants     = true,
    })

    self:Make("UIStroke", { Parent = obj.ArmorBarOutline, Thickness = 1, LineJoinMode = Enum.LineJoinMode.Miter })

    obj.ArmorBar = self:Make("Frame", {
        Parent               = obj.ArmorBarOutline,
        ZIndex               = 6,
        AnchorPoint          = NewVector2(0,0),
        Position             = Dim2(0,0,0,0),
        Size                 = Dim2(1,0,1,0),
        BorderSizePixel      = 0,
        BorderColor3         = Color3.fromRGB(0,0,0),
        BackgroundColor3     = Color3.fromRGB(255,255,255),
    })

    obj.ArmorBarGradient = self:Make("UIGradient", {
        Parent   = obj.ArmorBar,
        Rotation = 0,
        Color    = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Cfg.Bars["Armor Bar"].Top),
            ColorSequenceKeypoint.new(0.5, Cfg.Bars["Armor Bar"].Mid),
            ColorSequenceKeypoint.new(1,   Cfg.Bars["Armor Bar"].Bot),
        }),
        Transparency = NumSeq({ NumKey(0,0), NumKey(1,0) }),
    })

    obj.ArmorBarText = self:Make("TextLabel", {
        Parent               = obj.ArmorBar,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        ZIndex               = 10,
        TextColor3           = Color3.fromRGB(255,255,255),
        Text                 = "",
        TextXAlignment       = Enum.TextXAlignment.Center,
        AnchorPoint          = NewVector2(0.5,0.5),
        Position             = Dim2(0.5,0,0.5,0),
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.ArmorBarText, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    --> Text labels
    obj.TargetName = self:Make("TextLabel", {
        Parent               = obj.TopTextHolder,
        FontFace             = Library.TahomaBold,
        TextSize             = 12,
        LayoutOrder          = 2,
        TextColor3           = Cfg.Texts.Name.Color,
        Text                 = "",
        TextXAlignment       = Enum.TextXAlignment.Center,
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        ZIndex               = 5,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.TargetName, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    obj.Distance = self:Make("TextLabel", {
        Parent               = obj.BottomTextHolder,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        LayoutOrder          = 2,
        TextColor3           = Cfg.Texts.Distance.Color,
        Text                 = "",
        TextXAlignment       = Enum.TextXAlignment.Center,
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        ZIndex               = 5,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.Distance, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    obj.WalkFlag = self:Make("TextLabel", {
        Parent               = obj.RightTextHolder,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        LayoutOrder          = 1,
        TextColor3           = Color3.fromRGB(255,0,0),
        Text                 = "Walking",
        TextXAlignment       = Enum.TextXAlignment.Left,
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        ZIndex               = 5,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.WalkFlag, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    obj.JumpFlag = self:Make("TextLabel", {
        Parent               = obj.RightTextHolder,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        LayoutOrder          = 2,
        TextColor3           = Color3.fromRGB(255,0,0),
        Text                 = "Jumping",
        TextXAlignment       = Enum.TextXAlignment.Left,
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        ZIndex               = 5,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.JumpFlag, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })

    obj.Weapon = self:Make("TextLabel", {
        Parent               = obj.BottomTextHolder,
        FontFace             = Library.SmallestPixel,
        TextSize             = 9,
        LayoutOrder          = 3,
        TextColor3           = Cfg.Texts.Weapon.Color,
        Text                 = "none",
        TextXAlignment       = Enum.TextXAlignment.Center,
        BorderSizePixel      = 0,
        Visible              = false,
        BackgroundTransparency = 1,
        ZIndex               = 5,
        AutomaticSize        = Enum.AutomaticSize.XY,
        Size                 = Dim2(0,0,0,0),
    })

    self:Make("UIStroke", { Parent = obj.Weapon, Color = Color3.fromRGB(0,0,0), LineJoinMode = Enum.LineJoinMode.Miter })
end

--------------------------------------------------------------------------------
-- CalculateBox
--------------------------------------------------------------------------------

function Library:CalculateBox(data)
    local root = data.RootPart
    if not root then return nil, nil, nil, nil, false end

    local rootScreen, onScreen = WorldToViewportPoint(Camera, root.Position)
    if not onScreen then return nil, nil, nil, nil, false end

    local bbCfg = Cfg.Boxes["Bounding Box"]

    if bbCfg.Enabled then
        local children = data.Children
        if not children then return nil, nil, nil, nil, false end

        local minX, minY =  Huge,  Huge
        local maxX, maxY = -Huge, -Huge
        local hasValid   = false

        for _, part in children do
            if part:IsA("BasePart") and part.Transparency ~= 1 and part ~= root then
                local parent = part.Parent
                if parent == nil then continue end
                if not data.IncludeAccessories and parent:IsA("Accessory") then continue end

                local ps, pOn = WorldToViewportPoint(Camera, part.Position)
                if not pOn or ps.Z <= 0 then continue end

                hasValid = true

                local cf = part.CFrame
                local sz = part.Size
                local hx, hy, hz = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
                local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
                local ds = CachedFocalLength / ps.Z

                local ex = (Abs(rx.X*hx) + Abs(uy.X*hy) + Abs(lz.X*hz)) * ds
                local ey = (Abs(rx.Y*hx) + Abs(uy.Y*hy) + Abs(lz.Y*hz)) * ds

                if ps.X - ex < minX then minX = ps.X - ex end
                if ps.X + ex > maxX then maxX = ps.X + ex end
                if ps.Y - ey < minY then minY = ps.Y - ey end
                if ps.Y + ey > maxY then maxY = ps.Y + ey end
            end
        end

        if not hasValid then return nil, nil, nil, nil, false end

        local px = bbCfg.BoxX
        local py = bbCfg.BoxY
        local w  = (maxX - minX) + px
        local h  = (maxY - minY) + py

        return w, h, minX - (px * 0.5), minY - (py * 0.5), true
    else
        local scale = (root.Size.Y * ViewPortY) / (rootScreen.Z * 2)
        local w, h  = 3 * scale, 4.5 * scale
        return w, h, rootScreen.X - (w * 0.5), rootScreen.Y - (h * 0.5), onScreen
    end
end

--------------------------------------------------------------------------------
-- AddTarget
--------------------------------------------------------------------------------

function Library:AddTarget(player)
    if player == LocalPlayer then return end
    if self.Cache[player] then return end

    local data = {
        Player      = player,
        Objects     = {},
        Conns       = {},  -- always initialized so RemoveTarget never hits nil
        Character   = nil,
        RootPart    = nil,
        Humanoid    = nil,
        Children    = nil,
        Health      = 0,
        MaxHealth   = 100,
        Armor       = 100,
        MaxArmor    = 100,
        CurrentTool = nil,
        Alive       = false,
        IncludeAccessories = Cfg.Boxes["Bounding Box"].IncludeAcsessories,

        -- dirty-check cache
        LastW = nil, LastH = nil, LastX = nil, LastY = nil,
        LastGlowTop = nil, LastGlowBot = nil, LastGlowT1 = nil, LastGlowT2 = nil,
        LastGradTop = nil, LastGradBot = nil,
        LastFillTop = nil, LastFillBot = nil, LastFillT1 = nil, LastFillT2 = nil,
        LastDist = nil, LastDistColor = nil,
        LastDisplayName = nil, LastNameColor = nil,
        LastHealthTop = nil, LastHealthMid = nil, LastHealthBot = nil,
        LastHealthFloor = nil, LastRatio = nil,
        LastArmorTop = nil, LastArmorMid = nil, LastArmorBot = nil,
        LastArmorFloor = nil, LastArmorRatio = nil,
        LastWeapon = nil, LastWeaponColor = nil,
        WalkActive = false, JumpActive = false,
    }

    -- build GUI objects before registering in cache
    self:InitEsp(data)
    self.Cache[player] = data

    --> Health binding
    local function bindHealth(hum)
        if data.Conns.Health then data.Conns.Health:Disconnect() end
        if data.Conns.Died   then data.Conns.Died:Disconnect() end

        data.Humanoid  = hum
        data.Health    = hum.Health
        data.MaxHealth = hum.MaxHealth
        data.Alive     = hum.Health > 0

        data.Conns.Health = hum.HealthChanged:Connect(function(hp)
            data.Alive  = hp > 0
            data.Health = hp
        end)

        data.Conns.Died = hum.Died:Connect(function()
            data.Alive = false
        end)
    end

    --> Tool binding
    local function bindTool(char)
        if data.Conns.ToolAdded   then data.Conns.ToolAdded:Disconnect() end
        if data.Conns.ToolRemoved then data.Conns.ToolRemoved:Disconnect() end

        if data.Children then
            for _, child in pairs(data.Children) do
                if child:IsA("Tool") then
                    data.CurrentTool = child.Name
                    break
                end
            end
        end

        data.Conns.ToolAdded = char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then data.CurrentTool = child.Name end
        end)

        data.Conns.ToolRemoved = char.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then data.CurrentTool = nil end
        end)
    end

    --> Children binding
    local function bindChildren(char)
        if data.Conns.ChildAdded   then data.Conns.ChildAdded:Disconnect() end
        if data.Conns.ChildRemoved then data.Conns.ChildRemoved:Disconnect() end

        local children    = char:GetChildren()
        data.Children     = children

        data.Conns.ChildAdded = char.ChildAdded:Connect(function(child)
            children[#children + 1] = child
        end)

        data.Conns.ChildRemoved = char.ChildRemoved:Connect(function(child)
            for i = #children, 1, -1 do
                if children[i] == child then
                    Remove(children, i)
                    break
                end
            end
        end)

        bindTool(char)
    end

    --> Flags binding (walk / jump indicators)
    local function bindFlags(hum)
        if data.Conns.MoveDir     then data.Conns.MoveDir:Disconnect() end
        if data.Conns.StateChange then data.Conns.StateChange:Disconnect() end

        local obj          = data.Objects
        data.JumpActive    = false
        data.WalkActive    = false
        obj.WalkFlag.Visible = false
        obj.JumpFlag.Visible = false

        data.Conns.MoveDir = hum:GetPropertyChangedSignal("MoveDirection"):Connect(function()
            local walking = hum.MoveDirection ~= ZeroVector3

            if walking and not data.WalkActive then
                data.WalkActive = true
                obj.WalkFlag.LayoutOrder = data.JumpActive and 2 or 1
                if not data.JumpActive then obj.JumpFlag.LayoutOrder = 2 end
                obj.WalkFlag.Visible = true

            elseif not walking and data.WalkActive then
                data.WalkActive = false
                obj.WalkFlag.Visible = false
                if data.JumpActive then obj.JumpFlag.LayoutOrder = 1 end
            end
        end)

        data.Conns.StateChange = hum.StateChanged:Connect(function(_, newState)
            local jumping = newState == Enum.HumanoidStateType.Jumping
                         or newState == Enum.HumanoidStateType.Freefall

            if jumping and not data.JumpActive then
                data.JumpActive = true
                obj.JumpFlag.LayoutOrder = data.WalkActive and 2 or 1
                if not data.WalkActive then obj.WalkFlag.LayoutOrder = 2 end
                obj.JumpFlag.Visible = true

            elseif not jumping and data.JumpActive then
                data.JumpActive = false
                obj.JumpFlag.Visible = false
                if data.WalkActive then obj.WalkFlag.LayoutOrder = 1 end
            end
        end)
    end

    --> Character handler
    local function onCharacter(char)
        data.Character  = char
        data.RootPart   = nil
        data.Humanoid   = nil
        data.Children   = nil
        data.Alive      = false
        data.WalkActive = false
        data.JumpActive = false

        if not char or not char.Parent then return end

        local root = FindFirstChild(char, "HumanoidRootPart")
            or char:WaitForChild("HumanoidRootPart", 10)

        local hum = FindFirstChildOfClass(char, "Humanoid")
            or char:WaitForChild("Humanoid", 10)

        -- re-check parent after yield
        if not root or not hum or not char.Parent then return end

        data.RootPart = root
        data.Humanoid = hum

        bindChildren(char)
        bindHealth(hum)
        bindFlags(hum)
    end

    data.Conns.CharAdded = player.CharacterAdded:Connect(function(char)
        task.defer(onCharacter, char)
    end)

    if player.Character and player.Character.Parent then
        task.defer(onCharacter, player.Character)
    end
end

--------------------------------------------------------------------------------
-- RemoveTarget — guarded against nil Conns / Objects
--------------------------------------------------------------------------------

function Library:RemoveTarget(player)
    local data = self.Cache[player]
    if not data then return end

    -- disconnect all connections safely
    if data.Conns then
        for _, conn in pairs(data.Conns) do
            pcall(function() conn:Disconnect() end)
        end
        Clear(data.Conns)
    end

    -- destroy root GUI frame (children go with it)
    if data.Objects and data.Objects.TargetHolder then
        pcall(function() data.Objects.TargetHolder:Destroy() end)
    end

    if data.Objects then
        Clear(data.Objects)
    end

    self.Cache[player] = nil
end

--------------------------------------------------------------------------------
-- Update — renders one target per frame budget
--------------------------------------------------------------------------------

function Library:Update(player, data)
    -- guard: objects must exist
    if not data or not data.Objects or not data.Objects.TargetHolder then return end

    local obj = data.Objects

    local function hide()
        if obj.TargetHolder.Visible then
            obj.TargetHolder.Visible = false
        end
    end

    if not data.RootPart  then hide() return end
    if not data.Alive     then hide() return end

    -- guard: root part may have been removed
    local rootOk, rootPos = pcall(function() return data.RootPart.Position end)
    if not rootOk then hide() return end

    local dist = Floor((CameraPosition - rootPos).Magnitude)
    if dist > Cfg.Distance then hide() return end

    local w, h, x, y, onScreen = self:CalculateBox(data)
    if not onScreen or not w then hide() return end

    w = Floor(w)
    h = Floor(h)
    x = Floor(x)
    y = Floor(y)

    if not obj.TargetHolder.Visible then
        obj.TargetHolder.Visible = true
    end

    local sizeChanged = data.LastW ~= w or data.LastH ~= h
    local posChanged  = data.LastX ~= x or data.LastY ~= y

    if posChanged then
        obj.TargetHolder.Position = DimOffset(x, y)
        data.LastX = x
        data.LastY = y
    end

    if sizeChanged then
        obj.TargetHolder.Size        = DimOffset(w, h)
        obj.BoxGlow.Size             = DimOffset(w, h)
        obj.BoxOutlineHolder.Size    = DimOffset(w, h)
        obj.BoxInlineHolder.Size     = DimOffset(w + 2, h + 2)
        obj.BoxFill.Size             = DimOffset(w, h)
        data.LastW = w
        data.LastH = h
    end

    local boxCfg  = Cfg.Boxes
    local textCfg = Cfg.Texts

    --> Boxes
    if boxCfg.Enabled then
        local glowCfg = boxCfg["Box Glow"]

        if glowCfg.Enabled then
            if obj.BoxGlow.ImageTransparency ~= 0 then obj.BoxGlow.ImageTransparency = 0 end

            local gt, gb = glowCfg.Top, glowCfg.Bot
            if data.LastGlowTop ~= gt or data.LastGlowBot ~= gb then
                obj.BoxGlowGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, gt), ColorSequenceKeypoint.new(1, gb) })
                data.LastGlowTop = gt
                data.LastGlowBot = gb
            end

            local t1, t2 = glowCfg.Transparency[1], glowCfg.Transparency[2]
            if data.LastGlowT1 ~= t1 or data.LastGlowT2 ~= t2 then
                obj.BoxGlowGradient.Transparency = NumSeq({ NumKey(0, t1), NumKey(1, t2) })
                data.LastGlowT1 = t1
                data.LastGlowT2 = t2
            end
        else
            if obj.BoxGlow.ImageTransparency ~= 1 then obj.BoxGlow.ImageTransparency = 1 end
        end

        if not obj.BoxOutlineHolder.Visible then obj.BoxOutlineHolder.Visible = true end
        if not obj.BoxInlineHolder.Visible  then obj.BoxInlineHolder.Visible  = true end

        local gradTop, gradBot = boxCfg.Gradients.Top, boxCfg.Gradients.Bot
        if data.LastGradTop ~= gradTop or data.LastGradBot ~= gradBot then
            obj.BoxInlineGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, gradTop), ColorSequenceKeypoint.new(1, gradBot) })
            data.LastGradTop = gradTop
            data.LastGradBot = gradBot
        end

        if boxCfg.Filled.Enabled then
            if not obj.BoxFill.Visible then obj.BoxFill.Visible = true end

            local ft, fb = boxCfg.Filled.Top, boxCfg.Filled.Bot
            local ft1, ft2 = boxCfg.Filled.Transparency[1], boxCfg.Filled.Transparency[2]

            if data.LastFillTop ~= ft or data.LastFillBot ~= fb then
                obj.BoxFillGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, ft), ColorSequenceKeypoint.new(1, fb) })
                data.LastFillTop = ft
                data.LastFillBot = fb
            end

            if data.LastFillT1 ~= ft1 or data.LastFillT2 ~= ft2 then
                obj.BoxFillGradient.Transparency = NumSeq({ NumKey(0, ft1), NumKey(1, ft2) })
                data.LastFillT1 = ft1
                data.LastFillT2 = ft2
            end
        else
            if obj.BoxFill.Visible then obj.BoxFill.Visible = false end
        end
    else
        if obj.BoxGlow.ImageTransparency ~= 1 then obj.BoxGlow.ImageTransparency = 1 end
        if obj.BoxOutlineHolder.Visible then obj.BoxOutlineHolder.Visible = false end
        if obj.BoxInlineHolder.Visible  then obj.BoxInlineHolder.Visible  = false end
        if obj.BoxFill.Visible          then obj.BoxFill.Visible          = false end
    end

    --> Name
    if textCfg.Name.Enabled then
        if not obj.TargetName.Visible then obj.TargetName.Visible = true end

        local name = player.DisplayName
        if data.LastDisplayName ~= name then
            obj.TargetName.Text = name
            data.LastDisplayName = name
        end

        local nc = textCfg.Name.Color
        if data.LastNameColor ~= nc then
            obj.TargetName.TextColor3 = nc
            data.LastNameColor = nc
        end
    else
        if obj.TargetName.Visible then obj.TargetName.Visible = false end
    end

    --> Distance
    if textCfg.Distance.Enabled then
        if not obj.Distance.Visible then obj.Distance.Visible = true end

        if data.LastDist ~= dist then
            obj.Distance.Text = Format("%dst", dist)
            data.LastDist = dist
        end

        local dc = textCfg.Distance.Color
        if data.LastDistColor ~= dc then
            obj.Distance.TextColor3 = dc
            data.LastDistColor = dc
        end
    else
        if obj.Distance.Visible then obj.Distance.Visible = false end
    end

    --> Health bar
    local hpCfg    = Cfg.Bars["Health Bar"]
    local armorCfg = Cfg.Bars["Armor Bar"]

    if hpCfg.Enabled then
        local hp      = data.Health    or 0
        local maxHp   = data.MaxHealth or 100
        local ratio   = Clamp(hp / maxHp, 0, 1)

        if not obj.LeftBarHolder.Visible    then obj.LeftBarHolder.Visible    = true end
        if not obj.HealthBarOutline.Visible then obj.HealthBarOutline.Visible = true end

        if data.LastRatio ~= ratio then
            obj.HealthBar.Size = Dim2(1, 0, ratio, 0)
            data.LastRatio = ratio
        end

        local ht, hm, hb = hpCfg.Top, hpCfg.Mid, hpCfg.Bot
        if data.LastHealthTop ~= ht or data.LastHealthMid ~= hm or data.LastHealthBot ~= hb then
            obj.HealthBarGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,   ht),
                ColorSequenceKeypoint.new(0.5, hm),
                ColorSequenceKeypoint.new(1,   hb),
            })
            data.LastHealthTop = ht
            data.LastHealthMid = hm
            data.LastHealthBot = hb
        end

        if not obj.HealthBarText.Visible then obj.HealthBarText.Visible = true end

        local fh = Floor(hp)
        if data.LastHealthFloor ~= fh then
            obj.HealthBarText.Text     = Format("%d", fh)
            obj.HealthBarText.Position = Dim2(1, -10, 1 - ratio, 1)
            data.LastHealthFloor = fh
        end
    else
        if obj.HealthBarOutline.Visible then obj.HealthBarOutline.Visible = false end
        if obj.HealthBarText.Visible    then obj.HealthBarText.Visible    = false end
        if not armorCfg.Enabled then
            if obj.LeftBarHolder.Visible then obj.LeftBarHolder.Visible = false end
        end
    end

    --> Armor bar
    if armorCfg.Enabled then
        local ratio = Clamp(data.Armor / data.MaxArmor, 0, 1)

        if not obj.BottomBarHolder.Visible  then obj.BottomBarHolder.Visible  = true end
        if not obj.ArmorBarOutline.Visible  then obj.ArmorBarOutline.Visible  = true end

        if data.LastArmorRatio ~= ratio then
            obj.ArmorBar.Size = Dim2(ratio, 0, 1, 0)
            data.LastArmorRatio = ratio
        end

        local at, am, ab = armorCfg.Top, armorCfg.Mid, armorCfg.Bot
        if data.LastArmorTop ~= at or data.LastArmorMid ~= am or data.LastArmorBot ~= ab then
            obj.ArmorBarGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,   at),
                ColorSequenceKeypoint.new(0.5, am),
                ColorSequenceKeypoint.new(1,   ab),
            })
            data.LastArmorTop = at
            data.LastArmorMid = am
            data.LastArmorBot = ab
        end

        if ratio < 1 then
            if not obj.ArmorBarText.Visible then obj.ArmorBarText.Visible = true end
            local fa = Floor(data.Armor)
            if data.LastArmorFloor ~= fa then
                obj.ArmorBarText.Text = Format("%d", fa)
                data.LastArmorFloor = fa
            end
        else
            if obj.ArmorBarText.Visible then obj.ArmorBarText.Visible = false end
        end
    else
        if obj.BottomBarHolder.Visible  then obj.BottomBarHolder.Visible  = false end
        if obj.ArmorBarOutline.Visible  then obj.ArmorBarOutline.Visible  = false end
        if obj.ArmorBarText.Visible     then obj.ArmorBarText.Visible     = false end
    end

    --> Weapon
    local wpnCfg = textCfg.Weapon
    if wpnCfg.Enabled then
        if not obj.Weapon.Visible then obj.Weapon.Visible = true end

        local tool = data.CurrentTool or "none"
        if data.LastWeapon ~= tool then
            obj.Weapon.Text = tool
            data.LastWeapon = tool
        end

        local wc = wpnCfg.Color
        if data.LastWeaponColor ~= wc then
            obj.Weapon.TextColor3 = wc
            data.LastWeaponColor = wc
        end
    else
        if obj.Weapon.Visible then obj.Weapon.Visible = false end
    end
end

--------------------------------------------------------------------------------
-- Renderer
--------------------------------------------------------------------------------

Library:Track("Renderer", RunService.RenderStepped, function()
    if not Cfg.Enabled then
        for _, data in pairs(Library.Cache) do
            if data.Objects and data.Objects.TargetHolder
            and data.Objects.TargetHolder.Visible then
                data.Objects.TargetHolder.Visible = false
            end
        end
        return
    end

    local now = os.clock()
    if now - LastUpdate < FRAME_BUDGET then return end

    LastUpdate       = now
    CameraPosition   = Camera.CFrame.Position

    for player, data in pairs(Library.Cache) do
        Library:Update(player, data)
    end
end)

--------------------------------------------------------------------------------
-- Player tracking
--------------------------------------------------------------------------------

for _, player in Players:GetPlayers() do
    Library:AddTarget(player)
end

Library:Track("PlayerAdded", Players.PlayerAdded, function(player)
    Library:AddTarget(player)
end)

Library:Track("PlayerRemoving", Players.PlayerRemoving, function(player)
    Library:RemoveTarget(player)
end)

--------------------------------------------------------------------------------
-- Unload
--------------------------------------------------------------------------------

function Library:Unload()
    for player in pairs(self.Cache) do
        self:RemoveTarget(player)
    end

    for _, conn in pairs(self.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Clear(self.Connections)

    for _, conn in pairs(self.Threads) do
        pcall(function() conn:Disconnect() end)
    end
    Clear(self.Threads)

    if self.Holder then
        pcall(function() self.Holder:Destroy() end)
        self.Holder = nil
    end

    Clear(self.Cache)
end

return Library
