#RequireAdmin
#include <WinAPI.au3>
#include <NomadMemory.au3>

if (not IsAdmin()) then
	MsgBox(4096, "Error", "Admin rights needed!")
	exit
endif

global $version = "0.3.1.1 - [28.01.2017]"

OnAutoItExitRegister("_Exit")

local $d2client = 0x6FAB0000
local $d2win	= 0x6F8E0000
local $d2inject = 0x6FB7DE00

local $gui_event_close = -3
local $gui[128][5] = [[0]]

local const $numStats = 1024
local $stats_cache[2][$numStats]
for $i = 0 to $numStats-1
	$stats_cache[0][$i] = null
	$stats_cache[1][$i] = null
next

local $d2window, $d2pid, $d2handle

HotKeySet("+{INS}", "HotKey_WriteStatsToDisk")
HotKeySet("{INS}", "HotKey_CopyItem")
HotKeySet("{DEL}", "HotKey_ShowIlvl")
local $hotkeyactive = True

CreateGUI()
Main()

func _Exit()
	_MemoryClose($d2handle)
endfunc

func _Debug($msg)
	MsgBox(4096, "Error", $msg)
	return False
endfunc

func UpdateHandle()
	local $hwnd = WinGetHandle("[CLASS:Diablo II]")
	local $pid = WinGetProcess($hwnd)
	if ($pid == -1) then
		_MemoryClose($d2handle)
		$d2handle = 0
		$d2pid = 0
		return False
	endif

	if ($pid == $d2pid) then return True
	$d2pid = $pid
	
	_MemoryClose($d2handle)
	$d2handle = _MemoryOpen($d2pid)
	if (@error) then 
		$d2pid = 0
		return _Debug("Couldn't open Diablo II memory handle")
	endif
	$d2window = $hwnd
	
	return True
endfunc

func IsIngame()
	return _MemoryRead($d2client + 0x11BBFC, $d2handle) <> 0
endfunc

#Region Hotkeys
func GetIlvl()
	local $ilvl_offsets[3] = [0, 0x14, 0x2C]
	return _MemoryPointerRead($d2client + 0x11BC38, $d2handle, $ilvl_offsets)
endfunc

func HotKeyCheck()
	if (not $hotkeyactive) then return False
	if (UpdateHandle() and WinActive($d2window)) then return IsIngame()
	
	$hotkeyactive = False
	ControlSend("[ACTIVE]", "", "", @HotKeyPressed)
	$hotkeyactive = True
	
	return False
endfunc

func HotKey_CopyItem()
	if (not HotKeyCheck() or GetIlvl() == 0) then return False

	local $timer = TimerInit()
	local $text = ""
	
	while ($text == "" and TimerDiff($timer) < 10)
		$text = _MemoryRead($d2win + 0xC9E58, $d2handle, "wchar[800]")
	wend
	
	$text = StringRegExpReplace($text, "ÿc.", "")
	local $split = StringSplit($text, @LF)
	
	$text = ""
	for $i = $split[0] to 1 step -1
		$text &= $split[$i] & @CRLF
	next

	ClipPut($text)
	return True
endfunc

func HotKey_ShowIlvl()
	if (not HotKeyCheck()) then return False
	if (not InjectCode()) then return _Debug("Failed to inject code")
	
	local $ilvl = GetIlvl()
	if ($ilvl) then
		local $ret = _MemoryWrite($d2inject+0x2C, $d2handle, $ilvl, "wchar[2]")
		if ($ret) then
			_D2Call($d2inject)
		endif
	endif
endfunc

func HotKey_WriteStatsToDisk()
	if (not HotKeyCheck()) then return False
	
	updateStatValues()
	local $str = ""
	for $i = 0 to $numStats-1
		local $val = getStatValue($i)
		if ($val) then
			$str &= StringFormat("%s = %s%s", $i, $val, @CRLF)
		endif
	next
	FileDelete(@ScriptName & ".txt")
	FileWrite(@ScriptName & ".txt", $str)
endfunc
#EndRegion

#Region Stat reading
func updateStatValueMem($ivector)
	if ($ivector <> 0 and $ivector <> 1) then _Debug("Invalid $ivector value")
	
	local $ptr_offsets[3] = [0, 0x5C, ($ivector+1)*0x24]
	local $ptr = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $ptr_offsets)

	$ptr_offsets[2] += 0x4
	local $statcount = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $ptr_offsets, "word") - 1

	local $struct = "word wSubIndex;word wStatIndex;int dwStatValue;", $finalstruct
	for $i = 0 to $statcount
		$finalstruct &= $struct
	next

	local $stats = DllStructCreate($finalstruct)
	_WinAPI_ReadProcessMemory($d2handle[1], $ptr, DllStructGetPtr($stats), DllStructGetSize($stats), 0)

	local $start = $ivector == 1 ? 5 : 0
	local $index, $val
	for $i = $start to $statcount
		$index = DllStructGetData($stats, 2 + (3 * $i))
		if ($index >= $numStats) then
			continueloop ; Should never happen
		endif
		
		$val = DllStructGetData($stats, 3 + (3 * $i))
		switch $index
			case 6 to 11
				$stats_cache[$ivector][$index] += $val / 256
			case else
				$stats_cache[$ivector][$index] += $val
		endswitch
	next
endfunc

func updateStatValues()
	for $i = 0 to $numStats-1
		$stats_cache[0][$i] = null
		$stats_cache[1][$i] = null
	next
	
	if (UpdateHandle() and IsIngame()) then
		updateStatValueMem(0)
		updateStatValueMem(1)
	endif
endfunc

func getStatValue($istat, $default = 0)
	local $ivector = $istat < 4 ? 0 : 1
	local $val = $stats_cache[$ivector][$istat]
	return $val == null ? $default : $val
endfunc
#EndRegion

#Region GUI
func Main()
	while 1
		switch GUIGetMsg()
			case $gui_event_close
				exitloop
			case $btnRead
				ReadCharacterData()
			case $btnAbout
				MsgBox(4096 + 64, "About", "D2Stats " & $version & " made by Wojen. Using Shaggi's offsets. Press INSERT to copy an item to clipboard, and DELETE to display its ilvl.")
		endswitch
	wend
endfunc

func ReadCharacterData()
	updateStatValues()
	UpdateGUI()
endfunc

func NewLabel($text, $i)
	local $width = 8*(StringLen($text)+3)
	return GUICtrlCreateLabel($text, $gui[0][1]-$width/2, 4+15*$i, $width, 15, 0x1)
endfunc

func NewItem($statid, $i, $text, $tip = "", $clr = -1, $updatefunc = 0)
	local $arrPos = $gui[0][0] + 1
	$gui[$arrPos][0] = $statid
	$gui[$arrPos][1] = $text
	$gui[$arrPos][2] = NewLabel($text, $i)
	$gui[$arrPos][3] = $updatefunc
	if ($tip <> "") then
		GUICtrlSetTip(-1, $tip)
	endif
	if ($clr >= 0) then
		GUICtrlSetColor(-1, $clr)
	endif
	$gui[0][0] = $arrPos
endfunc

func UpdateGUI()
	for $i = 1 to $gui[0][0]
		local $val = getStatValue($gui[$i][0])
		local $func = $gui[$i][3]
		
		if ($func) then
			; $val = Call($func, $val)
		endif
		
		local $text = StringReplace($gui[$i][1], "*", $val)
		GUICtrlSetData($gui[$i][2], $text)
	next
endfunc

func UpdateFunc_IAS($val)
	local $nval = getStatValue(68, 100)
	return $nval == 100 ? $val : $val + ($nval - 100)
endfunc
func UpdateFunc_FHR($val)
	local $nval = getStatValue(69, 100)
	return $nval == 100 ? $val : $val + ($nval - 100)
endfunc
func UpdateFunc_FRW($val)
	local $nval = getStatValue(67, 100)
	return $nval == 100 ? $val : $val + ($nval - 100)
endfunc

func CreateGUI()
	local $clr_red	= 0xFF0000
	local $clr_blue	= 0x0066CC
	local $clr_gold	= 0x808000
	local $clr_green= 0x008000
	local $clr_purp	= 0xFF00FF

	GUICreate(StringFormat("D2Stats%s %s", @AutoItX64 ? "-64" : "", $version), 500, 250, 329, 143)
	GUISetFont(9, 0, 0, "Courier New")
	
	global $btnRead = GUICtrlCreateButton("Read data", 8, 192, 105, 25)
	global $btnAbout = GUICtrlCreateButton("About", 8, 216, 105, 25)
	
	local $groupX1 = 42
	local $groupX2 = 80+$groupX1
	local $groupX3 = 80+$groupX2
	local $groupX4 = 80+$groupX3
	local $groupX5 = 80+$groupX4
	local $groupX6 = 80+$groupX5

	$gui[0][1] = $groupX1
	NewLabel("Base stats", 0)
	NewItem(000, 1, "* Str", "Strength")
	NewItem(002, 2, "* Dex", "Dexterity")
	NewItem(003, 3, "* Vit", "Vitality")
	NewItem(001, 4, "* Ene", "Energy")
	
	NewItem(080, 6, "*% MF", "Magic Find")
	NewItem(079, 7, "*% GF", "Gold Find")
	NewItem(085, 8, "*% Exp", "Experience")
	NewItem(183, 9, "* CP", "Crafting Points")
	NewItem(185, 10, "* Sigs", "Signets of Learning")
	NewItem(479, 11, "* M.Skill", "Maximum Skill Level")
	
	$gui[0][1] = $groupX2
	NewItem(025, 0, "*% EWD", "Enchanced Weapon Damage")
	NewItem(136, 1, "*% CB", "Crushing Blow")
	NewItem(135, 2, "*% OW", "Open Wounds")
	NewItem(141, 3, "*% DS", "Deadly Strike")
	NewItem(119, 4, "*% AR", "Attack Rating")
	NewItem(489, 5, "* TTAD", "Target Takes Additional Damage")
	
	NewItem(093, 7, "*% IAS", "Increased Attack Speed", -1, "UpdateFunc_IAS")
	NewItem(105, 8, "*% FCR", "Faster Cast Rate")
	NewItem(099, 9, "*% FHR", "Faster Hit Recovery", -1, "UpdateFunc_FHR")
	NewItem(102, 10, "*% FBR", "Faster Block Rate", -1, "UpdateFunc_FHR")
	NewItem(096, 11, "*% FRW", "Faster Run/Walk", -1, "UpdateFunc_FRW")
	
	$gui[0][1] = $groupX3
	NewItem(076, 0, "*% Life", "Max Life")
	NewItem(077, 1, "*% Mana", "Max Mana")
	
	NewItem(171, 2, "*% TCD", "Total Character Defense")
	NewItem(034, 3, "* DR", "Flat damage reduction")
	NewItem(035, 4, "* MDR", "Flat magic damage reduction")
	NewItem(036, 5, "*% DR", "Percent damage reduction")
	NewItem(037, 6, "*% MR", "Magic Resist")
	
	NewItem(339, 7, "*% Avoid")
	NewItem(338, 8, "*% Dodge", "Avoid melee attack")
	
	NewItem(150, 10, "*% ST", "Slow Target")
	NewItem(363, 11, "*% SA", "Slow Attacker")
	NewItem(376, 12, "*% SMT", "Slow Melee Target")
	
	NewItem(164, 13, "*% UA", "Uninterruptable Attack")
	NewItem(165, 14, "*% CLR", "Curse Length Reduction")
	NewItem(166, 15, "*% PLR", "Poison Length Reduction")
	
	$gui[0][1] = $groupX4
	NewLabel("Absorb", 0)
	NewItem(142, 1, "*%", "Percent Fire Absorb", $clr_red)
	NewItem(143, 2, "*", "Flat Fire Absorb", $clr_red)
	NewItem(148, 3, "*%", "Percent Cold Absorb", $clr_blue)
	NewItem(149, 4, "*", "Flat Cold Absorb", $clr_blue)
	NewItem(144, 5, "*%", "Percent Light Absorb", $clr_gold)
	NewItem(145, 6, "*", "Flat Light Absorb", $clr_gold)
	
	NewItem(060, 7, "*% LL", "Life Leech")
	NewItem(086, 8, "* LaeK", "Life after each Kill")
	NewItem(208, 9, "* LoS", "Life on Striking")
	NewItem(210, 10, "* LoSiM", "Life on Striking in Melee")
	
	NewItem(062, 12, "*% ML", "Mana Leech")
	NewItem(138, 13, "* MaeK", "Mana after each Kill")
	NewItem(209, 14, "* MoS", "Mana on Striking")
	NewItem(211, 15, "* MoSiM", "Mana on Striking in Melee")
	
	$gui[0][1] = $groupX5
	NewLabel("Resists", 0)
	NewItem(039, 1, "*%", "", $clr_red)
	NewItem(043, 2, "*%", "", $clr_blue)
	NewItem(041, 3, "*%", "", $clr_gold)
	NewItem(045, 4, "*%", "", $clr_green)
	
	NewLabel("Spell damage", 5)
	NewItem(329, 6, "*%", "", $clr_red)
	NewItem(331, 7, "*%", "", $clr_blue)
	NewItem(330, 8, "*%", "", $clr_gold)
	NewItem(332, 9, "*%", "", $clr_green)
	NewItem(377, 10, "*%", "", $clr_purp)
	
	NewLabel("Pierce", 11)
	NewItem(333, 12, "*%", "", $clr_red)
	NewItem(335, 13, "*%", "", $clr_blue)
	NewItem(334, 14, "*%", "", $clr_gold)
	NewItem(336, 15, "*%", "", $clr_green)
	
	$gui[0][1] = $groupX6
	NewLabel("Minions", 0)
	NewItem(444, 1, "*% Life")
	NewItem(470, 2, "*% Damage")
	NewItem(487, 3, "*% Resist")
	NewItem(500, 4, "*% AR", "Attack Rating")
	
	NewItem(278, 6, "* SF", "Flat Strength Factor")
	NewItem(485, 7, "* EF", "Flat Energy Factor")
	NewItem(488, 8, "*% EF", "Percent Energy Factor")
	NewItem(431, 9, "*% PSD", "Poison Skill Duration")
	NewItem(409, 10, "*% Buff.Dur", "Buff/Debuff/Cold Skill Duration")
	NewItem(027, 11, "*% Mana.Reg", "Mana Regeneration")
	
	UpdateGUI()
	GUISetState(@SW_SHOW)
endfunc
#EndRegion

#Region Injection
func InjectCode()
	if (not UpdateHandle()) then return False
	
	local $injected = _MemoryRead($d2inject, $d2handle)
	if ($injected == 1465275221) then return True
	
	local $sCode = "0x5553565768000000006820DEB76F33C0BB50D8B26FFFD35F5E5B5DC30000000069006C0076006C003A002000300030000000"
	local $ret = _MemoryWrite($d2inject, $d2handle, $sCode, "byte[50]")
	
	$injected = _MemoryRead($d2inject, $d2handle)
	return $injected == 1465275221
endfunc

func _D2Call($address)
	if (not UpdateHandle()) then return False
	
	local $call = DllCall($d2handle[0], "ptr", "CreateRemoteThread", "ptr", $d2handle[1], "ptr", 0, "uint", 0, "ptr", $address, "ptr", 0, "dword", 0, "ptr", 0)
	if ($call[0] == 0) then return _Debug("Couldn't create remote thread")
	
	local $ret = _WinAPI_WaitForSingleObject($call[0])
	_WinAPI_CloseHandle($call[0])

	return $ret
endfunc   ;==>_CreateRemoteThread

#cs

6FB7DE00   . 55             PUSH EBP
6FB7DE01   . 53             PUSH EBX
6FB7DE02   . 56             PUSH ESI
6FB7DE03   . 57             PUSH EDI
6FB7DE04   . 68 00000000    PUSH 0
6FB7DE09   . 68 20DEB76F    PUSH D2Client.6FB7DE20                   ;  UNICODE "ilvl: 00"
6FB7DE0E   . 33C0           XOR EAX,EAX
6FB7DE10   . BB 50D8B26F    MOV EBX,D2Client.6FB2D850                ;  Entry address
6FB7DE15   . FFD3           CALL EBX
6FB7DE17   . 5F             POP EDI
6FB7DE18   . 5E             POP ESI
6FB7DE19   . 5B             POP EBX
6FB7DE1A   . 5D             POP EBP
6FB7DE1B   . C3             RETN
6FB7DE1C   . 00             DB 00
6FB7DE1D     00             DB 00
6FB7DE1E     00             DB 00
6FB7DE1F     00             DB 00
6FB7DE20   . 6900 6C00 7600>UNICODE "ilvl: 00"
6FB7DE30   . 0000           UNICODE 0

55 53 56 57 68 00 00 00 00 68 20 DE B7 6F 33 C0 BB 50 D8 B2 6F FF D3 5F 5E 5B 5D C3 00 00 00 00 69 00 6C 00 76 00 6C 00 3A 00 20 00 30 00 30 00 00 00

#ce
#EndRegion
