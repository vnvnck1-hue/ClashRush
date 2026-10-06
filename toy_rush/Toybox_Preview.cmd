@echo off
start "" /D "%~dp0" "%~dp0build\CodexLookPreview.exe" --path "%~dp0." -- --codex-look=toybox
