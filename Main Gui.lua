--[[
	TaC — "exploit" panel for your own game
	-------------------------------------------------------
	Put it in: LocalScript → StarterPlayer > StarterPlayerScripts
	ONE LocalScript, no server script needed.
	REAL modules: ESP (Visuals tab) and Kill Aura (Combat tab).
	Everything else is a stub that only shows a notification —
	hook your own logic where marked TODO.

	Controls:
	  • RightShift  — hide / show menu
	  • Drag the top bar to move
	  • "–" minimize, "×" close

	Extras:
	  • Watermark (top-left): TaC | user | fps | ping | time
	  • Arraylist (top-right): every enabled module
	  • Fake injector splash with console log

	API:
	  local Window = Library:CreateWindow({ Title = "TaC", Subtitle = "..." })
	  local Tab = Window:CreateTab({ Name = "Combat", Description = "..." })
	  Tab:AddSection("Aimbot")
	  Tab:AddToggle({ Name, Description, Default, NoList, Callback(state) })
	  Tab:AddSlider({ Name, Min, Max, Default, Step, Suffix, Callback(value) })
	  Tab:AddButton({ Name, Description, Callback() })
	  Tab:AddDropdown({ Name, Options = {...}, Default, Callback(option) })
	  Tab:AddKeybind({ Name, Default = Enum.KeyCode.X, Callback() })
	  Tab:AddInput({ Name, Placeholder, Callback(text, enterPressed) })
	  Tab:AddParagraph({ Title, Text })
	  Library:Notify({ Title, Text, Duration })
	  Library:SetAccent(Color3, Color3)
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Debris           = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------
local THEME = {
	Background   = Color3.fromRGB(9, 8, 12),
	Sidebar      = Color3.fromRGB(13, 12, 17),
	Element      = Color3.fromRGB(17, 16, 23),
	ElementHover = Color3.fromRGB(23, 21, 31),
	Stroke       = Color3.fromRGB(36, 33, 48),
	Accent       = Color3.fromRGB(145, 85, 255),  -- main purple
	Accent2      = Color3.fromRGB(205, 120, 255), -- light violet (for gradients)
	Text         = Color3.fromRGB(232, 230, 240),
	SubText      = Color3.fromRGB(122, 118, 140),
	Good         = Color3.fromRGB(70, 240, 130),
	Font         = Enum.Font.RobotoMono,
	FontBold     = Enum.Font.GothamBlack,
	FontLight    = Enum.Font.RobotoMono,
}

local TOGGLE_KEY  = Enum.KeyCode.RightShift
local WINDOW_SIZE = Vector2.new(560, 370)
local BRAND       = "TaC"

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function create(className, props, children)
	local obj = Instance.new(className)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else obj[k] = v end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = obj
	end
	if parent then obj.Parent = parent end
	return obj
end

local function tween(obj, time, props, style, dir)
	local tw = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 3) })
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color or THEME.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(t, b, l, r)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or 0),
		PaddingLeft = UDim.new(0, l or 0),
		PaddingRight = UDim.new(0, r or 0),
	})
end

local function safeCall(fn, ...)
	if typeof(fn) ~= "function" then return end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then warn("[TaC] callback error: " .. tostring(err)) end
	end)
end

-- accent colour registry (lets you switch theme live)
local accentListeners = {}
local function onAccent(fn)
	table.insert(accentListeners, fn)
	fn(THEME.Accent, THEME.Accent2)
end

local function accentGradient(rotation)
	local g = create("UIGradient", { Rotation = rotation or 0 })
	onAccent(function(a1, a2) g.Color = ColorSequence.new(a1, a2) end)
	return g
end

-- animated purple "shimmer" gradient (top line, arraylist, bars)
local shimmerGradients = {}
local function shimmerGradient(rotation)
	local g = create("UIGradient", { Rotation = rotation or 0 })
	table.insert(shimmerGradients, g)
	return g
end

local shimmerT = 0
RunService.RenderStepped:Connect(function(dt)
	shimmerT += dt
	local kp = {}
	for i = 0, 6 do
		local t = i / 6
		local a = (math.sin(shimmerT * 2.2 - t * math.pi * 2) + 1) / 2
		kp[#kp + 1] = ColorSequenceKeypoint.new(t, THEME.Accent:Lerp(THEME.Accent2, a))
	end
	local seq = ColorSequence.new(kp)
	for i = #shimmerGradients, 1, -1 do
		local g = shimmerGradients[i]
		if g.Parent then g.Color = seq else table.remove(shimmerGradients, i) end
	end
end)

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function hover(frame, normal, hovered)
	frame.MouseEnter:Connect(function() tween(frame, 0.15, { BackgroundColor3 = hovered }) end)
	frame.MouseLeave:Connect(function() tween(frame, 0.15, { BackgroundColor3 = normal }) end)
end

---------------------------------------------------------------------
-- LIBRARY
---------------------------------------------------------------------
local Library = {}
local Window = {}; Window.__index = Window
local Tab = {};    Tab.__index = Tab

local ScreenGui = create("ScreenGui", {
	Name = "TaCPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = playerGui,
})

---------------------------------------------------------------------
-- WATERMARK (top-left)
---------------------------------------------------------------------
local watermark = create("Frame", {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.Background,
	Visible = false,
	Parent = ScreenGui,
}, { corner(3), stroke(THEME.Stroke), padding(0, 0, 8, 8) })
create("Frame", {
	Size = UDim2.new(1, 16, 0, 2),
	Position = UDim2.fromOffset(-8, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	Parent = watermark,
}, { shimmerGradient(0) })
local wmText = create("TextLabel", {
	Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Font = THEME.Font,
	RichText = true,
	Text = "",
	TextColor3 = THEME.Text,
	TextSize = 11,
	Parent = watermark,
})

do
	local frames, last = 0, os.clock()
	RunService.RenderStepped:Connect(function()
		frames += 1
		local now = os.clock()
		if now - last >= 0.5 then
			local fps = math.floor(frames / (now - last) + 0.5)
			frames, last = 0, now
			local ping = 0
			pcall(function() ping = math.floor(player:GetNetworkPing() * 1000) end)
			wmText.Text = ('<font color="#%s"><b>%s</b></font>  |  %s  |  %d fps  |  %d ms  |  %s')
				:format(THEME.Accent:ToHex(), BRAND, player.Name, fps, ping, os.date("%H:%M:%S"))
		end
	end)
end

---------------------------------------------------------------------
-- ARRAYLIST (top-right) — shows enabled modules
---------------------------------------------------------------------
local arraylist = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(220, 600),
	BackgroundTransparency = 1,
	Parent = ScreenGui,
}, {
	create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local arrayEntries = {}
local function setModule(name, enabled)
	if enabled and not arrayEntries[name] then
		local row = create("Frame", {
			Size = UDim2.fromOffset(0, 17),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = THEME.Background,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			LayoutOrder = -#name,
			Parent = arraylist,
		}, { padding(0, 0, 7, 8) })
		local lbl = create("TextLabel", {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = THEME.Font,
			Text = name,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 12,
			TextTransparency = 1,
			Parent = row,
		}, { shimmerGradient(90) })
		create("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = row,
		}, { shimmerGradient(90) })
		tween(lbl, 0.25, { TextTransparency = 0 })
		arrayEntries[name] = row
	elseif not enabled and arrayEntries[name] then
		arrayEntries[name]:Destroy()
		arrayEntries[name] = nil
	end
end

---------------------------------------------------------------------
-- NOTIFICATIONS
---------------------------------------------------------------------
local NotifyHolder = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.new(0, 240, 1, -40),
	BackgroundTransparency = 1,
	Parent = ScreenGui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local notifyOrder = 0
function Library:Notify(cfg)
	cfg = cfg or {}
	local duration = cfg.Duration or 3.5
	notifyOrder += 1

	local slot = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = notifyOrder,
		Parent = NotifyHolder,
	})
	local card = create("Frame", {
		Position = UDim2.new(1, 30, 0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Background,
		Parent = slot,
	}, { corner(3), stroke(THEME.Stroke) })

	create("TextLabel", {
		Position = UDim2.fromOffset(10, 7),
		Size = UDim2.new(1, -20, 0, 14),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		RichText = true,
		Text = ('<font color="#%s">[%s]</font> %s'):format(THEME.Accent:ToHex(), BRAND, cfg.Title or ""),
		TextColor3 = THEME.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	create("TextLabel", {
		Position = UDim2.fromOffset(10, 23),
		Size = UDim2.new(1, -20, 0, 16),
		BackgroundTransparency = 1,
		Font = THEME.FontLight,
		Text = "> " .. (cfg.Text or ""),
		TextColor3 = THEME.SubText,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local progress = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, { shimmerGradient(0) })

	tween(card, 0.35, { Position = UDim2.new(0, 0, 0, 0) })
	tween(progress, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		tween(card, 0.3, { Position = UDim2.new(1, 30, 0, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(0.31)
		slot:Destroy()
	end)
end

function Library:SetAccent(color, color2)
	THEME.Accent = color
	if color2 then THEME.Accent2 = color2 end
	for _, fn in ipairs(accentListeners) do fn(THEME.Accent, THEME.Accent2) end
end

---------------------------------------------------------------------
-- WINDOW
---------------------------------------------------------------------
function Library:CreateWindow(cfg)
	cfg = cfg or {}
	local self = setmetatable({ Tabs = {}, Current = nil, Minimized = false, Hidden = true }, Window)

	local root = create("CanvasGroup", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = ScreenGui,
	})
	local scale = create("UIScale", { Scale = 0.94, Parent = root })

	local win = create("Frame", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = THEME.Background,
		ClipsDescendants = true,
		Parent = root,
	}, { corner(4), stroke(THEME.Stroke) })

	create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = win,
	}, { shimmerGradient(0) })

	-------------------------------------------------------------- TOPBAR
	local topbar = create("Frame", {
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = win,
	})
	makeDraggable(topbar, root)

	local title = create("TextLabel", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = THEME.FontBold,
		Text = cfg.Title or BRAND,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topbar,
	}, { accentGradient(0) })

	create("TextLabel", {
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.fromOffset(240, 12),
		BackgroundTransparency = 1,
		Font = THEME.FontLight,
		Text = cfg.Subtitle or "build 1.0.4 // private",
		TextColor3 = THEME.SubText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topbar,
	})

	-- glitch effect on the title
	task.spawn(function()
		local original = cfg.Title or BRAND
		local glitch = { "T4C", "7aC", "T@C", "Ta<", "TA©", "#aC" }
		while title.Parent do
			task.wait(math.random(30, 70) / 10)
			for _ = 1, 3 do
				title.Text = glitch[math.random(1, #glitch)]
				task.wait(0.05)
			end
			title.Text = original
		end
	end)

	local statusPill = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -64, 0.5, 0),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(10, 28, 18),
		Parent = topbar,
	}, { corner(3), stroke(Color3.fromRGB(30, 100, 58)), padding(0, 0, 18, 8) })
	local sdot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -11, 0.5, 0),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = THEME.Good,
		Parent = statusPill,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	create("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "INJECTED · UNDETECTED",
		TextColor3 = THEME.Good,
		TextSize = 10,
		Parent = statusPill,
	})
	task.spawn(function()
		while sdot.Parent do
			tween(sdot, 0.6, { BackgroundTransparency = 0.8 }, Enum.EasingStyle.Sine)
			task.wait(0.6)
			tween(sdot, 0.6, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
			task.wait(0.6)
		end
	end)

	local function topButton(text, offsetX, hoverColor)
		local b = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, offsetX, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = THEME.Element,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = THEME.Font,
			Text = text,
			TextColor3 = THEME.SubText,
			TextSize = 14,
			Parent = topbar,
		}, { corner(3) })
		b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundTransparency = 0, TextColor3 = hoverColor or THEME.Text }) end)
		b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundTransparency = 1, TextColor3 = THEME.SubText }) end)
		return b
	end
	local closeBtn = topButton("×", -8, Color3.fromRGB(255, 80, 110))
	local minBtn   = topButton("–", -32)

	create("Frame", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = win,
	})

	-------------------------------------------------------------- SIDEBAR
	local FOOTER_H = 18
	local sidebar = create("Frame", {
		Position = UDim2.fromOffset(0, 39),
		Size = UDim2.new(0, 136, 1, -39 - FOOTER_H),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = win,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = sidebar,
	})

	local tabList = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = sidebar,
	}, {
		padding(8, 8, 6, 7),
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local userCard = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -6),
		Size = UDim2.new(1, -13, 0, 34),
		BackgroundColor3 = THEME.Element,
		Parent = sidebar,
	}, { corner(3), stroke(THEME.Stroke) })
	local avatar = create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = THEME.Stroke,
		Parent = userCard,
	}, { corner(3) })
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, player.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		if ok then avatar.Image = img end
	end)
	create("TextLabel", {
		Position = UDim2.fromOffset(34, 5),
		Size = UDim2.new(1, -38, 0, 13),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = player.Name,
		TextColor3 = THEME.Text,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = userCard,
	})
	local plan = create("TextLabel", {
		Position = UDim2.fromOffset(34, 18),
		Size = UDim2.new(1, -38, 0, 11),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "lifetime · uid " .. tostring(player.UserId % 100000),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = userCard,
	})
	onAccent(function(a) plan.TextColor3 = a end)

	-------------------------------------------------------------- CONTENT
	local content = create("Frame", {
		Position = UDim2.fromOffset(137, 39),
		Size = UDim2.new(1, -137, 1, -39 - FOOTER_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = win,
	})

	-------------------------------------------------------------- FOOTER (fake console line)
	local footer = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		BackgroundColor3 = THEME.Sidebar,
		BorderSizePixel = 0,
		Parent = win,
	})
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = footer,
	})
	local footerText = create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "> ready.",
		TextColor3 = THEME.SubText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = footer,
	})
	create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "[RShift] toggle",
		TextColor3 = THEME.SubText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = footer,
	})
	function self:Log(text)
		footerText.Text = "> " .. text
		footerText.TextColor3 = THEME.Text
		tween(footerText, 1.2, { TextColor3 = THEME.SubText })
	end

	self.Root, self.Scale, self.TabList, self.Content = root, scale, tabList, content

	function self:Show()
		self.Hidden = false
		root.Visible = true
		tween(root, 0.3, { GroupTransparency = 0 })
		tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	function self:Hide()
		self.Hidden = true
		tween(root, 0.2, { GroupTransparency = 1 })
		tween(scale, 0.2, { Scale = 0.95 })
		task.delay(0.21, function() if self.Hidden then root.Visible = false end end)
	end
	function self:ToggleMinimize()
		self.Minimized = not self.Minimized
		tween(root, 0.35, { Size = UDim2.fromOffset(WINDOW_SIZE.X, self.Minimized and 41 or WINDOW_SIZE.Y) })
		minBtn.Text = self.Minimized and "+" or "–"
	end

	minBtn.MouseButton1Click:Connect(function() self:ToggleMinimize() end)
	closeBtn.MouseButton1Click:Connect(function()
		self:Hide()
		Library:Notify({ Title = "menu hidden", Text = "press " .. TOGGLE_KEY.Name .. " to open", Duration = 3 })
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == TOGGLE_KEY then
			if self.Hidden then self:Show() else self:Hide() end
		end
	end)

	return self
end

---------------------------------------------------------------------
-- TABS
---------------------------------------------------------------------
function Window:CreateTab(cfg)
	cfg = cfg or {}
	local tab = setmetatable({ Window = self, Order = 0 }, Tab)
	local index = #self.Tabs + 1

	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = index,
		Parent = self.TabList,
	}, { corner(3) })

	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(2, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = btn,
	}, { accentGradient(90) })

	local num = create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(0, 18, 1, 0),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = ("%02d"):format(index),
		TextColor3 = THEME.Stroke,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	local label = create("TextLabel", {
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -34, 1, 0),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = string.upper(cfg.Name or ("TAB " .. index)),
		TextColor3 = THEME.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	local page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self.Content,
	}, {
		padding(12, 12, 12, 12),
		create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	onAccent(function(a) page.ScrollBarImageColor3 = a end)

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, cfg.Description and 32 or 20),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = page,
	})
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 17),
		BackgroundTransparency = 1,
		Font = THEME.FontBold,
		Text = string.upper(cfg.Name or ""),
		TextColor3 = THEME.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	if cfg.Description then
		create("TextLabel", {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Font = THEME.FontLight,
			Text = "// " .. cfg.Description,
			TextColor3 = THEME.SubText,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		})
	end

	tab.Button, tab.Page, tab.Indicator, tab.Label, tab.Num = btn, page, indicator, label, num

	function tab:Select()
		local w = self.Window
		if w.Current == self then return end
		if w.Current then
			local old = w.Current
			old.Page.Visible = false
			tween(old.Button, 0.15, { BackgroundTransparency = 1 })
			tween(old.Label, 0.15, { TextColor3 = THEME.SubText })
			tween(old.Num, 0.15, { TextColor3 = THEME.Stroke })
			tween(old.Indicator, 0.15, { Size = UDim2.fromOffset(2, 0) })
		end
		w.Current = self
		page.Visible = true
		page.Position = UDim2.fromOffset(6, 0)
		tween(page, 0.3, { Position = UDim2.fromOffset(0, 0) })
		tween(btn, 0.15, { BackgroundTransparency = 0 })
		tween(label, 0.15, { TextColor3 = THEME.Text })
		tween(num, 0.15, { TextColor3 = THEME.Accent })
		tween(indicator, 0.2, { Size = UDim2.fromOffset(2, 28) })
		w:Log("loaded tab: " .. string.lower(cfg.Name or ""))
	end

	onAccent(function(a)
		if self.Current == tab then num.TextColor3 = a end
	end)

	btn.MouseEnter:Connect(function()
		if self.Current ~= tab then tween(label, 0.12, { TextColor3 = THEME.Text }) end
	end)
	btn.MouseLeave:Connect(function()
		if self.Current ~= tab then tween(label, 0.12, { TextColor3 = THEME.SubText }) end
	end)
	btn.MouseButton1Click:Connect(function() tab:Select() end)

	table.insert(self.Tabs, tab)
	if index == 1 then tab:Select() end
	return tab
end

---------------------------------------------------------------------
-- ELEMENTS
---------------------------------------------------------------------
local ROW_H      = 30  -- single-line element height
local ROW_DESC_H = 38  -- element with description

function Tab:_next()
	self.Order += 1
	return self.Order
end

function Tab:_element(height)
	local f = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = THEME.Element,
		LayoutOrder = self:_next(),
		Parent = self.Page,
	}, { corner(3), stroke(THEME.Stroke, 1, 0.25) })
	hover(f, THEME.Element, THEME.ElementHover)
	return f
end

local function elementText(parent, name, desc, rightPad)
	rightPad = rightPad or 70
	local main = create("TextLabel", {
		Position = UDim2.fromOffset(10, desc and 6 or 0),
		Size = UDim2.new(1, -(10 + rightPad), desc and 0 or 1, desc and 14 or 0),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = name or "",
		TextColor3 = THEME.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
	if desc then
		create("TextLabel", {
			Position = UDim2.fromOffset(10, 21),
			Size = UDim2.new(1, -(10 + rightPad), 0, 12),
			BackgroundTransparency = 1,
			Font = THEME.FontLight,
			Text = desc,
			TextColor3 = THEME.SubText,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = parent,
		})
	end
	return main
end

function Tab:AddSection(name)
	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = self:_next(),
		Parent = self.Page,
	})
	local lbl = create("TextLabel", {
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(0, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "[ " .. string.upper(name or "") .. " ]",
		TextSize = 10,
		Parent = holder,
	})
	onAccent(function(a) lbl.TextColor3 = a end)
	local line = create("Frame", {
		Position = UDim2.new(0, 0, 0, 12),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = holder,
	})
	task.defer(function()
		line.Position = UDim2.new(0, lbl.AbsoluteSize.X + 6, 0, 12)
		line.Size = UDim2.new(1, -(lbl.AbsoluteSize.X + 6), 0, 1)
	end)
end

-- Toggle (checkbox; shows up in the arraylist when enabled)
function Tab:AddToggle(cfg)
	cfg = cfg or {}
	local state = cfg.Default == true
	local f = self:_element(cfg.Description and ROW_DESC_H or ROW_H)
	elementText(f, cfg.Name, cfg.Description, 56)

	local stateText = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, 0.5, 0),
		Size = UDim2.fromOffset(24, 12),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "OFF",
		TextColor3 = THEME.SubText,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = f,
	})

	local box = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = THEME.Background,
		Parent = f,
	}, { corner(3) })
	local boxStroke = stroke(THEME.Stroke)
	boxStroke.Parent = box
	local fill = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = box,
	}, { corner(2), accentGradient(45) })

	local hit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = f,
	})

	local function render(t)
		tween(fill, t, { Size = state and UDim2.fromOffset(8, 8) or UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		tween(boxStroke, t, { Color = state and THEME.Accent or THEME.Stroke })
		stateText.Text = state and "ON" or "OFF"
		stateText.TextColor3 = state and THEME.Accent or THEME.SubText
	end
	onAccent(function() render(0) end)

	local api = {}
	function api:Set(v, silent)
		state = v and true or false
		render(0.25)
		if not cfg.NoList then setModule(cfg.Name or "Module", state) end
		if not silent then safeCall(cfg.Callback, state) end
	end
	function api:Get() return state end

	hit.MouseButton1Click:Connect(function() api:Set(not state) end)
	if state then api:Set(true) end
	return api
end

-- Slider
function Tab:AddSlider(cfg)
	cfg = cfg or {}
	local min, max = cfg.Min or 0, cfg.Max or 100
	local step = cfg.Step or 1
	local suffix = cfg.Suffix or ""
	local value = math.clamp(cfg.Default or min, min, max)

	local f = self:_element(40)
	local nameLbl = elementText(f, cfg.Name, nil, 80)
	nameLbl.Size = UDim2.new(1, -90, 0, 24)

	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(70, 24),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = f,
	})
	onAccent(function(a) valueLabel.TextColor3 = a end)

	local track = create("Frame", {
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -20, 0, 3),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = f,
	})
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, { accentGradient(0) })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(3, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})

	local hit = create("TextButton", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		Parent = f,
	})

	local function fmt(v)
		if step < 1 then return ("%.1f%s"):format(v, suffix) end
		return ("%d%s"):format(v, suffix)
	end

	local api = {}
	function api:Set(v, silent, instant)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		local changed = v ~= value
		value = v
		local rel = (max == min) and 0 or (value - min) / (max - min)
		local t = instant and 0 or 0.1
		tween(fill, t, { Size = UDim2.fromScale(rel, 1) })
		tween(knob, t, { Position = UDim2.fromScale(rel, 0.5) })
		valueLabel.Text = fmt(value)
		if changed and not silent then safeCall(cfg.Callback, value) end
	end
	function api:Get() return value end

	local dragging = false
	local function fromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		api:Set(min + (max - min) * rel)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)

	value = value - 1e-9
	api:Set(cfg.Default or min, true, true)
	return api
end

-- Button
function Tab:AddButton(cfg)
	cfg = cfg or {}
	local f = self:_element(cfg.Description and ROW_DESC_H or ROW_H)
	elementText(f, cfg.Name, cfg.Description, 80)

	local exec = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.Background,
		Font = THEME.Font,
		Text = "EXECUTE",
		TextSize = 9,
		Parent = f,
	}, { corner(3), padding(0, 0, 6, 6) })
	local execStroke = stroke(THEME.Accent, 1, 0.4)
	execStroke.Parent = exec
	onAccent(function(a) exec.TextColor3 = a; execStroke.Color = a end)

	local flash = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Accent,
		BackgroundTransparency = 1,
		Parent = f,
	}, { corner(3) })
	onAccent(function(a) flash.BackgroundColor3 = a end)

	local hit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = f,
	})
	hit.MouseButton1Click:Connect(function()
		flash.BackgroundTransparency = 0.8
		tween(flash, 0.4, { BackgroundTransparency = 1 })
		exec.Text = "RUNNING..."
		task.delay(0.6, function() exec.Text = "EXECUTE" end)
		safeCall(cfg.Callback)
	end)
end

-- Dropdown
function Tab:AddDropdown(cfg)
	cfg = cfg or {}
	local options = cfg.Options or {}
	local selected = cfg.Default or options[1]
	local open = false

	local f = self:_element(ROW_H)
	f.ClipsDescendants = true
	local nameLbl = elementText(f, cfg.Name, nil, 150)
	nameLbl.Size = UDim2.new(1, -160, 0, ROW_H)

	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -26, 0, 0),
		Size = UDim2.fromOffset(130, ROW_H),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = tostring(selected or "-"),
		TextColor3 = THEME.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = f,
	})
	local arrow = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -15, 0, ROW_H / 2),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = ">",
		Rotation = 90,
		TextColor3 = THEME.SubText,
		TextSize = 11,
		Parent = f,
	})
	local header = create("TextButton", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		Text = "",
		Parent = f,
	})
	local list = create("Frame", {
		Position = UDim2.fromOffset(5, ROW_H + 2),
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = f,
	}, { create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local optionButtons = {}
	local api = {}

	local function refreshColors()
		for opt, b in pairs(optionButtons) do
			local isSel = opt == selected
			b.TextColor3 = isSel and THEME.Accent or THEME.SubText
			b.BackgroundTransparency = isSel and 0 or 1
			b.Text = (isSel and " > " or "   ") .. tostring(opt)
		end
	end
	onAccent(refreshColors)

	local function targetHeight()
		return open and (ROW_H + 4 + #options * 24 + 4) or ROW_H
	end

	function api:Set(opt, silent)
		selected = opt
		valueLabel.Text = tostring(opt)
		refreshColors()
		if not silent then safeCall(cfg.Callback, opt) end
	end
	function api:Get() return selected end
	function api:Toggle(state)
		if state == nil then open = not open else open = state end
		tween(f, 0.25, { Size = UDim2.new(1, 0, 0, targetHeight()) })
		tween(arrow, 0.25, { Rotation = open and 270 or 90 })
	end
	function api:Refresh(newOptions, keepSelected)
		for _, b in pairs(optionButtons) do b:Destroy() end
		optionButtons = {}
		options = newOptions or {}
		for i, opt in ipairs(options) do
			local b = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = THEME.Background,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = THEME.Font,
				Text = "   " .. tostring(opt),
				TextColor3 = THEME.SubText,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = i,
				Parent = list,
			}, { corner(3) })
			b.MouseEnter:Connect(function()
				if opt ~= selected then tween(b, 0.1, { TextColor3 = THEME.Text }) end
			end)
			b.MouseLeave:Connect(function()
				if opt ~= selected then tween(b, 0.1, { TextColor3 = THEME.SubText }) end
			end)
			b.MouseButton1Click:Connect(function()
				api:Set(opt)
				api:Toggle(false)
			end)
			optionButtons[opt] = b
		end
		if not keepSelected or not table.find(options, selected) then
			selected = options[1]
			valueLabel.Text = tostring(selected or "-")
		end
		refreshColors()
		if open then f.Size = UDim2.new(1, 0, 0, targetHeight()) end
	end

	header.MouseButton1Click:Connect(function() api:Toggle() end)
	api:Refresh(options, true)
	return api
end

-- Keybind
function Tab:AddKeybind(cfg)
	cfg = cfg or {}
	local key = cfg.Default or Enum.KeyCode.F
	local listening = false

	local f = self:_element(ROW_H)
	elementText(f, cfg.Name, nil, 90)

	local box = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.Background,
		AutoButtonColor = false,
		Font = THEME.Font,
		Text = "[" .. key.Name .. "]",
		TextColor3 = THEME.Text,
		TextSize = 10,
		Parent = f,
	}, { corner(3), padding(0, 0, 6, 6) })
	local boxStroke = stroke(THEME.Stroke)
	boxStroke.Parent = box

	box.MouseButton1Click:Connect(function()
		listening = true
		box.Text = "[...]"
		boxStroke.Color = THEME.Accent
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if listening and input.UserInputType == Enum.UserInputType.Keyboard then
			listening = false
			if input.KeyCode ~= Enum.KeyCode.Escape then key = input.KeyCode end
			box.Text = "[" .. key.Name .. "]"
			boxStroke.Color = THEME.Stroke
			safeCall(cfg.Changed, key)
			return
		end
		if not processed and input.KeyCode == key then safeCall(cfg.Callback) end
	end)
	return { Get = function() return key end }
end

-- Text input
function Tab:AddInput(cfg)
	cfg = cfg or {}
	local f = self:_element(ROW_H)
	elementText(f, cfg.Name, nil, 150)

	local tb = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(130, 18),
		BackgroundColor3 = THEME.Background,
		ClearTextOnFocus = false,
		Font = THEME.Font,
		PlaceholderText = cfg.Placeholder or "type here...",
		PlaceholderColor3 = THEME.SubText,
		Text = cfg.Default or "",
		TextColor3 = THEME.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
		Parent = f,
	}, { corner(3), padding(0, 0, 6, 6) })
	local s = stroke(THEME.Stroke)
	s.Parent = tb
	tb.Focused:Connect(function() tween(s, 0.12, { Color = THEME.Accent }) end)
	tb.FocusLost:Connect(function(enter)
		tween(s, 0.12, { Color = THEME.Stroke })
		safeCall(cfg.Callback, tb.Text, enter)
	end)
	return tb
end

-- Paragraph
function Tab:AddParagraph(cfg)
	cfg = cfg or {}
	local f = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Element,
		LayoutOrder = self:_next(),
		Parent = self.Page,
	}, {
		corner(3), stroke(THEME.Stroke, 1, 0.25), padding(8, 8, 10, 10),
		create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local t = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		RichText = true,
		Text = cfg.Title or "",
		TextColor3 = THEME.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = f,
	})
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = THEME.FontLight,
		RichText = true,
		Text = cfg.Text or "",
		TextColor3 = THEME.SubText,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = f,
	})
	return t
end

---------------------------------------------------------------------
-- FAKE INJECTOR SPLASH (console log)
---------------------------------------------------------------------
local function playIntro(onDone)
	local splash = create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 196),
		BackgroundColor3 = THEME.Background,
		GroupTransparency = 1,
		Parent = ScreenGui,
	}, { corner(4) })
	create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = splash,
	}, { corner(4), stroke(THEME.Stroke) })
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = splash,
	}, { shimmerGradient(0) })

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 11),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = THEME.FontBold,
		Text = BRAND,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		Parent = splash,
	}, { accentGradient(0) })
	create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(140, 12),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "injector v1.0.4",
		TextColor3 = THEME.SubText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = splash,
	})

	local console = create("Frame", {
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 0, 108),
		BackgroundColor3 = Color3.fromRGB(5, 4, 7),
		ClipsDescendants = true,
		Parent = splash,
	}, {
		corner(3), stroke(THEME.Stroke), padding(6, 6, 8, 8),
		create("UIListLayout", {
			Padding = UDim.new(0, 1),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})

	local status = create("TextLabel", {
		Position = UDim2.fromOffset(14, 156),
		Size = UDim2.new(1, -28, 0, 12),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "initializing...",
		TextColor3 = THEME.SubText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = splash,
	})
	local percent = create("TextLabel", {
		Position = UDim2.fromOffset(14, 156),
		Size = UDim2.new(1, -28, 0, 12),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		Text = "0%",
		TextColor3 = THEME.Text,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = splash,
	})
	local track = create("Frame", {
		Position = UDim2.fromOffset(14, 176),
		Size = UDim2.new(1, -28, 0, 3),
		BackgroundColor3 = THEME.Stroke,
		BorderSizePixel = 0,
		Parent = splash,
	})
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, { shimmerGradient(0) })

	local lineOrder = 0
	local function log(prefix, text, color)
		lineOrder += 1
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Font = THEME.Font,
			RichText = true,
			Text = ('<font color="#%s">%s</font> %s'):format(color:ToHex(), prefix, text),
			TextColor3 = THEME.Text,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = lineOrder,
			Parent = console,
		})
	end

	tween(splash, 0.3, { GroupTransparency = 0 })

	local function hex() return ("0x%X"):format(math.random(0x10000000, 0x7FFFFFFF)) end
	local steps = {
		{ "[*]", "waiting for RobloxPlayer...",                    THEME.SubText, 0.06 },
		{ "[+]", "process found  pid=" .. math.random(1000, 9999), THEME.Good,    0.14 },
		{ "[*]", "allocating memory at " .. hex(),                 THEME.SubText, 0.27 },
		{ "[+]", "anti-cheat hooks patched",                       THEME.Good,    0.41 },
		{ "[*]", "mapping tac.dll  (1.8 MB)",                      THEME.SubText, 0.55 },
		{ "[+]", "lua state captured " .. hex(),                   THEME.Good,    0.68 },
		{ "[*]", "loading modules: aim, esp, move, world",         THEME.SubText, 0.82 },
		{ "[+]", "license OK  (lifetime)",                         THEME.Good,    0.93 },
		{ "[!]", "injected successfully. have fun :)",             THEME.Accent,  1.00 },
	}

	task.spawn(function()
		task.wait(0.35)
		for _, s in ipairs(steps) do
			log(s[1], s[2], s[3])
			status.Text = s[2]
			tween(fill, 0.3, { Size = UDim2.fromScale(s[4], 1) })
			percent.Text = math.floor(s[4] * 100) .. "%"
			task.wait(math.random(22, 45) / 100)
		end
		task.wait(0.6)
		tween(splash, 0.3, { GroupTransparency = 1 })
		task.wait(0.31)
		splash:Destroy()
		onDone()
	end)
end

---------------------------------------------------------------------
-- ESP (REAL, client-side — purely visual)
-- Мобы ищутся в папках ниже (как workspace.Enemies в Blox Fruits).
-- Если ни одной папки нет — ищутся все Humanoid в workspace.
---------------------------------------------------------------------
local ENEMY_FOLDERS = { "Enemies", "NPCs", "Mobs" }

local ESP = {
	Box = false, Name = false, Tracers = false, Health = false, Chams = false,
	ShowPlayers = true, ShowNPCs = true, TeamCheck = false,
	MaxDistance = 800,
	BoxStyle = "Corner",
	NPCColor  = Color3.fromRGB(255, 165, 60),
	TeamColor = Color3.fromRGB(70, 240, 130),
}

local camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
end)

local espGui = create("ScreenGui", {
	Name = "TaC_ESP",
	ResetOnSpawn = false,
	IgnoreGuiInset = true, -- so viewport coords match GUI coords
	DisplayOrder = 10,
	Parent = playerGui,
})

local espEntries = {}

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model.PrimaryPart
end

local function collectNPCModels()
	local models, seen, foundFolder = {}, {}, false
	local function add(h)
		local m = h.Parent
		if m and m:IsA("Model") and not seen[m] and not Players:GetPlayerFromCharacter(m) then
			seen[m] = true
			table.insert(models, m)
		end
	end
	for _, name in ipairs(ENEMY_FOLDERS) do
		local f = workspace:FindFirstChild(name)
		if f then
			foundFolder = true
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("Humanoid") then add(d) end
			end
		end
	end
	if not foundFolder then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Humanoid") then add(d) end
		end
	end
	return models
end

local function espAny()
	return ESP.Box or ESP.Name or ESP.Tracers or ESP.Health or ESP.Chams
end

local function destroyEntry(e)
	for _, k in ipairs({ "Box", "Label", "HpBack", "Tracer", "Highlight" }) do
		if e[k] then e[k]:Destroy() end
	end
	espEntries[e.Model] = nil
end

local function newEntry(model, plr)
	local e = { Model = model, IsPlayer = plr ~= nil, Player = plr }

	e.Box = create("Frame", { BackgroundTransparency = 1, Visible = false, Parent = espGui })
	e.BoxStroke = create("UIStroke", { Thickness = 1, Parent = e.Box })
	e.Corners = {}
	local L = 0.28
	local specs = {
		{ UDim2.new(0, 0, 0, 0),      UDim2.new(L, 0, 0, 1) },
		{ UDim2.new(0, 0, 0, 0),      UDim2.new(0, 1, L, 0) },
		{ UDim2.new(1 - L, 0, 0, 0),  UDim2.new(L, 0, 0, 1) },
		{ UDim2.new(1, -1, 0, 0),     UDim2.new(0, 1, L, 0) },
		{ UDim2.new(0, 0, 1, -1),     UDim2.new(L, 0, 0, 1) },
		{ UDim2.new(0, 0, 1 - L, 0),  UDim2.new(0, 1, L, 0) },
		{ UDim2.new(1 - L, 0, 1, -1), UDim2.new(L, 0, 0, 1) },
		{ UDim2.new(1, -1, 1 - L, 0), UDim2.new(0, 1, L, 0) },
	}
	for _, s in ipairs(specs) do
		table.insert(e.Corners, create("Frame", { Position = s[1], Size = s[2], BorderSizePixel = 0, Parent = e.Box }))
	end

	e.Label = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(220, 14),
		BackgroundTransparency = 1,
		Font = THEME.Font,
		RichText = true,
		TextSize = 11,
		TextStrokeTransparency = 0.4,
		Visible = false,
		Parent = espGui,
	})
	e.HpBack = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		Parent = espGui,
	})
	e.HpFill = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = e.HpBack,
	})
	e.Tracer = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Visible = false,
		Parent = espGui,
	})

	-- vertical size/offset of the model relative to its root (works for big bosses too)
	local root = getRoot(model)
	local ok, cf, size = pcall(model.GetBoundingBox, model)
	if model:GetAttribute("TaC_Expanded") then ok = false end -- hitbox is enlarged, bbox would lie
	if ok and root then
		e.Height = math.clamp(size.Y, 3, 60)
		e.OffsetY = cf.Position.Y - root.Position.Y
	else
		e.Height, e.OffsetY = 5.5, -0.5
	end

	espEntries[model] = e
	return e
end

local function clearESP()
	for _, e in pairs(espEntries) do destroyEntry(e) end
end

local function refreshESPTargets()
	if not espAny() then clearESP() return end
	local wanted = {}
	if ESP.ShowPlayers then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p.Character then wanted[p.Character] = p end
		end
	end
	if ESP.ShowNPCs then
		for _, m in ipairs(collectNPCModels()) do wanted[m] = false end
	end
	for m, e in pairs(espEntries) do
		if wanted[m] == nil or not m.Parent then destroyEntry(e) end
	end
	for m, p in pairs(wanted) do
		if not espEntries[m] then newEntry(m, p or nil) end
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		refreshESPTargets()
	end
end)

local function hideParts(e)
	e.Box.Visible = false
	e.Label.Visible = false
	e.HpBack.Visible = false
	e.Tracer.Visible = false
end

RunService.RenderStepped:Connect(function()
	if not espAny() or not camera then return end
	local vp = camera.ViewportSize
	local camPos = camera.CFrame.Position
	local chamList = {}

	for model, e in pairs(espEntries) do
		e._cham = false
		local root = model.Parent and getRoot(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		local shown = false

		if root and hum and hum.Health > 0 then
			local dist = (root.Position - camPos).Magnitude
			if dist <= ESP.MaxDistance then
				local color
				if e.IsPlayer then
					local sameTeam = ESP.TeamCheck and e.Player and e.Player.Team ~= nil and e.Player.Team == player.Team
					color = sameTeam and ESP.TeamColor or THEME.Accent
				else
					color = ESP.NPCColor
				end

				local center = root.Position + Vector3.new(0, e.OffsetY, 0)
				local topV = camera:WorldToViewportPoint(center + Vector3.new(0, e.Height / 2, 0))
				local botV = camera:WorldToViewportPoint(center - Vector3.new(0, e.Height / 2, 0))

				if topV.Z > 0 and botV.Z > 0 then
					shown = true
					local h = math.max(botV.Y - topV.Y, 4)
					local w = h * 0.55
					local cx = (topV.X + botV.X) / 2
					local x, y = cx - w / 2, topV.Y

					if ESP.Box then
						local cornerStyle = ESP.BoxStyle == "Corner"
						e.Box.Visible = true
						e.Box.Position = UDim2.fromOffset(x, y)
						e.Box.Size = UDim2.fromOffset(w, h)
						e.BoxStroke.Enabled = not cornerStyle
						e.BoxStroke.Color = color
						for _, c in ipairs(e.Corners) do
							c.Visible = cornerStyle
							c.BackgroundColor3 = color
						end
					else
						e.Box.Visible = false
					end

					if ESP.Name then
						local name = (e.IsPlayer and e.Player) and e.Player.DisplayName or model.Name
						e.Label.Visible = true
						e.Label.Position = UDim2.fromOffset(cx, y - 2)
						e.Label.TextColor3 = color
						e.Label.Text = ('%s <font color="#AAAAAA">[%dm]</font>'):format(name, math.floor(dist))
					else
						e.Label.Visible = false
					end

					if ESP.Health then
						local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						e.HpBack.Visible = true
						e.HpBack.Position = UDim2.fromOffset(x - 3, y)
						e.HpBack.Size = UDim2.fromOffset(2, h)
						e.HpFill.Size = UDim2.fromScale(1, pct)
						e.HpFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(70, 240, 130), pct)
					else
						e.HpBack.Visible = false
					end

					if ESP.Tracers then
						local from = Vector2.new(vp.X / 2, vp.Y - 2)
						local to = Vector2.new(cx, botV.Y)
						local d = to - from
						e.Tracer.Visible = true
						e.Tracer.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
						e.Tracer.Size = UDim2.fromOffset(d.Magnitude, 1)
						e.Tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
						e.Tracer.BackgroundColor3 = color
					else
						e.Tracer.Visible = false
					end
				end

				if ESP.Chams then table.insert(chamList, { e, dist, color }) end
			end
		end

		if not shown then hideParts(e) end
	end

	-- Chams: only the nearest 30 (Roblox renders max 31 Highlights at once)
	table.sort(chamList, function(a, b) return a[2] < b[2] end)
	for i, c in ipairs(chamList) do
		if i > 30 then break end
		local e = c[1]
		e._cham = true
		if not e.Highlight or not e.Highlight.Parent then
			e.Highlight = create("Highlight", {
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				FillTransparency = 0.6,
				OutlineTransparency = 0,
				Adornee = e.Model,
				Parent = e.Model,
			})
		end
		e.Highlight.Enabled = true
		e.Highlight.FillColor = c[3]
		e.Highlight.OutlineColor = c[3]
	end
	for _, e in pairs(espEntries) do
		if e.Highlight and not e._cham then e.Highlight.Enabled = false end
	end
end)

---------------------------------------------------------------------
-- KILL AURA (REAL, client-only — spams your weapon's normal M1)
---------------------------------------------------------------------
local Aura = {
	On = false,
	Range = 18,
	ShowRange = true,
	Weapon = "Melee",     -- "Melee" | "Sword" | "Fruit" | "Any"
	CPS = 10,             -- M1 clicks per second
	HitboxSize = 10,      -- expanded enemy hitbox (studs), 0 = off
	ShowHitbox = false,
	NoAnim = true,        -- stop attack animations
	FaceTarget = true,    -- turn to the nearest enemy before each hit
	TPToTarget = false,   -- teleport behind the target
	TargetPlayers = false,
}

-- How weapon types are detected (Blox Fruits style: Tool.ToolTip = "Melee" / "Sword" / "Blox Fruit").
-- Also checks attributes WeaponType / Type on the Tool, then the tool name.
local WEAPON_TYPES = {
	Melee = { "melee", "combat", "fighting" },
	Sword = { "sword" },
	Fruit = { "blox fruit", "fruit" },
}

-- purple flash on the enemy whenever it loses HP while the aura is on
local function flashHit(model)
	if not model or not model.Parent then return end
	local h = create("Highlight", {
		DepthMode = Enum.HighlightDepthMode.Occluded,
		FillColor = THEME.Accent,
		FillTransparency = 0.35,
		OutlineTransparency = 1,
		Adornee = model,
		Parent = model,
	})
	tween(h, 0.3, { FillTransparency = 1 })
	Debris:AddItem(h, 0.35)
end

local watchedHumanoids = setmetatable({}, { __mode = "k" })
local function watchHealth(hum, model)
	if watchedHumanoids[hum] then return end
	local last = hum.Health
	watchedHumanoids[hum] = hum.HealthChanged:Connect(function(hp)
		if hp < last and Aura.On then flashHit(model) end
		last = hp
	end)
end

---------------------------------------------------------------- weapon helpers
local function toolKind(tool)
	local t = tool:GetAttribute("WeaponType") or tool:GetAttribute("Type") or tool.ToolTip
	return string.lower(tostring(t or ""))
end

local function toolMatches(tool, kind)
	if kind == "Any" then return true end
	local keys = WEAPON_TYPES[kind] or {}
	local t, n = toolKind(tool), string.lower(tool.Name)
	for _, k in ipairs(keys) do
		if string.find(t, k, 1, true) then return true end
	end
	for _, k in ipairs(keys) do
		if string.find(n, k, 1, true) then return true end
	end
	return false
end

local function findWeapon()
	local char = player.Character
	if not char then return nil end
	local equipped = char:FindFirstChildOfClass("Tool")
	if equipped and toolMatches(equipped, Aura.Weapon) then return equipped end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and toolMatches(t, Aura.Weapon) then return t end
		end
	end
	return nil
end

local function auraTargets()
	local list = collectNPCModels()
	if Aura.TargetPlayers then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p.Character then table.insert(list, p.Character) end
		end
	end
	return list
end

local function isWeaponMode()
	return Aura.On
end

---------------------------------------------------------------- M1 spam loop
local auraTargetsCache, auraScanTime, warnedNoWeapon = {}, 0, false
task.spawn(function()
	while true do
		task.wait(1 / math.max(Aura.CPS, 1))
		if isWeaponMode() then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				if os.clock() - auraScanTime > 1 then
					auraTargetsCache = auraTargets()
					auraScanTime = os.clock()
				end

				-- nearest alive target in range
				local best, bestRoot, bestD = nil, nil, math.huge
				for _, m in ipairs(auraTargetsCache) do
					local h = m.Parent and m:FindFirstChildOfClass("Humanoid")
					local r = h and getRoot(m)
					if r and h.Health > 0 and m ~= char then
						local d = (r.Position - root.Position).Magnitude
						if d <= Aura.Range and d < bestD then
							best, bestRoot, bestD = m, r, d
						end
					end
				end

				if best then
					local tool = findWeapon()
					if tool then
						warnedNoWeapon = false
						if tool.Parent ~= char then hum:EquipTool(tool) end

						local tp = bestRoot.Position
						if Aura.TPToTarget then
							local behind = bestRoot.CFrame * CFrame.new(0, 0, 3)
							root.CFrame = CFrame.lookAt(behind.Position, Vector3.new(tp.X, behind.Position.Y, tp.Z))
						elseif Aura.FaceTarget then
							root.CFrame = CFrame.lookAt(root.Position, Vector3.new(tp.X, root.Position.Y, tp.Z))
						end

						watchHealth(best:FindFirstChildOfClass("Humanoid"), best)
						tool:Activate() -- fires Tool.Activated → your normal M1
					elseif not warnedNoWeapon then
						warnedNoWeapon = true
						Library:Notify({ Title = "Kill Aura", Text = "no " .. Aura.Weapon .. " weapon in backpack", Duration = 3 })
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------- hitbox expander (local)
-- Enlarges enemy HumanoidRootParts on YOUR client only. Works if your
-- hit detection runs on the client (or the server trusts the client's hits).
local resized = {} -- [part] = original size
local function restoreHitbox(part)
	local orig = resized[part]
	if orig and part.Parent then
		part.Size = orig.Size
		part.Transparency = orig.Transparency
		part.CanCollide = orig.CanCollide
		local model = part.Parent
		if model then model:SetAttribute("TaC_Expanded", nil) end
	end
	resized[part] = nil
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local active = isWeaponMode() and Aura.HitboxSize > 0
		local keep = {}
		if active then
			local char = player.Character
			local myRoot = char and char:FindFirstChild("HumanoidRootPart")
			if myRoot then
				for _, m in ipairs(auraTargetsCache) do
					local r = m.Parent and m:FindFirstChild("HumanoidRootPart")
					if r and m ~= char and (r.Position - myRoot.Position).Magnitude <= Aura.Range + 60 then
						if not resized[r] then
							resized[r] = { Size = r.Size, Transparency = r.Transparency, CanCollide = r.CanCollide }
							m:SetAttribute("TaC_Expanded", true)
						end
						local s = Aura.HitboxSize
						r.Size = Vector3.new(s, s, s)
						r.Transparency = Aura.ShowHitbox and 0.75 or 1
						r.CanCollide = false
						keep[r] = true
					end
				end
			end
		end
		for part in pairs(resized) do
			if not keep[part] then restoreHitbox(part) end
		end
	end
end)

---------------------------------------------------------------- no attack animations
-- Stops Action-priority animations (attacks) while the aura is on.
-- Walk/idle (Core/Movement) keep playing.
-- NOTE: if your combat deals damage on animation markers
-- (GetMarkerReachedSignal), turn "No Animations" off.
local function hookAnimator(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local animator = hum and hum:WaitForChild("Animator", 10)
	if not animator then return end
	animator.AnimationPlayed:Connect(function(track)
		if isWeaponMode() and Aura.NoAnim then
			local p = track.Priority
			if p ~= Enum.AnimationPriority.Core and p.Value >= Enum.AnimationPriority.Action.Value then
				track:Stop(0)
			end
		end
	end)
end
if player.Character then task.spawn(hookAnimator, player.Character) end
player.CharacterAdded:Connect(hookAnimator)

-- range circle under the player
local ring = create("Part", {
	Name = "TaC_AuraRange",
	Shape = Enum.PartType.Cylinder,
	Anchored = true,
	CanCollide = false,
	CanTouch = false,
	CanQuery = false,
	CastShadow = false,
	Material = Enum.Material.ForceField,
	Transparency = 0.2,
})
RunService.RenderStepped:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if Aura.On and Aura.ShowRange and root then
		ring.Size = Vector3.new(0.2, Aura.Range * 2, Aura.Range * 2)
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = THEME.Accent
		if ring.Parent ~= workspace then ring.Parent = workspace end
	elseif ring.Parent then
		ring.Parent = nil
	end
end)

---------------------------------------------------------------------
-- BUILD THE MENU
-- Every feature is fake: callbacks only show a notification.
-- Put your own logic where it says TODO (e.g. fire a RemoteEvent
-- that "catches" the player using cheats ;) ).
---------------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = BRAND,
	Subtitle = "build 1.0.4 // private",
})

local function fake(name)
	return function(state)
		if typeof(state) == "boolean" then
			Library:Notify({ Title = name, Text = state and "module enabled" or "module disabled", Duration = 2.2 })
			Window:Log(string.lower(name) .. (state and " -> on" or " -> off"))
		end
		-- TODO: your logic here
	end
end

local function fakeAction(name, text)
	return function()
		Library:Notify({ Title = name, Text = text, Duration = 2.5 })
		Window:Log(string.lower(name) .. " executed")
		-- TODO: your logic here
	end
end

-- HOME
local Home = Window:CreateTab({ Name = "Home", Description = "dashboard" })
Home:AddParagraph({
	Title = '<font color="#46F082">●</font> STATUS: UNDETECTED',
	Text = "All modules loaded. Last update: today.\nPress RightShift to hide the menu.",
})
Home:AddSection("Quick")
Home:AddToggle({ Name = "God Mode", Description = "you can't die", Callback = fake("God Mode") })
Home:AddToggle({ Name = "Anti-AFK", Callback = fake("Anti-AFK") })
Home:AddToggle({ Name = "Anti-Kick", Description = "blocks kick packets", Callback = fake("Anti-Kick") })
Home:AddButton({ Name = "Re-inject", Description = "reload all modules", Callback = fakeAction("Re-inject", "modules reloaded") })

-- COMBAT
local Combat = Window:CreateTab({ Name = "Combat", Description = "aimbot & rage" })
Combat:AddSection("Aimbot")
Combat:AddToggle({ Name = "Aimbot", Description = "locks onto closest target", Callback = fake("Aimbot") })
Combat:AddToggle({ Name = "Silent Aim", Description = "bullets redirect to target", Callback = fake("Silent Aim") })
Combat:AddSlider({ Name = "FOV", Min = 10, Max = 360, Default = 120, Suffix = "°" })
Combat:AddSlider({ Name = "Smoothness", Min = 0, Max = 1, Default = 0.4, Step = 0.1 })
Combat:AddDropdown({ Name = "Target Part", Options = { "Head", "Torso", "Closest" }, Default = "Head" })
Combat:AddKeybind({ Name = "Aim Key", Default = Enum.KeyCode.E })
Combat:AddSection("Kill Aura")
Combat:AddToggle({ Name = "Kill Aura", Description = "auto M1 with your weapon", Callback = function(s)
	fake("Kill Aura")(s)
	Aura.On = s
end })
Combat:AddDropdown({ Name = "Weapon", Options = { "Melee", "Sword", "Fruit", "Any" }, Default = "Melee",
	Callback = function(o) Aura.Weapon = o end })
Combat:AddSlider({ Name = "Aura Range", Min = 5, Max = 50, Default = 18, Suffix = " st", Callback = function(v)
	Aura.Range = v
end })
Combat:AddSlider({ Name = "Attack Speed", Min = 1, Max = 20, Default = 10, Suffix = " cps",
	Callback = function(v) Aura.CPS = v end })
Combat:AddSlider({ Name = "Hitbox Size", Min = 0, Max = 30, Default = 10, Suffix = " st", Callback = function(v)
	Aura.HitboxSize = v
end })
Combat:AddToggle({ Name = "No Animations", Default = true, NoList = true, Callback = function(s) Aura.NoAnim = s end })
Combat:AddToggle({ Name = "Face Target", Default = true, NoList = true, Callback = function(s) Aura.FaceTarget = s end })
Combat:AddToggle({ Name = "TP to Target", Description = "teleport behind the enemy", Callback = function(s)
	fake("TP to Target")(s)
	Aura.TPToTarget = s
end })
Combat:AddToggle({ Name = "Target Players", Description = "PvP", NoList = true, Callback = function(s)
	Aura.TargetPlayers = s
	auraScanTime = 0
end })
Combat:AddToggle({ Name = "Show Range", Default = true, NoList = true, Callback = function(s) Aura.ShowRange = s end })
Combat:AddToggle({ Name = "Show Hitbox", NoList = true, Callback = function(s) Aura.ShowHitbox = s end })
Combat:AddSection("Rage")
Combat:AddToggle({ Name = "Triggerbot", Callback = fake("Triggerbot") })
Combat:AddToggle({ Name = "No Recoil", Callback = fake("No Recoil") })
Combat:AddToggle({ Name = "Rapid Fire", Callback = fake("Rapid Fire") })
Combat:AddToggle({ Name = "Spinbot", Callback = fake("Spinbot") })

-- VISUALS
local Visuals = Window:CreateTab({ Name = "Visuals", Description = "esp & render" })
Visuals:AddSection("ESP")
local function espToggle(name, key)
	return function(s)
		fake(name)(s)
		ESP[key] = s
		refreshESPTargets()
	end
end
Visuals:AddToggle({ Name = "Box ESP", Callback = espToggle("Box ESP", "Box") })
Visuals:AddToggle({ Name = "Name ESP", Callback = espToggle("Name ESP", "Name") })
Visuals:AddToggle({ Name = "Tracers", Callback = espToggle("Tracers", "Tracers") })
Visuals:AddToggle({ Name = "Health Bars", Callback = espToggle("Health Bars", "Health") })
Visuals:AddToggle({ Name = "Chams", Description = "see targets through walls", Callback = espToggle("Chams", "Chams") })
Visuals:AddSlider({ Name = "Max Distance", Min = 50, Max = 2000, Default = 800, Step = 50, Suffix = " st",
	Callback = function(v) ESP.MaxDistance = v end })
Visuals:AddDropdown({ Name = "Box Style", Options = { "Corner", "2D" }, Default = "Corner",
	Callback = function(o) ESP.BoxStyle = o end })
Visuals:AddSection("ESP Filter")
Visuals:AddToggle({ Name = "Players", Default = true, NoList = true, Callback = function(s)
	ESP.ShowPlayers = s
	refreshESPTargets()
end })
Visuals:AddToggle({ Name = "NPCs / Mobs", Default = true, NoList = true, Callback = function(s)
	ESP.ShowNPCs = s
	refreshESPTargets()
end })
Visuals:AddToggle({ Name = "Team Check", Description = "teammates in green", NoList = true,
	Callback = function(s) ESP.TeamCheck = s end })
Visuals:AddSection("World")
Visuals:AddToggle({ Name = "Fullbright", Callback = fake("Fullbright") })
Visuals:AddToggle({ Name = "No Fog", Callback = fake("No Fog") })
Visuals:AddToggle({ Name = "X-Ray", Callback = fake("X-Ray") })

-- MOVEMENT
local Movement = Window:CreateTab({ Name = "Movement", Description = "speed, fly, noclip" })
Movement:AddSection("Character")
Movement:AddSlider({ Name = "WalkSpeed", Min = 16, Max = 250, Default = 16 })
Movement:AddSlider({ Name = "JumpPower", Min = 50, Max = 350, Default = 50 })
Movement:AddToggle({ Name = "Fly", Description = "WASD + Space / Shift", Callback = fake("Fly") })
Movement:AddSlider({ Name = "Fly Speed", Min = 10, Max = 300, Default = 80 })
Movement:AddToggle({ Name = "Noclip", Callback = fake("Noclip") })
Movement:AddToggle({ Name = "Infinite Jump", Callback = fake("Infinite Jump") })
Movement:AddToggle({ Name = "Bhop", Callback = fake("Bhop") })
Movement:AddKeybind({ Name = "Fly Key", Default = Enum.KeyCode.F })

Movement:AddSection("Teleport")
local function playerNames()
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then table.insert(names, p.Name) end
	end
	if #names == 0 then names = { "no players" } end
	return names
end
local tpDropdown = Movement:AddDropdown({ Name = "Target", Options = playerNames() })
Players.PlayerAdded:Connect(function() tpDropdown:Refresh(playerNames(), true) end)
Players.PlayerRemoving:Connect(function() task.wait(); tpDropdown:Refresh(playerNames(), true) end)
Movement:AddButton({
	Name = "Teleport to player",
	Callback = function()
		fakeAction("Teleport", "teleported to " .. tostring(tpDropdown:Get()))()
	end,
})
Movement:AddToggle({ Name = "Loop TP", Callback = fake("Loop TP") })

-- EXPLOITS
local Exploits = Window:CreateTab({ Name = "Exploits", Description = "server-side // use at own risk" })
Exploits:AddParagraph({
	Title = '<font color="#FF5070">[!]</font> WARNING',
	Text = "Server-side modules. High ban risk. You have been warned.",
})
Exploits:AddSection("Economy")
Exploits:AddInput({ Name = "Give Money", Placeholder = "amount", Callback = function(text, enter)
	if enter and text ~= "" then
		fakeAction("Money", "added $" .. text .. " to balance")()
	end
end })
Exploits:AddToggle({ Name = "Auto Farm", Callback = fake("Auto Farm") })
Exploits:AddToggle({ Name = "Auto Collect", Callback = fake("Auto Collect") })
Exploits:AddButton({ Name = "Dupe Items", Description = "duplicates your inventory", Callback = fakeAction("Dupe", "inventory duplicated x2") })
Exploits:AddSection("Server")
Exploits:AddButton({ Name = "Kill All", Callback = fakeAction("Kill All", "killed all players") })
Exploits:AddButton({ Name = "Fling All", Callback = fakeAction("Fling All", "flinging everyone...") })
Exploits:AddButton({ Name = "Btools", Description = "delete / move any part", Callback = fakeAction("Btools", "building tools given") })
Exploits:AddButton({ Name = "Admin Commands", Description = "unlock ;cmds", Callback = fakeAction("Admin", "admin granted. type ;cmds") })
Exploits:AddButton({ Name = "Crash Server", Callback = fakeAction("Crash", "sending packets...") })

-- MISC
local Misc = Window:CreateTab({ Name = "Misc", Description = "utilities" })
Misc:AddSection("Server")
Misc:AddButton({ Name = "Rejoin", Callback = fakeAction("Rejoin", "rejoining...") })
Misc:AddButton({ Name = "Server Hop", Callback = fakeAction("Server Hop", "searching for a new server...") })
Misc:AddSection("Chat")
Misc:AddToggle({ Name = "Chat Spammer", Callback = fake("Chat Spammer") })
Misc:AddInput({ Name = "Spam Message", Placeholder = "message" })
Misc:AddToggle({ Name = "Chat Bypass", Callback = fake("Chat Bypass") })

-- SETTINGS
local Settings = Window:CreateTab({ Name = "Settings", Description = "menu config" })
Settings:AddSection("Theme")
local themes = {
	Purple = { Color3.fromRGB(145, 85, 255), Color3.fromRGB(205, 120, 255) },
	Blood  = { Color3.fromRGB(255, 45, 85),  Color3.fromRGB(255, 120, 150) },
	Toxic  = { Color3.fromRGB(60, 240, 120), Color3.fromRGB(150, 255, 190) },
	Ice    = { Color3.fromRGB(0, 180, 255),  Color3.fromRGB(130, 220, 255) },
	Gold   = { Color3.fromRGB(255, 180, 40), Color3.fromRGB(255, 220, 130) },
}
Settings:AddDropdown({
	Name = "Accent",
	Options = { "Purple", "Blood", "Toxic", "Ice", "Gold" },
	Default = "Purple",
	Callback = function(name)
		local t = themes[name]
		Library:SetAccent(t[1], t[2])
		Window:Log("theme -> " .. string.lower(name))
	end,
})
local showWatermark = true
Settings:AddToggle({ Name = "Watermark", Default = true, NoList = true, Callback = function(s)
	showWatermark = s
	watermark.Visible = s
end })
Settings:AddToggle({ Name = "Arraylist", Default = true, NoList = true, Callback = function(s) arraylist.Visible = s end })
Settings:AddParagraph({
	Title = "About",
	Text = "TaC · build 1.0.4\nmenu key: RightShift",
})

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------
watermark.Visible = false -- shown after the intro

playIntro(function()
	watermark.Visible = showWatermark
	Window:Show()
	Library:Notify({ Title = "loaded", Text = "welcome back, " .. player.Name, Duration = 4 })
end)
