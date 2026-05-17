-- OKShift for Aseprite

-- OKLab L is perceptual lightness, so rotating hue in OKLCh keeps perceptual brightness.
-- way more swag than HSV/HSL/YIQ.

-- color math

local function srgb_to_linear(c)
	if c<=0.04045 then return c/12.92 end
	return ((c+0.055)/1.055)^2.4
end

local function linear_to_srgb(c)
	if c<=0.0031308 then return c*12.92 end
	return 1.055*(c^(1/2.4))-0.055
end

-- stands for cube root
local function cbrt(x)
	-- lua's ^ doesn't like negative bases with fractional exponents, gives NaNs for some reason
	if x<0 then return -((-x)^(1/3)) end
	return x^(1/3)
end

local function rgb_to_oklab(r,g,b)
	r = srgb_to_linear(r/255)
	g = srgb_to_linear(g/255)
	b = srgb_to_linear(b/255)

	local l = 0.4122214708*r+0.5363325363*g+0.0514459929*b
	local m = 0.2119034982*r+0.6806995451*g+0.1073969566*b
	local s = 0.0883024619*r+0.2817188376*g+0.6299787005*b

	local l_ = cbrt(l)
	local m_ = cbrt(m)
	local s_ = cbrt(s)

	local L = 0.2104542553*l_+0.7936177850*m_-0.0040720468*s_
	local a = 1.9779984951*l_-2.4285922050*m_+0.4505937099*s_
	local bb = 0.0259040371*l_+0.7827717662*m_-0.8086757660*s_
	return L,a,bb
end

local function oklab_to_rgb(L,a,b)
	local l_ = L+0.3963377774*a+0.2158037573*b
	local m_ = L-0.1055613458*a-0.0638541728*b
	local s_ = L-0.0894841775*a-1.2914855480*b

	local l = l_*l_*l_
	local m = m_*m_*m_
	local s = s_*s_*s_

	local r = 4.0767416621*l-3.3077115913*m+0.2309699292*s
	local g = -1.2684380046*l+2.6097574011*m-0.3413193965*s
	local bl = -0.0041960863*l-0.7034186147*m+1.7076147010*s

	r = linear_to_srgb(r)
	g = linear_to_srgb(g)
	bl = linear_to_srgb(bl)

	-- gamut clip
	r = math.max(0,math.min(1,r))
	g = math.max(0,math.min(1,g))
	bl = math.max(0,math.min(1,bl))

	return math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(bl*255+0.5)
end
-- plugin entry

function init(plugin)
	plugin:newCommand{
		id="OklabHueShift",
		title="OKLab Hue Shift",
		group="edit_fx",
		onclick=function()
			show_dialog(plugin)
		end,
		onenabled=function()
			return app.activeSprite~=nil
		end
	}
end

function exit(plugin)
end