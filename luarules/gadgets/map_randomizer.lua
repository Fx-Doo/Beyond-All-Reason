function gadget:GetInfo()
	return {
		name	= "MapRandomizer",
		desc	= "Adds layers and layers of syms to randomize maps",
		author	= "Doo",
		date	= "September 2025 (wip)",
		layer	= -100,
        enabled = (select(1, Spring.GetGameFrame()) <= 0),
	}
end

--------------------------------------------------------------------------------
-- synced
--------------------------------------------------------------------------------

	-- MAPDEPENDANT VARS
	local sizeX = Game.mapSizeX
	local sizeZ = Game.mapSizeZ
	local sqr = Game.squareSize
	local startinSize = sqr

	-- helpers
	local rand = math.random
	local floor = math.floor
	local max = math.max
	local min = math.min
	local insert = table.insert
	local tan = math.tan
	local randseed = math.randomseed
	local pi = math.pi

	local nbLayers = rand(1,4)
	local SymFunctions = {}
	local SymTextures = {}
	local SymTexturesTexID

	local SourceSquareTextureName = {}
	local TargetSquareTextureName = {}
	local textureSizeX = math.floor(sizeX / sqr) + 1
	local textureSizeZ = math.floor(sizeZ / sqr) + 1
	
	

	local function GenerateTransformationFunction(st,size,isLeftSource,a,c)
		local mirrorFunc
		if st == 1 then
			mirrorFunc = function(x, z) return {x = sizeX - x, z = sizeZ - z} end
		elseif st == 2 then
			mirrorFunc = function(x, z) return {x = sizeX - x, z = z} end
		elseif st == 3 then
			mirrorFunc = function(x, z) return {x = x, z = sizeZ - z} end
		elseif st == 4 then
			mirrorFunc = function(x, z) return {x = z, z = x} end
		elseif st == 5 then
			mirrorFunc = function(x, z) return {x = sizeZ - z, z = sizeX - x} end
		else
			mirrorFunc = function(x, z) return {x = x, z = z} end
		end

		return function(x, z)
			local sourceSide = true
			if st == 1 then
				sourceSide = z <= (a * x + c)
			elseif st == 2 then
				sourceSide = x <= (sizeX / 2)
			elseif st == 3 then
				sourceSide = z <= (sizeZ / 2)
			elseif st == 4 then
				sourceSide = x >= z 
			elseif st == 5 then
				sourceSide = (x + z) <= (sizeX + sizeZ) / 2
			end

			if sourceSide == isLeftSource then
				return {x = x, z = z}
			else
				local m = mirrorFunc(x, z)
				local sx = m.x
				local sz = m.z
				sx = max(0, min(sizeX - size, sx))
				sz = max(0, min(sizeZ - size, sz))
				sx = floor(sx/size) * size
				sz = floor(sz/size) * size
				return {x = sx, z = sz}
			end
		end
	end

	local function WrapTransformationFunctions(symFuncs)
		return function(x, z)
			local pos = {x = x, z = z}
			for _, f in ipairs(symFuncs) do
				pos = f(pos.x, pos.z)
			end
			return pos
		end
	end

if gadgetHandler:IsSyncedCode() then

	local gdheight = Spring.GetGroundHeight
	local mapOptions = Spring.GetMapOptions
	local SetHeightMap = Spring.SetHeightMap
	local SetMetal = Spring.SetMetalAmount

	-- MAPDEPENDANT VARS
	local sizeX = Game.mapSizeX
	local sizeZ = Game.mapSizeZ
	local sqr = Game.squareSize
	local startingSize = Game.squareSize
	local pendingMessages = {}


	local metalMult = 0
	local metalTot = 0
	local metalTotAft = 0
	local nbLayers = 16

	function CustomSendToUnsynced(a,b,c,d,e,f,g,h,i,j,k,l)
		if unsyncedReady == true then
			SendToUnsynced("SymFunctions",a,b,c,d,e,f,g,h,i,j,k,l)
		else
			table.insert(pendingMessages, {"symFunctions",a,b,c,d,e,f,g,h,i,j,k,l})
		end
	end

	function gadget:RecvLuaMsg(a,b)
		if unsyncedReady == true then
			return
		end
		if a == "symFunctions" then
			for i = 1, #pendingMessages do
				SendToUnsynced(pendingMessages[i][1],pendingMessages[i][2],pendingMessages[i][3],pendingMessages[i][4],pendingMessages[i][5],pendingMessages[i][6],pendingMessages[i][7],pendingMessages[i][8],pendingMessages[i][9],pendingMessages[i][10],pendingMessages[i][11])
				pendingMessages[i] = nil
			end

		end
	end

	function gadget:Initialize()	
		local randomSeed
		if mapOptions() and mapOptions().seed and tonumber(mapOptions().seed) ~= 0 then
			randomSeed = tonumber(mapOptions().seed)
		else
			randomSeed = rand(1,10000)
		end
		randseed(randomSeed)
		Spring.Echo("Random Seed = "..tostring(randomSeed)..", Symtype = "..tostring((mapOptions() and mapOptions().symtype and tonumber(mapOptions().symtype)) or 0))

		-- PARAMS
		local Cells,Size = GenerateCells(startingSize)

		local symFuncs = {}
		for i = 1, nbLayers-1 do
			local symType = rand(1,2)
			local isLeftSource = rand() < 0.5
			local a = RandomSlope()
			local c = sizeZ / 2 - a * sizeX / 2
			CustomSendToUnsynced(symType,size,isLeftSource, a, c)
			local symFunc = GenerateTransformationFunction(symType,Size,isLeftSource,a,c)
			insert(symFuncs, symFunc)
		end
		if true then
			local symType = rand(3,4)
			local isLeftSource = rand() < 0.5
			local a = RandomSlope()
			local c = sizeZ / 2 - a * sizeX / 2
			CustomSendToUnsynced(symType,size,isLeftSource, a, c)
			CustomSendToUnsynced(_,_,_, _, _,_,_,_,true)
			local symFunc = GenerateTransformationFunction(symType,Size,isLeftSource,a,c)
			insert(symFuncs, symFunc)
		end

		local finalSymmetry = WrapTransformationFunctions(symFuncs)
		Cells,Size = ApplySymmetry(Cells, Size, finalSymmetry, false)

		Spring.SetHeightMapFunc(ApplyHeightMap, Cells)
		Cells = nil

		local metal = GenerateMetal(16)
		metal = ApplySymmetry(metal, 16, finalSymmetry,true)
		CountMetal(metal,Size)
		DoMetal(metal,Size)
	end
	
	function CountMetal(metals, size)
		for x = 0,sizeX , 16 do
			for z = 0, sizeZ, 16 do
				metalTotAft = metalTotAft + metals[x][z]
			end
		end
		metalMult = metalTot / metalTotAft
	end
	
	function DoMetal(metals, size)
		for x = 0,sizeX , 16 do
			for z = 0, sizeZ, 16 do
				SetMetal(x/16, z/16, metals[x][z]* metalMult)
			end
		end
	end

	function GenerateMetal(size)
		local metals = {}
		for x = 0,sizeX, size do
			metals[x] = metals[x] or {}
			for z = 0,sizeZ, size do
				local met = Spring.GetMetalAmount(x/16,z/16)
				if not metals[x][z] then
					metals[x][z] = met
					metalTot = metalTot + metals[x][z]
				end
			end
		end
		return metals, size
	end

	function RandomSlope()
		local theta = rand(1,9)/10 * (pi / 2)
		local a = tan(theta)
		return a
	end

	
	function ApplySymmetry(cells, size, symTable)
		for x = 0, sizeX, size do
			for z = 0, sizeZ, size do
				local sym = symTable(x, z)
				local nx, nz = sym.x, sym.z
				nx = floor(nx/size) * size
				nz = floor(nz/size) * size
				cells[x][z] = cells[nx][nz]
			end
		end
		return cells, size
	end
	
	function ApplyHeightMap(cells)
		for x = 0,sizeX,sqr do
			for z = 0,sizeZ,sqr do
				local height = cells[x][z]
				SetHeightMap(x,z, height )
			end
		end
	end
	
	function GenerateCells(size)
		local cells = {}
		for x = 0,sizeX,size do
			cells[x] = cells[x] or {}
			for z = 0,sizeZ,size do
				cells[x][z] = floor(gdheight(x,z))
			end
		end
		return cells,size
	end

--------------------------------------------------------------------------------
-- unsynced
--------------------------------------------------------------------------------
else
	sqr = sqr * 4

	function gadget:RecvFromSynced(strsymFunctions, st,size,isLeftSource,a,c,_,_,_,finalize)
		if strsymFunctions ~= "symFunctions" then return end
		Spring.Echo("received data")
		Spring.Echo(st,size,isLeftSource,a,c,finalize)
		if not finalize then
			local SymFunc = GenerateTransformationFunction(st,sqr,isLeftSource,a,c)
			table.insert(SymFunctions,SymFunc)
		else
			finFunc = WrapTransformationFunctions(SymFunctions)
			DoSymTextures(finFunc)
			Spring.Echo("finalize")
		end
	end


	function DoSymTextures(finfunc)
		local SymTex = RenderSymToTex(finfunc)
		table.insert(SymTextures,SymTex)
	end

	function GetSourceCoords(x,z,x2,z2)
		if x > x2 then
			x2 = x - sqr
		else
			x2 = x + sqr
		end
		if z>z2 then
			z2 = z - sqr
		else
			z2 = z + sqr
		end
		local startX = x/sizeX
		local endX = x2/sizeX
		local startZ = z/sizeZ
		local endZ = z2/sizeZ
		return {startX = startX, startZ = startZ, endX = endX, endZ = endZ}
	end

	function GetTargetSquareAndCoords(x,z,x2,z2)
		local sqrX = math.floor(x/1024)
		local sqrZ = math.floor(z/1024)
		local startX = (((x - sqrX*1024)/1024)*2 -1)
		local startZ = (((z - sqrZ*1024)/1024)*2 -1)
		local endX = (((x2 - sqrX*1024)/1024)*2 -1)
		local endZ = (((z2 - sqrZ*1024)/1024)*2 -1)
		return {sqrX = sqrX, sqrZ = sqrZ, startX = startX,startZ = startZ, endX = endX, endZ = endZ}
	end

	function RenderSymToTex(SymFunc)
		imgData = {}
		for x = 0, sizeX , sqr do
			imgData[x] = imgData[x] or {}
			for z = 0, sizeZ, sqr do
				local sym = SymFunc(x, z)
				local symsqr = SymFunc(x+sqr, z+sqr)
				local source = GetSourceCoords(sym.x,sym.z,symsqr.x, symsqr.z)
				local target = GetTargetSquareAndCoords(x,z,x+sqr,z+sqr)
				imgData[x][z] = {source = source, target = target}
			end
		end
	end
	function CreateSquareTexture(x,z)
        local tex = gl.CreateTexture(1024, 1024, {
            -- format = GL.RGBA,
            min_filter = GL.LINEAR,
            mag_filter = GL.LINEAR,
            wrap_s = GL.MIRRORED_REPEAT,
            wrap_t = GL.MIRRORED_REPEAT,
			fbo =  true,
        })
		return tex
end

function GetSquareTexture(x,z)
	      local texOut = gl.CreateTexture(1024, 1024, {
            min_filter = GL.LINEAR,
            mag_filter = GL.LINEAR,
            wrap_s = GL.MIRRORED_REPEAT,
            wrap_t = GL.MIRRORED_REPEAT,
			fbo =  true,
        })
		local done = Spring.GetMapSquareTexture(x,z,0,texOut)
		return texOut
end

	function RenderToFullTex(texIn, row, column, texOut)
		gl.Texture(texIn)
		local func = function(row, column)
			gl.TexRect( 2*(row*1024/sizeX)-1,2*(((column+1)*1024)/sizeZ)-1, 2*(((row+1)*1024)/sizeX)-1, 2*(column*1024/sizeZ)-1)
			end
		gl.RenderToTexture(texOut, func, row, column)
		gl.Texture(false)	
	end
		
function gadget:DrawGenesis()
	if doitonce ~= true then
		fullTex = gl.CreateTexture( sizeX, sizeZ, {
            min_filter = GL.LINEAR,
            mag_filter = GL.LINEAR,
            wrap_s = GL.MIRRORED_REPEAT,
            wrap_t = GL.MIRRORED_REPEAT,
			fbo =  true,
        })
		for row= 0, (sizeX/1024)-1 do
			SourceSquareTextureName[row] = SourceSquareTextureName[row] or {}
			for column = 0, (sizeZ/1024)-1 do
				SourceSquareTextureName[row][column] = GetSquareTexture(row,column)
				RenderToFullTex(SourceSquareTextureName[row][column],row, column, fullTex)
				gl.DeleteTexture(SourceSquareTextureName[row][column])
				SourceSquareTextureName[row][column] = nil
			end
		end
		for row= 0, (sizeX/1024)-1 do
			TargetSquareTextureName[row] = TargetSquareTextureName[row] or {}
			for column = 0, (sizeZ/1024)-1 do
				TargetSquareTextureName[row][column] = CreateSquareTexture(row,column)
				for x= row*1024, ((row+1)*1024)-1,sqr do
					for z= column*1024, ((column+1)*1024)-1,sqr do
						local source = imgData[x][z].source
						local target = imgData[x][z].target
						glRenderToTarget(source, texSqr, target)
					end	
				end
				Spring.SetMapSquareTexture(row,column, TargetSquareTextureName[row][column])
			end
		end
		doitonce = true
	end
end

function glRenderToTarget(source, texIn, target)
	local tsqrX, tsqrZ, tsx, tsz, tex, tez = target.sqrX, target.sqrZ, target.startX, target.startZ, target.endX, target.endZ
	local ssx, ssz, sex, sez = source.startX, source.startZ, source.endX, source.endZ
	gl.Texture(fullTex)
	texOut = TargetSquareTextureName[tsqrX][tsqrZ]
	local IncludeSquare = function(tsqrX, tsqrZ, tsx, tsz, tex, tez,ssx, ssz, sex, sez, flips, flipt)
		gl.TexRect(tsx, tsz, tex, tez,ssx,ssz,sex,sez)
		end
	gl.RenderToTexture(texOut, IncludeSquare, tsqrX, tsqrZ, tsx, tsz, tex, tez,ssx, ssz, sex, sez, flips, flipt)
	gl.Texture(false)
	end
	function gadget:Initialize()
		Spring.SendLuaRulesMsg("symFunctions")
	end
end
