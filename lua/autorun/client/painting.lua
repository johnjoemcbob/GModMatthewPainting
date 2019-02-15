local ScreenshotRequested = 0
local Stages = 2
local Painting

-- Help: https://forum.facepunch.com/gmoddev/lzpr/Render-Targets-Alpha-Issues/1/
local TEXTURE_FLAGS_CLAMP_S = 0x0004
local TEXTURE_FLAGS_CLAMP_T = 0x0008

local RenTex_Temp = GetRenderTargetEx( 
	"mm_paint_temp"..CurTime(),
	ScrW(), ScrH(),
	RT_SIZE_NO_CHANGE,
	MATERIAL_RT_DEPTH_SEPARATE,
	bit.bor( TEXTURE_FLAGS_CLAMP_S, TEXTURE_FLAGS_CLAMP_T ),
	CREATERENDERTARGETFLAGS_UNFILTERABLE_OK,
    IMAGE_FORMAT_RGBA8888
 )
local RenTex_TempAlpha = GetRenderTargetEx( 
	"mm_paint_temp_alpha"..CurTime(),
	ScrW(), ScrH(),
	RT_SIZE_NO_CHANGE,
	MATERIAL_RT_DEPTH_SEPARATE,
	bit.bor( TEXTURE_FLAGS_CLAMP_S, TEXTURE_FLAGS_CLAMP_T ),
	CREATERENDERTARGETFLAGS_UNFILTERABLE_OK,
    IMAGE_FORMAT_RGB888
 )
local RenTex_Painting = GetRenderTarget( "mm_paint_canvas"..CurTime(), ScrW(), ScrH(), true )

local RenMat_Painting = CreateMaterial( "mm_paint_canvas_material"..CurTime(), "UnlitGeneric", {
	["$ignorez"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
	["$nolod"] = 1,
	["$basetexture"] = RenTex_Painting:GetName()
} )
local RenMat_Temp = CreateMaterial( "mm_paint_temp_material"..CurTime(), "UnlitGeneric", {
	["$ignorez"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
	["$nolod"] = 1,
	["$basetexture"] = RenTex_Temp:GetName()
} )
local RenMat_TempAlpha = CreateMaterial( "mm_paint_temp_alpha_material"..CurTime(), "UnlitGeneric", {
	["$ignorez"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
	["$nolod"] = 1,
	["$basetexture"] = RenTex_TempAlpha:GetName()
} )

function RequestAScreenshot()
	ScreenshotRequested = Stages + 1
end
concommand.Add( "make_screenshot", RequestAScreenshot )

local LeapPoints = LocalPlayer().LeapPoints or {}
function Calibrate( ply, cmd, args )
	local frame = LeapMotion_GetCurrentFrame()
	if ( frame and frame.HandsNumber > 0 ) then
		LeapPoints[tonumber(args[1])] = frame.Hands[1].PalmPosition
		LocalPlayer().LeapPoints = LeapPoints
		PrintTable( LeapPoints )
	end
end
concommand.Add( "mc_paint_calibrate", Calibrate )

local click = false
local clickpos
hook.Add( "HUDShouldDraw", "HideHUD", function( name )
	if ( ( click and name != "CHudGMod" and name != "CHudMenu" ) or ( ScreenshotRequested > 0 and ScreenshotRequested < Stages + 1 ) ) then return false end
end )

local Style = 1
local style = {}
local LastMousePosX, LastMousePosX
hook.Add( "Think", "Think_MC_Paint", function()
	-- Style input
	local colourmult = {
		[ "$pp_colour_addr" ] = 0,
		[ "$pp_colour_addg" ] = 0,
		[ "$pp_colour_addb" ] = 0,
		[ "$pp_colour_brightness" ] = 0,
		[ "$pp_colour_contrast" ] = 1,
		[ "$pp_colour_colour" ] = 3,
		[ "$pp_colour_mulr" ] = 0,
		[ "$pp_colour_mulg" ] = 0,
		[ "$pp_colour_mulb" ] = 0
	}
	style = {
		function()
			DrawSobel( 1 )
		end,
		function()
			DrawTexturize( 1, Material( "pp/texturize/plain.png" ) )
		end,
		function()
			DrawTexturize( 1, Material( "pp/texturize/pinko.png" ) )
		end,
		function()
			DrawBloom( -0.1, 2, 9, 9, 1, 1, 1, 1, 1 )
			DrawTexturize( 1, Material( "pp/texturize/plain.png" ) )
			DrawSharpen( 100, 10 )
		end,
		function()
			colourmult["$pp_colour_addr"] = 0.02
			DrawColorModify( colourmult )
		end,
	}
	for inp = 1, #style do
		if ( input.IsButtonDown( KEY_PAD_0 + inp ) ) then
			Style = inp
			print( "SET STYLE TO " .. inp )
		end
	end

	-- Stroke input
	click = input.IsMouseDown( MOUSE_LEFT )
	clickpos = input.GetCursorPos
	if ( LeapPoints[3] != nil ) then
		local frame = LeapMotion_GetCurrentFrame()
		if ( frame and frame.HandsNumber > 0 ) then
			local pos = frame.Hands[1].PalmPosition

			local width = math.abs( LeapPoints[1].x - LeapPoints[2].x )
			local height = math.abs( LeapPoints[2].z - LeapPoints[3].z )
			local pointOnPlane = Vector( math.abs( LeapPoints[1].x - pos.x ) / width, math.abs( LeapPoints[3].z - pos.z ) / height, 0 )
			-- print( "-" )
			-- PrintTable( LeapPoints )
			-- print( pos )
			-- print( pointOnPlane )
			click = true
			clickpos = function() return ScrW() * pointOnPlane.x, ScrH() * ( 1 - pointOnPlane.y ) end
		end
	end
end )

local Dirty = false
local BorderAllowance = 0.5 -- Stroke border allowance to stop weird edge rendering (render big and then cut back down to size)
hook.Add( "HUDPaint", "HUDPaint_DrawABox", function()
	if ( Painting ) then
		if ( click ) then
			-- First render to temp target for any unique effects
			render.PushRenderTarget( RenTex_TempAlpha )
				render.ClearDepth()
				render.Clear( 0, 0, 0, 255 )
			render.PopRenderTarget()
			render.PushRenderTarget( RenTex_Temp )
				render.ClearDepth()
				render.Clear( 0, 0, 0, 255 )

				-- Convoluted method to get alpha transparency working
				render.SetStencilEnable( true )
					render.ClearStencil()

					render.SetStencilReferenceValue ( 1 )
					render.SetStencilFailOperation( STENCILOPERATION_KEEP )
					render.SetStencilZFailOperation( STENCILOPERATION_KEEP )
					render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
					render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
						cam.Start2D()
								
								render.SetStencilFailOperation( STENCILOPERATION_KEEP )
								render.SetStencilZFailOperation( STENCILOPERATION_KEEP )
								render.SetStencilPassOperation( STENCILOPERATION_KEEP )
								render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
								
								surface.SetMaterial( RenMat_TempAlpha )
								surface.SetDrawColor( 255, 255, 255, 255 )
								surface.DrawTexturedRect( 0, 0, ScrW(), ScrH() )

								render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_NOTEQUAL )
								
								render.ClearBuffersObeyStencil( 255, 255, 255, 0 )
						cam.End2D()
				render.SetStencilEnable( false )

				-- Now render the actual stroke
				local circles = {}
				cam.Start2D()
					-- draw.SimpleText( "Hello there matthew!" )

					local function mask()
						local x, y = clickpos()
						local dist = math.Distance( LastMousePosX, LastMousePosY, x, y )
						local extra = 0
						local off = 0
						for p = 1 - extra, dist + extra do
							local ix = ( LastMousePosX - x ) / dist * p
							local iy = ( LastMousePosY - y ) / dist * p
							local radius = 64
								if ( p < 1 ) then
									radius = radius / extra * ( extra - math.abs( 1 - p ) )
									ix = ix * extra * ( math.abs( 1 - p ) ) * radius
									iy = iy * extra * ( math.abs( 1 - p ) ) * radius
									print( radius )
								end
							local seg = 16
							local rotate = 0
							surface.SetDrawColor( 255, 255, 255, 100 )
							table.insert( circles, { x = x + ix, y = y + iy, r = radius, s = seg, rotate = rotate } )
							draw.Circle( x + ix, y + iy, radius / BorderAllowance, seg, rotate )
						end
						if ( dist != 0 ) then
							Dirty = true
						end
						LastMousePosX, LastMousePosY = clickpos()
					end
					local function inner()
						surface.SetDrawColor( 255, 255, 255, 255 )
						surface.SetMaterial( Painting )
						surface.DrawTexturedRect( 0, 0, ScrW(), ScrH() )
						style[Style]()
					end
					draw.StencilBasic( mask, inner )
				cam.End2D()
			render.PopRenderTarget()

			-- Now blur for paint stroke effect - No this makes the edge effect even MORE obvious
			render.DrawTextureToScreen( RenTex_Painting )
			render.BlurRenderTarget( RenTex_Temp, 0, 0, 5 )

			-- Then render down on to the canvas
			render.PushRenderTarget( RenTex_Painting )
				local function mask()
					for k, c in pairs( circles ) do
						draw.Circle( c.x, c.y, c.r, c.s, c.rotate )
					end
				end
				local function inner()
					surface.SetMaterial( RenMat_Temp )
					surface.SetDrawColor( 255, 255, 255, 255 )
					surface.DrawTexturedRect( 0, 0, ScrW(), ScrH() )
				end
				draw.StencilBasic( mask, inner )
			render.PopRenderTarget()
		else
			-- Reset lastmousepos
			LastMousePosX, LastMousePosY = clickpos()
		end

		if ( Dirty ) then
			-- Now blur for paint stroke effect
			render.DrawTextureToScreen( RenTex_Painting ) -- Required BEFORE blur otherwise it can't render this frame
			-- render.BlurRenderTarget( RenTex_Painting, 0, 0, 1 )
			Dirty = false
		end

		-- temp test
		render.DrawTextureToScreen( RenTex_Painting )
		-- surface.SetMaterial( RenMat_Painting )
		-- surface.SetDrawColor( 255, 255, 255, 255 )
		-- surface.DrawTexturedRect( 0, 0, ScrW(), ScrH() )
	end
end )

hook.Add( "PostRender", "example_screenshot", function()
			-- render.UpdateFullScreenDepthTexture()
		-- print( render.SupportsPixelShaders_2_0() )
	if ( ScreenshotRequested == 0 ) then return end

	-- Store current render to replace after
	if ( ScreenshotRequested == Stages + 1 ) then
		render.CopyRenderTargetToTexture( RenTex_Temp )
	end
		-- Process
		if ( ScreenshotRequested == 3 ) then
			render.PushRenderTarget( RenTex_Painting )
				render.ClearDepth()
				render.Clear( 255, 255, 255, 255 )
			render.PopRenderTarget()
			-- render.DrawTextureToScreen( render.GetResolvedFullFrameDepth() )
		elseif ( ScreenshotRequested == 2 ) then
			-- DrawBloom( -0.1, 2, 9, 9, 1, 1, 1, 1, 1 )
			-- DrawTexturize( 1, Material( "pp/texturize/plain.png" ) )
			-- DrawSharpen( 100, 10 )
			-- DrawToyTown( 1, ScrH() ) -- maybe

			-- DrawTexturize( 1, Material( "pp/texturize/pattern1.png" ) )
		elseif ( ScreenshotRequested == 1 ) then
			-- DrawTexturize( 1, Material( "pp/texturize/pattern1.png" ) )
		end

		-- Store
		local data = render.Capture( {
			format = "jpeg",
			quality = 70, //100 is max quality, but 70 is good enough.
			h = ScrH(),
			w = ScrW(),
			x = 0,
			y = 0,
		} )
		file.CreateDir( "mc_paint" )
		local f = file.Open( "mc_paint/painting"..ScreenshotRequested..".jpg", "wb", "DATA" )
			f:Write( data )
		f:Close()

		-- Load in as material
		Painting = Material( "../data/mc_paint/painting2.jpg" )
	-- Restore old render
	render.DrawTextureToScreen( RenTex_Temp )

	-- Next stage
	ScreenshotRequested = ScreenshotRequested - 1
end )

function draw.Circle( x, y, radius, seg, rotate )
	local cir = PRK_GetCirclePoints( x, y, radius, seg, rotate )
	surface.DrawPoly( cir )
end

-- From: http://wiki.garrysmod.com/page/surface/DrawPoly
function PRK_GetCirclePoints( x, y, radius, seg, rotate )
	local cir = {}
		for i = 0, seg do
			local a = math.rad( ( ( i / seg ) * -360 ) + rotate )
			table.insert( cir, { x = x + math.sin( a ) * radius, y = y + math.cos( a ) * radius, u = math.sin( a ) / 2 + 0.5, v = math.cos( a ) / 2 + 0.5 } )
		end
	return cir
end

function draw.StencilBasic( mask, inner )
	render.ClearStencil()
	render.SetStencilEnable( true )
		render.SetStencilWriteMask( 255 )
		render.SetStencilTestMask( 255 )
		render.SetStencilFailOperation( STENCILOPERATION_KEEP )
		render.SetStencilZFailOperation( STENCILOPERATION_REPLACE )
		render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
		render.SetBlend( 0 ) --makes shit invisible
		render.SetStencilReferenceValue( 10 )
			mask()
		render.SetBlend( 1 )
		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
			inner()
	render.SetStencilEnable( false )
end

-- Water colour?
-- DrawSharpen( 4, 50 )
-- DrawSobel( 0.5 )

-- INTENSITY/COLOUR
-- DrawSharpen( 10, 25 )

-- Focus
-- DrawToyTown( 14, ScrH()/2 )

-- Grainy/textured
-- DrawSharpen( 4, 4 )
-- DrawSobel( 0.5 )

-- Monochrome
-- DrawTexturize( 1, Material( "pp/texturize/plain.png" ) )

-- Monochrome dither
-- DrawTexturize( 1, Material( "pp/texturize/pattern1.png" ) )

-- Lines are good
-- DrawTexturize( 1, Material( "pp/texturize/lines.png" ) )

-- Minimal/Absense
-- DrawTexturize( 1, Material( "pp/texturize/pinko.png" ) )

-- Sketchy?
-- DrawBloom( -0.1, 2, 9, 9, 1, 1, 1, 1, 1 )
-- DrawTexturize( 1, Material( "pp/texturize/plain.png" ) )
-- DrawSharpen( 100, 10 )
-- DrawToyTown( 1, ScrH() ) -- maybe