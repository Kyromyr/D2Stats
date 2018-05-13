IF EXIST D2Stats.exe (
	Del D2Stats.exe /Q
)
"Assets/Aut2Exe.exe" /in D2Stats.au3 /out D2Stats.exe /icon "Assets/icon.ico" /x86
IF EXIST D2Stats.exe (
	signtool sign /a D2Stats.exe
)