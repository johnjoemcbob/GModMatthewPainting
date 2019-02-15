
-- Parameters
local ScreenshotRequested = false
local AnalyzeChunks = 20
local CircleSegments = 16

-- Variables
local Painting
local AnalyzeData

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
	ScreenshotRequested = true
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
hook.Add( "HUDShouldDraw", "HideHUD", function( name )
	if ( ( click and name != "CHudGMod" and name != "CHudMenu" ) or ScreenshotRequested ) then return false end
end )

local Style = 1
local style = {}
local LastMousePosX, LastMousePosX
local clickpos, clicksize
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
		function()
			return true
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
	clicksize = 128
	if ( LeapPoints[3] != nil ) then
		local frame = LeapMotion_GetCurrentFrame()
		if ( frame and frame.HandsNumber > 0 ) then
			local pos = frame.Hands[1].PalmPosition

			local width = math.abs( LeapPoints[1].x - LeapPoints[2].x )
			local height = math.abs( LeapPoints[2].z - LeapPoints[3].z )
			local pointOnPlane = Vector( math.abs( LeapPoints[1].x - pos.x ) / width, math.abs( LeapPoints[3].z - pos.z ) / height, 0 )
			local depthdist = LeapPoints[1].y - pos.y
			local depthmax = 45

			click = true
			clickpos = function() return ScrW() * pointOnPlane.x, ScrH() * ( 1 - pointOnPlane.y ) end
			clicksize = clicksize * math.max( 0, ( ( depthdist / depthmax ) ) )
		end
	end
	clicksize = click and clicksize or 0
end )

local Dirty = false
local BorderAllowance = 5 -- Stroke border allowance to stop weird edge rendering (render big and then cut back down to size)
hook.Add( "HUDPaint", "HUDPaint_DrawABox", function()
	local function drawcanvas()
		render.DrawTextureToScreen( RenTex_Painting ) -- TODO TEMP REMOVE
		-- Brush location and size
		local x, y = clickpos()
		surface.DrawCircle( x, y, math.max( 1, clicksize ), 255, 255, 255 )

		-- Debug test analyze
		for x = 1, AnalyzeChunks do
			for y = 1, AnalyzeChunks do
				local ax, ay = GetAnalyzePos( x, y )
				local w, h = 8, 8
				surface.DrawRect( ax - w / 2, ay - h / 2, w, h )
				-- local json = util.TableToJSON( AnalyzeData[x][y] )
				local json = AnalyzeData[x][y]
				draw.SimpleText( json, "DermaDefault", ax, ay )
			end
		end
	end

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
					local function mask()
						local x, y = clickpos()
						local dist = math.Distance( LastMousePosX, LastMousePosY, x, y )
						local extra = 0
						local off = 0
						local distoff = 50
							if ( dist < distoff ) then
								distoff = 1
							end
						for p = 1 - extra, dist / distoff + extra do
							local ix = ( LastMousePosX - x ) / dist * distoff * p
							local iy = ( LastMousePosY - y ) / dist * distoff * p
							local radius = clicksize
								if ( p < 1 ) then
									radius = radius / extra * ( extra - math.abs( 1 - p ) )
									ix = ix * extra * ( math.abs( 1 - p ) ) * radius
									iy = iy * extra * ( math.abs( 1 - p ) ) * radius
									print( radius )
								end
							local seg = CircleSegments
							local rotate = 0
							surface.SetDrawColor( 255, 255, 255, 100 )
							table.insert( circles, { x = x + ix, y = y + iy, r = radius, s = seg, rotate = rotate } )
							draw.Circle( x + ix, y + iy, radius * BorderAllowance, seg, rotate )
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
						local blur = style[Style]()
					end
					draw.StencilBasic( mask, inner )
				cam.End2D()
			render.PopRenderTarget()

			-- Now blur for paint stroke effect
			drawcanvas()
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

			if ( blur ) then
				render.BlurRenderTarget( RenTex_Painting, 1, 1, 5 )
			end
		else
			-- Reset lastmousepos
			LastMousePosX, LastMousePosY = clickpos()
		end

		-- This draw canvas only works if no blurring this frame
		drawcanvas()
	end
end )

hook.Add( "PostRender", "example_screenshot", function()
	if ( ScreenshotRequested ) then
		AnalyzeImage()

		-- Clear
		render.PushRenderTarget( RenTex_Painting )
			render.ClearDepth()
			render.Clear( 255, 255, 255, 255 )
		render.PopRenderTarget()

		-- Store
		local data = render.Capture( {
			format = "jpeg",
			quality = 70,
			h = ScrH(),
			w = ScrW(),
			x = 0,
			y = 0,
		} )
		file.CreateDir( "mc_paint" )
		local f = file.Open( "mc_paint/painting.jpg", "wb", "DATA" )
			f:Write( data )
		f:Close()

		-- Load in as material
		Painting = Material( "../data/mc_paint/painting.jpg" )

		ScreenshotRequested = false
	end
end )

function AnalyzeImage()
	-- Break screen down into chunks (try 2:2 to start?)
	local dist = 1000000
	AnalyzeData = {}
	local types = {}
	for x = 1, AnalyzeChunks do
		if ( !AnalyzeData[x] ) then
			AnalyzeData[x] = {}
		end

		for y = 1, AnalyzeChunks do
			local dir = gui.ScreenToVector( GetAnalyzePos( x, y ) )
			local tr = util.QuickTrace( LocalPlayer():EyePos(), dir * dist, LocalPlayer() )
			local info = AnalyzeGetInfo( tr )
				if ( !types[info] ) then
					types[info] = 0
				end
				types[info] = types[info] + 1
			AnalyzeData[x][y] = info
		end
	end

	-- Percentage output
	local total = 0
		for k, typ in pairs( types ) do
			total = total + typ
		end
	print( "Total: " .. total )
	for k, typ in pairs ( types ) do
		print( k .. ": " .. typ / total * 100 )
	end

	-- Raytrace to find hit
		-- If ent then
		-- If world then
			-- Get texture of world to find if sky or ground/wall/etc
			-- Material name could offer more info (like "building" or "wall" or "grass" etc)
		-- How detect water?
	-- Debug show these on screen with analyzed info
end

local AnalyzeMatTypes = {
	[MAT_ANTLION] = "Antlion",
	[MAT_BLOODYFLESH] = "Flesh",
	[MAT_CONCRETE] = "Concrete",
	[MAT_DIRT] = "Dirt",
	[MAT_EGGSHELL] = "Egg",
	[MAT_FLESH] = "Flesh",
	[MAT_GRATE] = "Grate",
	[MAT_ALIENFLESH] = "Alien Flesh",
	[MAT_SNOW] = "Snow",
	[MAT_PLASTIC] = "Plastic",
	[MAT_METAL] = "Metal",
	[MAT_SAND] = "Sand",
	[MAT_FOLIAGE] = "Foliage",
	[MAT_COMPUTER] = "Computer",
	[MAT_SLOSH] = "Liquid",
	[MAT_TILE] = "Tile",
	[MAT_GRASS] = "Grass",
	[MAT_VENT] = "Vent",
	[MAT_WOOD] = "Wood",
	[MAT_GLASS] = "Glass",
	[MAT_WARPSHIELD] = "Shield",
}

function AnalyzeGetInfo( tr )
	-- Water and sky have priority
	if ( bit.band( util.PointContents( tr.HitPos ), CONTENTS_WATER ) == CONTENTS_WATER ) then
		return "Water"
	end
	if ( tr.HitSky ) then
		return "Sky"
	end

	if ( tr.HitNonWorld and tr.Entity ) then
		return tr.Entity:GetClass()
	end

	-- World hit material types
	if ( AnalyzeMatTypes[tr.MatType] ) then
		return AnalyzeMatTypes[tr.MatType]
	end

	print( tr.MatType )
	return "Unknown"
end

function GetAnalyzePos( x, y )
	local off = ( 1 / 2 ) / AnalyzeChunks
	return ( ( x / AnalyzeChunks ) - off ) * ScrW(), ( ( y / AnalyzeChunks ) - off ) * ScrH()
end

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