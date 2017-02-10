IF EXIST D2Stats.exe (
	Del D2Stats.exe /Q
)
REM IF EXIST D2Stats-64.exe (
REM 	Del D2Stats-64.exe /Q
REM )
"Assets/Aut2Exe.exe" /in D2Stats.au3 /out D2Stats.exe /icon "Assets/icon.ico" /x86
REM "Assets/Aut2Exe.exe" /in D2Stats.au3 /out D2Stats-64.exe /icon "Assets/icon.ico" /x64