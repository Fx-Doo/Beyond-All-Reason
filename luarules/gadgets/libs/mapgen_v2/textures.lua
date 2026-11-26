-- Applies a Transform to the map's textures on the GPU (unsynced, call step() from DrawGenesis).
--
--  * Diffuse: every 1024x1024 map square is rebuilt by a shader that evaluates the transform for each texel
--    and samples the original squares (kept as compressed copies while the job runs).
--  * Map-wide shading textures (minimap, splat distribution, specular...): one pass each.
--
-- Work is spread over frames; the original textures are restored by restore().
--
-- Job state machine (self.phase, advanced by step()):
--   "init"    -> beginDiffuse() probes the square size, then goes to "sources" (or straight to "shading" when
--                the diffuse cannot be rebuilt)
--   "sources" -> cacheSources(): copies the original map squares, a few per frame
--   "targets" -> renderTargets(): renders the transformed squares, a few per frame; finishDiffuse() cleans up
--   "shading" -> shadingStep(): one map-wide shading texture per frame
--   "done" / "failed" (a failure restores everything)
-- self.cursor counts the work items done within the current phase. Texture squares are indexed by
-- (tileX, tileZ), 0-based; the flat index into self.sources / self.targets is tileZ * self.nx + tileX + 1.
--
-- Terminology: "source" = the original map (the input of the transform), "target" = the rebuilt (output) map;
-- a "tap" is one weighted source position the transform samples for an output position.

local LIB = "luarules/gadgets/libs/mapgen_v2/"
local Shader = VFS.Include(LIB .. "shader.lua")
local Patches = VFS.Include(LIB .. "patches.lua")

local floor = math.floor
local min = math.min
local max = math.max

local SOURCES_PER_STEP = 32
local TARGETS_PER_STEP = 2
local SAMPLES_PER_TILE = 64 -- 16 elmo spacing on a 1024 elmo square

-- map-wide textures that make sense to transform (tiling detail textures do not).
-- "normals" textures hold vectors and are turned along with the terrain; the engine's own height-derived
-- normals ($normals) and shading ($shading) textures are regenerated from the heightmap and left alone.
local SHADING_TEXTURES = {
	{ "$minimap", "whole" },
	{ "$ssmf_splat_distr", "whole" },
	{ "$ssmf_specular", "whole" },
	{ "$ssmf_normals", "normals" },
	{ "$ssmf_emission", "whole" },
	{ "$ssmf_parallax", "whole" },
	{ "$ssmf_sky_refl", "whole" },
	{ "$grass", "whole" },
}

local Textures = {}
Textures.__index = Textures

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

-- Logs a message with the module prefix.
local function echo(msg)
	Spring.Echo("[MapGen v2] textures: " .. msg)
end

-- Parameter table for gl.CreateTexture: clamped, linear filtered, optionally mipmapped.
-- fbo: true when the texture is rendered into; mips: true for a mipmapped texture;
-- kind: "diffuse" / "shading" (only with mips) to copy the player's anisotropy / lod bias settings.
local function luaTextureParams(fbo, mips, kind)
	local params = {
		min_filter = mips and GL.LINEAR_MIPMAP_LINEAR or GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = fbo,
	}
	-- the engine's own map textures use the player's anisotropy / lod bias settings; rebuilt ones must match
	if mips and kind then
		local key = kind == "diffuse" and "SMFTexAniso" or "SSMFTexAniso"
		local aniso = Spring.GetConfigFloat and Spring.GetConfigFloat(key, 0) or 0
		if aniso >= 1 then
			params.aniso = aniso
		end
		if kind == "diffuse" and Spring.GetConfigFloat then
			params.lodBias = Spring.GetConfigFloat("SMFTextureLodBias", 0)
		end
	end
	return params
end

--------------------------------------------------------------------------------
-- construction and shaders
--------------------------------------------------------------------------------

-- Creates a texture job (nothing is touched until step() is called).
-- transform: the Transform; mapWidth, mapHeight: map size in elmos; patches (optional): metal-spot patch list.
-- Returns the job object.
function Textures.new(transform, mapWidth, mapHeight, patches)
	local prog, count = transform:program()
	return setmetatable({
		T = transform,
		W = mapWidth,
		H = mapHeight,
		prog = prog,
		count = count,
		patches = patches or {},
		phase = "init",
		sources = {},
		targets = {},
		shading = {},
		cursor = 0,
	}, Textures)
end

-- Compiles the remap shader (see shader.lua) for one texture kind and looks up its uniforms.
-- kind: "tiled" (diffuse squares), "whole" or "normals" (map-wide textures).
-- Returns { id, prog, mapInfo, outInfo, passInfo, tileInfo, maskInfo, maskMode } (shader id + uniform locations),
-- or nil when compilation failed.
function Textures:createShader(kind)
	local shader = gl.CreateShader({
		vertex = Shader.vertex,
		fragment = Shader.fragment(kind),
		uniformInt = { src = 0 },
	})
	if not shader or shader == 0 then
		echo("shader (" .. kind .. ") failed to compile:\n" .. tostring(gl.GetShaderLog()))
		return nil
	end
	return {
		id = shader,
		prog = gl.GetUniformLocation(shader, "prog"),
		mapInfo = gl.GetUniformLocation(shader, "mapInfo"),
		outInfo = gl.GetUniformLocation(shader, "outInfo"),
		passInfo = gl.GetUniformLocation(shader, "passInfo"),
		tileInfo = gl.GetUniformLocation(shader, "tileInfo"),
		maskInfo = gl.GetUniformLocation(shader, "maskInfo"),
		maskMode = gl.GetUniformLocation(shader, "maskMode"),
	}
end

--------------------------------------------------------------------------------
-- diffuse: the map squares
--------------------------------------------------------------------------------

-- Square map textures are bigTexSize elmos wide and bigTexSize pixels wide; find that size by asking the engine.
-- Returns squareSize, textureName (square (0, 0), already filled by the probe), or nothing when none worked.
local function detectSquareSize()
	for _, squareSize in ipairs({ 1024, 512, 256, 2048 }) do
		local name = gl.CreateTexture(squareSize, squareSize, luaTextureParams(false, false))
		if name then
			if Spring.GetMapSquareTexture(0, 0, 0, name) then
				return squareSize, name
			end
			gl.DeleteTexture(name)
		end
	end
end

-- Starts the diffuse job: probes the square size, checks the map size fits, compiles the "tiled" shader and the
-- rock tint. Returns true when the diffuse rebuild can proceed (self.size, self.nx, self.nz are then set).
function Textures:beginDiffuse()
	local squareSize, firstName = detectSquareSize()
	if not squareSize then
		echo("could not read the map square textures, diffuse left untouched")
		return false
	end
	if self.W % squareSize ~= 0 or self.H % squareSize ~= 0 then
		gl.DeleteTexture(firstName)
		echo("map size is not a multiple of the texture square size, diffuse left untouched")
		return false
	end
	self.size = squareSize
	self.nx = floor(self.W / squareSize)
	self.nz = floor(self.H / squareSize)
	self.sources[1] = firstName -- tile (0, 0), already filled by the probe
	self.cursor = 1
	self.tiled = self:createShader("tiled")
	if not self.tiled then
		return false
	end
	self:createRock()
	return true
end

-- Copies up to SOURCES_PER_STEP more original map squares into self.sources.
-- Returns true once every square has been copied.
function Textures:cacheSources()
	local total = self.nx * self.nz
	local last = min(total, self.cursor + SOURCES_PER_STEP)
	for i = self.cursor + 1, last do
		local tileX = (i - 1) % self.nx
		local tileZ = floor((i - 1) / self.nx)
		local name = gl.CreateTexture(self.size, self.size, luaTextureParams(false, false))
		if not (name and Spring.GetMapSquareTexture(tileX, tileZ, 0, name)) then
			error("could not copy map square " .. tileX .. "," .. tileZ)
		end
		self.sources[i] = name
	end
	self.cursor = last
	return last >= total
end

-- Source squares that any texel of the target square may sample (taps sampled on a 16 elmo grid).
-- tileX, tileZ: the target square. Returns a list of { srcTileX, srcTileZ, flatIndex }.
function Textures:neededSources(tileX, tileZ)
	local transform = self.T
	local squareSize = self.size
	local tilesX = self.nx
	local tilesZ = self.nz
	local mapWidth = self.W
	local mapHeight = self.H
	local seen = {}
	local list = {}
	-- adds a source square once (squares outside the map are ignored)
	local function addSource(srcTileX, srcTileZ)
		if srcTileX >= 0 and srcTileX < tilesX and srcTileZ >= 0 and srcTileZ < tilesZ then
			local key = srcTileZ * tilesX + srcTileX + 1
			if not seen[key] then
				seen[key] = true
				list[#list + 1] = { srcTileX, srcTileZ, key }
			end
		end
	end
	local step = squareSize / SAMPLES_PER_TILE
	for sampleZ = 0, SAMPLES_PER_TILE do
		for sampleX = 0, SAMPLES_PER_TILE do
			local tapCount, tapXs, tapZs, tapWeights =
				transform:taps(tileX * squareSize + sampleX * step, tileZ * squareSize + sampleZ * step)
			for k = 1, tapCount do
				if tapWeights[k] > 1e-5 then
					local srcX = max(0, min(mapWidth, tapXs[k]))
					local srcZ = max(0, min(mapHeight, tapZs[k]))
					local srcTileX = min(floor(srcX / squareSize), tilesX - 1)
					local srcTileZ = min(floor(srcZ / squareSize), tilesZ - 1)
					addSource(srcTileX, srcTileZ)
					-- float rounding on the GPU may put a tap on the other side of a square border
					local offsetX = srcX - srcTileX * squareSize
					local offsetZ = srcZ - srcTileZ * squareSize
					if offsetX < 1.5 then
						addSource(srcTileX - 1, srcTileZ)
					elseif squareSize - offsetX < 1.5 then
						addSource(srcTileX + 1, srcTileZ)
					end
					if offsetZ < 1.5 then
						addSource(srcTileX, srcTileZ - 1)
					elseif squareSize - offsetZ < 1.5 then
						addSource(srcTileX, srcTileZ + 1)
					end
				end
			end
		end
	end
	return list
end

-- Source squares a patch may sample: its original disc (positions outside the map are mirror-folded like in the
-- shader). patch: a patch record (see patches.lua). Returns a list of { srcTileX, srcTileZ, flatIndex }.
function Textures:patchSources(patch)
	local squareSize = self.size
	local tilesX = self.nx
	local tilesZ = self.nz
	local mapWidth = self.W
	local mapHeight = self.H
	local reach = patch.r + patch.blend
	local seen = {}
	local list = {}
	-- mirror-repeat a coordinate into [0, extent]
	local function fold(coordinate, extent)
		local wrapped = coordinate % (2 * extent)
		return wrapped > extent and 2 * extent - wrapped or wrapped
	end
	-- adds a source square once (squares outside the map are ignored)
	local function addSource(srcTileX, srcTileZ)
		if srcTileX >= 0 and srcTileX < tilesX and srcTileZ >= 0 and srcTileZ < tilesZ then
			local key = srcTileZ * tilesX + srcTileX + 1
			if not seen[key] then
				seen[key] = true
				list[#list + 1] = { srcTileX, srcTileZ, key }
			end
		end
	end
	-- probe the disc centre (k = 0) and 8 points around its rim, at half and full reach
	for k = 0, 8 do
		local deltaX = 0
		local deltaZ = 0
		if k > 0 then
			deltaX = reach * math.cos(k * math.pi / 4)
			deltaZ = reach * math.sin(k * math.pi / 4)
		end
		for _, scale in ipairs({ 0.5, 1 }) do
			local srcX = fold(patch.mx + patch.a * deltaX * scale + patch.b * deltaZ * scale, mapWidth)
			local srcZ = fold(patch.mz + patch.c * deltaX * scale + patch.d * deltaZ * scale, mapHeight)
			local srcTileX = min(floor(srcX / squareSize), tilesX - 1)
			local srcTileZ = min(floor(srcZ / squareSize), tilesZ - 1)
			addSource(srcTileX, srcTileZ)
			local offsetX = srcX - srcTileX * squareSize
			local offsetZ = srcZ - srcTileZ * squareSize
			if offsetX < 1.5 then
				addSource(srcTileX - 1, srcTileZ)
			elseif squareSize - offsetX < 1.5 then
				addSource(srcTileX + 1, srcTileZ)
			end
			if offsetZ < 1.5 then
				addSource(srcTileX, srcTileZ - 1)
			elseif squareSize - offsetZ < 1.5 then
				addSource(srcTileX, srcTileZ + 1)
			end
		end
	end
	return list
end

-- Redraws every patch disc that touches target square (tileX, tileZ): the area is cleared by the patch weight,
-- then the original neighbourhood is added back, one pass per source square it samples.
-- Runs inside RenderToTexture with the "tiled" shader active; shader: the record from createShader.
function Textures:drawPatches(tileX, tileZ, shader)
	local squareSize = self.size
	local originX = tileX * squareSize
	local originZ = tileZ * squareSize
	local any = false
	for _, patch in ipairs(self.patches) do
		local reach = patch.r + patch.blend
		if patch.qx + reach > originX and patch.qx - reach < originX + squareSize
			and patch.qz + reach > originZ and patch.qz - reach < originZ + squareSize then
			if not any then
				any = true
				gl.Uniform(shader.mapInfo, self.W, self.H, 1, 0)
			end
			-- the part of the patch's bounding square that lies on this target square
			local overlapMinX = max(originX, patch.qx - reach)
			local overlapMaxX = min(originX + squareSize, patch.qx + reach)
			local overlapMinZ = max(originZ, patch.qz - reach)
			local overlapMaxZ = min(originZ + squareSize, patch.qz + reach)
			-- ... as texture coordinates (0..1) and as clip-space coordinates (-1..1) of the target square
			local u0 = (overlapMinX - originX) / squareSize
			local u1 = (overlapMaxX - originX) / squareSize
			local v0 = (overlapMinZ - originZ) / squareSize
			local v1 = (overlapMaxZ - originZ) / squareSize
			local clipX0 = u0 * 2 - 1
			local clipX1 = u1 * 2 - 1
			local clipY0 = v0 * 2 - 1
			local clipY1 = v1 * 2 - 1
			gl.UniformArray(shader.prog, 2, Patches.program(patch))
			gl.Uniform(shader.maskInfo, patch.qx, patch.qz, patch.r, reach)
			-- 1. keep only (1 - weight) of what is there
			gl.Uniform(shader.maskMode, 1, 0, 0, 0)
			gl.Blending(GL.ZERO, GL.ONE_MINUS_SRC_ALPHA)
			gl.TexRect(clipX0, clipY0, clipX1, clipY1, u0, v0, u1, v1)
			-- 2. add weight * original, from every source square the original disc touches
			gl.Uniform(shader.maskMode, 0, 0, 0, 0)
			gl.Blending(GL.ONE, GL.ONE)
			for _, source in ipairs(self:patchSources(patch)) do
				gl.Texture(0, self.sources[source[3]])
				gl.Uniform(shader.passInfo, source[1], source[2], squareSize, 0)
				gl.TexRect(clipX0, clipY0, clipX1, clipY1, u0, v0, u1, v1)
			end
		end
	end
	if any then
		gl.Uniform(shader.maskInfo, 0, 0, 0, 0)
		gl.Uniform(shader.mapInfo, self.W, self.H, self.count, 0)
	end
end

--------------------------------------------------------------------------------
-- diffuse: rock tint
--------------------------------------------------------------------------------

-- Stores the rock mask (coarse terrain nodes the terrain pass left steep, see relax.lua); applied by createRock.
-- nodesX, nodesZ: coarse grid size; nodeSize: node spacing in elmos; weights: node index -> tint weight (0..1).
function Textures:setRockMask(nodesX, nodesZ, nodeSize, weights)
	self.rock = { ncx = nodesX, ncz = nodesZ, cs = nodeSize, weights = weights }
end

-- Rock tint: a small texture (one texel per coarse node) whose alpha holds the weights, and a shader that multiplies
-- the diffuse by a dark, desaturated colour in proportion to it. Returns false when there is nothing to tint.
-- On success rock.tex / rock.shader are set (released by freeRock).
function Textures:createRock()
	local rock = self.rock
	if not rock or next(rock.weights) == nil then
		return false
	end
	local tex = gl.CreateTexture(rock.ncx, rock.ncz, luaTextureParams(true, false))
	if not tex then
		return false
	end
	local shader = gl.CreateShader({
		vertex = Shader.vertex,
		fragment = [[
#version 120
uniform sampler2D mask;
void main() {
	float a = texture2D(mask, gl_TexCoord[0].st).a;
	gl_FragColor = vec4(mix(vec3(1.0), vec3(0.50, 0.47, 0.45), a), 1.0);
}
]],
		uniformInt = { mask = 0 },
	})
	if not shader or shader == 0 then
		gl.DeleteTexture(tex)
		echo("rock shader failed to compile:\n" .. tostring(gl.GetShaderLog()))
		return false
	end
	local nodesX = rock.ncx
	local nodesZ = rock.ncz
	local nodeCount = 0
	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 0)
		gl.DepthTest(false)
		gl.Culling(false)
		gl.Blending(false)
		-- half a node in clip space (-1..1 spans the whole texture)
		local halfX = 1 / nodesX
		local halfZ = 1 / nodesZ
		for i, weight in pairs(rock.weights) do
			local nodeX = (i - 1) % nodesX
			local nodeZ = floor((i - 1) / nodesX)
			local clipX = (nodeX + 0.5) / nodesX * 2 - 1
			local clipZ = (nodeZ + 0.5) / nodesZ * 2 - 1
			gl.Color(0, 0, 0, weight)
			gl.Rect(clipX - halfX, clipZ - halfZ, clipX + halfX, clipZ + halfZ)
			nodeCount = nodeCount + 1
		end
		gl.Color(1, 1, 1, 1)
	end)
	rock.tex = tex
	rock.shader = shader
	echo(string.format("rock tint on %d steep coarse nodes", nodeCount))
	return true
end

-- Multiplies the target square (tileX, tileZ) by the rock tint; runs inside RenderToTexture
function Textures:drawRock(tileX, tileZ)
	local rock = self.rock
	if not (rock and rock.tex) then
		return
	end
	local squareSize = self.size
	local originX = tileX * squareSize
	local originZ = tileZ * squareSize
	-- the target square's extent in rock-texture coordinates (node centres sit at half-texel offsets)
	local u0 = (originX / rock.cs + 0.5) / rock.ncx
	local u1 = ((originX + squareSize) / rock.cs + 0.5) / rock.ncx
	local v0 = (originZ / rock.cs + 0.5) / rock.ncz
	local v1 = ((originZ + squareSize) / rock.cs + 0.5) / rock.ncz
	gl.UseShader(rock.shader)
	gl.Texture(0, rock.tex)
	gl.Blending(GL.DST_COLOR, GL.ZERO)
	gl.TexRect(-1, -1, 1, 1, u0, v0, u1, v1)
	gl.Texture(0, false)
	gl.UseShader(0)
end

-- Releases the rock tint texture and shader (safe to call when there is none).
function Textures:freeRock()
	local rock = self.rock
	if rock and rock.tex then
		gl.DeleteTexture(rock.tex)
		gl.DeleteShader(rock.shader)
		rock.tex = nil
		rock.shader = nil
	end
end

--------------------------------------------------------------------------------
-- diffuse: the rebuilt squares
--------------------------------------------------------------------------------

-- Renders one transformed map square: every source square the output can sample is drawn additively through the
-- remap shader, then the metal-spot patches and the rock tint are applied, then mipmaps are generated.
-- tileX, tileZ: the target square. Returns the new texture.
function Textures:renderTarget(tileX, tileZ)
	local squareSize = self.size
	local shader = self.tiled
	local needed = self:neededSources(tileX, tileZ)
	local tex = gl.CreateTexture(squareSize, squareSize, luaTextureParams(true, true, "diffuse"))
	if not tex then
		error("could not create target texture")
	end

	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 0)
		gl.DepthTest(false)
		gl.Culling(false)
		gl.UseShader(shader.id)
		gl.UniformArray(shader.prog, 2, self.prog)
		gl.Uniform(shader.mapInfo, self.W, self.H, self.count, 0)
		gl.Uniform(shader.outInfo, tileX * squareSize, tileZ * squareSize, squareSize, squareSize)
		gl.Uniform(shader.tileInfo, self.nx, self.nz, 0, 0)
		gl.Uniform(shader.maskInfo, 0, 0, 0, 0)
		gl.Uniform(shader.maskMode, 0, 0, 0, 0)
		gl.Blending(GL.ONE, GL.ONE) -- each pass adds the taps that land in its source square
		for i = 1, #needed do
			local source = needed[i]
			gl.Texture(0, self.sources[source[3]])
			gl.Uniform(shader.passInfo, source[1], source[2], squareSize, 0)
			gl.TexRect(-1, -1, 1, 1, 0, 0, 1, 1)
		end
		self:drawPatches(tileX, tileZ, shader)
		self:drawRock(tileX, tileZ)
		gl.Blending(false)
		gl.Texture(0, false)
		gl.UseShader(0)
	end)
	gl.GenerateMipmap(tex)
	return tex
end

-- Renders up to TARGETS_PER_STEP more target squares and installs them as the engine's map square textures.
-- Returns true once every square has been rendered.
function Textures:renderTargets()
	local total = self.nx * self.nz
	local last = min(total, self.cursor + TARGETS_PER_STEP)
	for i = self.cursor + 1, last do
		local tileX = (i - 1) % self.nx
		local tileZ = floor((i - 1) / self.nx)
		local tex = self:renderTarget(tileX, tileZ)
		self.targets[i] = tex
		Spring.SetMapSquareTexture(tileX, tileZ, tex)
	end
	self.cursor = last
	return last >= total
end

-- Frees the copied source squares, the "tiled" shader and the rock tint once all targets are rendered.
function Textures:finishDiffuse()
	for i, name in pairs(self.sources) do
		gl.DeleteTexture(name)
		self.sources[i] = nil
	end
	gl.DeleteShader(self.tiled.id)
	self:freeRock()
	echo(string.format("diffuse rebuilt (%d squares of %d px)", self.nx * self.nz, self.size))
end

--------------------------------------------------------------------------------
-- map-wide shading textures
--------------------------------------------------------------------------------

-- Rebuilds the next map-wide shading texture from SHADING_TEXTURES (skipped when the map has none).
-- Returns true once the list is exhausted, false otherwise (also after a skipped or refused texture).
function Textures:shadingStep()
	self.cursor = self.cursor + 1
	local entry = SHADING_TEXTURES[self.cursor]
	if not entry then
		return true
	end
	local name = entry[1]
	local kind = entry[2]
	local info = gl.TextureInfo(name)
	if not (info and info.xsize >= 16 and info.ysize >= 16) then
		echo(name .. " not present, skipped")
		return false
	end
	-- one remap shader per texture kind, compiled on first use
	self.shaders = self.shaders or {}
	local shader = self.shaders[kind]
	if not shader then
		shader = self:createShader(kind)
		if not shader then
			return false
		end
		self.shaders[kind] = shader
	end
	local rebuilt = gl.CreateTexture(info.xsize, info.ysize, luaTextureParams(true, true, "shading"))
	if not rebuilt then
		return false
	end
	gl.RenderToTexture(rebuilt, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 0)
		gl.DepthTest(false)
		gl.Culling(false)
		gl.UseShader(shader.id)
		gl.UniformArray(shader.prog, 2, self.prog)
		gl.Uniform(shader.mapInfo, self.W, self.H, self.count, 0)
		gl.Uniform(shader.outInfo, 0, 0, self.W, self.H)
		gl.Texture(0, name)
		gl.TexRect(-1, -1, 1, 1, 0, 0, 1, 1)
		gl.Texture(0, false)
		gl.UseShader(0)
	end)
	gl.GenerateMipmap(rebuilt)
	if Spring.SetMapShadingTexture(name, rebuilt) then
		self.shading[name] = rebuilt
		echo(string.format("%s rebuilt (%dx%d, %s)", name, info.xsize, info.ysize, kind))
	else
		gl.DeleteTexture(rebuilt)
		echo(name .. ": the engine refused the rebuilt texture")
	end
	return false
end

--------------------------------------------------------------------------------
-- driver
--------------------------------------------------------------------------------

-- Call once per frame from DrawGenesis. Returns true while there is still work to do.
-- Runs one slice of the current phase inside pcall; an error restores the original textures and ends the job.
function Textures:step()
	local phase = self.phase
	if phase == "done" or phase == "failed" then
		return false
	end

	local ok, err = pcall(function()
		if phase == "init" then
			self.phase = self:beginDiffuse() and "sources" or "shading"
			self.cursor = self.phase == "sources" and self.cursor or 0
		elseif phase == "sources" then
			if self:cacheSources() then
				self.phase = "targets"
				self.cursor = 0
			end
		elseif phase == "targets" then
			if self:renderTargets() then
				self:finishDiffuse()
				self.phase = "shading"
				self.cursor = 0
			end
		elseif phase == "shading" then
			if self:shadingStep() then
				self.phase = "done"
				for _, shader in pairs(self.shaders or {}) do
					gl.DeleteShader(shader.id)
				end
			end
		end
	end)

	if not ok then
		echo("failed in phase '" .. phase .. "': " .. tostring(err))
		self:restore()
		self.phase = "failed"
		return false
	end
	return self.phase ~= "done"
end

-- Puts the engine's own textures back and frees everything this job created.
function Textures:restore()
	self:freeRock()
	if self.size then
		for i, tex in pairs(self.targets) do
			local tileX = (i - 1) % self.nx
			local tileZ = floor((i - 1) / self.nx)
			Spring.SetMapSquareTexture(tileX, tileZ, "")
			gl.DeleteTexture(tex)
			self.targets[i] = nil
		end
		for i, name in pairs(self.sources) do
			gl.DeleteTexture(name)
			self.sources[i] = nil
		end
	end
	for name, tex in pairs(self.shading) do
		Spring.SetMapShadingTexture(name, "")
		gl.DeleteTexture(tex)
		self.shading[name] = nil
	end
end

return Textures
