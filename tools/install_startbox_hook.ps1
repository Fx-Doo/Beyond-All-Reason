# Installs the MapGen v2 hook into BAR's startbox_utilities.lua (idempotent, keeps a backup).
#
#   powershell -ExecutionPolicy Bypass -File install_startbox_hook.ps1 [-Bar "C:\path\to\BAR.sdd"] [-Uninstall]
#
# Why: BAR's gadgets and widgets each load their own copy of startbox_utilities.lua, so one widget cannot patch the copy
# the start box overlay uses. The hook makes every copy apply the start boxes MapGen v2 publishes (rules param
# "mapgen_startboxes"). Without that param it does nothing. Re-run it after BAR updates overwrite the file.
param(
	[string]$Bar = "C:\Program Files\Beyond-All-Reason\data\games\BAR.sdd",
	[switch]$Uninstall
)

$file = Join-Path $Bar "luarules\gadgets\include\startbox_utilities.lua"
$backup = "$file.mapgen_backup"
if (-not (Test-Path $file)) { Write-Error "not found: $file"; exit 1 }
$text = [IO.File]::ReadAllText($file)

if ($Uninstall) {
	if (Test-Path $backup) { Copy-Item $backup $file -Force; Write-Host "restored $file from backup" } else { Write-Host "no backup found" }
	exit 0
}
if ($text.Contains("MapGen v2 hook")) { Write-Host "hook already installed"; exit 0 }

$anchor = 'local PolygonLib = require("common/lib_polygon")'
$pos = $text.IndexOf($anchor)
if ($pos -lt 0) { Write-Error "anchor line not found, BAR's file changed; the hook needs updating"; exit 1 }

$hook = @'
-- MapGen v2 hook: every file that includes this module (gadgets and widgets alike) parses its own copy, so patching
-- one copy from a widget never reaches the start box overlay. When MapGen v2 has published new start boxes
-- (rules param "mapgen_startboxes") each copy applies them itself. No param = no change.
do
	local baseParse = ParseBoxes
	local mapgenLib, mapgenEntries, mapgenText
	ParseBoxes = function()
		local config, source, explicit = baseParse()
		local text = Spring.GetGameRulesParam and Spring.GetGameRulesParam("mapgen_startboxes")
		if config and text and text ~= "" then
			if text ~= mapgenText then
				mapgenText = text
				mapgenLib, mapgenEntries = nil, nil
				for _, path in ipairs({ "luarules/gadgets/libs/mapgen_v2/startboxes.lua", "luarules/gadgets/libs/mapgen/startboxes.lua" }) do
					local ok, lib = pcall(VFS.Include, path)
					if ok and type(lib) == "table" and lib.applyToConfig then
						mapgenLib = lib
						mapgenEntries = lib.deserialize(text)
						break
					end
				end
			end
			if mapgenLib then
				local ok, err = pcall(mapgenLib.applyToConfig, config, mapgenEntries, Game.mapSizeZ - 1)
				if not ok then
					Spring.Echo("[MapGen v2] start box hook failed: " .. tostring(err))
				end
			end
		end
		return config, source, explicit
	end
end

'@
if (-not (Test-Path $backup)) { Copy-Item $file $backup }
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$hook = $hook -replace "`r?`n", $nl
[IO.File]::WriteAllText($file, $text.Substring(0, $pos) + $hook + $text.Substring($pos), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "hook installed in $file (backup: $backup)"
