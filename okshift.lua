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

local function shift_color(r,g,b,hueDeg,chromaMult,lightShift)
	local L,a,bb = rgb_to_oklab(r,g,b)

	-- to OKLCh polar form
	local C = math.sqrt(a*a+bb*bb)
	local h = math.atan(bb,a)

	h = h+math.rad(hueDeg)
	C = C*chromaMult
	L = L+lightShift

	a = C*math.cos(h)
	bb = C*math.sin(h)

	return oklab_to_rgb(L,a,bb)
end

-- main

local function process_rgb_image(image,celPos,sprite,useSel,hue,chroma,light)
	local sel = sprite.selection
	local pc = app.pixelColor

	for it in image:pixels() do
		local px = it()
		local a = pc.rgbaA(px)
		if a>0 then
			local inSel = true
			if useSel then
				inSel = sel:contains(it.x+celPos.x,it.y+celPos.y)
			end
			if inSel then
				local r = pc.rgbaR(px)
				local g = pc.rgbaG(px)
				local b = pc.rgbaB(px)
				local nr,ng,nb = shift_color(r,g,b,hue,chroma,light)
				it(pc.rgba(nr,ng,nb,a))
			end
		end
	end
end

-- returns true if any sprite state was actually written (used to gate undo bookkeeping)
local function apply_impl(sprite,hue,chroma,light,selOnly,allCels)
	local wrote = false

	if sprite.colorMode==ColorMode.INDEXED then
		local transparentIdx = sprite.transparentColor
		for _,palette in ipairs(sprite.palettes) do
			for i=0,#palette-1 do
				if i~=transparentIdx then
					local c = palette:getColor(i)
					if c.alpha>0 then
						local nr,ng,nb = shift_color(c.red,c.green,c.blue,hue,chroma,light)
						palette:setColor(i,Color{r=nr,g=ng,b=nb,a=c.alpha})
						wrote = true
					end
				end
			end
		end
	elseif sprite.colorMode==ColorMode.RGB then
		local cels = {}
		if allCels and #app.range.cels>0 then
			for _,c in ipairs(app.range.cels) do
				table.insert(cels,c)
			end
		elseif app.activeCel then
			table.insert(cels,app.activeCel)
		end

		local useSel = selOnly and not sprite.selection.isEmpty
		for _,cel in ipairs(cels) do
			local img = cel.image:clone()
			process_rgb_image(img,cel.position,sprite,useSel,hue,chroma,light)
			cel.image = img
			wrote = true
		end
	end

	return wrote
end

-- ui

local function show_dialog(plugin)
	local sprite = app.activeSprite
	if not sprite then
		app.alert("No active sprite!")
		return
	end

	if sprite.colorMode==ColorMode.GRAY then
		app.alert("Grayscale mode has no hue to shift :(")
		return
	end

	-- restore last-used settings
	local prefs = plugin.preferences
	if prefs.hue==nil then prefs.hue = 0 end
	if prefs.chroma==nil then prefs.chroma = 100 end
	if prefs.light==nil then prefs.light = 0 end
	if prefs.selOnly==nil then prefs.selOnly = true end
	if prefs.allCels==nil then prefs.allCels = false end
	if prefs.livePreview==nil then prefs.livePreview = true end

	local dlg
	-- true when we have a preview transaction sitting on the undo stack waiting to be
	-- either committed (OK) or undone (Cancel / next preview).
	local previewing = false

	local function clear_preview()
		if previewing then
			app.command.Undo()
			previewing = false
			app.refresh()
		end
	end

	local function do_preview()
		-- always rewind the previous preview first; each preview is fresh from original
		clear_preview()

		local d = dlg.data
		local hue = d.hue
		local chroma = d.chroma/100
		local light = d.light/100

		-- skip identity transform: nothing to show, and crucially no transaction to undo later
		if hue==0 and chroma==1 and light==0 then
			return
		end

		local wrote = false
		app.transaction("OKShift",function()
			wrote = apply_impl(sprite,hue,chroma,light,d.selOnly,d.allCels)
		end)

		-- only flag as previewing if we know the transaction actually wrote something,
		-- otherwise the next app.command.Undo() would undo a user action instead of ours
		if wrote then
			previewing = true
		end
		app.refresh()
	end

	local function on_change()
		if dlg.data.livePreview then
			do_preview()
		else
			clear_preview()
		end
	end

	dlg = Dialog{title="OKShift"}
	dlg:slider{id="hue",label="Hue (°)",min=-180,max=180,value=prefs.hue,onchange=on_change}
	dlg:slider{id="chroma",label="Chroma (%)",min=0,max=200,value=prefs.chroma,onchange=on_change}
	dlg:slider{id="light",label="Lightness ±",min=-50,max=50,value=prefs.light,onchange=on_change}
	dlg:separator()
	dlg:check{id="selOnly",label="Selection only",selected=prefs.selOnly,onchange=on_change}
	dlg:check{id="allCels",label="All cels in timeline range",selected=prefs.allCels,onchange=on_change}
	dlg:separator()
	dlg:check{id="livePreview",label="Live preview (very laggy at the moment)",selected=prefs.livePreview,onchange=on_change}
	dlg:separator()
	dlg:button{id="ok",text="Apply",focus=true}
	dlg:button{id="cancel",text="Cancel"}

	-- show initial preview reflecting starting slider values
	if prefs.livePreview then
		do_preview()
	end

	dlg:show{wait=true}

	if dlg.data.ok then
		-- persist settings for next session
		prefs.hue = dlg.data.hue
		prefs.chroma = dlg.data.chroma
		prefs.light = dlg.data.light
		prefs.selOnly = dlg.data.selOnly
		prefs.allCels = dlg.data.allCels
		prefs.livePreview = dlg.data.livePreview

		-- if live preview was off, no preview transaction was ever made; apply now
		if not dlg.data.livePreview then
			local hue = dlg.data.hue
			local chroma = dlg.data.chroma/100
			local light = dlg.data.light/100
			if not (hue==0 and chroma==1 and light==0) then
				app.transaction("OKShift",function()
					apply_impl(sprite,hue,chroma,light,dlg.data.selOnly,dlg.data.allCels)
				end)
				app.refresh()
			end
		end
		-- else: the last preview is the final state, already recorded as one undo entry
	else
		-- cancelled (Cancel button or X): rewind the active preview if any
		clear_preview()
	end
end

-- plugin entry

function init(plugin)
	plugin:newCommand{
		id="OKShift",
		title="OKShift",
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
