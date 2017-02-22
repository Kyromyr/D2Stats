#RequireAdmin
#include <WinAPI.au3>
#include <NomadMemory.au3>
#include <Misc.au3>

#pragma compile(Icon, Assets/icon.ico)
#pragma compile(FileDescription, Diablo II Stats reader)
#pragma compile(ProductName, D2Stats)
#pragma compile(ProductVersion, 0.3.4.1)
#pragma compile(FileVersion, 0.3.4.1)
#pragma compile(Comments, 20.02.2017)
#pragma compile(UPX, True) ;compression
;#pragma compile(ExecLevel, requireAdministrator)
;#pragma compile(Compatibility, win7)
;#pragma compile(x64, True)
;#pragma compile(Out, D2Stats.exe)
;#pragma compile(LegalCopyright, Legal stuff here)
;#pragma compile(LegalTrademarks, '"Trademark something, and some text in "quotes" and stuff')

if (not _Singleton("D2Stats-Singleton")) then
	exit
endif

if (not IsAdmin()) then
	MsgBox(4096, "Error", "Admin rights needed!")
	exit
endif

OnAutoItExitRegister("_Exit")

local $gui_event_close = -3
local $gui[128][3] = [[0]]
local $gui_opt[16][2] = [[0]]

local const $numStats = 1024
local $stats_cache[2][$numStats]

local $d2client, $d2common, $d2win, $d2sgpt
local $d2window, $d2pid, $d2handle

local $d2inject_print, $d2inject_string

local $hotkey_enabled = False
local $options[5] = [1, 1, 1, 1, 1]

CreateGUI()
Main()

func _Exit()
	GUIDelete()
	_CloseHandle()
endfunc

func _CloseHandle()
	if ($d2handle) then
		_MemoryClose($d2handle)
		$d2handle = 0
		$d2pid = 0
		$d2window = 0
	endif
endfunc

func _Debug($msg)
	MsgBox(4096, "Error", $msg)
	return False
endfunc

func UpdateHandle()
	local $hwnd = WinGetHandle("[CLASS:Diablo II]")
	local $pid = WinGetProcess($hwnd)
	
	if ($pid == -1) then return _CloseHandle()
	if ($pid == $d2pid) then return

	_CloseHandle()
	$d2handle = _MemoryOpen($pid)
	if (@error) then return _Debug("Couldn't open Diablo II memory handle")
	
	if (not UpdateDllHandles()) then return _CloseHandle()
	
	if (not InjectPrintFunction()) then
		_CloseHandle()
		return _Debug("Couldn't inject print function")
	endif

	$d2window = $hwnd
	$d2pid = $pid
	$d2sgpt = _MemoryRead($d2common + 0x99E1C, $d2handle)
endfunc

func IsIngame()
	if (not $d2pid) then return False
	return _MemoryRead($d2client + 0x11BBFC, $d2handle) <> 0
endfunc

#Region Hotkeys
func GetIlvl()
	local $ilvl_offsets[3] = [0, 0x14, 0x2C]
	return _MemoryPointerRead($d2client + 0x11BC38, $d2handle, $ilvl_offsets)
endfunc

func HotKeyEnable($enable)
	if ($enable <> $hotkey_enabled) then
		HotKeySet("+{INS}", ($enable and not @Compiled) ? "HotKey_WriteStatsToDisk" : null)
		HotKeySet("{INS}", ($enable and $options[0]) ? "HotKey_CopyItem" : null)
		HotKeySet("{DEL}", ($enable and $options[1]) ? "HotKey_ShowIlvl" : null)
		HotKeySet("{HOME}", ($enable and $options[2]) ? "HotKey_ToggleShowItems" : null)
		HotKeySet("+{HOME}", ($enable and $options[4]) ? "HotKey_DropFilter" : null)
		$hotkey_enabled = $enable
	endif
endfunc

func HotKeyCheck()
	if (not IsIngame()) then return _Debug("Enter a game first")
	return True
endfunc

func HotKey_WriteStatsToDisk()
	if (not HotKeyCheck()) then return
	
	UpdateStatValues()
	local $str = ""
	for $i = 0 to $numStats-1
		local $val = GetStatValue($i)
		if ($val) then
			$str &= StringFormat("%s = %s%s", $i, $val, @CRLF)
		endif
	next
	FileDelete(@ScriptName & ".txt")
	FileWrite(@ScriptName & ".txt", $str)
endfunc

func HotKey_CopyItem()
	if (not HotKeyCheck() or GetIlvl() == 0) then return

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
endfunc

func HotKey_ShowIlvl()
	if (not HotKeyCheck()) then return

	local $ilvl = GetIlvl()
	if ($ilvl) then PrintString(StringFormat("ilvl: %02s", $ilvl))
endfunc

func HotKey_ToggleShowItems()
	if (not HotKeyCheck()) then return
	ToggleShowItems()
endfunc

func HotKey_DropFilter()
	if (not FileExists("DropFilter.dll")) then return PrintString("Couldn't find DropFilter.dll", 1)
	if (not HotKeyCheck()) then return

	local $handle = GetDropFilterHandle()

	if ($handle) then
		if (EjectDropFilter($handle)) then
			PrintString("Ejected DropFilter", 10)
		else
			PrintString("Failed to eject DropFilter???", 1)
		endif
	else
		if (InjectDropFilter()) then
			PrintString("Injected DropFilter", 10)
		else
			PrintString("Failed to inject DropFilter", 1)
		endif
	endif
endfunc
#EndRegion

#Region Stat reading
func UpdateStatValueMem($ivector)
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

func UpdateStatValues()
	for $i = 0 to $numStats-1
		$stats_cache[0][$i] = 0
		$stats_cache[1][$i] = 0
	next
	
	if (IsIngame()) then
		UpdateStatValueMem(0)
		UpdateStatValueMem(1)
		FixStatVelocities()
		
		; Poison damage to damage/second
		$stats_cache[1][57] *= (25/256)
		$stats_cache[1][58] *= (25/256)
	endif
endfunc

func FixStatVelocities() ; This game is stupid
	for $i = 67 to 69
		$stats_cache[1][$i] = 0
	next
	
	local $pSkillsTxt = _MemoryRead($d2sgpt + 0xB98, $d2handle)
	local $skill, $pStats, $nStats, $txt, $index, $val, $ownerType, $ownerId
	
	local $wep_main_offsets[3] = [0, 0x60, 0x1C]
	local $wep_main = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $wep_main_offsets)
	
	local $ptr_offsets[3] = [0, 0x5C, 0x3C]
	local $ptr = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $ptr_offsets)

	while $ptr
		$ownerType = _MemoryRead($ptr + 0x08, $d2handle)
		$ownerId = _MemoryRead($ptr + 0x0C, $d2handle)
		$pStats = _MemoryRead($ptr + 0x24, $d2handle)
		$nStats = _MemoryRead($ptr + 0x28, $d2handle, "word")
		$ptr = _MemoryRead($ptr + 0x2C, $d2handle)
		$skill = 0

		for $i = 0 to $nStats-1
			$index = _MemoryRead($pStats + $i*8 + 2, $d2handle, "word")
			$val = _MemoryRead($pStats + $i*8 + 4, $d2handle, "int")
			
			if ($index == 350 and $val <> 511) then $skill = $val
			if ($ownerType == 4 and $index == 67) then $stats_cache[1][$index] += $val ; Armor FRW penalty
		next
		if ($ownerType == 4) then continueloop

		local $has[3] = [0,0,0]
		if ($skill) then ; Game doesn't even bother setting the skill id for some skills, so we'll just have to assume the stat list isn't lying...
			$txt = $pSkillsTxt + 0x23C*$skill
		
			for $i = 0 to 4
				$index = _MemoryRead($txt + 0x98 + $i*2, $d2handle, "word")
				switch $index
					case 67 to 69
						$has[$index-67] = 1
				endswitch
			next
			
			for $i = 0 to 5
				$index = _MemoryRead($txt + 0x54 + $i*2, $d2handle, "word")
				switch $index
					case 67 to 69
						$has[$index-67] = 1
				endswitch
			next
		endif
		
		for $i = 0 to $nStats-1
			$index = _MemoryRead($pStats + $i*8 + 2, $d2handle, "word")
			$val = _MemoryRead($pStats + $i*8 + 4, $d2handle, "int")
			switch $index
				case 67 to 69
					if (not $skill or $has[$index-67]) then $stats_cache[1][$index] += $val
			endswitch
		next
	wend
endfunc

func GetStatValue($istat)
	local $ivector = $istat < 4 ? 0 : 1
	local $val = $stats_cache[$ivector][$istat]
	return Floor($val ? $val : 0)
endfunc
#EndRegion

#Region GUI
func Main()
	local $timer = TimerInit()
	local $showitems, $lastshowitems
	
	while 1
		switch GUIGetMsg()
			case $gui_event_close
				exit
			case $btnRead
				ReadCharacterData()
			case $gui_opt[1][1] to $gui_opt[$gui_opt[0][0]][1]
				UpdateGUIOptions()
		endswitch

		if (TimerDiff($timer) > 250) then
			$timer = TimerInit()
			
			UpdateHandle()
			HotKeyEnable($d2window and WinActive($d2window))
			if (IsIngame() and IsShowItemsToggle()) then
				if ($options[3]) then
					$showitems = _MemoryRead($d2client + 0xFADB4, $d2handle) == 1
					if ($lastshowitems and not $showitems) then PrintString("Not showing items", 3)
					$lastshowitems = $showitems
				endif
				if (not $options[2]) then ToggleShowItems()
			else
				$lastshowitems = False
			endif
		endif
	wend
endfunc

func ReadCharacterData()
	UpdateStatValues()
	UpdateGUI()
endfunc

func StringWidth($text)
	return 2 + 7 * StringLen($text)
endfunc

func GetLineHeight($line)
	return 28+15*$line
endfunc

func NewTextBasic($line, $text, $centered = 1)
	local $width = StringWidth($text)
	local $x = $gui[0][1] - ($centered ? $width/2 : 0)
	return GUICtrlCreateLabel($text, $x, GetLineHeight($line), $width, 15, $centered)
endfunc

func NewText($line, $text, $tip = "", $clr = -1)
	local $width = StringWidth($text)
	local $ret = NewTextBasic($line, $text)

	; GUICtrlSetBkColor(-1, Random(0, 2147483647, 1))
	if ($tip <> "") then
		GUICtrlSetTip(-1, $tip)
	endif
	if ($clr >= 0) then
		GUICtrlSetColor(-1, $clr)
	endif
	return $ret
endfunc

func NewItem($line, $text, $tip = "", $clr = -1)
	local $arrPos = $gui[0][0] + 1
	
	$gui[$arrPos][0] = $text
	$gui[$arrPos][1] = $gui[0][1]
	$gui[$arrPos][2] = NewText($line, $text, $tip, $clr)

	$gui[0][0] = $arrPos
endfunc

func NewOption($line, $text)
	local $arrPos = $gui_opt[0][0] + 1
	local $ret = GUICtrlCreateCheckbox($text, 8, GetLineHeight($line)*2-GetLineHeight(0))
	
	$gui_opt[$arrPos][0] = $line
	$gui_opt[$arrPos][1] = $ret
	
	$gui_opt[0][0] = $arrPos
	return $ret
endfunc

func UpdateGUI()
	local $text, $matches, $match, $width
	for $i = 1 to $gui[0][0]
		$text = $gui[$i][0]
		$matches = StringRegExp($text, "{(\d+)}", 4)
		for $j = 0 to UBound($matches)-1
			$match = $matches[$j]
			$text = StringReplace($text, $match[0], GetStatValue($match[1]))
		next
		GUICtrlSetData($gui[$i][2], $text)
		
		$width = StringWidth($text)
		GUICtrlSetPos($gui[$i][2], $gui[$i][1]-$width/2, Default, $width, Default)
	next
endfunc

func UpdateGUIOptions()
	local $write = ""
	local $optid, $checked
	for $i = 1 to $gui_opt[0][0]
		$optid = $gui_opt[$i][0]
		$checked = GUICtrlRead($gui_opt[$i][1]) == 1 ? 1 : 0
		$options[$optid] = $checked
		$write &= StringFormat("%s=%s%s", $optid, $checked, @LF)
	next

	IniWriteSection(@AutoItExe & ".ini", "General", $write)
endfunc

func CreateGUI()
	local $clr_red	= 0xFF0000
	local $clr_blue	= 0x0066CC
	local $clr_gold	= 0x808000
	local $clr_green= 0x008000
	local $clr_pink	= 0xFF00FF
	
	local $groupLines = 14
	local $groupWidth = 110
	local $groupXStart = 8 + $groupWidth/2

	local $title = not @Compiled ? "Test" : StringFormat("D2Stats%s %s - [%s]", @AutoItX64 ? "-64" : "", FileGetVersion(@AutoItExe, "FileVersion"), FileGetVersion(@AutoItExe, "Comments"))
	local $guiWidth = 16 + 4*$groupWidth
	local $guiHeight = 34 + 15*$groupLines
	GUICreate($title, $guiWidth, $guiHeight)
	GUISetFont(9, 0, 0, "Courier New")
	
	global $btnRead = GUICtrlCreateButton("Read", $groupXStart-35, $guiHeight-31, 70, 25)

	GUICtrlCreateTab(0, 0, $guiWidth, 0, 0x8000)
	
	GUICtrlCreateTabItem("Page 1")
	$gui[0][1] = $groupXStart
	NewText(00, "Base stats")
	NewItem(01, "{000} Strength")
	NewItem(02, "{002} Dexterity")
	NewItem(03, "{003} Vitality")
	NewItem(04, "{001} Energy")
	
	NewItem(06, "{080}% M.Find", "Magic Find")
	NewItem(07, "{079}% Gold", "Extra Gold from Monsters")
	NewItem(08, "{085}% Exp.Gain", "Experience gained")
	NewItem(09, "{183} CP", "Crafting Points")
	NewItem(10, "{185} Signets", "Signets of Learning")
	NewItem(11, "{479} M.Skill", "Maximum Skill Level")
	
	
	$gui[0][1] += $groupWidth
	NewText(00, "Bonus stats")
	NewItem(01, "{359}% Strength")
	NewItem(02, "{360}% Dexterity")
	NewItem(03, "{362}% Vitality")
	NewItem(04, "{361}% Energy")
	
	NewText(06, "Item/Skill", "Speed from items and skills behave differently. Use SpeedCalc to find your breakpoints")
	NewItem(07, "{093}%/{068}% IAS", "Increased Attack Speed")
	NewItem(08, "{099}%/{069}% FHR", "Faster Hit Recovery")
	NewItem(09, "{102}%/{069}% FBR", "Faster Block Rate")
	NewItem(10, "{096}%/{067}% FRW", "Faster Run/Walk")
	NewItem(11, "{105}% FCR", "Item Faster Cast Rate")
	
	
	$gui[0][1] += $groupWidth
	NewItem(00, "{076}% Life", "Maximum Life")
	NewItem(01, "{077}% Mana", "Maximum Mana")
	NewItem(02, "{025}% EWD", "Enchanced Weapon Damage")
	NewItem(03, "{171}% TCD", "Total Character Defense")
	NewItem(04, "{119}% AR", "Attack Rating")
	NewItem(05, "{035} MDR", "Magic Damage Reduction")
	NewItem(06, "{339}% Avoid")
	NewItem(07, "{338}% Dodge", "Avoid melee attack")	

	NewItem(09, "{136}% CB", "Crushing Blow")
	NewItem(10, "{135}% OW", "Open Wounds")
	NewItem(11, "{141}% DS", "Deadly Strike")
	NewItem(12, "{164}% UA", "Uninterruptable Attack")
	
	
	$gui[0][1] += $groupWidth
	NewText(00, "Res/Abs/Flat", "Resist / Absorb / Flat absorb")
	NewItem(01, "{039}%/{142}%/{143}", "Fire", $clr_red)
	NewItem(02, "{043}%/{148}%/{149}", "Cold", $clr_blue)
	NewItem(03, "{041}%/{144}%/{145}", "Lightning", $clr_gold)
	NewItem(04, "{045}%", "Poison resist", $clr_green)
	NewItem(05, "{037}%/{146}%/{147}", "Magic", $clr_pink)
	NewItem(06, "{036}%/{034}", "Physical (aka Damage Reduction)")
	
	NewText(08, "Damage/Pierce", "Spell damage / -Enemy resist")
	NewItem(09, "{329}%/{333}%", "Fire", $clr_red)
	NewItem(10, "{331}%/{335}%", "Cold", $clr_blue)
	NewItem(11, "{330}%/{334}%", "Lightning", $clr_gold)
	NewItem(12, "{332}%/{336}%", "Poison", $clr_green)
	NewItem(13, "{377}%/0%", "Physical/Magic", $clr_pink)
	
	
	GUICtrlCreateTabItem("Page 2")
	$gui[0][1] = $groupXStart
	NewItem(00, "{278} SF", "Strength Factor")
	NewItem(01, "{485} EF", "Energy Factor")
	NewItem(02, "{431}% PSD", "Poison Skill Duration")
	NewItem(03, "{409}% Buff.Dur", "Buff/Debuff/Cold Skill Duration")
	NewItem(04, "{27}% Mana.Reg", "Mana Regeneration")
	NewItem(05, "{109}% CLR", "Curse Length Reduction")
	NewItem(06, "{110}% PLR", "Poison Length Reduction")
	NewItem(07, "{489} TTAD", "Target Takes Additional Damage")
	
	NewText(09, "Slow")
	NewItem(10, "{150}%/{376}% Tgt.", "Slows Target / Slows Melee Target")
	NewItem(11, "{363}%/{493}% Att.", "Slows Attacker / Slows Ranged Attacker")
	
	
	$gui[0][1] += $groupWidth
	NewText(00, "Weapon Damage")
	NewItem(01, "{048}-{049}", "Fire", $clr_red)
	NewItem(02, "{054}-{055}", "Cold", $clr_blue)
	NewItem(03, "{050}-{051}", "Lightning", $clr_gold)
	NewItem(04, "{057}-{058}/s", "Poison/sec", $clr_green)
	NewItem(05, "{052}-{053}", "Magic", $clr_pink)
	
	NewText(07, "Life/Mana")
	NewItem(08, "{060}%/{062}% Leech", "Life/Mana Stolen per Hit")
	NewItem(09, "{086}/{138} *aeK", "Life/Mana after each Kill")
	NewItem(10, "{208}/{209} *oS", "Life/Mana on Striking")
	NewItem(11, "{210}/{295} *oSiM", "Life/Mana on Striking in Melee")
	
	$gui[0][1] += $groupWidth
	NewText(00, "Minions")
	NewItem(01, "{444}% Life")
	NewItem(02, "{470}% Damage")
	NewItem(03, "{487}% Resist")
	NewItem(04, "{500}% AR", "Attack Rating")
	
	; TODO
	; $gui[0][1] += $groupWidth
	; NewText(00, "Mercenary")
	
	
	GUICtrlCreateTabItem("Options")
	NewOption(00, "Enable copy item stats (INSERT)")
	NewOption(01, "Enable display ilvl (DELETE)")
	NewOption(02, "Enable Show Items mode (HOME)")
	NewOption(03, "Message when Show Items is disabled in toggle mode")
	NewOption(04, "Enable DropFilter injector (Shift + HOME)")
	

	GUICtrlCreateTabItem("About")
	$gui[0][1] = 8
	NewTextBasic(00, "Made by Wojen and Kyromyr, using Shaggi's offsets.", False)
	NewTextBasic(01, "Layout help by krys.", False)
	NewTextBasic(02, "Additional help by suchbalance and Quirinus.", False)
	
	NewTextBasic(04, "If you're unsure what any of the abbreviations mean, all of", False)
	NewTextBasic(05, " them should have a tooltip when hovered over.", False)
	
	NewTextBasic(07, "Press INSERT to copy item stats to clipboard.", False)
	NewTextBasic(08, "Press DELETE to display item ilvl.", False)
	NewTextBasic(09, "Press HOME to switch Show Items between hold and toggle mode.", False)
	NewTextBasic(10, "Press Shift + HOME to inject DropFilter.dll, if present", False)
	
	GUICtrlCreateTabItem("")
	
	local $ini = IniReadSection(@AutoItExe & ".ini", "General")
	if (not @error) then
		for $i = 1 to $ini[0][0]
			$options[$ini[$i][0]] = Int($ini[$i][1])
		next
	endif
	for $i = 1 to $gui_opt[0][0]
		GUICtrlSetState($gui_opt[$i][1], $options[$gui_opt[$i][0]] == 1 ? 1 : 4)
	next
	
	UpdateGUI()
	GUISetState(@SW_SHOW)
endfunc
#EndRegion

#Region Injection
func PrintString($string, $color = 0)
	if (not WriteWString($string)) then return False
	_CreateRemoteThread($d2inject_print, $color)
	return True
endfunc

func WriteString($string)
	if (not IsIngame()) then return False
	_MemoryWrite($d2inject_string, $d2handle, $string, StringFormat("char[%s]", StringLen($string)+1))
	return True
endfunc
	
func WriteWString($string)
	if (not IsIngame()) then return False
	_MemoryWrite($d2inject_string, $d2handle, $string, StringFormat("wchar[%s]", StringLen($string)+1))
	return True
endfunc

func GetDropFilterHandle()
	if (not WriteString("DropFilter.dll")) then return False
	
	local $gethandle = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "GetModuleHandleA")
	if (not $gethandle) then return _Debug("Couldn't get GetModuleHandleA address")
	
	return _CreateRemoteThread($gethandle, $d2inject_string)
endfunc

func InjectDropFilter()
	if (not WriteString(FileGetLongName("DropFilter.dll", 1))) then return _Debug("Failed to write DropFilter.dll path")
	
	local $loadlib = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "LoadLibraryA")
	if (not $loadlib) then return _Debug("Couldn't get LoadLibraryA address")

	local $ret = _CreateRemoteThread($loadlib, $d2inject_string)
	if ($ret) then
		local $handle = _WinAPI_LoadLibrary("DropFilter.dll")
		if ($handle) then
			local $addr = _WinAPI_GetProcAddress($handle, "_PATCH_DropFilter@0")
			if ($addr) then
				local $jmp = $addr - 0x5 - ($d2client + 0x5907E)
				_MemoryWrite($d2client + 0x5907E, $d2handle, "0xE9" & GetOffsetAddress($jmp), "byte[5]")
			else
				$ret = False
			endif
			_WinAPI_FreeLibrary($handle)
		else
			$ret = False
		endif
	endif
	
	return $ret
endfunc

func EjectDropFilter($handle)
	local $freelib = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "FreeLibrary")
	if (not $freelib) then return _Debug("Couldn't get FreeLibrary address")

	local $ret = _CreateRemoteThread($freelib, $handle)
	if ($ret) then
		_MemoryWrite($d2client + 0x5907E, $d2handle, "0x833E040F85", "byte[5]")
	endif
	
	return $ret
endfunc

func GetOffsetAddress($addr)
	return StringFormat("%08s", StringLeft(Hex(Binary($addr)), 8))
endfunc

#cs
D2Client.dll+3AECF - A3 *                  - mov [D2Client.dll+FADB4],eax { [00000000] }
-->
D2Client.dll+3AECF - 90                    - nop 
D2Client.dll+3AED0 - 90                    - nop 
D2Client.dll+3AED1 - 90                    - nop 
D2Client.dll+3AED2 - 90                    - nop 
D2Client.dll+3AED3 - 90                    - nop 


D2Client.dll+3B224 - CC                    - int 3 
D2Client.dll+3B225 - CC                    - int 3 
D2Client.dll+3B226 - CC                    - int 3 
D2Client.dll+3B227 - CC                    - int 3 
D2Client.dll+3B228 - CC                    - int 3 
D2Client.dll+3B229 - CC                    - int 3 
D2Client.dll+3B22A - CC                    - int 3 
D2Client.dll+3B22B - CC                    - int 3 
D2Client.dll+3B22C - CC                    - int 3 
D2Client.dll+3B22D - CC                    - int 3 
D2Client.dll+3B22E - CC                    - int 3 
D2Client.dll+3B22F - CC                    - int 3 
-->
D2Client.dll+3B224 - 83 35 * 01            - xor dword ptr [D2Client.dll+FADB4],01 { [00000000] }
D2Client.dll+3B22B - E9 B6000000           - jmp D2Client.dll+3B2E6


D2Client.dll+3B2E1 - 89 1D *               - mov [D2Client.dll+FADB4],ebx { [00000000] }
-->
D2Client.dll+3B2E1 - E9 3EFFFFFF           - jmp D2Client.dll+3B224
D2Client.dll+3B2E6 - 90                    - nop 
#ce

func IsShowItemsToggle()
	return _MemoryRead($d2client + 0x3AECF, $d2handle, "byte") == 0x90
endfunc

func ToggleShowItems()
	local $write1 = "0x9090909090"
	local $write2 = "0x8335" & GetOffsetAddress($d2client + 0xFADB4) & "01E9B6000000"
	local $write3 = "0xE93EFFFFFF90"
	
	local $restore = IsShowItemsToggle()
	if ($restore) then
		$write1 = "0xA3" & GetOffsetAddress($d2client + 0xFADB4)
		$write2	= "0xCCCCCCCCCCCCCCCCCCCCCCCC"
		$write3 = "0x891D" & GetOffsetAddress($d2client + 0xFADB4)
	endif
	
	_MemoryWrite($d2client + 0x3AECF, $d2handle, $write1, "byte[5]")
	_MemoryWrite($d2client + 0x3B224, $d2handle, $write2, "byte[12]")
	_MemoryWrite($d2client + 0x3B2E1, $d2handle, $write3, "byte[6]")
	
	if (IsIngame()) then PrintString($restore ? "Hold to show items" : "Toggle to show items", 3)
endfunc

#cs
D2Client.dll+CDE00 - 53                    - push ebx
D2Client.dll+CDE01 - 68 *                  - push D2Client.dll+CDE10
D2Client.dll+CDE06 - 31 C0                 - xor eax,eax
D2Client.dll+CDE08 - E8 43FAFAFF           - call D2Client.dll+7D850
D2Client.dll+CDE0D - C3                    - ret 
#ce

func InjectPrintFunction()
	local $sCode = "0x5368" & GetOffsetAddress($d2inject_string) & "31C0E843FAFAFFC3"
	local $ret = _MemoryWrite($d2inject_print, $d2handle, $sCode, "byte[14]")
	
	local $injected = _MemoryRead($d2inject_print, $d2handle)
	return Hex($injected, 8) == Hex(Binary(Int(StringLeft($sCode, 10))))
endfunc

func UpdateDllHandles()
	local $loadlib = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "LoadLibraryA")
	if (not $loadlib) then return _Debug("Couldn't get LoadLibraryA address")
	
	local $addr = _MemVirtualAllocEx($d2handle[1], 0, 0x100, 0x3000, 0x40)
	if (@error) then return _Debug("Failed to allocate memory")

	local $nDlls = 3
	local $dlls[$nDlls] = ["D2Client.dll", "D2Common.dll", "D2Win.dll"]
	local $handles[$nDlls]
	local $failed = False
	
	for $i = 0 to $nDlls-1
		_MemoryWrite($addr, $d2handle, $dlls[$i], StringFormat("char[%s]", StringLen($dlls[$i])+1))
		$handles[$i] = _CreateRemoteThread($loadlib, $addr)
		if ($handles[$i] == 0) then $failed = True
	next
	
	$d2client = $handles[0]
	$d2common = $handles[1]
	$d2win = $handles[2]
	
	local $d2inject = $d2client + 0xCDE00
	$d2inject_print = $d2inject + 0x0
	$d2inject_string = $d2inject + 0x10
	
	$d2sgpt = _MemoryRead($d2common + 0x99E1C, $d2handle)

	_MemVirtualFreeEx($d2handle[1], $addr, 0x100, 0x8000)
	if (@error) then return _Debug("Failed to free memory")
	if ($failed) then return _Debug("Couldn't retrieve dll addresses")
	
	return True
endfunc

func _CreateRemoteThread($func, $var = 0) ; $var is in EBX register
	local $call = DllCall($d2handle[0], "ptr", "CreateRemoteThread", "ptr", $d2handle[1], "ptr", 0, "uint", 0, "ptr", $func, "ptr", $var, "dword", 0, "ptr", 0)
	if ($call[0] == 0) then return _Debug("Couldn't create remote thread")
	
	_WinAPI_WaitForSingleObject($call[0])
	local $ret = _GetExitCodeThread($call[0])
	
	_WinAPI_CloseHandle($call[0])
	return $ret
endfunc

func _GetExitCodeThread($thread)
	local $dummy = DllStructCreate("dword")
	local $call = DllCall($d2handle[0], "bool", "GetExitCodeThread", "handle", $thread, "ptr", DllStructGetPtr($dummy))
	return Dec(Hex(DllStructGetData($dummy, 1)))
endfunc

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......:
; ===============================================================================================================================
Func _MemVirtualAllocEx($hProcess, $pAddress, $iSize, $iAllocation, $iProtect)
	Local $aResult = DllCall($d2handle[0], "ptr", "VirtualAllocEx", "handle", $hProcess, "ptr", $pAddress, "ulong_ptr", $iSize, "dword", $iAllocation, "dword", $iProtect)
	If @error Then Return SetError(@error, @extended, 0)
	Return $aResult[0]
EndFunc   ;==>_MemVirtualAllocEx

; #FUNCTION# ====================================================================================================================
; Author ........: Paul Campbell (PaulIA)
; Modified.......:
; ===============================================================================================================================
Func _MemVirtualFreeEx($hProcess, $pAddress, $iSize, $iFreeType)
	Local $aResult = DllCall("kernel32.dll", "bool", "VirtualFreeEx", "handle", $hProcess, "ptr", $pAddress, "ulong_ptr", $iSize, "dword", $iFreeType)
	If @error Then Return SetError(@error, @extended, False)
	Return $aResult[0]
EndFunc   ;==>_MemVirtualFreeEx
#EndRegion
