@echo off
rem Usage: mapgen_bmp.cmd in.bmp out.bmp --seed 123 --map 8192x8192   (see mapgen_bmp.lua for all options)
where lua >nul 2>nul
if %errorlevel%==0 (
  lua "%~dp0mapgen_bmp.lua" %*
) else if exist "%LOCALAPPDATA%\Programs\Lua\bin\lua.exe" (
  "%LOCALAPPDATA%\Programs\Lua\bin\lua.exe" "%~dp0mapgen_bmp.lua" %*
) else (
  echo Lua 5.3 or newer was not found. Install it or add lua.exe to PATH.
  exit /b 1
)
