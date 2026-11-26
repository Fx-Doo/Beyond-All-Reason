-- OPTIONAL. Paste these entries into the `options` table of BAR.sdd/modoptions.lua if you want to set the
-- seed and friends from the lobby / "Advanced options". The gadget works without them (transform ON, random seed).
-- You can also set them by hand in a start script's [modoptions] block (mg_seed=12345;).
--
-- Each entry is one modoption; all of them are shown in the "options_experimental" section:
--   mg_mode      on / off switch for the whole transform
--   mg_seed      seed of the transform (0 = random each game)
--   mg_layers    number of composed transform steps (0 = random 1-4)
--   mg_band      half-width of the cross-fade around transform seams, in elmos
--   mg_metal     how the metal is carried over (spot stamping and/or resampling, normalised or not)
--   mg_textures  rebuild the map textures on the GPU so they follow the terrain

	{
		key = "mg_mode",
		name = "MapGen v2 transform",
		desc = "Apply a seeded symmetry/kaleidoscope transform to the terrain, metal, features, type map, grass and "
			.. "textures.",
		type = "list",
		def = "on",
		section = "options_experimental",
		items = {
			{ key = "on", name = "On", desc = "Transform the map" },
			{ key = "off", name = "Off", desc = "Play the map unchanged" },
		},
	},
	{
		key = "mg_seed",
		name = "MapGen v2 seed",
		desc = "0 = random seed each game. The seed is printed in the infolog as '[MapGen v2] seed N: ...'.",
		type = "number",
		def = 0,
		min = 0,
		max = 2147483646,
		step = 1,
		section = "options_experimental",
	},
	{
		key = "mg_layers",
		name = "MapGen v2 transform steps",
		desc = "Total number of composed steps, the closing symmetry included. 0 = random 1-4.",
		type = "number",
		def = 0,
		min = 0,
		max = 6,
		step = 1,
		section = "options_experimental",
	},
	{
		key = "mg_band",
		name = "MapGen v2 seam blend (elmos)",
		desc = "Half-width of the cross-fade around transform seams.",
		type = "number",
		def = 192,
		min = 0,
		max = 1024,
		step = 16,
		section = "options_experimental",
	},
	{
		key = "mg_metal",
		name = "MapGen v2 metal",
		desc = "Spots: every metal spot keeps its exact shape wherever the transform shows it. "
			.. "Spots + normalize additionally scales all metal so the map keeps its original total. "
			.. "Normalize / Raw resample the metal grid.",
		type = "list",
		def = "spots_normalize",
		section = "options_experimental",
		items = {
			{
				key = "spots_normalize",
				name = "Spots + normalize",
				desc = "Spots stamped from the source, then scaled so the total metal stays the original",
			},
			{
				key = "spots",
				name = "Spots",
				desc = "Spots stamped unchanged (more copies = more metal)",
			},
			{
				key = "normalize",
				name = "Normalize",
				desc = "Resampled grid, original total",
			},
			{
				key = "raw",
				name = "Raw",
				desc = "Resampled grid as is",
			},
		},
	},
	{
		key = "mg_textures",
		name = "MapGen v2 textures",
		desc = "Rebuild diffuse/minimap/shading textures on the GPU so they follow the terrain. Off = terrain only.",
		type = "list",
		def = "on",
		section = "options_experimental",
		items = {
			{ key = "on", name = "On", desc = "Textures follow the transform" },
			{ key = "off", name = "Off", desc = "Keep the original textures" },
		},
	},
