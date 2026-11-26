-- Offline MapGen v2: applies the in-game transform to a BMP image and writes a BMP.
-- Uses the very same transform.lua / generate.lua as the gadget, so a seed gives the same layout as in the game.
--
--   lua mapgen_bmp.lua <in.bmp> <out.bmp> [options]
--
--   --seed N | A-B | A,B,C   seed(s) to render (default 1). Several seeds: {seed} in <out.bmp> is replaced
--                           by the seed, otherwise "_<seed>" is added before the extension.
--   --map WxH               map size in elmos (default: 8 elmos per pixel). The transform depends on the
--                           real map size, so give the size of the map the image belongs to.
--   --layers N              total steps incl. the closing symmetry, 0 = random 1-4 (default 0, like mg_layers)
--   --band N                seam cross-fade half-width in elmos (default 192, like mg_band)
--   --attempt N             chain attempt, as in the infolog line "chain attempt N" (default 0)
--   --nearest               nearest-neighbour sampling instead of bilinear (use for index / type maps)
--   --corners               pixels sit on grid corners (heightmap: width = W/8 + 1) instead of cell centres;
--                           switched on automatically when the width is W/8 + 1
--   --no-half               compute every pixel instead of mirroring the computed half
--   --info                  only print the transform of each seed (needs --map, no image)
--
-- Input: uncompressed BMP, 8 bit (palette), 24 or 32 bit. Output: 24 bit, or 8 bit gray when the input is 8 bit gray.
-- The image has to cover the whole map (pixel centres are spread evenly over W x H).
-- Needs Lua 5.3+.

local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local packageRoot = scriptDir .. "/../"

-- The libraries are written for the game engine and load each other through VFS.Include; provide it here.
VFS = {
	Include = function(path)
		return dofile(packageRoot .. path)
	end,
}

local libDir = "luarules/gadgets/libs/mapgen_v2/"
local probeFile = io.open(packageRoot .. libDir .. "transform.lua", "rb")
if probeFile then
	probeFile:close()
else
	-- running from the map folder instead of the portable package
	libDir = "luarules/gadgets/libs/mapgen/"
end
local Transform = VFS.Include(libDir .. "transform.lua")
local Generate = VFS.Include(libDir .. "generate.lua")

local floor = math.floor

--------------------------------------------------------------------------------
-- command line arguments
--------------------------------------------------------------------------------

-- Prints an optional error message and the usage text (the leading comment block of this file) to stderr,
-- then exits with status 1.
-- message: error text, or nil to print only the usage text
-- Does not return.
local function usage(message)
	if message then
		io.stderr:write("error: " .. message .. "\n\n")
	end
	local scriptFile = io.open(arg[0], "r")
	if scriptFile then
		for line in scriptFile:lines() do
			if not line:match("^%-%-") then
				break
			end
			io.stderr:write((line:gsub("^%-%- ?", "")) .. "\n")
		end
		scriptFile:close()
	end
	os.exit(1)
end

-- options.seeds:     list of seeds to render
-- options.mapWidth/mapHeight: map size in elmos (--map), nil when not given
-- options.interp:    "bilinear" or "nearest" sampling
-- options.corners:   true when forced by --corners, nil = decide from the image size
-- options.half:      mirror the computed half of the image instead of computing every pixel
-- options.info:      only print the transform of each seed
local options = {
	corners = nil,
	seeds = { 1 },
	layers = 0,
	band = 192,
	attempt = 0,
	interp = "bilinear",
	half = true,
}
local positionalArgs = {}
do
	local argIndex = 1
	while argIndex <= #arg do
		local argument = arg[argIndex]

		-- Returns the argument after the current option and skips it; a missing value is a usage error.
		local function nextValue()
			argIndex = argIndex + 1
			if not arg[argIndex] then
				usage("missing value after " .. argument)
			end
			return arg[argIndex]
		end

		if argument == "--seed" then
			-- list of seeds: "A", "A-B" (range) or "A,B,C", mixed
			options.seeds = {}
			for part in nextValue():gmatch("[^,]+") do
				local firstSeed, lastSeed = part:match("^(%d+)%-(%d+)$")
				if firstSeed then
					for seed = tonumber(firstSeed), tonumber(lastSeed) do
						options.seeds[#options.seeds + 1] = seed
					end
				elseif tonumber(part) then
					options.seeds[#options.seeds + 1] = floor(tonumber(part))
				else
					usage("bad seed '" .. part .. "'")
				end
			end
		elseif argument == "--map" then
			local width, height = nextValue():match("^(%d+)[xX](%d+)$")
			if not width then
				usage("--map expects WxH, e.g. 8192x4096")
			end
			options.mapWidth, options.mapHeight = tonumber(width), tonumber(height)
		elseif argument == "--layers" then
			options.layers = floor(tonumber(nextValue()) or 0)
		elseif argument == "--band" then
			options.band = tonumber(nextValue()) or 192
		elseif argument == "--attempt" then
			options.attempt = floor(tonumber(nextValue()) or 0)
		elseif argument == "--nearest" then
			options.interp = "nearest"
		elseif argument == "--corners" then
			options.corners = true
		elseif argument == "--no-half" then
			options.half = false
		elseif argument == "--info" then
			options.info = true
		elseif argument:sub(1, 2) == "--" then
			usage("unknown option " .. argument)
		else
			positionalArgs[#positionalArgs + 1] = argument
		end
		argIndex = argIndex + 1
	end
end
if #positionalArgs < (options.info and 0 or 2) or (not options.info and #positionalArgs == 0) then
	usage()
end
local inputPath, outputPath = positionalArgs[1], positionalArgs[2]

--------------------------------------------------------------------------------
-- BMP reading and writing
--------------------------------------------------------------------------------

-- Reads an uncompressed 8 bit (palette), 24 bit or 32 bit BMP file.
-- path: file to read
-- Returns an image table { w, h, pix, gray }: width and height in pixels, pix = row-major list (row 0 = top,
-- index = pixelY * w + pixelX + 1) of colours packed as 0xRRGGBB, gray = true for an 8 bit image whose palette is gray.
-- Raises an error for anything that is not a supported BMP.
local function readBmp(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("a")
	file:close()
	if data:sub(1, 2) ~= "BM" then
		error(path .. " is not a BMP file")
	end

	-- file header: offset of the pixel data; info header: its size, then the image properties
	local dataOffset = string.unpack("<I4", data, 11)
	local headerSize = string.unpack("<I4", data, 15)
	if headerSize < 40 then
		error("unsupported BMP header (OS/2 style)")
	end
	-- the skipped fields are: planes, image size, horizontal and vertical resolution
	local width, height, _, bitsPerPixel, compression, _, _, _, paletteColors =
		string.unpack("<i4i4I2I2I4I4i4i4I4", data, 19)
	if compression ~= 0 and not (compression == 3 and bitsPerPixel == 32) then
		error("compressed BMPs are not supported (compression " .. compression .. ")")
	end
	if bitsPerPixel ~= 8 and bitsPerPixel ~= 24 and bitsPerPixel ~= 32 then
		error("only 8, 24 and 32 bit BMPs are supported (this one is " .. bitsPerPixel .. ")")
	end
	local topDown = height < 0
	height = math.abs(height)

	-- 8 bit images index a palette of blue, green, red, unused entries
	local palette
	local gray = false
	if bitsPerPixel == 8 then
		local paletteSize = paletteColors ~= 0 and paletteColors or 256
		palette = {}
		gray = true
		for paletteIndex = 0, paletteSize - 1 do
			local blue, green, red = string.byte(
				data,
				14 + headerSize + paletteIndex * 4 + 1,
				14 + headerSize + paletteIndex * 4 + 3
			)
			palette[paletteIndex] = (red << 16) | (green << 8) | blue
			if red ~= green or green ~= blue then
				gray = false
			end
		end
	end

	-- each stored row is padded to a multiple of 4 bytes; rows are stored bottom-up unless the height is negative
	local rowBytes = ((width * bitsPerPixel + 31) // 32) * 4
	local pixels = {}
	for pixelY = 0, height - 1 do
		local fileRow = topDown and pixelY or (height - 1 - pixelY)
		local rowOffset = dataOffset + fileRow * rowBytes
		for pixelX = 0, width - 1 do
			local color
			if bitsPerPixel == 8 then
				color = palette[string.byte(data, rowOffset + pixelX + 1)] or 0
			else
				local bytesPerPixel = bitsPerPixel // 8
				local blue, green, red = string.byte(
					data,
					rowOffset + pixelX * bytesPerPixel + 1,
					rowOffset + pixelX * bytesPerPixel + 3
				)
				color = (red << 16) | (green << 8) | blue
			end
			pixels[pixelY * width + pixelX + 1] = color
		end
	end
	return { w = width, h = height, pix = pixels, gray = gray }
end

-- Writes an image as an uncompressed BMP: 8 bit with a gray palette for gray images, 24 bit otherwise.
-- path: file to write
-- image: table in the format returned by readBmp
-- Returns nothing.
local function writeBmp(path, image)
	local width, height, pixels = image.w, image.h, image.pix
	local bitsPerPixel = image.gray and 8 or 24
	local rowBytes = ((width * bitsPerPixel + 31) // 32) * 4
	local paletteBytes = image.gray and 1024 or 0
	local dataOffset = 54 + paletteBytes

	-- file header + info header (+ palette)
	local parts = {}
	parts[1] = "BM" .. string.pack("<I4I4I4I4", dataOffset + rowBytes * height, 0, dataOffset, 40)
		.. string.pack(
			"<i4i4I2I2I4I4i4i4I4I4",
			width, height, 1, bitsPerPixel, 0, rowBytes * height, 2835, 2835, image.gray and 256 or 0, 0
		)
	if image.gray then
		local palette = {}
		for level = 0, 255 do
			palette[#palette + 1] = string.char(level, level, level, 0)
		end
		parts[#parts + 1] = table.concat(palette)
	end

	-- pixel rows, bottom row first, each padded to a multiple of 4 bytes
	local rowPadding = string.rep("\0", rowBytes - width * (bitsPerPixel // 8))
	for pixelY = height - 1, 0, -1 do
		local rowChars = {}
		local rowStart = pixelY * width
		for pixelX = 1, width do
			local color = pixels[rowStart + pixelX]
			if image.gray then
				rowChars[pixelX] = string.char(color & 255)
			else
				rowChars[pixelX] = string.char(color & 255, (color >> 8) & 255, (color >> 16) & 255)
			end
		end
		parts[#parts + 1] = table.concat(rowChars) .. rowPadding
	end

	local file = assert(io.open(path, "wb"))
	file:write(table.concat(parts))
	file:close()
end

--------------------------------------------------------------------------------
-- transform
--------------------------------------------------------------------------------

-- Builds the exact pixel mirror of the transform's closing symmetry S (pixel centres are symmetric under S),
-- which lets render() compute only half of the pixels and copy the rest.
-- descriptors: transform descriptors; the first one is the closing symmetry
-- imageWidth, imageHeight: image size in pixels
-- mapWidth, mapHeight: map size in elmos
-- Returns a function (pixelX, pixelY) -> mirrored pixelX, pixelY, or nil when the closing symmetry is not a
-- pixel-exact mirror (e.g. a diagonal on a non-square image or map).
local function mirrorFor(descriptors, imageWidth, imageHeight, mapWidth, mapHeight)
	local first = descriptors[1]
	local kind = first and first.closing
	if kind == "vertical" then
		return function(pixelX, pixelY)
			return imageWidth - 1 - pixelX, pixelY
		end
	elseif kind == "horizontal" then
		return function(pixelX, pixelY)
			return pixelX, imageHeight - 1 - pixelY
		end
	elseif kind == "central" then
		return function(pixelX, pixelY)
			return imageWidth - 1 - pixelX, imageHeight - 1 - pixelY
		end
	elseif kind == "diagonal" and imageWidth == imageHeight and mapWidth == mapHeight then
		if first.angle == math.pi / 4 then
			return function(pixelX, pixelY)
				return pixelY, pixelX
			end
		end
		return function(pixelX, pixelY)
			return imageWidth - 1 - pixelY, imageHeight - 1 - pixelX
		end
	end
end

-- Renders one seed: builds its transform and, unless --info was given, applies it to every pixel of the image.
-- Every output pixel is a weighted mix of "taps": positions in the source map that the transform maps it from.
-- image: input image (format of readBmp)
-- mapWidth, mapHeight: map size in elmos
-- seed: seed to render
-- Returns the output image (same size and format as the input), or nil with --info.
local function render(image, mapWidth, mapHeight, seed)
	local descriptors = Generate.descriptors(seed, mapWidth, mapHeight, {
		layers = options.layers, band = options.band, attempt = options.attempt,
	})
	local mapTransform = Transform.new(descriptors, mapWidth, mapHeight)
	print(string.format(
		"seed %d: %s [%s]", seed, Transform.describe(descriptors), Transform.signature(descriptors)
	))
	if options.info then
		return nil
	end

	local imageWidth, imageHeight, srcPixels = image.w, image.h, image.pix
	local outPixels = {}
	local mirror = options.half and mirrorFor(descriptors, imageWidth, imageHeight, mapWidth, mapHeight) or nil
	local nearest = options.interp == "nearest"

	-- corner-aligned: pixels sit on grid corners (heightmap) instead of cell centres
	local cornerAligned = options.corners
	if cornerAligned == nil then
		cornerAligned = (imageWidth - 1) * 8 == mapWidth and (imageHeight - 1) * 8 == mapHeight
	end
	if cornerAligned then
		print("  corner-aligned samples (heightmap grid)")
	end

	-- Returns the packed colour of a source pixel; coordinates outside the image are clamped to its border.
	local function srcPixelAt(pixelX, pixelY)
		if pixelX < 0 then
			pixelX = 0
		elseif pixelX > imageWidth - 1 then
			pixelX = imageWidth - 1
		end
		if pixelY < 0 then
			pixelY = 0
		elseif pixelY > imageHeight - 1 then
			pixelY = imageHeight - 1
		end
		return srcPixels[pixelY * imageWidth + pixelX + 1]
	end

	-- Returns r, g, b of the source image at the source-map position (srcX, srcZ) in elmos
	-- (nearest pixel or bilinear mix of the four surrounding pixels).
	local function sampleSource(srcX, srcZ)
		-- position in (fractional) source pixel coordinates
		local gridX, gridZ
		if cornerAligned then
			gridX, gridZ = srcX / mapWidth * (imageWidth - 1), srcZ / mapHeight * (imageHeight - 1)
		else
			gridX, gridZ = srcX / mapWidth * imageWidth - 0.5, srcZ / mapHeight * imageHeight - 0.5
		end
		if nearest then
			local color = srcPixelAt(floor(gridX + 0.5), floor(gridZ + 0.5))
			return (color >> 16) & 255, (color >> 8) & 255, color & 255
		end
		local pixelX, pixelZ = floor(gridX), floor(gridZ)
		local fracX, fracZ = gridX - pixelX, gridZ - pixelZ
		local color00 = srcPixelAt(pixelX, pixelZ)
		local color10 = srcPixelAt(pixelX + 1, pixelZ)
		local color01 = srcPixelAt(pixelX, pixelZ + 1)
		local color11 = srcPixelAt(pixelX + 1, pixelZ + 1)
		local weight00 = (1 - fracX) * (1 - fracZ)
		local weight10 = fracX * (1 - fracZ)
		local weight01 = (1 - fracX) * fracZ
		local weight11 = fracX * fracZ
		local red = ((color00 >> 16) & 255) * weight00 + ((color10 >> 16) & 255) * weight10
			+ ((color01 >> 16) & 255) * weight01 + ((color11 >> 16) & 255) * weight11
		local green = ((color00 >> 8) & 255) * weight00 + ((color10 >> 8) & 255) * weight10
			+ ((color01 >> 8) & 255) * weight01 + ((color11 >> 8) & 255) * weight11
		local blue = (color00 & 255) * weight00 + (color10 & 255) * weight10
			+ (color01 & 255) * weight01 + (color11 & 255) * weight11
		return red, green, blue
	end

	-- Rounds a colour channel and limits it to 0..255.
	local function clampChannel(value)
		value = floor(value + 0.5)
		return value < 0 and 0 or (value > 255 and 255 or value)
	end

	for pixelY = 0, imageHeight - 1 do
		-- output position of this row in elmos
		local outZ = cornerAligned
			and (pixelY / (imageHeight - 1) * mapHeight)
			or ((pixelY + 0.5) / imageHeight * mapHeight)
		for pixelX = 0, imageWidth - 1 do
			local pixelIndex = pixelY * imageWidth + pixelX + 1
			local mirrorX, mirrorY
			if mirror then
				mirrorX, mirrorY = mirror(pixelX, pixelY)
			end
			if mirrorX and (mirrorY * imageWidth + mirrorX + 1) < pixelIndex then
				-- the mirrored pixel was already computed earlier in the scan
				outPixels[pixelIndex] = outPixels[mirrorY * imageWidth + mirrorX + 1]
			else
				-- the taps give the source-map positions (tapsX[k], tapsZ[k]) and weights that make up this pixel
				local tapCount, tapsX, tapsZ, tapWeights = mapTransform:taps(
					cornerAligned
						and (pixelX / (imageWidth - 1) * mapWidth)
						or ((pixelX + 0.5) / imageWidth * mapWidth),
					outZ
				)
				local red, green, blue = 0, 0, 0
				if tapCount == 1 then
					red, green, blue = sampleSource(tapsX[1], tapsZ[1])
				else
					for tapIndex = 1, tapCount do
						local tapRed, tapGreen, tapBlue = sampleSource(tapsX[tapIndex], tapsZ[tapIndex])
						red = red + tapWeights[tapIndex] * tapRed
						green = green + tapWeights[tapIndex] * tapGreen
						blue = blue + tapWeights[tapIndex] * tapBlue
					end
				end
				outPixels[pixelIndex] = (clampChannel(red) << 16) | (clampChannel(green) << 8) | clampChannel(blue)
			end
		end
	end
	return { w = imageWidth, h = imageHeight, pix = outPixels, gray = image.gray }
end

--------------------------------------------------------------------------------
-- main
--------------------------------------------------------------------------------

local image
if options.info then
	if not options.mapWidth then
		usage("--info needs --map WxH")
	end
else
	image = readBmp(inputPath)
end

local mapWidth, mapHeight = options.mapWidth, options.mapHeight
if not mapWidth then
	mapWidth, mapHeight = image.w * 8, image.h * 8
	print(string.format(
		"map size not given: assuming 8 elmos per pixel = %dx%d (use --map WxH for the real size)", mapWidth, mapHeight
	))
end
if mapWidth % 512 ~= 0 or mapHeight % 512 ~= 0 then
	print("warning: BAR maps are multiples of 512 elmos, " .. mapWidth .. "x" .. mapHeight .. " is not")
end

-- Returns the output file name for a seed: the plain output path for a single seed; for several seeds "{seed}"
-- in the path is replaced by the seed, otherwise "_<seed>" is added before the extension.
local function outputPathFor(seed)
	if #options.seeds == 1 then
		return outputPath
	end
	if outputPath:find("{seed}", 1, true) then
		return (outputPath:gsub("{seed}", tostring(seed)))
	end
	local stem, extension = outputPath:match("^(.*)(%.[^./\\]+)$")
	return (stem or outputPath) .. "_" .. seed .. (extension or ".bmp")
end

for _, seed in ipairs(options.seeds) do
	local startTime = os.clock()
	local result = render(image, mapWidth, mapHeight, seed)
	if result then
		local seedPath = outputPathFor(seed)
		writeBmp(seedPath, result)
		print(string.format("  wrote %s (%dx%d, %.1fs)", seedPath, result.w, result.h, os.clock() - startTime))
	end
end
