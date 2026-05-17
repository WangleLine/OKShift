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