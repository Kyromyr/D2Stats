#RequireAdmin
#include <ProcessCall.au3>
#include <Security.au3>
#include <WinAPI.au3>

If IsAdmin() = False Then
	MsgBox(0, "", "Admin rights needed!")
	Exit
EndIf
$version = "0.3.0.3 - [26.01.2017]"

Global $gui_event_close = -3
Global $pid, $__dll_kernel32, $diablo_memhandle
Global $ptr_statlist
Global $d2client = 1873477632

Func _readd2memory($ahandle, $address, $format = "dword", $debugenabled = False, $hdll = "kernel32.dll")
	Local $v_buffer = DllStructCreate($format)
	Local $result = readprocessmemory($ahandle, $address, DllStructGetPtr($v_buffer), DllStructGetSize($v_buffer), $hdll)
	Local $temp = DllStructGetData($v_buffer, 1)
	If $debugenabled Then
		ConsoleWrite(@CRLF & $pid & " <--- pID of process." & @CRLF)
		ConsoleWrite($ahandle & " <--- Handle to process." & @CRLF)
		ConsoleWrite($format & " <--- DllStruct of format." & @CRLF)
		ConsoleWrite($result & " <--- Result of ReadprocessMemory (1 = success, 0 = failure)." & @CRLF)
		ConsoleWrite($temp & " <--- Memory Read." & @CRLF)
	EndIf
	Return $temp
EndFunc
Func readprocessmemory($hprocess, $pbaseaddress, $pbuffer, $isize, $hdll = "kernel32.dll")
	If $hprocess <> 0 Then
		Local $aresult = DllCall($__dll_kernel32, "bool", "ReadProcessMemory", "handle", $hprocess, "ptr", $pbaseaddress, "ptr", $pbuffer, "ulong_ptr", $isize, "ulong_ptr*", 0)
		Return $aresult[0]
	Else
		Return 0
	EndIf
EndFunc
Func setprivilege($privilege, $enable)
	Local $htoken = _security__openthreadtokenex(BitOR($token_adjust_privileges, $token_query))
	If @error Then Return SetError(@error, @extended, 0)
	_security__setprivilege($htoken, $privilege, $enable)
EndFunc
Func opensecureprocess($pid, $rights)
	If NOT ProcessExists($pid) Then Return False
	$process = _winapi_openprocess($rights, False, $pid, True)
	If $process Then
		Return $process
	EndIf
	Local $process
	Local $dacl = DllStructCreate("ptr")
	Local $secdesc = DllStructCreate("ptr")
	Local $dacl_target = DllStructCreate("ptr")
	Local $secdesc_target = DllStructCreate("ptr")
	If (getsecurityinfo(_winapi_getcurrentprocess(), $se_kernel_object, $dacl_security_information, 0, 0, DllStructGetPtr($dacl, 1), 0, DllStructGetPtr($secdesc, 1)) <> $error_success) Then
		Return False
	EndIf
	$process = _winapi_openprocess(BitOR($write_dac, $read_control), 0, $pid)
	If NOT $process Then
		_winapi_localfree($secdesc)
		Return False
	EndIf
	If (getsecurityinfo($process, $se_kernel_object, $dacl_security_information, 0, 0, DllStructGetPtr($dacl_target, 1), 0, DllStructGetPtr($secdesc_target, 1)) <> $error_success) Then
		Return False
	EndIf
	If (setsecurityinfo($process, $se_kernel_object, BitOR($dacl_security_information, $unprotected_dacl_security_information), 0, 0, DllStructGetData($dacl, 1), 0) <> $error_success) Then
		_winapi_localfree($secdesc)
		Return False
	EndIf
	_winapi_localfree($secdesc)
	_winapi_closehandle($process)
	$hproc = _winapi_openprocess($rights, False, $pid, True)
	If NOT $hproc Then
		Return False
	EndIf
	If (setsecurityinfo($hproc, $se_kernel_object, BitOR($dacl_security_information, $unprotected_dacl_security_information), 0, 0, DllStructGetData($dacl_target, 1), 0) <> $error_success) Then
		_winapi_localfree($secdesc_target)
		Return False
	EndIf
	_winapi_localfree($secdesc_target)
	Return $hproc
EndFunc
Func _memoryreadwidestring($iv_address, $sv_type = "wchar[10]")
	Return _readd2memory($diablo_memhandle, $iv_address, $sv_type, False, $__dll_kernel32)
EndFunc

local $cache_stats[2][1024]

func updateStatValueMem($ivector)
	local $istatlist = 0
	local $ptr = -1;$ptr_statlist
	
	Local $ret, $statcount, $ptr_stats, $statindex, $startcount = 0
	If $ptr = -1 Then
		$ptr = _readd2memory($diablo_memhandle, 92 + _readd2memory($diablo_memhandle, $d2client + 1162236, "dword", False, $__dll_kernel32), "dword", False, $__dll_kernel32)
	EndIf
	For $i = 1 To $istatlist
		$ptr = _readd2memory($diablo_memhandle, $ptr + 60, "dword", False, $__dll_kernel32)
	Next
	Switch $ivector
		Case 0
			$ptr_stats = _readd2memory($diablo_memhandle, $ptr + 36, "dword", False, $__dll_kernel32)
			$statcount = _readd2memory($diablo_memhandle, $ptr + 40, "word", False, $__dll_kernel32)
			$startcount = 0
		Case 1
			$ptr_stats = _readd2memory($diablo_memhandle, $ptr + 72, "dword", False, $__dll_kernel32)
			$statcount = _readd2memory($diablo_memhandle, $ptr + 76, "word", False, $__dll_kernel32)
			$startcount = 5
		Case 2
			$ptr_stats = _readd2memory($diablo_memhandle, $ptr + 80, "dword", False, $__dll_kernel32)
	EndSwitch
	$statcount -= 1
	Local $szstruct = "word wSubIndex;word wStatIndex;int dwStatValue;", $finalstruct
	For $i = 0 To $statcount
		$finalstruct &= $szstruct
	Next
	Local $statstruct = DllStructCreate($finalstruct)
	Local $isize = DllStructGetSize($statstruct)
	Local $iptr = DllStructGetPtr($statstruct)
	readprocessmemory($diablo_memhandle, $ptr_stats, $iptr, $isize, $__dll_kernel32)
	For $i = $startcount To $statcount
		$statindex = DllStructGetData($statstruct, 2 + (3 * $i))
		if ($statindex > 1023) then
			ContinueLoop ; Should never happen, not sure why it does
		endif
		$ret = DllStructGetData($statstruct, 3 + (3 * $i))
		Switch $statindex
			Case 6 To 11
				$cache_stats[$ivector][$statindex] += $ret / 256
			Case Else
				$cache_stats[$ivector][$statindex] += $ret
		EndSwitch
	Next
endfunc

func updateStatValue()
	for $i = 0 to 1023
		$cache_stats[0][$i] = 0
		$cache_stats[1][$i] = 0
	next
	
	updateStatValueMem(0)
	updateStatValueMem(1)
endfunc

Func getStatValue($istat)
	local $ivector = $istat < 4 ? 0 : 1
	local $val = $cache_stats[$ivector][$istat]
	return $val ? $val : 0
EndFunc

Func game_detectingame()
	If _readd2memory($diablo_memhandle, $d2client + 1162236, "dword", False, $__dll_kernel32) > 0 Then
		Return True
	Else
		Return False
	EndIf
EndFunc

Func item_getilvl()
	Local $v_buffer = DllStructCreate("dword")
	readprocessmemory($diablo_memhandle, $d2client + 1162296, DllStructGetPtr($v_buffer), DllStructGetSize($v_buffer), $__dll_kernel32)
	$ptr1 = DllStructGetData($v_buffer, 1)
	readprocessmemory($diablo_memhandle, $ptr1 + 20, DllStructGetPtr($v_buffer), DllStructGetSize($v_buffer), $__dll_kernel32)
	$ptr2 = DllStructGetData($v_buffer, 1)
	readprocessmemory($diablo_memhandle, $ptr2 + 44, DllStructGetPtr($v_buffer), DllStructGetSize($v_buffer), $__dll_kernel32)
	Return DllStructGetData($v_buffer, 1)
EndFunc

Func delccode(Const ByRef $szstring)
	If StringInStr($szstring, "?c") > 0 Then
		Local $sz_split
		$sz_split = StringSplit($szstring, "?c", 1)
		Local $nmsg
		For $i = 1 To $sz_split[0]
			$nmsg &= StringTrimLeft($sz_split[$i], 1)
		Next
		Return $nmsg
	ElseIf StringInStr($szstring, "ÿc") > 0 Then
		Local $sz_split
		$sz_split = StringSplit($szstring, "ÿc", 1)
		Local $nmsg
		For $i = 1 To $sz_split[0]
			$nmsg &= StringTrimLeft($sz_split[$i], 1)
		Next
		Return $nmsg
	Else
		Return $szstring
	EndIf
EndFunc

Func gettext($bitems = False)
	If $bitems Then
		If item_getilvl() = 0 Then Return -1
		Local $szmsg, $amsg, $rmsg
		$szmsg = _memoryreadwidestring(1872404056, "wchar[1000]")
		While StringLen($szmsg) < 5
			$szmsg = _memoryreadwidestring(1872404056, "wchar[1000]")
			Sleep(10)
		WEnd
	Else
		Local $szmsg, $amsg, $rmsg
		$szmsg = _memoryreadwidestring(1872404056, "wchar[1000]")
		For $i = 0 To 5
			$szmsg = _memoryreadwidestring(1872404056, "wchar[1000]")
			Sleep(10)
			If StringLen($szmsg) < 4 Then ExitLoop
		Next
	EndIf
	$amsg = StringSplit($szmsg, @CRLF, 2)
	If NOT IsArray($amsg) Then Return $szmsg
	_arrayreverse($amsg)
	For $i = 0 To UBound($amsg) - 1
		$rmsg &= $amsg[$i] & @CR
	Next
	Return $rmsg
EndFunc

local $guiItems[128][4]
$guiItems[0][0] = 0

local $groupX
func newlabel($text, $i)
	local $width = 8*(StringLen($text)+3)
	return GUICtrlCreateLabel($text, $groupX-$width/2, 4+15*$i, $width, 15, 0x1)
endfunc

func newitem($statid, $i, $text, $tip = "", $clr = -1, $updatefunc = 0)
	local $arrPos = $guiItems[0][0] + 1
	$guiItems[$arrPos][0] = $statid
	$guiItems[$arrPos][1] = $text
	$guiItems[$arrPos][2] = newlabel($text, $i)
	updateitem($arrPos) ; Calling it before setting updatefunc stops haste values from showing -100% until updated
	$guiItems[$arrPos][3] = $updatefunc
	if ($tip <> "") then
		GUICtrlSetTip(-1, $tip)
	endif
	if ($clr >= 0) then
		GUICtrlSetColor(-1, $clr)
	endif
	$guiItems[0][0] = $arrPos
endfunc

func updateitem($guiItem)
	local $val = getStatValue($guiItems[$guiItem][0])
	local $func = $guiItems[$guiItem][3]
	if ($func) then
		$val = Call($func, $val)
	endif
	
	local $text = StringReplace($guiItems[$guiItem][1], "*", $val)
	GUICtrlSetData($guiItems[$guiItem][2], $text)
endfunc

func iasfunc($val)
	return $val + getStatValue(68) - 100
endfunc
func fhrfunc($val)
	return $val + getStatValue(69) - 100
endfunc
func frwfunc($val)
	return $val + getStatValue(67) - 100
endfunc

#Region GUI
	local $clr_red	= 0xFF0000
	local $clr_blue	= 0x0066CC
	local $clr_gold	= 0x808000
	local $clr_green= 0x008000
	local $clr_purp	= 0xFF00FF

	GUICreate("D2Stats " & $version, 500, 250, 329, 143)
	GUISetFont(9, 0, 0, "Courier New")
	
	$btnread = GUICtrlCreateButton("Read data", 8, 192, 105, 25)
	$btnabout = GUICtrlCreateButton("About", 8, 216, 105, 25)
	
	local $groupX1 = 42
	local $groupX2 = 80+$groupX1
	local $groupX3 = 80+$groupX2
	local $groupX4 = 80+$groupX3
	local $groupX5 = 80+$groupX4
	local $groupX6 = 80+$groupX5
	
	local $y = 0
	
	$groupX = $groupX1
	newlabel("Base stats", 0)
	newitem(000, 1, "* Str", "Strength")
	newitem(002, 2, "* Dex", "Dexterity")
	newitem(003, 3, "* Vit", "Vitality")
	newitem(001, 4, "* Ene", "Energy")
	
	newitem(080, 6, "*% MF", "Magic Find")
	newitem(079, 7, "*% GF", "Gold Find")
	newitem(085, 8, "*% Exp", "Experience")
	newitem(183, 9, "* CP", "Crafting Points")
	newitem(185, 10, "* Sigs", "Signets of Learning")
	newitem(479, 11, "* M.Skill", "Maximum Skill Level")
	
	$groupX = $groupX2
	newitem(025, 0, "*% EWD", "Enchanced Weapon Damage")
	newitem(136, 1, "*% CB", "Crushing Blow")
	newitem(135, 2, "*% OW", "Open Wounds")
	newitem(141, 3, "*% DS", "Deadly Strike")
	newitem(119, 4, "*% AR", "Attack Rating")
	newitem(489, 5, "* TTAD", "Target Takes Additional Damage")
	
	newitem(093, 7, "*% IAS", "Increased Attack Speed", -1, "iasfunc")
	newitem(105, 8, "*% FCR", "Faster Cast Rate")
	newitem(099, 9, "*% FHR", "Faster Hit Recovery", -1, "fhrfunc")
	newitem(102, 10, "*% FBR", "Faster Block Rate", -1, "fhrfunc")
	newitem(096, 11, "*% FRW", "Faster Run/Walk", -1, "frwfunc")
	
	$groupX = $groupX3
	newitem(076, 0, "*% Life", "Max Life")
	newitem(077, 1, "*% Mana", "Max Mana")
	
	newitem(171, 2, "*% TCD", "Total Character Defense")
	newitem(034, 3, "* DR", "Flat damage reduction")
	newitem(035, 4, "* MDR", "Flat magic damage reduction")
	newitem(036, 5, "*% DR", "Percent damage reduction")
	newitem(037, 6, "*% MR", "Magic Resist")
	
	newitem(339, 7, "*% Avoid")
	newitem(338, 8, "*% Dodge", "Avoid melee attack")
	
	newitem(150, 10, "*% ST", "Slow Target")
	newitem(363, 11, "*% SA", "Slow Attacker")
	newitem(376, 12, "*% SMT", "Slow Melee Target")
	
	newitem(164, 13, "*% UA", "Uninterruptable Attack")
	newitem(165, 14, "*% CLR", "Curse Length Reduction")
	newitem(166, 15, "*% PLR", "Poison Length Reduction")
	
	$groupX = $groupX4
	newlabel("Absorb", 0)
	newitem(142, 1, "*%", "Percent Fire Absorb", $clr_red)
	newitem(143, 2, "*", "Flat Fire Absorb", $clr_red)
	newitem(148, 3, "*%", "Percent Cold Absorb", $clr_blue)
	newitem(149, 4, "*", "Flat Cold Absorb", $clr_blue)
	newitem(144, 5, "*%", "Percent Light Absorb", $clr_gold)
	newitem(145, 6, "*", "Flat Light Absorb", $clr_gold)
	
	newitem(060, 7, "*% LL", "Life Leech")
	newitem(086, 8, "* LaeK", "Life after each Kill")
	newitem(208, 9, "* LoS", "Life on Striking")
	newitem(210, 10, "* LoSiM", "Life on Striking in Melee")
	
	newitem(062, 12, "*% ML", "Mana Leech")
	newitem(138, 13, "* MaeK", "Mana after each Kill")
	newitem(209, 14, "* MoS", "Mana on Striking")
	newitem(211, 15, "* MoSiM", "Mana on Striking in Melee")
	
	$groupX = $groupX5
	newlabel("Resists", 0)
	newitem(039, 1, "*%", "", $clr_red)
	newitem(043, 2, "*%", "", $clr_blue)
	newitem(041, 3, "*%", "", $clr_gold)
	newitem(045, 4, "*%", "", $clr_green)
	
	newlabel("Spell damage", 5)
	newitem(329, 6, "*%", "", $clr_red)
	newitem(331, 7, "*%", "", $clr_blue)
	newitem(330, 8, "*%", "", $clr_gold)
	newitem(332, 9, "*%", "", $clr_green)
	newitem(377, 10, "*%", "", $clr_purp)
	
	newlabel("Pierce", 11)
	newitem(333, 12, "*%", "", $clr_red)
	newitem(335, 13, "*%", "", $clr_blue)
	newitem(334, 14, "*%", "", $clr_gold)
	newitem(336, 15, "*%", "", $clr_green)
	
	$groupX = $groupX6
	newlabel("Minions", 0)
	newitem(444, 1, "*% Life")
	newitem(470, 2, "*% Damage")
	newitem(487, 3, "*% Resist")
	newitem(500, 4, "*% AR", "Attack Rating")
	
	newitem(278, 6, "* SF", "Flat Strength Factor")
	newitem(485, 7, "* EF", "Flat Energy Factor")
	newitem(488, 8, "*% EF", "Percent Energy Factor")
	newitem(431, 9, "*% PSD", "Poison Skill Duration")
	newitem(409, 10, "*% Buff.Dur", "Buff/Debuff/Cold Skill Duration")
	newitem(027, 11, "*% Mana.Reg", "Mana Regeneration")
	
	GUISetState(@SW_SHOW)
#EndRegion
$__dll_kernel32 = DllOpen("Kernel32.dll")
OnAutoItExitRegister("_Exit")
HotKeySet("+{INS}", "printstatvalue")
HotKeySet("{INS}", "copyitem")
HotKeySet("{DEL}", "copyilvl")
local $hotkeyactive = 1
While 1
	$msg = GUIGetMsg()
	Select 
		Case $msg = $gui_event_close
			ExitLoop
		Case $msg = $btnread
			readchardata()
		Case $msg = $btnabout
			MsgBox(4096 + 64, "About", "D2Stats " & $version & " made by Wojen. Using Shaggi's offsets. Press INSERT to copy an item to clipboard, and DELETE to display its ilvl.")
	EndSelect
WEnd
func _Exit()
	if ($__dll_kernel32) then
		DllClose($__dll_kernel32)
	endif
endfunc
Func readchardata()
	$pid = WinGetProcess("[CLASS:Diablo II]")
	$goodtogo = False
	If $pid = -1 Then
		MsgBox(4096, "Error", "Run Diablo 2 first!")
	Else
		$diablo_memhandle = opensecureprocess($pid, 2035711)
		setprivilege("SeDebugPrivilige", True)
		$goodtogo = True
		$ptr_statlist = _readd2memory($diablo_memhandle, 92 + _readd2memory($diablo_memhandle, $d2client + 1162236, "dword", False, $__dll_kernel32), "dword", False, $__dll_kernel32)
	EndIf
	If $goodtogo = True Then
		updateStatValue()
		local $arrItems = $guiItems[0][0]
		for $i = 1 to $arrItems
			updateitem($i)
		next
	EndIf
EndFunc
func hotkeycheck()
	if (not $hotkeyactive) then
		return 0
	endif
	
	if (WinActive("[CLASS:Diablo II]")) then
		return 1
	endif
	
	$hotkeyactive = 0
	ControlSend("[ACTIVE]", "", "", @HotKeyPressed)
	$hotkeyactive = 1
	return 0
endfunc
Func copyitem()
	if (not hotkeycheck()) then
		return
	endif
	$pid = WinGetProcess("Diablo II")
	$diablo_memhandle = opensecureprocess($pid, 2035711)
	setprivilege("SeDebugPrivilige", True)
	If game_detectingame() = False Then
		return
		MsgBox(4096, "Error", "Are you ingame?")
	EndIf
	Local $sztext, $sz_split
	$sztext = gettext(True)
	If StringLen($sztext) < 5 Then Return 
	$sz_split = StringSplit($sztext, @CR)
	Local $szitem
	$szitem = delccode($sz_split[1]) & @CRLF
	For $i = 2 To $sz_split[0]
		If StringInStr($sz_split[$i], "ÿc") > 0 Then
			$szitem &= delccode($sz_split[$i]) & @CRLF
		Else
			$szitem &= $sz_split[$i] & @CRLF
		EndIf
	Next
	ClipPut($szitem)
	TrayTip("", "Clipboard item data: " & delccode($sz_split[1]), 10)
	Sleep(2000)
EndFunc
func copyilvl()
	if (not hotkeycheck()) then
		return
	endif
	$pid = WinGetProcess("Diablo II")
	$diablo_memhandle = opensecureprocess($pid, 2035711)
	setprivilege("SeDebugPrivilige", True)
	If game_detectingame() = False Then
		return
		MsgBox(4096, "Error", "Are you ingame?")
	EndIf
	local $ilvl = item_getilvl()
	if ($ilvl) then
		ProcCall($pid, "stdcall", $d2client + 0x7D850, "void", "wchar*", "ilvl: " & $ilvl, "int", 0)
	endif
endfunc
Func printstatvalue()
	if (not hotkeycheck()) then
		return
	endif
	$pid = WinGetProcess("Diablo II")
	$diablo_memhandle = opensecureprocess($pid, 2035711)
	setprivilege("SeDebugPrivilige", True)
	If game_detectingame() = False Then
		return
		MsgBox(4096, "Error", "Are you ingame?")
	EndIf
	updateStatValue()
	local $str = ""
	for $i = 0 to 1023
		local $val = getStatValue($i)
		if ($val) then
			$str &= StringFormat("%s = %s%s", $i, $val, @CRLF)
		endif
	next
	FileDelete(@ScriptName & ".txt")
	FileWrite(@ScriptName & ".txt", $str)
EndFunc
