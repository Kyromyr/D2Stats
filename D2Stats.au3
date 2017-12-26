#RequireAdmin
#include <Array.au3>
#include <GuiEdit.au3>
#include <HotKey.au3>
#include <HotKeyInput.au3>
#include <Misc.au3>
#include <NomadMemory.au3>
#include <WinAPI.au3>

#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <GUIConstantsEx.au3>
#include <MemoryConstants.au3>
#include <MsgBoxConstants.au3>
#include <StringConstants.au3>
#include <StaticConstants.au3>
#include <TabConstants.au3>
#include <WindowsConstants.au3>

#pragma compile(Icon, Assets/icon.ico)
#pragma compile(FileDescription, Diablo II Stats reader)
#pragma compile(ProductName, D2Stats)
#pragma compile(ProductVersion, 3.9.5)
#pragma compile(FileVersion, 3.9.5)
#pragma compile(Comments, 26.12.2017)
#pragma compile(UPX, True) ;compression
#pragma compile(inputboxres, True)
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
	MsgBox($MB_ICONERROR, "D2Stats", "Admin rights needed!")
	exit
endif

if (not @Compiled) then
	HotKeySet("+{INS}", "HotKey_CopyStatsToClipboard")
	HotKeySet("+{PgUp}", "HotKey_CopyItemsToClipboard")
endif

Opt("MustDeclareVars", 1)
Opt("GUICloseOnESC", 0)
Opt("GUIOnEventMode", 1)

DefineGlobals()

OnAutoItExitRegister("_Exit")

CreateGUI()
Main()

#Region Main
func Main()
	_HotKey_Disable($HK_FLAG_D2STATS)

	local $hTimerUpdateDelay = TimerInit()
	local $bIsIngame, $bShowItems
	
	while 1
		Sleep(20)
		
		if (TimerDiff($hTimerUpdateDelay) > 250) then
			$hTimerUpdateDelay = TimerInit()
			
			UpdateHandle()
			UpdateGUIOptions()
			
			if (IsIngame()) then
				if (not $bIsIngame) then
					GUICtrlSetState($g_idNotifyTest, $GUI_ENABLE)
					$g_bNotifyCache = True
				endif
				
				InjectFunctions()
				_MemoryWrite($g_hD2Client + 0x6011B, $g_ahD2Handle, _GUI_Option("hidePass") ? 0x7F : 0x01, "byte")
				
				if (_GUI_Option("mousefix") <> IsMouseFixEnabled()) then ToggleMouseFix()
				
				if (IsShowItemsEnabled()) then
					if (_GUI_Option("toggleMsg")) then
						if (_MemoryRead($g_hD2Client + 0xFADB4, $g_ahD2Handle) == 0) then
							if ($bShowItems) then PrintString("Not showing items.", $ePrintBlue)
							$bShowItems = False
						else
							$bShowItems = True
						endif
					endif
					if (not _GUI_Option("toggle")) then ToggleShowItems()
				else
					$bShowItems = False
				endif
				
				if (_GUI_Option("nopickup") and not $bIsIngame) then _MemoryWrite($g_hD2Client + 0x11C2F0, $g_ahD2Handle, 1, "byte")
				
				if (_GUI_Option("notify-enabled")) then NotifierMain()
				
				$bIsIngame = True
			else
				if ($bIsIngame) then GUICtrlSetState($g_idNotifyTest, $GUI_DISABLE)
				
				$bIsIngame = False
			endif
		endif
	wend
endfunc

func _Exit()
	if (BitAND(GUICtrlGetState($g_idNotifySave), $GUI_ENABLE)) then
		local $iButton = MsgBox(BitOR($MB_ICONQUESTION, $MB_YESNO), "D2Stats", "There are unsaved changes in the notifier rules. Save?", 0, $g_hGUI)
		if ($iButton == $IDYES) then OnClick_NotifySave()
	endif
	
	OnAutoItExitUnRegister("_Exit")
	_GUICtrlHKI_Release()
	GUIDelete()
	_CloseHandle()
	_LogSave()
	exit
endfunc

func _CloseHandle()
	if ($g_ahD2Handle) then
		_MemoryClose($g_ahD2Handle)
		$g_ahD2Handle = 0
		$g_iD2pid = 0
	endif
endfunc

func UpdateHandle()
	local $hWnd = WinGetHandle("[CLASS:Diablo II]")
	local $iPID = WinGetProcess($hWnd)
	
	if ($iPID == -1) then return _CloseHandle()
	if ($iPID == $g_iD2pid) then return

	_CloseHandle()
	$g_iUpdateFailCounter += 1
	$g_ahD2Handle = _MemoryOpen($iPID)
	if (@error) then return _Debug("UpdateHandle", "Couldn't open Diablo II memory handle.")
	
	if (not UpdateDllHandles()) then
		_CloseHandle()
		return _Debug("UpdateHandle", "Couldn't update dll handles.")
	endif
	
	if (not InjectFunctions()) then
		_CloseHandle()
		return _Debug("UpdateHandle", "Couldn't inject functions.")
	endif

	$g_iUpdateFailCounter = 0
	$g_iD2pid = $iPID
	$g_pD2sgpt = _MemoryRead($g_hD2Common + 0x99E1C, $g_ahD2Handle)
endfunc

func IsIngame()
	if (not $g_iD2pid) then return False
	return _MemoryRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle) <> 0
endfunc

func _Debug($sFuncName, $sMessage, $iError = @error, $iExtended = @extended)
	_Log($sFuncName, $sMessage, $iError, $iExtended)
	PrintString($sMessage, $ePrintRed)
endfunc

func _Log($sFuncName, $sMessage, $iError = @error, $iExtended = @extended)
	$g_sLog &= StringFormat("[%s] %s (error: %s; extended: %s)%s", $sFuncName, $sMessage, $iError, $iExtended, @CRLF)
	
	if ($g_iUpdateFailCounter >= 10) then
		MsgBox($MB_ICONERROR, "D2Stats", "Failed too many times in a row. Check log for details. Closing D2Stats...", 0, $g_hGUI)
		exit
	endif
endfunc

func _LogSave()
	if ($g_sLog <> "") then
		local $hFile = FileOpen("D2Stats-log.txt", $FO_OVERWRITE)
		FileWrite($hFile, $g_sLog)
		FileFlush($hFile)
		FileClose($hFile)
	endif
endfunc
#EndRegion

#Region Hotkeys
func GetIlvl()
	local $apOffsetsIlvl[3] = [0, 0x14, 0x2C]
	local $iRet = _MemoryPointerRead($g_hD2Client + 0x11BC38, $g_ahD2Handle, $apOffsetsIlvl)
	if (not $iRet) then PrintString("Hover the cursor over an item first.", $ePrintRed)
	return $iRet
endfunc

func HotKey_CopyStatsToClipboard($TEST = False)
	if ($TEST or not IsIngame()) then return
	
	UpdateStatValues()
	local $sOutput = ""
	
	for $i = 0 to $g_iNumStats - 1
		local $iVal = GetStatValue($i)
		
		if ($iVal) then
			$sOutput &= StringFormat("%s = %s%s", $i, $iVal, @CRLF)
		endif
	next
	
	ClipPut($sOutput)
	PrintString("Stats copied to clipboard.")
endfunc

func HotKey_CopyItemsToClipboard($TEST = False)
	if ($TEST or not IsIngame()) then return
	
	local $iItemsTxt = _MemoryRead($g_hD2Common + 0x9FB94, $g_ahD2Handle)
	local $pItemsTxt = _MemoryRead($g_hD2Common + 0x9FB98, $g_ahD2Handle)

	local $pBaseAddr, $iNameID, $sName, $iMisc
	local $sOutput = ""
	
	for $iClass = 0 to $iItemsTxt - 1
		$pBaseAddr = $pItemsTxt + 0x1A8 * $iClass
		
		$iMisc = _MemoryRead($pBaseAddr + 0x84, $g_ahD2Handle, "dword")
		$iNameID = _MemoryRead($pBaseAddr + 0xF4, $g_ahD2Handle, "word")
		
		$sName = RemoteThread($g_pD2InjectGetString, $iNameID)
		$sName = _MemoryRead($sName, $g_ahD2Handle, "wchar[100]")
		$sName = StringReplace($sName, @LF, "|")
		
		$sOutput &= StringFormat("[class:%04i] [misc:%s] <%s>%s", $iClass, $iMisc ? 0 : 1, $sName, @CRLF)
	next
	
	ClipPut($sOutput)
	PrintString("Items copied to clipboard.")
endfunc

func HotKey_CopyItem($TEST = False)
	if ($TEST or not IsIngame() or GetIlvl() == 0) then return

	local $hTimerRetry = TimerInit()
	local $sOutput = ""
	
	while ($sOutput == "" and TimerDiff($hTimerRetry) < 10)
		$sOutput = _MemoryRead($g_hD2Win + 0xC9E58, $g_ahD2Handle, "wchar[800]")
	wend
	
	$sOutput = StringRegExpReplace($sOutput, "ÿc.", "")
	local $asLines = StringSplit($sOutput, @LF)
	
	$sOutput = ""
	for $i = $asLines[0] to 1 step -1
		$sOutput &= $asLines[$i] & @CRLF
	next

	ClipPut($sOutput)
	PrintString("Item text copied.")
endfunc

func HotKey_ShowIlvl($TEST = False)
	if ($TEST or not IsIngame()) then return

	local $iItemLevel = GetIlvl()
	if ($iItemLevel) then PrintString(StringFormat("ilvl: %02s", $iItemLevel))
endfunc

func HotKey_DropFilter($TEST = False)
	if ($TEST or not IsIngame()) then return

	local $hDropFilter = GetDropFilterHandle()

	if ($hDropFilter) then
		if (EjectDropFilter($hDropFilter)) then
			PrintString("Ejected DropFilter.", $ePrintGreen)
			_Log("HotKey_DropFilter", "Ejected DropFilter.")
		else
			_Debug("HotKey_DropFilter", "Failed to eject DropFilter.")
		endif
	else
		if (InjectDropFilter()) then
			PrintString("Injected DropFilter.", $ePrintGreen)
			_Log("HotKey_DropFilter", "Injected DropFilter.")
		else
			_Debug("HotKey_DropFilter", "Failed to inject DropFilter.")
		endif
	endif
endfunc

func HotKey_ToggleShowItems($TEST = False)
	if ($TEST or not IsIngame()) then return
	ToggleShowItems()
endfunc
#EndRegion

#Region Stat reading
func UpdateStatValueMem($iVector)
	if ($iVector <> 0 and $iVector <> 1) then _Debug("UpdateStatValueMem", "Invalid $iVector value.")
	
	local $aiOffsets[3] = [0, 0x5C, ($iVector+1)*0x24]
	local $pStatList = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets)

	$aiOffsets[2] += 0x4
	local $iStatCount = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets, "word") - 1

	local $tagStat = "word wSubIndex;word wStatIndex;int dwStatValue;", $tagStatsAll
	for $i = 0 to $iStatCount
		$tagStatsAll &= $tagStat
	next

	local $tStats = DllStructCreate($tagStatsAll)
	_WinAPI_ReadProcessMemory($g_ahD2Handle[1], $pStatList, DllStructGetPtr($tStats), DllStructGetSize($tStats), 0)

	local $iStart = $iVector == 1 ? 5 : 0
	local $iStatIndex, $iStatValue
	
	for $i = $iStart to $iStatCount
		$iStatIndex = DllStructGetData($tStats, 2 + (3 * $i))
		if ($iStatIndex >= $g_iNumStats) then
			continueloop ; Should never happen
		endif
		
		$iStatValue = DllStructGetData($tStats, 3 + (3 * $i))
		switch $iStatIndex
			case 6 to 11
				$g_aiStatsCache[$iVector][$iStatIndex] += $iStatValue / 256
			case else
				$g_aiStatsCache[$iVector][$iStatIndex] += $iStatValue
		endswitch
	next
endfunc

func UpdateStatValues()
	for $i = 0 to $g_iNumStats - 1
		$g_aiStatsCache[0][$i] = 0
		$g_aiStatsCache[1][$i] = 0
	next
	
	if (IsIngame()) then
		UpdateStatValueMem(0)
		UpdateStatValueMem(1)
		FixStatVelocities()
		FixVeteranToken()
		
		; Poison damage to damage/second
		$g_aiStatsCache[1][57] *= (25/256)
		$g_aiStatsCache[1][58] *= (25/256)
	endif
endfunc

func FixStatVelocities() ; This game is stupid
	for $i = 67 to 69
		$g_aiStatsCache[1][$i] = 0
	next
	
	local $pSkillsTxt = _MemoryRead($g_pD2sgpt + 0xB98, $g_ahD2Handle)
	local $iSkillID, $pStats, $iStatCount, $pSkill, $iStatIndex, $iStatValue, $iOwnerType, $iStateID
	
	; local $wep_main_offsets[3] = [0, 0x60, 0x1C]
	; local $wep_main = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $wep_main_offsets)
	
	local $aiOffsets[3] = [0, 0x5C, 0x3C]
	local $pStatList = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets)

	while $pStatList
		$iOwnerType = _MemoryRead($pStatList + 0x08, $g_ahD2Handle)
		$pStats = _MemoryRead($pStatList + 0x24, $g_ahD2Handle)
		$iStatCount = _MemoryRead($pStatList + 0x28, $g_ahD2Handle, "word")
		$pStatList = _MemoryRead($pStatList + 0x2C, $g_ahD2Handle)
		
		$iSkillID = 0

		for $i = 0 to $iStatCount - 1
			$iStatIndex = _MemoryRead($pStats + $i*8 + 2, $g_ahD2Handle, "word")
			$iStatValue = _MemoryRead($pStats + $i*8 + 4, $g_ahD2Handle, "int")
			
			if ($iStatIndex == 350 and $iStatValue <> 511) then $iSkillID = $iStatValue
			if ($iOwnerType == 4 and $iStatIndex == 67) then $g_aiStatsCache[1][$iStatIndex] += $iStatValue ; Armor FRW penalty
		next
		
		if ($iOwnerType == 4) then continueloop
		
		$iStateID = _MemoryRead($pStatList + 0x14, $g_ahD2Handle)
		if ($iStateID == 195) then ; Dark Power / Tome of Possession aura
			$iSkillID = 687 ; Dark Power
		endif

		local $bHasStat[3] = [False,False,False]
		if ($iSkillID) then ; Game doesn't even bother setting the skill id for some skills, so we'll just have to hope the state is correct or the stat list isn't lying...
			$pSkill = $pSkillsTxt + 0x23C*$iSkillID
		
			for $i = 0 to 4
				$iStatIndex = _MemoryRead($pSkill + 0x98 + $i*2, $g_ahD2Handle, "word")
				
				switch $iStatIndex
					case 67 to 69
						$bHasStat[$iStatIndex-67] = True
				endswitch
			next
			
			for $i = 0 to 5
				$iStatIndex = _MemoryRead($pSkill + 0x54 + $i*2, $g_ahD2Handle, "word")
				
				switch $iStatIndex
					case 67 to 69
						$bHasStat[$iStatIndex-67] = True
				endswitch
			next
		endif
		
		for $i = 0 to $iStatCount - 1
			$iStatIndex = _MemoryRead($pStats + $i*8 + 2, $g_ahD2Handle, "word")
			$iStatValue = _MemoryRead($pStats + $i*8 + 4, $g_ahD2Handle, "int")
			
			switch $iStatIndex
				case 67 to 69
					if (not $iSkillID or $bHasStat[$iStatIndex-67]) then $g_aiStatsCache[1][$iStatIndex] += $iStatValue
			endswitch
		next
	wend
endfunc

func FixVeteranToken()
	$g_aiStatsCache[1][219] = 0 ; Veteran token

	local $aiOffsets[3] = [0, 0x60, 0x0C]
	local $pItem = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets)
	
	local $pItemData, $pStatsEx, $pStats, $iStatCount, $iStatIndex, $iVeteranTokenCounter
	
	while $pItem
		$pItemData = _MemoryRead($pItem + 0x14, $g_ahD2Handle)
		$pStatsEx = _MemoryRead($pItem + 0x5C, $g_ahD2Handle)
		$pItem = _MemoryRead($pItemData + 0x64, $g_ahD2Handle)
		if (not $pStatsEx) then continueloop
		
		$pStats = _MemoryRead($pStatsEx + 0x48, $g_ahD2Handle)
		if (not $pStats) then continueloop
		
		$iStatCount = _MemoryRead($pStatsEx + 0x4C, $g_ahD2Handle, "word")
		$iVeteranTokenCounter = 0
		
		for $i = 0 to $iStatCount - 1
			$iStatIndex = _MemoryRead($pStats + $i*8 + 2, $g_ahD2Handle, "word")
			
			switch $iStatIndex
				case 83, 85, 219
					$iVeteranTokenCounter += 1
			endswitch
		next
		
		if ($iVeteranTokenCounter == 3) then
			$g_aiStatsCache[1][219] = 1 ; Veteran token
			return
		endif
	wend
endfunc

func GetStatValue($iStatID)
	local $iVector = $iStatID < 4 ? 0 : 1
	local $iStatValue = $g_aiStatsCache[$iVector][$iStatID]
	return Floor($iStatValue ? $iStatValue : 0)
endfunc
#EndRegion

#Region Drop notifier
func NotifierFlag($sFlag)
	for $i = 0 to $eNotifyFlagsLast - 1
		for $j = 0 to UBound($g_asNotifyFlags, $UBOUND_COLUMNS) - 1
			if ($g_asNotifyFlags[$i][$j] == "") then
				exitloop
			elseif ($g_asNotifyFlags[$i][$j] == $sFlag) then
				return BitRotate(1, $j, "D")
			endif
		next
	next
	return SetError(1, 0, 0)
endfunc

func NotifierFlagRef($sFlag, ByRef $iFlag, ByRef $iGroup)
	$iFlag = 0
	$iGroup = 0
	
	for $i = 0 to $eNotifyFlagsLast - 1
		for $j = 0 to UBound($g_asNotifyFlags, $UBOUND_COLUMNS) - 1
			if ($g_asNotifyFlags[$i][$j] == "") then
				exitloop
			elseif ($g_asNotifyFlags[$i][$j] == $sFlag) then
				$iGroup = $i
				$iFlag = $j
				return 1
			endif
		next
	next
	
	return SetError(1, 0, 0)
endfunc

func NotifierCache()
	if (not $g_bNotifyCache) then return
	$g_bNotifyCache = False
	
	local $iItemsTxt = _MemoryRead($g_hD2Common + 0x9FB94, $g_ahD2Handle)
	local $pItemsTxt = _MemoryRead($g_hD2Common + 0x9FB98, $g_ahD2Handle)

	local $pBaseAddr, $iNameID, $sName, $asMatch, $sTier
	
	redim $g_avNotifyCache[$iItemsTxt][2]
	
	for $iClass = 0 to $iItemsTxt - 1
		$pBaseAddr = $pItemsTxt + 0x1A8 * $iClass
		
		$iNameID = _MemoryRead($pBaseAddr + 0xF4, $g_ahD2Handle, "word")
		$sName = RemoteThread($g_pD2InjectGetString, $iNameID)
		$sName = _MemoryRead($sName, $g_ahD2Handle, "wchar[100]")
		
		$sName = StringReplace($sName, @LF, "|")
		$sName = StringRegExpReplace($sName, "ÿc.", "")
		$sTier = "0"
		
		if (_MemoryRead($pBaseAddr + 0x84, $g_ahD2Handle)) then ; Weapon / Armor
			$asMatch = StringRegExp($sName, "[1-6]|\Q(Sacred)\E", $STR_REGEXPARRAYGLOBALMATCH)
			if (not @error) then $sTier = $asMatch[0] == "(Sacred)" ? "sacred" : $asMatch[0]
		endif
		
		$g_avNotifyCache[$iClass][0] = $sName
		$g_avNotifyCache[$iClass][1] = NotifierFlag($sTier)
		
		if (@error) then
			_Debug("NotifierCache", StringFormat("Invalid tier flag '%s'", $sTier))
			exit
		endif
	next
endfunc

func NotifierCompileFlag($sFlag, ByRef $avRet, $sLine)
	if ($sFlag == "") then return False
	
	local $iFlag, $iGroup
	if (not NotifierFlagRef($sFlag, $iFlag, $iGroup)) then
		MsgBox(0, "D2Stats", StringFormat("Unknown notifier flag '%s' in line:%s%s", $sFlag, @CRLF, $sLine))
		return False
	endif
	
	if ($iGroup <> $eNotifyFlagsColour) then $iFlag = BitOR(BitRotate(1, $iFlag, "D"), $avRet[$iGroup])
	$avRet[$iGroup] = $iFlag

	return $iGroup <> $eNotifyFlagsColour
endfunc

func NotifierCompileLine($sLine, ByRef $avRet)
	$sLine = StringStripWS(StringRegExpReplace($sLine, "#.*", ""), BitOR($STR_STRIPLEADING, $STR_STRIPTRAILING, $STR_STRIPSPACES))
	local $iLineLength = StringLen($sLine)
	
	local $sArg = "", $sChar
	local $bQuoted = False, $bHasFlags = False
	
	redim $avRet[0]
	redim $avRet[$eNotifyFlagsLast]
	
	for $i = 1 to $iLineLength
		$sChar = StringMid($sLine, $i, 1)
		
		if ($sChar == '"') then
			if ($bQuoted) then
				$avRet[$eNotifyFlagsMatch] = $sArg
				$sArg = ""
			endif
			
			$bQuoted = not $bQuoted
		elseif ($sChar == " " and not $bQuoted) then
			if (NotifierCompileFlag($sArg, $avRet, $sLine)) then $bHasFlags = True
			$sArg = ""
		else
			$sArg &= $sChar
		endif
	next

	if (NotifierCompileFlag($sArg, $avRet, $sLine)) then $bHasFlags = True
	if ($bHasFlags and $avRet[$eNotifyFlagsMatch] == "") then $avRet[$eNotifyFlagsMatch] = ".+"
endfunc

func NotifierCompile()
	if (not $g_bNotifyCompile) then return
	$g_bNotifyCompile = False
	
	local $asLines = StringSplit(_GUI_Option("notify-text"), @LF)
	local $iLines = $asLines[0]
	
	redim $g_avNotifyCompile[0][0]
	redim $g_avNotifyCompile[$iLines][$eNotifyFlagsLast]
	
	local $avRet[0]
	local $iCount = 0
	
	for $i = 1 to $iLines
		NotifierCompileLine($asLines[$i], $avRet)
		
		if ($avRet[$eNotifyFlagsMatch] <> "") then
			for $j = 0 to $eNotifyFlagsLast - 1
				$g_avNotifyCompile[$iCount][$j] = $avRet[$j]
			next
			$iCount += 1
		endif
	next
	
	redim $g_avNotifyCompile[$iCount][$eNotifyFlagsLast]
endfunc

func NotifierTest($sInput)
	NotifierCache()
	
	local $avRet[0]
	NotifierCompileLine($sInput, $avRet)
	
	local $sMatch = $avRet[$eNotifyFlagsMatch]
	local $iFlagsTier = $avRet[$eNotifyFlagsTier]
	
	local $sFlags = StringRegExpReplace($sInput, '("[^"]+")|(#.*)', "")
	$sFlags = StringStripWS($sFlags, BitOR($STR_STRIPLEADING, $STR_STRIPTRAILING))
	
	local $iItems = UBound($g_avNotifyCache)
	local $asMatches[$iItems + 1][2] = [ [$sMatch, $sFlags] ]
	
	local $sName, $iTierFlag, $asMatch, $bRequireTier
	local $iCount = 1
	
	if ($sMatch <> "" or $iFlagsTier) then
		for $i = 0 to $iItems - 1
			$sName = $g_avNotifyCache[$i][0]
			$iTierFlag = $g_avNotifyCache[$i][1]
			
			$asMatch = StringRegExp($sName, $sMatch == "" ? ".*" : $sMatch, $STR_REGEXPARRAYGLOBALMATCH)
			if (not @error) then
				if ($iFlagsTier and not BitAND($iFlagsTier, $iTierFlag)) then continueloop
				
				$asMatches[$iCount][0] = $sName
				$asMatches[$iCount][1] = $asMatch[0]
				$iCount += 1
			endif
		next
	endif
	
	redim $asMatches[$iCount][2]
	_ArrayDisplay($asMatches, "Notifier Test", default, 32, @LF, "Item|Text")
endfunc

func NotifierMain()
	NotifierCache()
	NotifierCompile()
	
	local $aiOffsets[4] = [0, 0x2C, 0x1C, 0x0]
	local $pPaths = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets)
	
	$aiOffsets[3] = 0x24
	local $iPaths = _MemoryPointerRead($g_hD2Client + 0x11BBFC, $g_ahD2Handle, $aiOffsets)
	
	if (not $pPaths or not $iPaths) then return
	
	local $pPath, $pUnit, $pUnitData
	local $iUnitType, $iClass, $iQuality, $iEarLevel, $iFlags, $sName, $iTierFlag
	local $bIsNewItem, $bIsSocketed, $bIsEthereal
	local $iFlagsTier, $iFlagsQuality, $iFlagsMisc, $iFlagsColour
	local $asMatch, $sText, $iColor, $bNotify

	local $tUnitAny = DllStructCreate("dword iUnitType;dword iClass;dword pad1[3];dword pUnitData;dword pad2[52];dword pUnit;")
	local $tItemData = DllStructCreate("dword iQuality;dword pad1[5];dword iFlags;dword pad2[11];byte iEarLevel;")
	
	for $i = 0 to $iPaths - 1
		$pPath = _MemoryRead($pPaths + 4*$i, $g_ahD2Handle)
		$pUnit = _MemoryRead($pPath + 0x74, $g_ahD2Handle)
		
		while $pUnit
			_WinAPI_ReadProcessMemory($g_ahD2Handle[1], $pUnit, DllStructGetPtr($tUnitAny), DllStructGetSize($tUnitAny), 0)
			$iUnitType = DllStructGetData($tUnitAny, "iUnitType")
			$pUnitData = DllStructGetData($tUnitAny, "pUnitData")
			$iClass = DllStructGetData($tUnitAny, "iClass")
			$pUnit = DllStructGetData($tUnitAny, "pUnit")
			
			; iUnitType 4 = item
			if ($iUnitType == 4) then
				_WinAPI_ReadProcessMemory($g_ahD2Handle[1], $pUnitData, DllStructGetPtr($tItemData), DllStructGetSize($tItemData), 0)
				$iQuality = DllStructGetData($tItemData, "iQuality")
				$iFlags = DllStructGetData($tItemData, "iFlags")
				$iEarLevel = DllStructGetData($tItemData, "iEarLevel")
				
				; Using the ear level field to check if we've seen this item on the ground before
				; Resets when the item is picked up or we move too far away
				if ($iEarLevel <> 0) then continueloop
				_MemoryWrite($pUnitData + 0x48, $g_ahD2Handle, 1, "byte")
				
				$bIsNewItem = BitAND(0x2000, $iFlags) <> 0
				$bIsSocketed = BitAND(0x800, $iFlags) <> 0
				$bIsEthereal = BitAND(0x400000, $iFlags) <> 0
				
				$sName = $g_avNotifyCache[$iClass][0]
				$iTierFlag = $g_avNotifyCache[$iClass][1]
				
				$bNotify = False
				
				for $j = 0 to UBound($g_avNotifyCompile) - 1
					$asMatch = StringRegExp($sName, $g_avNotifyCompile[$j][$eNotifyFlagsMatch], $STR_REGEXPARRAYGLOBALMATCH)

					if (not @error) then
						$sText = $asMatch[0]
						if ($sText == "") then continueloop
						
						$iFlagsTier = $g_avNotifyCompile[$j][$eNotifyFlagsTier]
						$iFlagsQuality = $g_avNotifyCompile[$j][$eNotifyFlagsQuality]
						$iFlagsMisc = $g_avNotifyCompile[$j][$eNotifyFlagsMisc]
						$iFlagsColour = $g_avNotifyCompile[$j][$eNotifyFlagsColour]

						if ($iFlagsTier and not BitAND($iFlagsTier, $iTierFlag)) then continueloop
						if ($iFlagsQuality and not BitAND($iFlagsQuality, BitRotate(1, $iQuality - 1, "D"))) then continueloop
						if (not $bIsSocketed and BitAND($iFlagsMisc, NotifierFlag("socket"))) then continueloop
						
						if ($bIsEthereal) then
							$sText &= " (Eth)"
						elseif (BitAND($iFlagsMisc, NotifierFlag("eth"))) then
							continueloop
						endif
						$bNotify = True
						exitloop
					endif
				next
				
				if ($bNotify) then
					if ($iFlagsColour) then
						$iColor = $iFlagsColour - 1
					elseif ($iQuality == $eQualityNormal and $iTierFlag == NotifierFlag("0")) then
						$iColor = $ePrintOrange
					else
						$iColor = $g_iQualityColor[$iQuality]
					endif

					PrintString("- " & $sText, $iColor)
				endif
			endif
		wend
	next
endfunc
#EndRegion

#Region GUI helper functions
func _GUI_StringWidth($sText)
	return 2 + 7 * StringLen($sText)
endfunc

func _GUI_LineY($iLine)
	return 28 + 15*$iLine
endfunc

func _GUI_GroupX($iX = default)
	if ($iX <> default) then $g_avGUI[0][1] = $iX
	return $g_avGUI[0][1]
endfunc

func _GUI_GroupFirst()
	$g_avGUI[0][1] = $g_iGroupXStart
endfunc

func _GUI_GroupNext()
	$g_avGUI[0][1] += $g_iGroupWidth
endfunc

func _GUI_ItemCount()
	return $g_avGUI[0][0]
endfunc

func _GUI_NewItem($iLine, $sText, $sTip = default, $iColor = default)
	$g_avGUI[0][0] += 1
	local $iCount = $g_avGUI[0][0]
	
	$g_avGUI[$iCount][0] = $sText
	$g_avGUI[$iCount][1] = _GUI_GroupX()
	$g_avGUI[$iCount][2] = _GUI_NewText($iLine, $sText, $sTip, $iColor)
endfunc

func _GUI_NewText($iLine, $sText, $sTip = default, $iColor = default)
	local $idRet = _GUI_NewTextBasic($iLine, $sText)

	; GUICtrlSetBkColor(-1, Random(0, 2147483647, 1))
	if ($sTip <> default) then
		GUICtrlSetTip(-1, StringReplace($sTip, "|", @LF), default, default, $TIP_CENTER)
	endif
	if ($iColor >= default) then
		GUICtrlSetColor(-1, $iColor)
	endif
	return $idRet
endfunc

func _GUI_NewTextBasic($iLine, $sText, $bCentered = True)
	local $iWidth = _GUI_StringWidth($sText)
	local $iX = _GUI_GroupX() - ($bCentered ? $iWidth/2 : 0)
	return GUICtrlCreateLabel($sText, $iX, _GUI_LineY($iLine), $iWidth, 15, $bCentered ? $SS_CENTER : $SS_LEFT)
endfunc

func _GUI_ItemByRef($iItem, byref $sText, byref $iX, byref $idControl)
	$sText = $g_avGUI[$iItem][0]
	$iX = $g_avGUI[$iItem][1]
	$idControl = $g_avGUI[$iItem][2]
endfunc

func _GUI_OptionCount()
	return $g_avGUIOption[0][0]
endfunc

func _GUI_NewOption($iLine, $sOption, $sText, $sFunc = "")
	local $iY = _GUI_LineY($iLine)*2 - _GUI_LineY(0)
	
	local $idControl
	local $sOptionType = _GUI_OptionType($sOption)
	
	switch $sOptionType
		case null
			_Log("_GUI_NewOption", "Invalid option '" & $sOption & "'")
			exit
		case "hk"
			Call($sFunc, True)
			if (@error == 0xDEAD and @extended == 0xBEEF) then
				_Log("_GUI_NewOption", StringFormat("No hotkey function '%s' for option '%s'", $sFunc, $sOption))
				exit
			endif
			
			local $iKeyCode = _GUI_Option($sOption)
			if ($iKeyCode) then
				_KeyLock($iKeyCode)
				_HotKey_Assign($iKeyCode, $sFunc, $HK_FLAG_D2STATS, "[CLASS:Diablo II]")
			endif
			
			$idControl = _GUICtrlHKI_Create($iKeyCode, _GUI_GroupX(), $iY, 120, 25)
			GUICtrlCreateLabel($sText, _GUI_GroupX() + 124, $iY + 4)
		case "cb"
			$idControl = GUICtrlCreateCheckbox($sText, _GUI_GroupX(), $iY)
			GUICtrlSetState(-1, _GUI_Option($sOption) ? $GUI_CHECKED : $GUI_UNCHECKED)
		case else
			_Log("_GUI_NewOption", "Invalid option type '" & $sOptionType & "'")
			exit
	endswitch
	
	$g_avGUIOption[0][0] += 1
	local $iIndex = $g_avGUIOption[0][0]
	
	$g_avGUIOption[$iIndex][0] = $sOption
	$g_avGUIOption[$iIndex][1] = $idControl
	$g_avGUIOption[$iIndex][2] = $sFunc
endfunc

func _GUI_OptionByRef($iOption, byref $sOption, byref $idControl, byref $sFunc)
	$sOption = $g_avGUIOption[$iOption][0]
	$idControl = $g_avGUIOption[$iOption][1]
	$sFunc = $g_avGUIOption[$iOption][2]
endfunc

func _GUI_OptionID($sOption)
	for $i = 0 to UBound($g_avGUIOptionList) - 1
		if ($g_avGUIOptionList[$i][0] == $sOption) then return $i
	next
	_Log("_GUI_OptionID", "Invalid option '" & $sOption "'")
	exit
endfunc

func _GUI_OptionType($sOption)
	return $g_avGUIOptionList[ _GUI_OptionID($sOption) ][2]
endfunc

func _GUI_Option($sOption, $vValue = default)
	local $iOption = _GUI_OptionID($sOption)
	local $vOld = $g_avGUIOptionList[$iOption][1]
	
	if ($vValue <> default and $vValue <> $vOld) then
		$g_avGUIOptionList[$iOption][1] = $vValue
		SaveGUISettings()
	endif
	
	return $vOld
endfunc
#EndRegion

#Region GUI
func UpdateGUI()
	local $sText, $iX, $idControl
	local $asMatches, $iMatches, $iWidth, $iColor, $iStatValue
	
	for $i = 1 to _GUI_ItemCount()
		_GUI_ItemByRef($i, $sText, $iX, $idControl)
		$iColor = 0
		
		$asMatches = StringRegExp($sText, "(\[(\d+):(\d+)/(\d+)\])", $STR_REGEXPARRAYGLOBALMATCH)
		$iMatches = UBound($asMatches)
		
		if ($iMatches <> 0 and $iMatches <> 4) then
			_Log("UpdateGUI", "Invalid coloring pattern '" & $sText & "'")
			exit
		elseif ($iMatches == 4) then
			$sText = StringReplace($sText, $asMatches[0], "")
			$iColor = $g_iColorRed
			
			$iStatValue = GetStatValue($asMatches[1])
			if ($iStatValue >= $asMatches[2]) then
				$iColor = $g_iColorGreen
			elseif ($iStatValue >= $asMatches[3]) then
				$iColor = $g_iColorGold
			endif
		endif
		
		$asMatches = StringRegExp($sText, "({(\d+)})", $STR_REGEXPARRAYGLOBALMATCH)
		for $j = 0 to UBound($asMatches) - 1 step 2
			$sText = StringReplace($sText, $asMatches[$j+0], GetStatValue($asMatches[$j+1]))
		next
		
		$sText = StringStripWS($sText, BitOR($STR_STRIPLEADING, $STR_STRIPTRAILING, $STR_STRIPSPACES))
		GUICtrlSetData($idControl, $sText)
		if ($iColor <> 0) then GUICtrlSetColor($idControl, $iColor)
		
		$iWidth = _GUI_StringWidth($sText)
		GUICtrlSetPos($idControl, $iX - $iWidth/2, default, $iWidth, default)
	next
endfunc

func OnClick_ReadStats()
	UpdateStatValues()
	UpdateGUI()
endfunc

func OnClick_Tab()
	GUICtrlSetState($g_idReadStats, GUICtrlRead($g_idTab) < 2 ? $GUI_SHOW : $GUI_HIDE)
endfunc

func OnClick_NotifySave()
	_GUI_Option("notify-text", GUICtrlRead($g_idNotifyEdit))
	OnChange_NotifyEdit()
	$g_bNotifyCompile = True
endfunc

func OnClick_NotifyReset()
	GUICtrlSetData($g_idNotifyEdit, _GUI_Option("notify-text"))
	OnChange_NotifyEdit()
endfunc

func OnClick_NotifyTest()
	local $asText[] = [ _ 
		'"Item Name" flag1 flag2 ... flagN # Everything after hashtag is a comment.', _
		'', _
		'Item name is what you''re matching against. It''s a regex string.', _
		'If you''re unsure what regex is, use letters only.', _
		'', _
		'Flags:', _
		'> 0-6 sacred - Item must be one of these tiers.', _
		'   Tier 0 means untiered items (runes, amulets, etc).', _
		'> superior rare set unique - Item must be one of these qualities.', _
		'> eth socket - Item must be ethereal and/or socketed.', _
		'> white red lime blue gold orange yellow green purple - Notification color', _
		'', _
		'Example:', _
		'"Battle" sacred unique eth', _
		'', _
		'This would notify for ethereal SU Battle Axe, Battle Staff,', _
		'Short Battle Bow and Long Battle Bow' _
	]
	
	local $sText = ""
	for $i = 0 to UBound($asText) - 1
		$sText &= $asText[$i] & @CRLF
	next
	
	local $sInput = InputBox("Notifier Test", $sText, default, default, 420, 120 + UBound($asText) * 13, default, default, default, $g_hGUI)
	if (not @error) then NotifierTest($sInput)
endfunc

func OnClick_NotifyDefault()
	GUICtrlSetData($g_idNotifyEdit, $g_sNotifyTextDefault)
	OnChange_NotifyEdit()
endfunc

func OnChange_NotifyEdit()
	local $iState = _GUI_Option("notify-text") == GUICtrlRead($g_idNotifyEdit) ? $GUI_DISABLE : $GUI_ENABLE
	GUICtrlSetState($g_idNotifySave, $iState)
	GUICtrlSetState($g_idNotifyReset, $iState)
endfunc

func CreateGUI()
	global $g_iGroupLines = 14
	global $g_iGroupWidth = 110
	global $g_iGroupXStart = 8 + $g_iGroupWidth/2
	global $g_iGUIWidth = 16 + 4*$g_iGroupWidth
	global $g_iGUIHeight = 34 + 15*$g_iGroupLines

	local $sTitle = not @Compiled ? "Test" : StringFormat("D2Stats%s %s - [%s]", @AutoItX64 ? "-64" : "", FileGetVersion(@AutoItExe, "FileVersion"), FileGetVersion(@AutoItExe, "Comments"))
	
	global $g_hGUI = GUICreate($sTitle, $g_iGUIWidth, $g_iGUIHeight)
	GUISetFont(9 / _GetDPI()[2], 0, 0, "Courier New")
	GUISetOnEvent($GUI_EVENT_CLOSE, "_Exit")
	
	global $g_idReadStats = GUICtrlCreateButton("Read", $g_iGroupXStart-35, $g_iGUIHeight-31, 70, 25)
	GUICtrlSetOnEvent(-1, "OnClick_ReadStats")

	global $g_idTab = GUICtrlCreateTab(0, 0, $g_iGUIWidth, 0, $TCS_FOCUSNEVER)
	GUICtrlSetOnEvent(-1, "OnClick_Tab")
	
	local $idDummySelectAll = GUICtrlCreateDummy()
	GUICtrlSetOnEvent(-1, "DummySelectAll")

	local $avAccelKeys[][2] = [ ["^a", $idDummySelectAll] ]
	GUISetAccelerators($avAccelKeys)
	
#Region Stats
	GUICtrlCreateTabItem("Page 1")
	_GUI_GroupFirst()
	_GUI_NewText(00, "Base stats")
	_GUI_NewItem(01, "{000} Strength")
	_GUI_NewItem(02, "{002} Dexterity")
	_GUI_NewItem(03, "{003} Vitality")
	_GUI_NewItem(04, "{001} Energy")
	
	_GUI_NewItem(06, "{080}% M.Find", "Magic Find")
	_GUI_NewItem(07, "{085}% Exp.Gain", "Experience gained")
	_GUI_NewItem(08, "{479} M.Skill", "Maximum Skill Level")
	_GUI_NewItem(09, "{185} Sig.Stat [185:500/500]", "Signets of Learning. Up to 500 can be used||Any sacred unique item x1-25 + Catalyst of Learning ? Signet of Learning x1-25 + Catalyst of Learning|Any set item x1-25 + Catalyst of Learning ? Signet of Learning x1-25 + Catalyst of Learning|Unique ring/amulet/jewel/quiver + Catalyst of Learning ? Signet of Learning + Catalyst of Learning")
	_GUI_NewItem(10, "{186} Sig.Skill [186:3/3]", "Signets of Skill. Up to 3 can be used||On Destruction difficulty, monsters in the Torajan Jungles have a chance to drop these")
	_GUI_NewItem(11, "Veteran tokens [219:1/1]", "On Terror and Destruction difficulty, you can find veteran monsters near the end of|each Act. There are five types of veteran monsters, one for each Act||[Class Charm] + each of the 5 tokens ? returns [Class Charm] with added bonuses| +1 to [Your class] Skill Levels| +20% to Experience Gained")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Bonus stats")
	_GUI_NewItem(01, "{359}% Strength")
	_GUI_NewItem(02, "{360}% Dexterity")
	_GUI_NewItem(03, "{362}% Vitality")
	_GUI_NewItem(04, "{361}% Energy")
	
	_GUI_NewText(06, "Item/Skill", "Speed from items and skills behave differently. Use SpeedCalc to find your breakpoints")
	_GUI_NewItem(07, "{093}%/{068}% IAS", "Increased Attack Speed")
	_GUI_NewItem(08, "{099}%/{069}% FHR", "Faster Hit Recovery")
	_GUI_NewItem(09, "{102}%/{069}% FBR", "Faster Block Rate")
	_GUI_NewItem(10, "{096}%/{067}% FRW", "Faster Run/Walk")
	_GUI_NewItem(11, "{105}%/0% FCR", "Faster Cast Rate")
	
	_GUI_GroupNext()
	_GUI_NewItem(00, "{076}% Life", "Maximum Life")
	_GUI_NewItem(01, "{077}% Mana", "Maximum Mana")
	_GUI_NewItem(02, "{025}% EWD", "Enchanced Weapon Damage")
	_GUI_NewItem(03, "{171}% TCD", "Total Character Defense")
	_GUI_NewItem(04, "{119}% AR", "Attack Rating")
	_GUI_NewItem(05, "{035} MDR", "Magic Damage Reduction")
	_GUI_NewItem(06, "{338}% Dodge", "Chance to avoid melee attacks while standing still")
	_GUI_NewItem(07, "{339}% Avoid", "Chance to avoid projectiles while standing still")
	_GUI_NewItem(08, "{340}% Evade", "Chance to avoid any attack while moving")

	_GUI_NewItem(10, "{136}% CB", "Crushing Blow. Chance to deal physical damage based on target's current health")
	_GUI_NewItem(11, "{135}% OW", "Open Wounds. Chance to disable target's natural health regen for 8 seconds")
	_GUI_NewItem(12, "{141}% DS", "Deadly Strike. Chance to double physical damage of attack")
	_GUI_NewItem(13, "{164}% UA", "Uninterruptable Attack")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Res/Abs/Flat", "Resist / Absorb / Flat absorb")
	_GUI_NewItem(01, "{039}%/{142}%/{143}", "Fire", $g_iColorRed)
	_GUI_NewItem(02, "{043}%/{148}%/{149}", "Cold", $g_iColorBlue)
	_GUI_NewItem(03, "{041}%/{144}%/{145}", "Lightning", $g_iColorGold)
	_GUI_NewItem(04, "{045}%/0%/0", "Poison", $g_iColorGreen)
	_GUI_NewItem(05, "{037}%/{146}%/{147}", "Magic", $g_iColorPink)
	_GUI_NewItem(06, "{036}%/{034}", "Physical (aka Damage Reduction)")
	
	_GUI_NewText(08, "Damage/Pierce", "Spell damage / -Enemy resist")
	_GUI_NewItem(09, "{329}%/{333}%", "Fire", $g_iColorRed)
	_GUI_NewItem(10, "{331}%/{335}%", "Cold", $g_iColorBlue)
	_GUI_NewItem(11, "{330}%/{334}%", "Lightning", $g_iColorGold)
	_GUI_NewItem(12, "{332}%/{336}%", "Poison", $g_iColorGreen)
	_GUI_NewItem(13, "{377}%/0%", "Physical/Magic", $g_iColorPink)
	
	GUICtrlCreateTabItem("Page 2")
	_GUI_GroupFirst()
	_GUI_NewItem(00, "{278} SF", "Strength Factor")
	_GUI_NewItem(01, "{485} EF", "Energy Factor")
	_GUI_NewItem(02, "{431}% PSD", "Poison Skill Duration")
	_GUI_NewItem(03, "{409}% Buff.Dur", "Buff/Debuff/Cold Skill Duration")
	_GUI_NewItem(04, "{27}% Mana.Reg", "Mana Regeneration")
	_GUI_NewItem(05, "{109}% CLR", "Curse Length Reduction")
	_GUI_NewItem(06, "{110}% PLR", "Poison Length Reduction")
	_GUI_NewItem(07, "{489} TTAD", "Target Takes Additional Damage")
	
	_GUI_NewText(09, "Slow")
	_GUI_NewItem(10, "{150}%/{376}% Tgt.", "Slows Target / Slows Melee Target")
	_GUI_NewItem(11, "{363}%/{493}% Att.", "Slows Attacker / Slows Ranged Attacker")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Weapon Damage")
	_GUI_NewItem(01, "{048}-{049}", "Fire", $g_iColorRed)
	_GUI_NewItem(02, "{054}-{055}", "Cold", $g_iColorBlue)
	_GUI_NewItem(03, "{050}-{051}", "Lightning", $g_iColorGold)
	_GUI_NewItem(04, "{057}-{058}/s", "Poison/sec", $g_iColorGreen)
	_GUI_NewItem(05, "{052}-{053}", "Magic", $g_iColorPink)
	
	_GUI_NewText(07, "Life/Mana")
	_GUI_NewItem(08, "{060}%/{062}% Leech", "Life/Mana Stolen per Hit")
	_GUI_NewItem(09, "{086}/{138} *aeK", "Life/Mana after each Kill")
	_GUI_NewItem(10, "{208}/{209} *oS", "Life/Mana on Striking")
	_GUI_NewItem(11, "{210}/{295} *oSiM", "Life/Mana on Striking in Melee")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Minions")
	_GUI_NewItem(01, "{444}% Life")
	_GUI_NewItem(02, "{470}% Damage")
	_GUI_NewItem(03, "{487}% Resist")
	_GUI_NewItem(04, "{500}% AR", "Attack Rating")
	
	_GUI_GroupNext()
#EndRegion

	LoadGUISettings()
	_GUI_GroupX(8)
	
	GUICtrlCreateTabItem("Options")
	local $iOption = 0
	
	for $j = 1 to $g_iGUIOptionsGeneral
		_GUI_NewOption($j-1, $g_avGUIOptionList[$iOption][0], $g_avGUIOptionList[$iOption][3], $g_avGUIOptionList[$iOption][4])
		$iOption += 1
	next
	
	GUICtrlCreateTabItem("Hotkeys")
	for $j = 1 to $g_iGUIOptionsHotkey
		_GUI_NewOption($j-1, $g_avGUIOptionList[$iOption][0], $g_avGUIOptionList[$iOption][3], $g_avGUIOptionList[$iOption][4])
		$iOption += 1
	next
	
	GUICtrlCreateTabItem("Notifier")
	
	local $iNotifyY = $g_iGUIHeight - 29
	
	global $g_idNotifyEdit = GUICtrlCreateEdit("", 4, _GUI_LineY(0), $g_iGUIWidth - 8, $iNotifyY - _GUI_LineY(0) - 5)
	
	global $g_idNotifySave = GUICtrlCreateButton("Save", 4 + 0*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifySave")
	global $g_idNotifyReset = GUICtrlCreateButton("Reset", 4 + 1*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyReset")
	global $g_idNotifyTest = GUICtrlCreateButton("Test", 4 + 2*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyTest")
	GUICtrlCreateButton("Default", 4 + 3*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyDefault")
	
	OnClick_NotifyReset()

	GUICtrlCreateTabItem("Drop filter")
	_GUI_GroupX(8)
	_GUI_NewTextBasic(00, "The latest drop filter hides:", False)
	_GUI_NewTextBasic(01, " White/magic/rare tiered equipment with no filled sockets.", False)
	_GUI_NewTextBasic(02, " Runes below and including Zod.", False)
	_GUI_NewTextBasic(03, " Gems below Perfect.", False)
	_GUI_NewTextBasic(04, " Gold stacks below 2,000.", False)
	_GUI_NewTextBasic(05, " Magic rings, amulets and quivers.", False)
	_GUI_NewTextBasic(06, " Various junk (mana potions, TP/ID scrolls and tomes, keys).", False)
	_GUI_NewTextBasic(07, " Health potions below Greater.", False)
	
	GUICtrlCreateTabItem("About")
	_GUI_GroupX(8)
	_GUI_NewTextBasic(00, "Made by Wojen and Kyromyr, using Shaggi's offsets.", False)
	_GUI_NewTextBasic(01, "Layout help by krys.", False)
	_GUI_NewTextBasic(02, "Additional help by suchbalance and Quirinus.", False)
	
	_GUI_NewTextBasic(04, "If you're unsure what any of the abbreviations mean, all of", False)
	_GUI_NewTextBasic(05, " them should have a tooltip when hovered over.", False)
	
	_GUI_NewTextBasic(07, "Hotkeys can be disabled by setting them to ESC.", False)
	
	GUICtrlCreateTabItem("")
	UpdateGUI()
	GUIRegisterMsg($WM_COMMAND, "WM_COMMAND")
	
	GUISetState(@SW_SHOW)
endfunc

func UpdateGUIOptions()
	local $sType, $sOption, $idControl, $sFunc, $vValue, $vOld
	
	for $i = 1 to _GUI_OptionCount()
		_GUI_OptionByRef($i, $sOption, $idControl, $sFunc)
		
		$sType = _GUI_OptionType($sOption)
		$vOld = _GUI_Option($sOption)
		$vValue = $vOld
		
		switch $sType
			case "hk"
				$vValue = _GUICtrlHKI_GetHotKey($idControl)
			case "cb"
				$vValue = BitAND(GUICtrlRead($idControl), $GUI_CHECKED) ? 1 : 0
		endswitch
		
		if ($vOld <> $vValue) then
			_GUI_Option($sOption, $vValue)
			
			if ($sType == "hk") then
				if ($vOld) then _HotKey_Assign($vOld, 0, $HK_FLAG_D2STATS)
				if ($vValue) then _HotKey_Assign($vValue, $sFunc, $HK_FLAG_D2STATS, "[CLASS:Diablo II]")
			endif
		endif
	next

	local $bEnable = IsIngame()
	if ($bEnable <> $g_bHotkeysEnabled) then
		if ($bEnable) then
			_HotKey_Enable()
		else
			_HotKey_Disable($HK_FLAG_D2STATS)
		endif
		$g_bHotkeysEnabled = $bEnable
	endif
endfunc

func SaveGUISettings()
	local $sWrite = "", $vValue
	for $i = 0 to UBound($g_avGUIOptionList) - 1
		$vValue = $g_avGUIOptionList[$i][1]
		if ($g_avGUIOptionList[$i][2] == "tx") then $vValue = StringToBinary($vValue)
		$sWrite &= StringFormat("%s=%s%s", $g_avGUIOptionList[$i][0], $vValue, @LF)
	next
	IniWriteSection(@AutoItExe & ".ini", "General", $sWrite)
endfunc

func LoadGUISettings()
	local $asIniGeneral = IniReadSection(@AutoItExe & ".ini", "General")
	if (not @error) then
		local $vValue
		for $i = 1 to $asIniGeneral[0][0]
			$vValue = $asIniGeneral[$i][1]
			$vValue = _GUI_OptionType($asIniGeneral[$i][0]) == "tx" ? BinaryToString($vValue) : Int($vValue)
			_GUI_Option($asIniGeneral[$i][0], $vValue)
		next
	endif
endfunc

func DummySelectAll()
    local $hWnd = _WinAPI_GetFocus()
    local $sClass = _WinAPI_GetClassName($hWnd)
    if ($sClass == "Edit") then _GUICtrlEdit_SetSel($hWnd, 0, -1)
endfunc

Func WM_COMMAND($hWnd, $iMsg, $wParam, $lParam)
	Local $iIDFrom = BitAND($wParam, 0xFFFF)
	Local $iCode = BitShift($wParam, 16)
	
	If $iCode = $EN_CHANGE Then
		Switch $iIDFrom
			Case $g_idNotifyEdit
				OnChange_NotifyEdit()
		EndSwitch
	EndIf
EndFunc   ;==>WM_COMMAND

Func _GetDPI()
    Local $avRet[3]
    Local $iDPI, $iDPIRat, $hWnd = 0
    Local $hDC = DllCall("user32.dll", "long", "GetDC", "long", $hWnd)
    Local $aResult = DllCall("gdi32.dll", "long", "GetDeviceCaps", "long", $hDC[0], "long", 90)
    DllCall("user32.dll", "long", "ReleaseDC", "long", $hWnd, "long", $hDC)
    $iDPI = $aResult[0]

    Select
        Case $iDPI = 0
            $iDPI = 96
            $iDPIRat = 94
        Case $iDPI < 84
            $iDPIRat = $iDPI / 105
        Case $iDPI < 121
            $iDPIRat = $iDPI / 96
        Case $iDPI < 145
            $iDPIRat = $iDPI / 95
        Case Else
            $iDPIRat = $iDPI / 94
    EndSelect
	
    $avRet[0] = 2
    $avRet[1] = $iDPI
    $avRet[2] = $iDPIRat

    Return $avRet
EndFunc   ;==>_GetDPI
#EndRegion

#Region Injection
func RemoteThread($pFunc, $iVar = 0) ; $var is in EBX register
	local $aResult = DllCall($g_ahD2Handle[0], "ptr", "CreateRemoteThread", "ptr", $g_ahD2Handle[1], "ptr", 0, "uint", 0, "ptr", $pFunc, "ptr", $iVar, "dword", 0, "ptr", 0)
	local $hThread = $aResult[0]
	if ($hThread == 0) then return _Debug("RemoteThread", "Couldn't create remote thread.")
	
	_WinAPI_WaitForSingleObject($hThread)
	
	local $tDummy = DllStructCreate("dword")
	DllCall($g_ahD2Handle[0], "bool", "GetExitCodeThread", "handle", $hThread, "ptr", DllStructGetPtr($tDummy))
	local $iRet = Dec(Hex(DllStructGetData($tDummy, 1)))
	
	_WinAPI_CloseHandle($hThread)
	return $iRet
endfunc

func GetOffsetAddress($pAddress)
	return StringFormat("%08s", StringLeft(Hex(Binary($pAddress)), 8))
endfunc

func PrintString($sString, $iColor = $ePrintWhite)
	if (not IsIngame()) then return
	if (not WriteWString($sString)) then return _Log("PrintString", "Failed to write string.")
	
	RemoteThread($g_pD2InjectPrint, $iColor)
	if (@error) then return _Log("PrintString", "Failed to create remote thread.")
	
	return True
endfunc

func WriteString($sString)
	if (not IsIngame()) then return _Log("WriteString", "Not ingame.")
	
	_MemoryWrite($g_pD2InjectString, $g_ahD2Handle, $sString, StringFormat("char[%s]", StringLen($sString) + 1))
	if (@error) then return _Log("WriteString", "Failed to write string.")
	
	return True
endfunc
	
func WriteWString($sString)
	if (not IsIngame()) then return _Log("WriteWString", "Not ingame.")
	
	_MemoryWrite($g_pD2InjectString, $g_ahD2Handle, $sString, StringFormat("wchar[%s]", StringLen($sString) + 1))
	if (@error) then return _Log("WriteWString", "Failed to write string.")
	
	return True
endfunc

func GetDropFilterHandle()
	if (not WriteString("DropFilter.dll")) then return _Debug("GetDropFilterHandle", "Failed to write string.")
	
	local $pGetModuleHandleA = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "GetModuleHandleA")
	if (not $pGetModuleHandleA) then return _Debug("GetDropFilterHandle", "Couldn't retrieve GetModuleHandleA address.")
	
	return RemoteThread($pGetModuleHandleA, $g_pD2InjectString)
endfunc

#cs
D2Client.dll+5907E - 83 3E 04              - cmp dword ptr [esi],04 { 4 }
D2Client.dll+59081 - 0F85
-->
D2Client.dll+5907E - E9 *           - jmp DropFilter.dll+15D0 { PATCH_DropFilter }
#ce

func InjectDropFilter()
	local $sPath = FileGetLongName("DropFilter.dll", $FN_RELATIVEPATH)
	if (not FileExists($sPath)) then return _Debug("InjectDropFilter", "Couldn't find DropFilter.dll. Make sure it's in the same folder as " & @ScriptName & ".")
	if (not WriteString($sPath)) then return _Debug("InjectDropFilter", "Failed to write DropFilter.dll path.")
	
	local $pLoadLibraryA = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "LoadLibraryA")
	if (not $pLoadLibraryA) then return _Debug("InjectDropFilter", "Couldn't retrieve LoadLibraryA address.")

	local $iRet = RemoteThread($pLoadLibraryA, $g_pD2InjectString)
	if (@error) then return _Debug("InjectDropFilter", "Failed to create remote thread.")
	
	local $bInjected = 233 <> _MemoryRead($g_hD2Client + 0x5907E, $g_ahD2Handle, "byte")
	
	; TODO: Check if this is still needed
	if ($iRet and $bInjected) then
		local $hDropFilter = _WinAPI_LoadLibrary("DropFilter.dll")
		if ($hDropFilter) then
			local $pEntryAddress = _WinAPI_GetProcAddress($hDropFilter, "_PATCH_DropFilter@0")
			if ($pEntryAddress) then
				local $pJumpAddress = $pEntryAddress - 0x5 - ($g_hD2Client + 0x5907E)
				_MemoryWrite($g_hD2Client + 0x5907E, $g_ahD2Handle, "0xE9" & GetOffsetAddress($pJumpAddress), "byte[5]")
			else
				_Debug("InjectDropFilter", "Couldn't find DropFilter.dll entry point.")
				$iRet = 0
			endif
			_WinAPI_FreeLibrary($hDropFilter)
		else
			_Debug("InjectDropFilter", "Failed to load DropFilter.dll.")
			$iRet = 0
		endif
	endif
	
	return $iRet
endfunc

func EjectDropFilter($hDropFilter)
	local $pFreeLibrary = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "FreeLibrary")
	if (not $pFreeLibrary) then return _Debug("EjectDropFilter", "Couldn't retrieve FreeLibrary address.")

	local $iRet = RemoteThread($pFreeLibrary, $hDropFilter)
	if (@error) then return _Debug("EjectDropFilter", "Failed to create remote thread.")
	
	if ($iRet) then _MemoryWrite($g_hD2Client + 0x5907E, $g_ahD2Handle, "0x833E040F85", "byte[5]")
	
	return $iRet
endfunc

#cs
D2Client.dll+42AE1 - A3 *                  - mov [D2Client.dll+11C3DC],eax { [00000000] }
D2Client.dll+42AE6 - A3 *                  - mov [D2Client.dll+11C3E0],eax { [00000000] }
->
D2Client.dll+42AE1 - 90                    - nop 
D2Client.dll+42AE2 - 90                    - nop 
D2Client.dll+42AE3 - 90                    - nop 
D2Client.dll+42AE4 - 90                    - nop 
D2Client.dll+42AE5 - 90                    - nop 
D2Client.dll+42AE6 - 90                    - nop 
D2Client.dll+42AE7 - 90                    - nop 
D2Client.dll+42AE8 - 90                    - nop 
D2Client.dll+42AE9 - 90                    - nop 
D2Client.dll+42AEA - 90                    - nop 
#ce

func IsMouseFixEnabled()
	return _MemoryRead($g_hD2Client + 0x42AE1, $g_ahD2Handle, "byte") == 0x90
endfunc

func ToggleMouseFix()
	local $sWrite = IsMouseFixEnabled() ? "0xA3" & GetOffsetAddress($g_hD2Client + 0x11C3DC) & "A3" & GetOffsetAddress($g_hD2Client + 0x11C3E0) : "0x90909090909090909090" 
	_MemoryWrite($g_hD2Client + 0x42AE1, $g_ahD2Handle, $sWrite, "byte[10]")
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

func IsShowItemsEnabled()
	return _MemoryRead($g_hD2Client + 0x3AECF, $g_ahD2Handle, "byte") == 0x90
endfunc

func ToggleShowItems()
	local $sWrite1 = "0x9090909090"
	local $sWrite2 = "0x8335" & GetOffsetAddress($g_hD2Client + 0xFADB4) & "01E9B6000000"
	local $sWrite3 = "0xE93EFFFFFF90" ; Jump within same DLL shouldn't require offset fixing
	
	local $bRestore = IsShowItemsEnabled()
	if ($bRestore) then
		$sWrite1 = "0xA3" & GetOffsetAddress($g_hD2Client + 0xFADB4)
		$sWrite2 = "0xCCCCCCCCCCCCCCCCCCCCCCCC"
		$sWrite3 = "0x891D" & GetOffsetAddress($g_hD2Client + 0xFADB4)
	endif
	
	_MemoryWrite($g_hD2Client + 0x3AECF, $g_ahD2Handle, $sWrite1, "byte[5]")
	_MemoryWrite($g_hD2Client + 0x3B224, $g_ahD2Handle, $sWrite2, "byte[12]")
	_MemoryWrite($g_hD2Client + 0x3B2E1, $g_ahD2Handle, $sWrite3, "byte[6]")
	
	_MemoryWrite($g_hD2Client + 0xFADB4, $g_ahD2Handle, 0)
	PrintString($bRestore ? "Hold to show items." : "Toggle to show items.", $ePrintBlue)
endfunc

#cs
D2Client.dll+CDE00 - 53                    - push ebx
D2Client.dll+CDE01 - 68 *                  - push D2Client.dll+CDE10
D2Client.dll+CDE06 - 31 C0                 - xor eax,eax
D2Client.dll+CDE08 - E8 43FAFAFF           - call D2Client.dll+7D850
D2Client.dll+CDE0D - C3                    - ret 

D2Client.dll+CDE10 - 8B CB                 - mov ecx,ebx
D2Client.dll+CDE12 - 31 C0                 - xor eax,eax
D2Client.dll+CDE14 - BB *                  - mov ebx,D2Lang.dll+9450
D2Client.dll+CDE19 - FF D3                 - call ebx
D2Client.dll+CDE1B - C3                    - ret 
#ce

func InjectCode($pWhere, $sCode)
	_MemoryWrite($pWhere, $g_ahD2Handle, $sCode, StringFormat("byte[%s]", StringLen($sCode)/2 - 1))
	
	local $iConfirm = _MemoryRead($pWhere, $g_ahD2Handle)
	return Hex($iConfirm, 8) == Hex(Binary(Int(StringLeft($sCode, 10))))
endfunc

func InjectFunctions()
	local $bPrint = InjectCode($g_pD2InjectPrint, "0x5368" & GetOffsetAddress($g_pD2InjectString) & "31C0E843FAFAFFC3")
	local $bGetString = InjectCode($g_pD2InjectGetString, "0x8BCB31C0BB" & GetOffsetAddress($g_hD2Lang + 0x9450) & "FFD3C3")
	
	return $bPrint and $bGetString
endfunc

func UpdateDllHandles()
	local $pLoadLibraryA = _WinAPI_GetProcAddress(_WinAPI_GetModuleHandle("kernel32.dll"), "LoadLibraryA")
	if (not $pLoadLibraryA) then return _Debug("UpdateDllHandles", "Couldn't retrieve LoadLibraryA address.")
	
	local $pAllocAddress = _MemVirtualAllocEx($g_ahD2Handle[1], 0, 0x100, BitOR($MEM_COMMIT, $MEM_RESERVE), $PAGE_EXECUTE_READWRITE)
	if (@error) then return _Debug("UpdateDllHandles", "Failed to allocate memory.")

	local $iDLLs = UBound($g_asDLL)
	local $hDLLHandle[$iDLLs]
	local $bFailed = False
	
	for $i = 0 to $iDLLs - 1
		_MemoryWrite($pAllocAddress, $g_ahD2Handle, $g_asDLL[$i], StringFormat("char[%s]", StringLen($g_asDLL[$i]) + 1))
		$hDLLHandle[$i] = RemoteThread($pLoadLibraryA, $pAllocAddress)
		if ($hDLLHandle[$i] == 0) then $bFailed = True
	next
	
	$g_hD2Client = $hDLLHandle[0]
	$g_hD2Common = $hDLLHandle[1]
	$g_hD2Win = $hDLLHandle[2]
	$g_hD2Lang = $hDLLHandle[3]
	
	local $pD2Inject = $g_hD2Client + 0xCDE00
	$g_pD2InjectPrint = $pD2Inject + 0x0
	$g_pD2InjectGetString = $pD2Inject + 0x10
	$g_pD2InjectString = $pD2Inject + 0x20
	
	$g_pD2sgpt = _MemoryRead($g_hD2Common + 0x99E1C, $g_ahD2Handle)

	_MemVirtualFreeEx($g_ahD2Handle[1], $pAllocAddress, 0x100, $MEM_RELEASE)
	if (@error) then return _Debug("UpdateDllHandles", "Failed to free memory.")
	if ($bFailed) then return _Debug("UpdateDllHandles", "Couldn't retrieve dll addresses.")
	
	return True
endfunc
#EndRegion

#Region Global Variables
func DefineGlobals()
	global $g_sLog = ""
	
	global const $HK_FLAG_D2STATS = BitOR($HK_FLAG_DEFAULT, $HK_FLAG_NOUNHOOK)

	global const $g_iColorRed	= 0xFF0000
	global const $g_iColorBlue	= 0x0066CC
	global const $g_iColorGold	= 0x808000
	global const $g_iColorGreen	= 0x008000
	global const $g_iColorPink	= 0xFF00FF
	
	global enum $ePrintWhite, $ePrintRed, $ePrintLime, $ePrintBlue, $ePrintGold, $ePrintGrey, $ePrintBlack, $ePrintUnk, $ePrintOrange, $ePrintYellow, $ePrintGreen, $ePrintPurple
	global enum $eQualityNone, $eQualityLow, $eQualityNormal, $eQualitySuperior, $eQualityMagic, $eQualitySet, $eQualityRare, $eQualityUnique, $eQualityCraft, $eQualityHonorific
	global $g_iQualityColor[] = [0x0, $ePrintWhite, $ePrintWhite, $ePrintWhite, $ePrintBlue, $ePrintLime, $ePrintYellow, $ePrintGold, $ePrintOrange, $ePrintGreen]
	
	global $g_avGUI[256][3] = [[0]]			; Text, X, Control [0] Count
	global $g_avGUIOption[32][3] = [[0]]	; Option, Control, Function [0] Count
	
	global enum $eNotifyFlagsTier, $eNotifyFlagsQuality, $eNotifyFlagsMisc, $eNotifyFlagsColour, $eNotifyFlagsMatch, $eNotifyFlagsLast
	global $g_asNotifyFlags[$eNotifyFlagsLast][32] = [ _
		[ "0", "1", "2", "3", "4", "5", "6", "sacred" ], _
		[ "low", "normal", "superior", "magic", "set", "rare", "unique", "craft", "honor" ], _
		[ "eth", "socket" ], _
		[ "clr_none", "white", "red", "lime", "blue", "gold", "grey", "black", "clr_unk", "orange", "yellow", "green", "purple" ] _
	]

	global $g_avNotifyCache[0][2]					; Name, Tier flag
	global $g_avNotifyCompile[0][$eNotifyFlagsLast]	; Flags, Regex
	global $g_bNotifyCache = True
	global $g_bNotifyCompile = True

	global const $g_iNumStats = 1024
	global $g_aiStatsCache[2][$g_iNumStats]

	global $g_asDLL[] = ["D2Client.dll", "D2Common.dll", "D2Win.dll", "D2Lang.dll"]
	global $g_hD2Client, $g_hD2Common, $g_hD2Win, $g_hD2Lang
	global $g_ahD2Handle
	
	global $g_iD2pid, $g_iUpdateFailCounter

	global $g_pD2sgpt, $g_pD2InjectPrint, $g_pD2InjectString, $g_pD2InjectGetString

	global $g_bHotkeysEnabled = False

	global const $g_iGUIOptionsGeneral = 4
	global const $g_iGUIOptionsHotkey = 5

	global const $g_sNotifyTextDefault = BinaryToString("0x312032203320342035203620756E6971756520202020202020202020202020232054696572656420756E69717565730D0A73616372656420756E69717565202020202020202020202020202020202020232053616372656420756E69717565730D0A225E2852696E677C416D756C65747C4A6577656C29242220756E69717565202320556E69717565206A6577656C72790D0A222E2B5175697665722220756E6971756520202020202020202020202020202320556E6971756520717569766572730D0A7365740D0A2242656C6C61646F6E6E612E2B220D0A22282E2B536872696E6529205C2831305C29222020202020202020202020202320536872696E65730D0A0D0A222E2A5369676E6574206F6620283F3A536B696C6C7C4C6561726E696E6729220D0A2247726561746572205369676E65742E2B220D0A22456D626C656D2E2B220D0A222E2B2054726F70687924220D0A222E2A4379636C65220D0A22456E6368616E74696E67220D0A2257696E67732E2B220D0A222E2B20457373656E636524220D0A2252756E6573746F6E65220D0A2247726561742052756E655C7C282E2A29220D0A224D7973746963204F72625C7C282E2A2922")
	
	global $g_avGUIOptionList[][5] = [ _
		["nopickup", 0, "cb", "Automatically enable /nopickup"], _
		["hidePass", 0, "cb", "Hide game password when minimap is open"], _
		["mousefix", 0, "cb", "Continue attacking when monster dies under cursor"], _
		["notify-enabled", 1, "cb", "Enable notifier"], _
		["copy", 0x002D, "hk", "Copy item text", "HotKey_CopyItem"], _
		["ilvl", 0x002E, "hk", "Display item ilvl", "HotKey_ShowIlvl"], _
		["filter", 0x0124, "hk", "Inject/eject DropFilter", "HotKey_DropFilter"], _
		["toggle", 0x0024, "hk", "Switch Show Items between hold/toggle mode", "HotKey_ToggleShowItems"], _
		["toggleMsg", 1, "cb", "Message when Show Items is disabled in toggle mode"], _
		["notify-text", $g_sNotifyTextDefault, "tx"] _
	]
endfunc
#EndRegion
