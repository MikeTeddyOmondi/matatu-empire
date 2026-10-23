--!strict
-- Tiny helpers for building UI in code, plus the shared visual style.

local UI = {}

UI.Colors = {
	panel = Color3.fromRGB(18, 18, 22),
	panelLight = Color3.fromRGB(34, 34, 40),
	accent = Color3.fromRGB(255, 196, 0), -- matatu yellow
	pink = Color3.fromRGB(255, 64, 129),
	cyan = Color3.fromRGB(0, 229, 255),
	green = Color3.fromRGB(118, 255, 3),
	text = Color3.fromRGB(245, 245, 245),
	muted = Color3.fromRGB(170, 170, 180),
	danger = Color3.fromRGB(255, 82, 82),
}

UI.Fonts = {
	heavy = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	body = Enum.Font.GothamMedium,
}

-- create("Frame", { Size = ..., Parent = ... }, { child1, child2 })
function UI.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UI.corner(radius: number?): Instance
	return UI.create("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UI.padding(px: number): Instance
	return UI.create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function UI.stroke(color: Color3, thickness: number?): Instance
	return UI.create("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = UI.Colors.text,
		Font = UI.Fonts.bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UI.create("TextLabel", defaults)
end

function UI.button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = UI.Colors.accent,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Font = UI.Fonts.heavy,
		TextSize = 18,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local button = UI.create("TextButton", defaults, { UI.corner(10) })
	return button
end

function UI.formatBob(amount: number): string
	local s = tostring(math.floor(amount))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return UI
