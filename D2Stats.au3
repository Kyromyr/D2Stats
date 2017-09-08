#RequireAdmin
#include <WinAPI.au3>
#include <NomadMemory.au3>
#include <Misc.au3>
#include <HotKey.au3>
#include <HotKeyInput.au3>

#include "notifier\notify_list.au3"

#pragma compile(Icon, Assets/icon.ico)
#pragma compile(FileDescription, Diablo II Stats reader)
#pragma compile(ProductName, D2Stats)
#pragma compile(ProductVersion, 0.3.7.2)
#pragma compile(FileVersion, 0.3.7.2)
#pragma compile(Comments, 09.09.2017)
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
if (not @Compiled) then HotKeySet("+{INS}", "HotKey_CopyStatsToClipboard")

global const $HK_FLAG_D2STATS = BitOR($HK_FLAG_DEFAULT, $HK_FLAG_NOUNHOOK)

local $gui_event_close = -3
local $gui[128][3] = [[0]]
local $gui_opt[16][3] = [[0]]

local const $numStats = 1024
local $stats_cache[2][$numStats]

local $dlls[] = ["D2Client.dll", "D2Common.dll", "D2Win.dll"]
local $d2client, $d2common, $d2win, $d2sgpt
local $d2pid, $d2handle, $failCounter
local $lastUpdate = TimerInit()

local $d2inject_print, $d2inject_string

local $logstr = ""

local $hotkey_enabled = False

local $opts_general = 6
local $opts_notify = 6

local $options[][5] = [ _
["copy", 0x002D, "hk", "Copy item text", "HotKey_CopyItem"], _
["ilvl", 0x002E, "hk", "Display item ilvl", "HotKey_ShowIlvl"], _
["filter", 0x0124, "hk", "Inject/eject DropFilter", "HotKey_DropFilter"], _
["nopickup", 0, "cb", "Automatically enable /nopickup", 0], _
["toggle", 0x0024, "hk", "Switch Show Items between hold/toggle mode", "HotKey_ToggleShowItems"], _
["toggleMsg", 1, "cb", "Message when Show Items is disabled in toggle mode"], _
["notify-enabled", 1, "cb", "Enable drop notifier", 0], _
["notify-tiered", 1, "cb", "Tiered uniques", 0], _
["notify-sacred", 1, "cb", "Sacred uniques / jewelry", 0], _
["notify-set", 1, "cb", "Set items", 0], _
["notify-shrine", 1, "cb", "Shrines", 0], _
["notify-respec", 1, "cb", "Belladonna Extract", 0] ]


CreateGUI()
Main()

#Region Main
func Main()
	_HotKey_Disable($HK_FLAG_D2STATS)

	local $timer = TimerInit()
	local $ingame, $showitems
	
	while 1
		switch GUIGetMsg()
			case $gui_event_close
				exit
			case $btnRead
				ReadCharacterData()
			case $tab
				GUICtrlSetState($btnRead, GUICtrlRead($tab) < 2 ? 16 : 32)
		endswitch
		
		if (TimerDiff($timer) > 250) then
			$timer = TimerInit()
			
			UpdateHandle()
			UpdateHotkeys()
			UpdateGUIOptions() ; Must update options after hotkeys
			
			if (IsIngame()) then
				if (IsShowItemsToggle()) then
					if (GetGUIOption("toggleMsg")) then
						if (_MemoryRead($d2client + 0xFADB4, $d2handle) == 0) then
							if ($showitems) then PrintString("Not showing items.", 3)
							$showitems = False
						else
							$showitems = True
						endif
					endif
					if (not GetGUIOption("toggle")) then ToggleShowItems()
				else
					$showitems = False
				endif
				
				if (GetGUIOption("nopickup") and not $ingame) then _MemoryWrite($d2client + 0x11C2F0, $d2handle, 1, "byte")
				
				if (GetGUIOption("notify-enabled")) then DropNotifier()
				
				$ingame = True
			else
				$ingame = False
			endif
		endif
	wend
endfunc

func _Exit()
	_GUICtrlHKI_Release()
	GUIDelete()
	_CloseHandle()
	_LogSave()
endfunc

func _CloseHandle()
	if ($d2handle) then
		_MemoryClose($d2handle)
		$d2handle = 0
		$d2pid = 0
	endif
endfunc

func UpdateHandle()
	if (TimerDiff($lastUpdate) < 100) then return
	$lastUpdate = TimerInit()
	
	local $hwnd = WinGetHandle("[CLASS:Diablo II]")
	local $pid = WinGetProcess($hwnd)
	
	if ($pid == -1) then return _CloseHandle()
	if ($pid == $d2pid) then return

	_CloseHandle()
	$failCounter += 1
	$d2handle = _MemoryOpen($pid)
	if (@error) then return _Debug("UpdateHandle", "Couldn't open Diablo II memory handle.")
	
	if (not UpdateDllHandles()) then
		_CloseHandle()
		return _Debug("UpdateHandle", "Couldn't update dll handles.")
	endif
	
	if (not InjectPrintFunction()) then
		_CloseHandle()
		return _Debug("UpdateHandle", "Couldn't inject print function.")
	endif

	$failCounter = 0
	$d2pid = $pid
	$d2sgpt = _MemoryRead($d2common + 0x99E1C, $d2handle)
endfunc

func IsIngame()
	if (not $d2pid) then return False
	return _MemoryRead($d2client + 0x11BBFC, $d2handle) <> 0
endfunc

func _Debug($function, $msg, $error = @error, $extended = @extended)
	_Log($function, $msg, $error, $extended)
	PrintString($msg, 1)
endfunc

func _Log($function, $msg, $error = @error, $extended = @extended)
	$logstr &= StringFormat("[%s] %s (error: %s; extended: %s)%s", $function, $msg, $error, $extended, @CRLF)
	
	if ($failCounter >= 10) then
		MsgBox(0, "D2Stats Error", "Failed too many times in a row. Check log for details. Closing D2Stats...")
		exit
	endif
endfunc

func _LogSave()
	if ($logstr <> "") then
		local $file = FileOpen("D2Stats-log.txt", 2)
		FileWrite($file, $logstr)
		FileFlush($file)
		FileClose($file)
	endif
endfunc

#EndRegion

#Region Hotkeys
func GetIlvl()
	local $ilvl_offsets[3] = [0, 0x14, 0x2C]
	local $ret = _MemoryPointerRead($d2client + 0x11BC38, $d2handle, $ilvl_offsets)
	if (not $ret) then PrintString("Hover the cursor over an item first.", 1)
	return $ret
endfunc

func UpdateHotkeys()
	local $opt, $value, $old
	for $i = 1 to $gui_opt[0][0]
		$opt = $gui_opt[$i][0]

		if (GetGUIOptionType($opt) == "hk") then
			$old = GetGUIOption($opt)
			$value = _GUICtrlHKI_GetHotKey($gui_opt[$i][1])
			
			if ($old <> $value) then
				if ($old) then _HotKey_Assign($old, 0, $HK_FLAG_D2STATS)
				if ($value) then _HotKey_Assign($value, $gui_opt[$i][2], $HK_FLAG_D2STATS, "[CLASS:Diablo II]")
			endif
		endif
	next
	
	local $enable = IsIngame()
	if ($enable <> $hotkey_enabled) then
		if ($enable) then
			_HotKey_Enable()
		else
			_HotKey_Disable($HK_FLAG_D2STATS)
		endif
		$hotkey_enabled = $enable
	endif
endfunc

func HotKey_CopyStatsToClipboard()
	if (not IsIngame()) then return
	
	UpdateStatValues()
	local $ret = ""
	for $i = 0 to $numStats-1
		local $val = GetStatValue($i)
		if ($val) then
			$ret &= StringFormat("%s = %s%s", $i, $val, @CRLF)
		endif
	next
	ClipPut($ret)
	PrintString("Stats copied to clipboard.")
endfunc

func HotKey_CopyItem()
	if (not IsIngame() or GetIlvl() == 0) then return

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
	PrintString("Item text copied.")
endfunc

func HotKey_ShowIlvl()
	if (not IsIngame()) then return

	local $ilvl = GetIlvl()
	if ($ilvl) then PrintString(StringFormat("ilvl: %02s", $ilvl))
endfunc

func HotKey_DropFilter()
	if (not IsIngame()) then return

	local $handle = GetDropFilterHandle()

	if ($handle) then
		if (EjectDropFilter($handle)) then
			PrintString("Ejected DropFilter.", 10)
			_Log("HotKey_DropFilter", "Ejected DropFilter.")
		else
			_Debug("HotKey_DropFilter", "Failed to eject DropFilter.")
		endif
	else
		if (InjectDropFilter()) then
			PrintString("Injected DropFilter.", 10)
			_Log("HotKey_DropFilter", "Injected DropFilter.")
		else
			_Debug("HotKey_DropFilter", "Failed to inject DropFilter.")
		endif
	endif
endfunc

func HotKey_ToggleShowItems()
	if (not IsIngame()) then return
	ToggleShowItems()
endfunc
#EndRegion

#Region Stat reading
func UpdateStatValueMem($ivector)
	if ($ivector <> 0 and $ivector <> 1) then _Debug("UpdateStatValueMem", "Invalid $ivector value.")
	
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

#Region Drop notifier
func DropNotifier()
	local $ptr_offsets[4] = [0, 0x2C, 0x1C, 0x0]
	local $pPaths = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $ptr_offsets)
	
	$ptr_offsets[3] = 0x24
	local $nPaths = _MemoryPointerRead($d2client + 0x11BBFC, $d2handle, $ptr_offsets)
	
	if (not $pPaths or not $nPaths) then return
	
	local $path, $unit, $data
	local $type, $class, $quality, $notify, $group, $text, $clr
	
	for $i = 0 to $nPaths-1
		$path = _MemoryRead($pPaths + 4*$i, $d2handle)
		$unit = _MemoryRead($path + 0x74, $d2handle)
		
		while $unit
			$type = _MemoryRead($unit + 0x0, $d2handle)
			
			if ($type == 4) then
				$class = _MemoryRead($unit + 0x4, $d2handle)
				$data = _MemoryRead($unit + 0x14, $d2handle)
				
				$notify = $notify_list[$class][0]
				$group = $notify_list[$class][1]
				
				$clr = 8 ; Orange
				if ($group <> "") then
					$quality = _MemoryRead($data + 0x0, $d2handle)
					
					if ($quality == 5) then
						$notify = GetGUIOption("notify-set")
						$clr = 2 ; Green
					elseif ($quality == 7 or ($group <> "tiered" and $group <> "sacred")) then
						$notify = GetGUIOption("notify-" & $group)
						$clr = $quality == 7 ? 4 : $clr  ; Gold or Orange
					else
						$notify = 0
					endif
				endif

				if ($notify and _MemoryRead($data + 0x48, $d2handle, "byte") == 0) then
					; Using the ear level field to check if we've seen this item on the ground before
					; Resets when the item is picked up or we move too far away
					_MemoryWrite($data + 0x48, $d2handle, 1, "byte")
					
					$text = $notify_list[$class][2]
					if ($text == "") then $text = "<Unknown>"

					PrintString("- " & $text, $clr)
				endif
			endif
			
			$unit = _MemoryRead($unit + 0xE8, $d2handle)
		wend
	next
endfunc
#EndRegion

#Region GUI
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
		GUICtrlSetTip(-1, StringReplace($tip, "|", @LF), default, default, 2)
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

func UpdateGUI()
	local $clr_red	= 0xFF0000
	local $clr_gold	= 0x808000
	local $clr_green= 0x008000
	
	local $text, $matches, $match, $width
	local $color, $val
	
	for $i = 1 to $gui[0][0]
		$text = $gui[$i][0]
		$color = 0
		
		$matches = StringRegExp($text, "\[(\d+):(\d+)/(\d+)\]", 4)
		for $j = 0 to UBound($matches)-1
			$match = $matches[$j]
			$text = StringReplace($text, $match[0], "")
			$color = $clr_red
			
			$val = GetStatValue($match[1])
			if ($val >= $match[2]) then
				$color = $clr_green
			elseif ($val >= $match[3]) then
				$color = $clr_gold
			endif
		next
		
		$matches = StringRegExp($text, "{(\d+)}", 4)
		for $j = 0 to UBound($matches)-1
			$match = $matches[$j]
			$text = StringReplace($text, $match[0], GetStatValue($match[1]))
		next
		
		$text = StringStripWS($text, 7)
		GUICtrlSetData($gui[$i][2], $text)
		if ($color <> 0) then GUICtrlSetColor($gui[$i][2], $color)
		
		$width = StringWidth($text)
		GUICtrlSetPos($gui[$i][2], $gui[$i][1]-$width/2, Default, $width, Default)
	next
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

	global $tab = GUICtrlCreateTab(0, 0, $guiWidth, 0, 0x8000)
	
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
	NewItem(09, "{185} Signets", "Signets of Learning")
	NewItem(10, "{479} M.Skill", "Maximum Skill Level")
	
	
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
	NewItem(11, "{105}%/0% FCR", "Faster Cast Rate")
	
	
	$gui[0][1] += $groupWidth
	NewItem(00, "{076}% Life", "Maximum Life")
	NewItem(01, "{077}% Mana", "Maximum Mana")
	NewItem(02, "{025}% EWD", "Enchanced Weapon Damage")
	NewItem(03, "{171}% TCD", "Total Character Defense")
	NewItem(04, "{119}% AR", "Attack Rating")
	NewItem(05, "{035} MDR", "Magic Damage Reduction")
	NewItem(06, "{338}% Dodge", "Chance to avoid melee attacks while standing still")
	NewItem(07, "{339}% Avoid", "Chance to avoid projectiles while standing still")
	NewItem(08, "{340}% Evade", "Chance to avoid any attack while moving")

	NewItem(10, "{136}% CB", "Crushing Blow. Chance to deal physical damage based on target's current health")
	NewItem(11, "{135}% OW", "Open Wounds. Chance to disable target's natural health regen for 8 seconds")
	NewItem(12, "{141}% DS", "Deadly Strike. Chance to double physical damage of attack")
	NewItem(13, "{164}% UA", "Uninterruptable Attack")
	
	
	$gui[0][1] += $groupWidth
	NewText(00, "Res/Abs/Flat", "Resist / Absorb / Flat absorb")
	NewItem(01, "{039}%/{142}%/{143}", "Fire", $clr_red)
	NewItem(02, "{043}%/{148}%/{149}", "Cold", $clr_blue)
	NewItem(03, "{041}%/{144}%/{145}", "Lightning", $clr_gold)
	NewItem(04, "{045}%/0%/0", "Poison", $clr_green)
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
	
	
	$gui[0][1] += $groupWidth
	NewText(00, "Minigames")
	NewItem(01, "Veteran tokens [219:1/1]", "On Terror and Destruction difficulty, you can find veteran monsters near the end of|each Act. There are five types of veteran monsters, one for each Act||[Class Charm] + each of the 5 tokens → returns [Class Charm] with added bonuses| +1 to [Your class] Skill Levels| +20% to Experience Gained")
	NewItem(02, "Dogmas {186}/3 [186:3/1]", "On Terror or Destruction difficulty, kill Act bosses to receive a 'Dogma' token||Each of the 5 tokens → Signet of Skill")
	NewItem(03, "Bremmtown [491:1/1]", "Defeat the Dark Star Dragon on Destruction difficulty within three minutes|after entering the level and without dying||[Class Charm] + Arcane Crystal → [Class Charm] with added bonuses| (Varies by class; see documentation)")
	

	LoadGUIOptions()
	GUICtrlCreateTabItem("Options")
	$gui[0][1] = 8
	
	local $i = 0
	for $j = 1 to $opts_general
		NewOption($j-1, $options[$i][0], $options[$i][3], $options[$i][4])
		$i += 1
	next
	
	
	GUICtrlCreateTabItem("Drop notifier")
	for $j = 1 to $opts_notify
		$gui[0][1] = $j == 1 ? 8 : 16
		NewOption($j-1, $options[$i][0], $options[$i][3], $options[$i][4])
		$i += 1
	next
	

	GUICtrlCreateTabItem("Drop filter")
	$gui[0][1] = 8
	NewTextBasic(00, "The latest drop filter hides:", False)
	NewTextBasic(01, " White/magic/rare tiered equipment with no filled sockets.", False)
	NewTextBasic(02, " Runes below and including Zod.", False)
	NewTextBasic(03, " Gems below Perfect.", False)
	NewTextBasic(04, " Gold stacks below 2,000.", False)
	NewTextBasic(05, " Magic rings, amulets and quivers.", False)
	NewTextBasic(06, " Elixirs of Experience/Greed/Concentration.", False)
	NewTextBasic(07, " Various junk (mana potions, TP/ID scrolls and tomes, keys).", False)
	NewTextBasic(08, " Health potions below Greater.", False)
	
	
	GUICtrlCreateTabItem("About")
	$gui[0][1] = 8
	NewTextBasic(00, "Made by Wojen and Kyromyr, using Shaggi's offsets.", False)
	NewTextBasic(01, "Layout help by krys.", False)
	NewTextBasic(02, "Additional help by suchbalance and Quirinus.", False)
	
	NewTextBasic(04, "If you're unsure what any of the abbreviations mean, all of", False)
	NewTextBasic(05, " them should have a tooltip when hovered over.", False)
	
	NewTextBasic(07, "Hotkeys can be disabled by setting them to ESC.", False)
	
	
	GUICtrlCreateTabItem("")
	UpdateGUI()
	GUISetState(@SW_SHOW)
endfunc
#EndRegion

#Region GUI-options
func NewOption($line, $opt, $text, $extra = 0)
	local $arrPos = $gui_opt[0][0] + 1
	local $y = GetLineHeight($line)*2 - GetLineHeight(0)
	
	local $control
	local $type = GetGUIOptionType($opt)
	if ($type == null) then
		_Log("NewOption", "Invalid option '" & $opt & "'")
		exit
	elseif ($type == "hk") then
		if (not $extra) then
			_Log("NewOption", "No hotkey function for option '" & $opt & "'")
			exit
		endif
		
		local $key = GetGUIOption($opt)
		if ($key) then
			_KeyLock($key)
			_HotKey_Assign($key, $extra, $HK_FLAG_D2STATS, "[CLASS:Diablo II]")
		endif
		
		$control = _GUICtrlHKI_Create($key, $gui[0][1], $y, 120, 25)
		GUICtrlCreateLabel($text, $gui[0][1] + 124, $y+4)
	elseif ($type == "cb") then
		$control = GUICtrlCreateCheckbox($text, $gui[0][1], $y)
		GUICtrlSetState(-1, GetGUIOption($opt) ? 1 : 4)
	else
		_Log("NewOption", "Invalid option type '" & $type & "'")
		exit
	endif
	
	$gui_opt[$arrPos][0] = $opt
	$gui_opt[$arrPos][1] = $control
	$gui_opt[$arrPos][2] = $extra
	
	$gui_opt[0][0] = $arrPos
endfunc

func SetGUIOption($name, $value)
	for $i = 0 to UBound($options)-1
		if ($options[$i][0] == $name) then
			$options[$i][1] = $value
			return
		endif
	next
endfunc

func GetGUIOption($name)
	for $i = 0 to UBound($options)-1
		if ($options[$i][0] == $name) then return $options[$i][1]
	next
	return null
endfunc

func GetGUIOptionType($name)
	for $i = 0 to UBound($options)-1
		if ($options[$i][0] == $name) then return $options[$i][2]
	next
	return null
endfunc

func UpdateGUIOptions()
	local $save = False
	local $opt, $type, $value
	for $i = 1 to $gui_opt[0][0]
		$opt = $gui_opt[$i][0]
		$type = GetGUIOptionType($opt)
		
		if ($type == "hk") then
			$value = _GUICtrlHKI_GetHotKey($gui_opt[$i][1])
		elseif ($type == "cb") then
			$value = (GUICtrlRead($gui_opt[$i][1]) == 1) ? 1 : 0
		endif
		
		if (GetGUIOption($opt) <> $value) then
			$save = True
			SetGUIOption($opt, $value)
		endif
	next

	if ($save) then SaveGUIOptions()
endfunc

func SaveGUIOptions()
	local $write = ""
	for $i = 0 to UBound($options)-1
		$write &= StringFormat("%s=%s%s", $options[$i][0], $options[$i][1], @LF)
	next
	IniWriteSection(@AutoItExe & ".ini", "General", $write)
endfunc

func LoadGUIOptions()
	local $ini = IniReadSection(@AutoItExe & ".ini", "General")
	if (not @error) then
		for $i = 1 to $ini[0][0]
			SetGUIOption($ini[$i][0], Int($ini[$i][1]))
		next
	endif
endfunc
#EndRegion

#Region Injection
func PrintString($string, $color = 0)
	if (not WriteWString($string)) then return _Log("PrintString", "Failed to write string.")
	
	_CreateRemoteThread($d2inject_print, $color)
	if (@error) then return _Log("PrintString", "Failed to create remote thread.")
	
	return True
endfunc

func WriteString($string)
	if (not IsIngame()) then return _Log("WriteString", "Not ingame.")
	
	_MemoryWrite($d2inject_string, $d2handle, $string, StringFormat("char[%s]", StringLen($string)+1))
	if (@error) then return _Log("WriteString", "Failed to write string.")
	
	return True
endfunc
	
func WriteWString($string)
	if (not IsIngame()) then return _Log("WriteWString", "Not ingame.")
	
	_MemoryWrite($d2inject_string, $d2handle, $string, StringFormat("wchar[%s]", StringLen($string)+1))
	if (@error) then return _Log("WriteWString", "Failed to write string.")
	
	return True
endfunc

func GetDropFilterHandle()
	if (not WriteString("DropFilter.dll")) then return _Debug("GetDropFilterHandle", "Failed to write string.")
	
	local $gethandle = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "GetModuleHandleA")
	if (not $gethandle) then return _Debug("GetDropFilterHandle", "Couldn't retrieve GetModuleHandleA address.")
	
	return _CreateRemoteThread($gethandle, $d2inject_string)
endfunc

#cs
D2Client.dll+5907E - 83 3E 04              - cmp dword ptr [esi],04 { 4 }
D2Client.dll+59081 - 0F85
-->
D2Client.dll+5907E - E9 *           - jmp DropFilter.dll+15D0 { PATCH_DropFilter }
#ce

func InjectDropFilter()
	local $path = FileGetLongName("DropFilter.dll", 1)
	if (not FileExists($path)) then return _Debug("InjectDropFilter", "Couldn't find DropFilter.dll. Make sure it's in the same folder as " & @ScriptName & ".")
	if (not WriteString($path)) then return _Debug("InjectDropFilter", "Failed to write DropFilter.dll path.")
	
	local $loadlib = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "LoadLibraryA")
	if (not $loadlib) then return _Debug("InjectDropFilter", "Couldn't retrieve LoadLibraryA address.")

	local $ret = _CreateRemoteThread($loadlib, $d2inject_string)
	if (@error) then return _Debug("InjectDropFilter", "Failed to create remote thread.")
	
	local $injected = _MemoryRead($d2client + 0x5907E, $d2handle, "byte")
	
	; If the jmp is already there it means my DropFilter isn't used, and it'll will probably close D2Stats if we load it from here
	if ($ret and $injected <> 233) then
		local $handle = _WinAPI_LoadLibrary("DropFilter.dll")
		if ($handle) then
			local $addr = _WinAPI_GetProcAddress($handle, "_PATCH_DropFilter@0")
			if ($addr) then
				local $jmp = $addr - 0x5 - ($d2client + 0x5907E)
				_MemoryWrite($d2client + 0x5907E, $d2handle, "0xE9" & GetOffsetAddress($jmp), "byte[5]")
			else
				_Debug("InjectDropFilter", "Couldn't find DropFilter.dll entry point.")
				$ret = False
			endif
			_WinAPI_FreeLibrary($handle)
		else
			_Debug("InjectDropFilter", "Failed to load DropFilter.dll.")
			$ret = False
		endif
	endif
	
	return $ret
endfunc

func EjectDropFilter($handle)
	local $freelib = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "FreeLibrary")
	if (not $freelib) then return _Debug("EjectDropFilter", "Couldn't retrieve FreeLibrary address.")

	local $ret = _CreateRemoteThread($freelib, $handle)
	if (@error) then return _Debug("EjectDropFilter", "Failed to create remote thread.")
	
	if ($ret) then _MemoryWrite($d2client + 0x5907E, $d2handle, "0x833E040F85", "byte[5]")
	
	return $ret
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
	local $write3 = "0xE93EFFFFFF90" ; Jump within same DLL shouldn't require offset fixing
	
	local $restore = IsShowItemsToggle()
	if ($restore) then
		$write1 = "0xA3" & GetOffsetAddress($d2client + 0xFADB4)
		$write2	= "0xCCCCCCCCCCCCCCCCCCCCCCCC"
		$write3 = "0x891D" & GetOffsetAddress($d2client + 0xFADB4)
	endif
	
	_MemoryWrite($d2client + 0x3AECF, $d2handle, $write1, "byte[5]")
	_MemoryWrite($d2client + 0x3B224, $d2handle, $write2, "byte[12]")
	_MemoryWrite($d2client + 0x3B2E1, $d2handle, $write3, "byte[6]")
	
	_MemoryWrite($d2client + 0xFADB4, $d2handle, 0)
	PrintString($restore ? "Hold to show items." : "Toggle to show items.", 3)
endfunc

func GetOffsetAddress($addr)
	return StringFormat("%08s", StringLeft(Hex(Binary($addr)), 8))
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
	if (not $loadlib) then return _Debug("UpdateDllHandles", "Couldn't retrieve LoadLibraryA address.")
	
	local $addr = _MemVirtualAllocEx($d2handle[1], 0, 0x100, 0x3000, 0x40)
	if (@error) then return _Debug("UpdateDllHandles", "Failed to allocate memory.")

	local $nDlls = UBound($dlls)
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
	if (@error) then return _Debug("UpdateDllHandles", "Failed to free memory.")
	if ($failed) then return _Debug("UpdateDllHandles", "Couldn't retrieve dll addresses.")
	
	return True
endfunc

func _CreateRemoteThread($func, $var = 0) ; $var is in EBX register
	local $call = DllCall($d2handle[0], "ptr", "CreateRemoteThread", "ptr", $d2handle[1], "ptr", 0, "uint", 0, "ptr", $func, "ptr", $var, "dword", 0, "ptr", 0)
	if ($call[0] == 0) then return _Debug("UpdateDllHandles", "Couldn't create remote thread.")
	
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
