#RequireAdmin
#include <Array.au3>
#include <File.au3>
#include <GuiEdit.au3>
#include <GuiSlider.au3>
#include <HotKey.au3>
#include <HotKeyInput.au3>
#include <Misc.au3>
#include <NomadMemory.au3>
#include <WinAPI.au3>

#include <AutoItConstants.au3>
#include <ComboConstants.au3>
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
#pragma compile(ProductVersion, 3.11.5)
#pragma compile(FileVersion, 3.11.5)
#pragma compile(Comments, 20.04.2022)
#pragma compile(UPX, True) ;compression
#pragma compile(inputboxres, True)
;#pragma compile(ExecLevel, requireAdministrator)
;#pragma compile(Compatibility, win7)
;#pragma compile(x64, True)
;#pragma compile(Out, D2Stats.exe)
;#pragma compile(LegalCopyright, Legal stuff here)
;#pragma compile(LegalTrademarks, '"Trademark something, and some text in "quotes" and stuff')

if ($CmdLine[0] == 3 and $CmdLine[1] == "sound") then ; Notifier sounds
	SoundSetWaveVolume($CmdLine[3])
	SoundPlay(StringFormat("%s\Sounds\%s.mp3", @ScriptDir, $CmdLine[2]), $SOUND_WAIT)
	SoundPlay("")
	exit
elseif (not _Singleton("D2Stats-Singleton")) then
	exit
elseif (@AutoItExe == @DesktopDir or @AutoItExe == @DesktopCommonDir) then
	MsgBox($MB_ICONERROR, "D2Stats", "Don't place D2Stats.exe on the desktop.")
	exit
elseif (not IsAdmin()) then
	MsgBox($MB_ICONERROR, "D2Stats", "Admin rights needed!")
	exit
elseif (not @Compiled) then
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
				if (not $bIsIngame) then $g_bNotifyCache = True
				
				InjectFunctions()
				
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
				$bIsIngame = False
				$g_hTimerCopyName = 0
			endif
			
			if ($g_hTimerCopyName and TimerDiff($g_hTimerCopyName) > 10000) then
				$g_hTimerCopyName = 0
				
				if ($bIsIngame) then PrintString("Item name multi-copy expired.")
			endif
		endif
	wend
endfunc

func _Exit()
	if (IsDeclared("g_idNotifySave") and BitAND(GUICtrlGetState($g_idNotifySave), $GUI_ENABLE)) then
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
func HotKey_CopyStatsToClipboard()
	if (not IsIngame()) then return
	
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

func HotKey_CopyItemsToClipboard()
	if (not IsIngame()) then return
	
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
	if ($TEST or not IsIngame()) then return

	local $hTimerRetry = TimerInit()
	local $sOutput = ""
	local $aiOffsets[2] = [0, 0]
	
	while ($sOutput == "" and TimerDiff($hTimerRetry) < 10)
		$sOutput = _MemoryPointerRead($g_hD2Win + 0x1191F, $g_ahD2Handle, $aiOffsets, "wchar[8192]")
		; $sOutput = _MemoryRead(0x00191FA4, $g_ahD2Handle, "wchar[2048]") ; Magic?
	wend
	
	if (StringLen($sOutput) == 0) then
		PrintString("Hover the cursor over an item first.", $ePrintRed)
		return
	endif
	
	$sOutput = StringRegExpReplace($sOutput, "ÿc.", "")
	local $asLines = StringSplit($sOutput, @LF)

	if (_GUI_Option("copy-name")) then
		if ($g_hTimerCopyName == 0 or not (ClipGet() == $g_sCopyName)) then $g_sCopyName = ""
		$g_hTimerCopyName = TimerInit()
		
		$g_sCopyName &= $asLines[$asLines[0]] & @CRLF
		ClipPut($g_sCopyName)
		
		local $avItems = StringRegExp($g_sCopyName, @CRLF, $STR_REGEXPARRAYGLOBALMATCH)
		PrintString(StringFormat("%s item name(s) copied.", UBound($avItems)))
		return
	endif
	
	$sOutput = ""
	for $i = $asLines[0] to 1 step -1
		if ($asLines[$i] <> "") then $sOutput &= $asLines[$i] & @CRLF
	next

	ClipPut($sOutput)
	PrintString("Item text copied.")
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

func HotKey_ReadStats()
	OnClick_ReadStats()
endfunc
#EndRegion

#Region Stat reading
func GetUnitToRead()
	local $bMercenary = BitAND(GUICtrlRead($g_idReadMercenary), $GUI_CHECKED) ? True : False
	return $g_hD2Client + ($bMercenary ? 0x10A80C : 0x11BBFC)
endfunc

func UpdateStatValueMem($iVector)
	if ($iVector <> 0 and $iVector <> 1) then _Debug("UpdateStatValueMem", "Invalid $iVector value.")
	
	local $pUnitAddress = GetUnitToRead()
	
	local $aiOffsets[3] = [0, 0x5C, ($iVector+1)*0x24]
	local $pStatList = _MemoryPointerRead($pUnitAddress, $g_ahD2Handle, $aiOffsets)

	$aiOffsets[2] += 0x4
	local $iStatCount = _MemoryPointerRead($pUnitAddress, $g_ahD2Handle, $aiOffsets, "word") - 1

	local $tagStat = "word wSubIndex;word wStatIndex;int dwStatValue;", $tagStatsAll
	for $i = 0 to $iStatCount
		$tagStatsAll &= $tagStat
	next

	local $tStats = DllStructCreate($tagStatsAll)
	_WinAPI_ReadProcessMemory($g_ahD2Handle[1], $pStatList, DllStructGetPtr($tStats), DllStructGetSize($tStats), 0)

	local $iStatIndex, $iStatValue
	
	for $i = 0 to $iStatCount
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
		FixStats()
		FixVeteranToken()
		CalculateWeaponDamage()
		
		; Poison damage to damage/second
		$g_aiStatsCache[1][57] *= (25/256)
		$g_aiStatsCache[1][58] *= (25/256)
		
		; Bonus stats from items; str, dex, vit, ene
		local $aiStats[] = [0, 359, 2, 360, 3, 362, 1, 361]
		local $iBase, $iTotal, $iPercent
		
		for $i = 0 to 3
			$iBase = GetStatValue($aiStats[$i*2 + 0])
			$iTotal = GetStatValue($aiStats[$i*2 + 0], 1)
			$iPercent = GetStatValue($aiStats[$i*2 + 1])
			
			$g_aiStatsCache[1][900+$i] = Ceiling($iTotal / (1 + $iPercent / 100) - $iBase)
		next
		
		; Factor cap
		local $iFactor = Floor((GetStatValue(278) * GetStatValue(0, 1) + GetStatValue(485) * GetStatValue(1, 1)) / 3e6 * 100)
		$g_aiStatsCache[1][904] = $iFactor > 100 ? 100 : $iFactor
	endif
endfunc

func GetUnitWeapon($pUnit)
	local $pInventory = _MemoryRead($pUnit + 0x60, $g_ahD2Handle)
	
	local $pItem = _MemoryRead($pInventory + 0x0C, $g_ahD2Handle)
	local $iWeaponID = _MemoryRead($pInventory + 0x1C, $g_ahD2Handle)
	
	local $pItemData, $pWeapon = 0
	
	while $pItem
		if ($iWeaponID == _MemoryRead($pItem + 0x0C, $g_ahD2Handle)) then
			$pWeapon = $pItem
			exitloop
		endif
		
		$pItemData = _MemoryRead($pItem + 0x14, $g_ahD2Handle)
		$pItem = _MemoryRead($pItemData + 0x64, $g_ahD2Handle)
	wend
	
	return $pWeapon
endfunc

func CalculateWeaponDamage()
	local $pUnitAddress = GetUnitToRead()
	local $pUnit = _MemoryRead($pUnitAddress, $g_ahD2Handle)
	
	local $pWeapon = GetUnitWeapon($pUnit)
	if (not $pWeapon) then return
	
	local $iWeaponClass = _MemoryRead($pWeapon + 0x04, $g_ahD2Handle)
	local $pItemsTxt = _MemoryRead($g_hD2Common + 0x9FB98, $g_ahD2Handle)
	local $pBaseAddr = $pItemsTxt + 0x1A8 * $iWeaponClass
	
	local $iStrBonus = _MemoryRead($pBaseAddr + 0x106, $g_ahD2Handle, "word")
	local $iDexBonus = _MemoryRead($pBaseAddr + 0x108, $g_ahD2Handle, "word")
	local $bIs2H = _MemoryRead($pBaseAddr + 0x11C, $g_ahD2Handle, "byte")
	local $bIs1H = $bIs2H ? _MemoryRead($pBaseAddr + 0x13D, $g_ahD2Handle, "byte") : 1
	
	local $iMinDamage1 = 0, $iMinDamage2 = 0, $iMaxDamage1 = 0, $iMaxDamage2 = 0
	
	if ($bIs2H) then
		; 2h weapon
		$iMinDamage2 = GetStatValue(23)
		$iMaxDamage2 = GetStatValue(24)
	endif
	
	if ($bIs1H) then
		; 1h weapon
		$iMinDamage1 = GetStatValue(21)
		$iMaxDamage1 = GetStatValue(22)
		
		if (not $bIs2H) then
			; thrown weapon
			$iMinDamage2 = GetStatValue(159)
			$iMaxDamage2 = GetStatValue(160)
		endif
	endif
	
	if ($iMaxDamage1 < $iMinDamage1) then $iMaxDamage1 = $iMinDamage1 + 1
	if ($iMaxDamage2 < $iMinDamage2) then $iMaxDamage2 = $iMinDamage2 + 1

	local $iStatBonus = Floor((GetStatValue(0, 1) * $iStrBonus + GetStatValue(2, 1) * $iDexBonus) / 100) - 1
	local $iEWD = GetStatValue(25) + GetStatValue(343) ; global EWD, itemtype-specific EWD
	local $fTotalMult = 1 + $iEWD / 100 + $iStatBonus / 100
	
	local $aiDamage[4] = [$iMinDamage1, $iMaxDamage1, $iMinDamage2, $iMaxDamage2]
	for $i = 0 to 3
		$g_aiStatsCache[1][21+$i] = Floor($aiDamage[$i] * $fTotalMult)
	next
endfunc

func FixStats() ; This game is stupid
	for $i = 67 to 69 ; Velocities
		$g_aiStatsCache[1][$i] = 0
	next
	$g_aiStatsCache[1][343] = 0 ; itemtype-specific EWD (Elfin Weapons, Shadow Dancer)
	
	local $pSkillsTxt = _MemoryRead($g_pD2sgpt + 0xB98, $g_ahD2Handle)
	local $iSkillID, $pStats, $iStatCount, $pSkill, $iStatIndex, $iStatValue, $iOwnerType, $iStateID
	
	local $pItemTypesTxt = _MemoryRead($g_pD2sgpt + 0xBF8, $g_ahD2Handle)
	local $pItemsTxt = _MemoryRead($g_hD2Common + 0x9FB98, $g_ahD2Handle)
	local $iWeaponClass, $pWeapon, $iWeaponType, $iItemType
	
	local $pUnitAddress = GetUnitToRead()
	local $pUnit = _MemoryRead($pUnitAddress, $g_ahD2Handle)
	
	local $aiOffsets[3] = [0, 0x5C, 0x3C]
	local $pStatList = _MemoryPointerRead($pUnitAddress, $g_ahD2Handle, $aiOffsets)

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
		switch $iStateID
			case 195 ; Dark Power, Tome of Possession aura
				$iSkillID = 687 ; Dark Power
		endswitch

		local $bHasVelocity[3] = [False,False,False]
		if ($iSkillID) then ; Game doesn't even bother setting the skill id for some skills, so we'll just have to hope the state is correct or the stat list isn't lying...
			$pSkill = $pSkillsTxt + 0x23C*$iSkillID
		
			for $i = 0 to 4
				$iStatIndex = _MemoryRead($pSkill + 0x98 + $i*2, $g_ahD2Handle, "word")
				
				switch $iStatIndex
					case 67 to 69
						$bHasVelocity[$iStatIndex-67] = True
				endswitch
			next
			
			for $i = 0 to 5
				$iStatIndex = _MemoryRead($pSkill + 0x54 + $i*2, $g_ahD2Handle, "word")
				
				switch $iStatIndex
					case 67 to 69
						$bHasVelocity[$iStatIndex-67] = True
				endswitch
			next
		endif
		
		for $i = 0 to $iStatCount - 1
			$iStatIndex = _MemoryRead($pStats + $i*8 + 2, $g_ahD2Handle, "word")
			$iStatValue = _MemoryRead($pStats + $i*8 + 4, $g_ahD2Handle, "int")
			
			switch $iStatIndex
				case 67 to 69
					if (not $iSkillID or $bHasVelocity[$iStatIndex-67]) then $g_aiStatsCache[1][$iStatIndex] += $iStatValue
				case 343
					$iItemType = _MemoryRead($pStats + $i*8 + 0, $g_ahD2Handle, "word")
					$pWeapon = GetUnitWeapon($pUnit)
					if (not $pWeapon or not $iItemType) then continueloop
					
					$iWeaponClass = _MemoryRead($pWeapon + 0x04, $g_ahD2Handle)
					$iWeaponType = _MemoryRead($pItemsTxt + 0x1A8 * $iWeaponClass + 0x11E, $g_ahD2Handle, "word")
					
					local $bApply = False
					local $aiItemTypes[256] = [1, $iWeaponType]
					local $iEquiv
					local $j = 1
					
					while ($j <= $aiItemTypes[0])
						if ($aiItemTypes[$j] == $iItemType) then
							$bApply = True
							exitloop
						endif
					
						for $k = 0 to 1
							$iEquiv = _MemoryRead($pItemTypesTxt + 0xE4 * $aiItemTypes[$j] + 0x04 + $k*2, $g_ahD2Handle, "word")
							if ($iEquiv) then
								$aiItemTypes[0] += 1
								$aiItemTypes[ $aiItemTypes[0] ] = $iEquiv
							endif
						next

						$j += 1
					wend
					
					if ($bApply) then $g_aiStatsCache[1][343] += $iStatValue
			endswitch
		next
	wend
endfunc

func FixVeteranToken()
	$g_aiStatsCache[1][219] = 0 ; Veteran token

	local $pUnitAddress = GetUnitToRead()
	
	local $aiOffsets[3] = [0, 0x60, 0x0C]
	local $pItem = _MemoryPointerRead($pUnitAddress, $g_ahD2Handle, $aiOffsets)
	
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

func GetStatValue($iStatID, $iVector = default)
	if ($iVector == default) then $iVector = $iStatID < 4 ? 0 : 1
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
				return $i > $eNotifyFlagsNoMask ? $j : BitRotate(1, $j, "D")
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
	
	redim $g_avNotifyCache[$iItemsTxt][3]
	
	for $iClass = 0 to $iItemsTxt - 1
		$pBaseAddr = $pItemsTxt + 0x1A8 * $iClass
		
		$iNameID = _MemoryRead($pBaseAddr + 0xF4, $g_ahD2Handle, "word")
		$sName = RemoteThread($g_pD2InjectGetString, $iNameID)
		$sName = _MemoryRead($sName, $g_ahD2Handle, "wchar[100]")
		
		$sName = StringReplace($sName, @LF, "|")
		$sName = StringRegExpReplace($sName, "ÿc.", "")
		$sTier = "0"
		
		if (_MemoryRead($pBaseAddr + 0x84, $g_ahD2Handle)) then ; Weapon / Armor
			$asMatch = StringRegExp($sName, "[1-4]|\Q(Sacred)\E", $STR_REGEXPARRAYGLOBALMATCH)
			if (not @error) then $sTier = $asMatch[0] == "(Sacred)" ? "sacred" : $asMatch[0]
		endif
		
		$g_avNotifyCache[$iClass][0] = $sName
		$g_avNotifyCache[$iClass][1] = NotifierFlag($sTier)
		$g_avNotifyCache[$iClass][2] = StringRegExpReplace($sName, ".+\|", "")

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
		MsgBox($MB_ICONWARNING, "D2Stats", StringFormat("Unknown notifier flag '%s' in line:%s%s", $sFlag, @CRLF, $sLine))
		return False
	endif
	
	if ($iGroup < $eNotifyFlagsNoMask) then $iFlag = BitOR(BitRotate(1, $iFlag, "D"), $avRet[$iGroup])
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

	if ($avRet[$eNotifyFlagsMatch] == "") then
		if (not $bHasFlags) then return False
		$avRet[$eNotifyFlagsMatch] = ".+"
	endif
	
	return True
endfunc

func NotifierCompile()
	if (not $g_bNotifyCompile) then return
	$g_bNotifyCompile = False
	$g_bNotifierChanged = True
	
	local $asLines = StringSplit(_GUI_Option("notify-text"), @LF)
	local $iLines = $asLines[0]
	
	redim $g_avNotifyCompile[0][0]
	redim $g_avNotifyCompile[$iLines][$eNotifyFlagsLast]
	
	local $avRet[0]
	local $iCount = 0
	
	for $i = 1 to $iLines
		if (NotifierCompileLine($asLines[$i], $avRet)) then
			for $j = 0 to $eNotifyFlagsLast - 1
				$g_avNotifyCompile[$iCount][$j] = $avRet[$j]
			next
			$iCount += 1
		endif
	next
	
	redim $g_avNotifyCompile[$iCount][$eNotifyFlagsLast]
endfunc

func NotifierHelp($sInput)
	NotifierCache()
	
	local $iItems = UBound($g_avNotifyCache)
	local $asMatches[$iItems][2]
	local $iCount = 0
	
	local $avRet[0]
	
	if (NotifierCompileLine($sInput, $avRet)) then
		local $sMatch = $avRet[$eNotifyFlagsMatch]
		local $iFlagsTier = $avRet[$eNotifyFlagsTier]
		
		local $sName, $iTierFlag
	
		for $i = 0 to $iItems - 1
			$sName = $g_avNotifyCache[$i][0]
			$iTierFlag = $g_avNotifyCache[$i][1]
			
			if (StringRegExp($sName, $sMatch)) then
				if ($iFlagsTier and not BitAND($iFlagsTier, $iTierFlag)) then continueloop
				
				$asMatches[$iCount][0] = $sName
				$asMatches[$iCount][1] = $g_avNotifyCache[$i][2]
				$iCount += 1
			endif
		next
	endif
	
	redim $asMatches[$iCount][2]
	_ArrayDisplay($asMatches, "Notifier Help", default, 32, @LF, "Item|Text")
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
	local $iUnitType, $iClass, $iQuality, $iEarLevel, $iNewEarLevel, $iFlags, $sName, $iTierFlag
	local $bIsNewItem, $bIsSocketed, $bIsEthereal
	local $iFlagsTier, $iFlagsQuality, $iFlagsMisc, $iFlagsColour, $iFlagsSound
	local $bNotify, $sText, $iColor
	
	local $bNotifySuperior = _GUI_Option("notify-superior")

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
				if (not $g_bNotifierChanged and $iEarLevel <> 0) then continueloop
				$iNewEarLevel = 1
				
				$bIsNewItem = BitAND(0x2000, $iFlags) <> 0
				$bIsSocketed = BitAND(0x800, $iFlags) <> 0
				$bIsEthereal = BitAND(0x400000, $iFlags) <> 0
				
				$sName = $g_avNotifyCache[$iClass][0]
				$iTierFlag = $g_avNotifyCache[$iClass][1]
				$sText = $g_avNotifyCache[$iClass][2]
				
				$bNotify = False
				
				for $j = 0 to UBound($g_avNotifyCompile) - 1
					if (StringRegExp($sName, $g_avNotifyCompile[$j][$eNotifyFlagsMatch])) then
						$iFlagsTier = $g_avNotifyCompile[$j][$eNotifyFlagsTier]
						$iFlagsQuality = $g_avNotifyCompile[$j][$eNotifyFlagsQuality]
						$iFlagsMisc = $g_avNotifyCompile[$j][$eNotifyFlagsMisc]
						$iFlagsColour = $g_avNotifyCompile[$j][$eNotifyFlagsColour]
						$iFlagsSound = $g_avNotifyCompile[$j][$eNotifyFlagsSound]

						if ($iFlagsTier and not BitAND($iFlagsTier, $iTierFlag)) then continueloop
						if ($iFlagsQuality and not BitAND($iFlagsQuality, BitRotate(1, $iQuality - 1, "D"))) then continueloop
						if (not $bIsSocketed and BitAND($iFlagsMisc, NotifierFlag("socket"))) then continueloop
						
						if ($bIsEthereal) then
							$sText &= " (Eth)"
						elseif (BitAND($iFlagsMisc, NotifierFlag("eth"))) then
							continueloop
						endif
						
						if ($iFlagsColour == NotifierFlag("hide")) then
							$iNewEarLevel = 2
						elseif ($iFlagsColour <> NotifierFlag("show")) then
							$bNotify = True
						endif
						
						exitloop
					endif
				next
				
				_MemoryWrite($pUnitData + 0x48, $g_ahD2Handle, $iNewEarLevel, "byte")

				if ($bNotify) then
					if ($iFlagsColour) then
						$iColor = $iFlagsColour - 1
					elseif ($iQuality == $eQualityNormal and $iTierFlag == NotifierFlag("0")) then
						$iColor = $ePrintOrange
					else
						$iColor = $g_iQualityColor[$iQuality]
					endif
					
					if ($bNotifySuperior and $iQuality == $eQualitySuperior) then $sText = "Superior " & $sText

					PrintString("- " & $sText, $iColor)
					
					if ($iFlagsSound <> NotifierFlag("sound_none")) then NotifierPlaySound($iFlagsSound)
				endif
			endif
		wend
	next
	
	$g_bNotifierChanged = False
endfunc

func NotifierPlaySound($iSound)
	local $iVolume = _GUI_Volume($iSound - 1) * 10
	if ($iVolume > 0) then
		local $sScriptFile = @Compiled ? "" : StringFormat(' "%s"', @ScriptFullPath)
		local $sRun = StringFormat('"%s"%s %s %s %s', @AutoItExe, $sScriptFile, "sound", $iSound, $iVolume)
		Run($sRun)
	endif
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

func _GUI_OptionExists($sOption)
	for $i = 0 to UBound($g_avGUIOptionList) - 1
		if ($g_avGUIOptionList[$i][0] == $sOption) then return True
	next
	return False
endfunc

func _GUI_OptionID($sOption)
	for $i = 0 to UBound($g_avGUIOptionList) - 1
		if ($g_avGUIOptionList[$i][0] == $sOption) then return $i
	next
	_Log("_GUI_OptionID", "Invalid option '" & $sOption & "'")
	exit
endfunc

func _GUI_OptionType($sOption)
	return $g_avGUIOptionList[ _GUI_OptionID($sOption) ][2]
endfunc

func _GUI_Option($sOption, $vValue = null)
	local $iOption = _GUI_OptionID($sOption)
	local $vOld = $g_avGUIOptionList[$iOption][1]
	
	if not ($vValue == null or $vValue == $vOld) then
		$g_avGUIOptionList[$iOption][1] = $vValue
		SaveGUISettings()
	endif
	
	return $vOld
endfunc

func _GUI_Volume($iIndex, $iValue = default)
	local $id = $g_idVolumeSlider + $iIndex * 3
	
	if not ($iValue == default) then GUICtrlSetData($id, $iValue)
	
	return GUICtrlRead($id)
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
	local $iState = GUICtrlRead($g_idTab) < 2 ? $GUI_SHOW : $GUI_HIDE
	GUICtrlSetState($g_idReadStats, $iState)
	GUICtrlSetState($g_idReadMercenary, $iState)
endfunc

func OnChange_NotifyRulesCombo()
	if (BitAND(GUICtrlGetState($g_idNotifySave), $GUI_ENABLE)) then
		local $iButton = MsgBox(BitOR($MB_ICONQUESTION, $MB_YESNO), "D2Stats", "There are unsaved changes in the current notifier rules. Save?", 0, $g_hGUI)
		if ($iButton == $IDYES) then
			SaveCurrentNotifierRulesToFile(_GUI_Option("selectedNotifierRulesName"))
		endif
	endif

	local $sSelectedNofitierRules = GUICtrlRead($g_idNotifyRulesCombo)
	
	local $sNotifierRulesFilePath = ""
	for $i = 1 to $g_aNotifierRulesFilePaths[0] step +1
		if (GetNotifierRulesName($g_aNotifierRulesFilePaths[$i]) == $sSelectedNofitierRules) then
			$sNotifierRulesFilePath = $g_aNotifierRulesFilePaths[$i]
			exitloop
		endif
	next
	
	; first case should never happen, but we'll check anyway
	if ($sNotifierRulesFilePath == "" or not FileExists($sNotifierRulesFilePath)) then
		MsgBox($MB_ICONERROR, "File Not Found", "The file for the notifier rules named " & $sNotifierRulesFilePath & " could not be found.")
		return
	endif
	
	local $aNotifierRules[] = []
	if (not _FileReadToArray($sNotifierRulesFilePath, $aNotifierRules)) then
		MsgBox($MB_ICONERROR, "Error Reading File", "Could not read the file '" & $sNotifierRulesFilePath & "'. Error code: " & @error)
		return
	endif
	
	local $sNotifierRules = ""
	for $i = 1 to $aNotifierRules[0] step +1
		$sNotifierRules &= $aNotifierRules[$i] & @CRLF
	next
	
	GUICtrlSetData($g_idNotifyEdit, $sNotifierRules)
	
	_GUI_Option("selectedNotifierRulesName", $sSelectedNofitierRules)
	_GUI_Option("notify-text", $sNotifierRules)
	OnChange_NotifyEdit()
	$g_bNotifyCompile = True
endfunc

func OnClick_NotifyNew()
	local $sNewNotifierRulesName = ""
	if (not AskUserForNotifierRulesName($sNewNotifierRulesName)) then
		return False
	endif
	
	if not CreateNotifierRulesFile(GetNotifierRulesFilePath($sNewNotifierRulesName)) then
		return False
	endif
	
	RefreshNotifyRulesCombo($sNewNotifierRulesName)
endfunc

func OnClick_NotifyRename()
	local $sOldNotifierRulesName = GUICtrlRead($g_idNotifyRulesCombo)
	local $sNewNotifierRulesName = ""
	
	if (not AskUserForNotifierRulesName($sNewNotifierRulesName, $sOldNotifierRulesName)) then
		return False
	endif
	
	if (not FileMove(GetNotifierRulesFilePath($sOldNotifierRulesName), GetNotifierRulesFilePath($sNewNotifierRulesName))) then
		MsgBox($MB_ICONERROR, "Error!", "An error occurred while renaming the notifier rules file!")
		return False
	endif
	
	RefreshNotifyRulesCombo($sNewNotifierRulesName)
endfunc

func OnClick_NotifyDelete()
	local $sSelectedNofitierRules = GUICtrlRead($g_idNotifyRulesCombo)
	
	local $iMessageBoxResult = MsgBox(4, "Delete Notifier Rules?" ,"Are you sure you want to delete the notifier rules named '" & $sSelectedNofitierRules & "'?", 0, $g_hGUI)
	if ($iMessageBoxResult == $IDNO) then
		return
	endif

	if (not FileDelete(GetNotifierRulesFilePath($sSelectedNofitierRules))) then
		MsgBox($MB_ICONERROR, "Error!", "An error occurred while deleting the notifier rules file!")
		return
	endif
	
	RefreshNotifyRulesCombo()
endfunc

func OnClick_NotifySave()
	SaveCurrentNotifierRulesToFile(GUICtrlRead($g_idNotifyRulesCombo))
endfunc

func OnClick_NotifyReset()
	GUICtrlSetData($g_idNotifyEdit, _GUI_Option("notify-text"))
	OnChange_NotifyEdit()
endfunc

func OnClick_NotifyHelp()
	local $asText[] = [ _ 
		'"Item Name" flag1 flag2 ... flagN # Everything after hashtag is a comment.', _
		'', _
		'Item name is what you''re matching against. It''s a regex string.', _
		'If you''re unsure what regex is, use letters only.', _
		'', _
		'Flags:', _
		'> 0-4 sacred - Item must be one of these tiers.', _
		'   Tier 0 means untiered items (runes, amulets, etc).', _
		'> normal superior rare set unique - Item must be one of these qualities.', _
		'> eth - Item must be ethereal.', _
		'> white red lime blue gold orange yellow green purple - Notification color.', _
		StringFormat('> sound[1-%s] - Notification sound.', $g_iNumSounds), _
		'> hide - Hides matching items on ground, without notification. Requires DropFilter.dll', _
		'', _
		'Example:', _
		'"Battle" sacred unique eth sound3', _
		'This would notify for ethereal SU Battle Axe, Battle Staff,', _
		'Short Battle Bow and Long Battle Bow, and would play Sound 3', _
		'', _
		'Write something in this box and click OK to see what matches!' _
	]
	
	local $sText = ""
	for $i = 0 to UBound($asText) - 1
		$sText &= $asText[$i] & @CRLF
	next
	
	local $sInput = InputBox("Notifier Help", $sText, default, default, 450, 120 + UBound($asText) * 13, default, default, default, $g_hGUI)
	if (not @error) then
		if (IsIngame()) then
			NotifierHelp($sInput)
		else
			MsgBox($MB_ICONINFORMATION, "D2Stats", "You need to be ingame to do that.")
		endif
	endif
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

func GetNotifierRulesName($sNotifierRulesFilePath)
	return StringReplace(StringMid($sNotifierRulesFilePath, StringInStr($sNotifierRulesFilePath, "\", 2, -1) + 1), $g_sNotifierRulesExtension, "", -1)
endfunc

func GetNotifierRulesFilePath($sNotifierRulesName)
	return $g_sNotifierRulesDirectory & "\" & $sNotifierRulesName & $g_sNotifierRulesExtension
endfunc

func SaveCurrentNotifierRulesToFile($sNotifierRulesName)
	local $sNotifyEditContents = GUICtrlRead($g_idNotifyEdit)
	CreateNotifierRulesFile(GetNotifierRulesFilePath($sNotifierRulesName), $sNotifyEditContents)
	_GUI_Option("selectedNotifierRulesName", $sNotifierRulesName)
	_GUI_Option("notify-text", $sNotifyEditContents)
	OnChange_NotifyEdit()
	$g_bNotifyCompile = True
endfunc

func CreateNotifierRulesFile($sNotifierRulesFilePath, $sNotifierRules = "")
	DirCreate($g_sNotifierRulesDirectory)
	
	if ($sNotifierRules == "") then $sNotifierRules = $g_sNotifyTextDefault
	
	local $aNotifierRules[] = [$sNotifierRules]
	
	if (not _FileWriteFromArray($sNotifierRulesFilePath, $aNotifierRules)) then
		MsgBox($MB_ICONERROR, "Error Creating File", "An error occurred when creating the notifier rules file. File: " & $sNotifierRulesFilePath & " Error code: " & @error)
		return False
	endif
	
	return True
endfunc

func AskUserForNotifierRulesName(byref $sNewNotifierRulesName, $sInitialNotifierRulesName = "")
	local const $iMaxNameLength = 30
	local $sInputBoxTitle = $sInitialNotifierRulesName == "" ? "New Notifier Rules" : "Rename Notifier Rules"
	
	while (True)
		local $sUserInput = InputBox($sInputBoxTitle, "Enter a name for the notifier rules (max "& $iMaxNameLength & " characters):", $sInitialNotifierRulesName, "", 320, 130, default, default, 0, $g_hGUI)
		
		if (@error) then
			return False
		endif
		
		$sUserInput = StringStripWS($sUserInput, BitOR($STR_STRIPLEADING, $STR_STRIPTRAILING))
		$sInitialNotifierRulesName = $sUserInput
		if ($sUserInput == "") then
			MsgBox($MB_ICONERROR, "Invalid Name", 'No name entered.')
			continueloop
		endif
		
		if (StringRegExp($sUserInput, '[\Q\/:*?"<>|\E]')) then
			MsgBox($MB_ICONERROR, "Invalid Name", 'The name you have entered should NOT contain the following symbols: \/:*?"<>|')
			continueloop
		endif
		
		if (StringLen($sUserInput) > $iMaxNameLength) then
			MsgBox($MB_ICONERROR, "Invalid Name", "The name you have entered is too long. Maximum is " & $iMaxNameLength & " characters.")
			continueloop
		endif
		
		local $sNewNotifierRulesFilePath = GetNotifierRulesFilePath($sUserInput)
		if (FileExists($sNewNotifierRulesFilePath)) then
			MsgBox($MB_ICONERROR, "Notifier Rules Already Exists", "The notifier rules name you have entered is already in use. Choose another name.")
			continueloop
		endif
		
		$sNewNotifierRulesName = $sUserInput
		return True;
	wend
endfunc

func RefreshNotifyRulesCombo($sSelectedNotifierRulesName = "")
	global $g_aNotifierRulesFilePaths = _FileListToArray($g_sNotifierRulesDirectory, "*" & $g_sNotifierRulesExtension, $FLTA_FILES, True)
	if (@error not == 0 or $g_aNotifierRulesFilePaths == 0) then
		SetError(0)
		CreateNotifierRulesFile(GetNotifierRulesFilePath("Default"), _GUI_Option("notify-text"))
		$g_aNotifierRulesFilePaths = _FileListToArray($g_sNotifierRulesDirectory, "*" & $g_sNotifierRulesExtension, $FLTA_FILES, True)
	endif

	if (@error not == 0 or $g_aNotifierRulesFilePaths == 0) then
		MsgBox($MB_ICONERROR, "Error!", "Could not locate/create any notifier rules files inside " & $g_sNotifierRulesDirectory)
		return False
	endif

	local $sComboData = ""
	local $sDefaultSelectedNotifierRules = GetNotifierRulesName($g_aNotifierRulesFilePaths[1])
	
	for $i = 1 to $g_aNotifierRulesFilePaths[0] step +1
		local $sNotifierRulesName = GetNotifierRulesName($g_aNotifierRulesFilePaths[$i])
		; the data must start with | so it can wipe the old data from the combo control
		$sComboData &= "|" & $sNotifierRulesName
		
		if ($sSelectedNotifierRulesName == $sNotifierRulesName) then
			$sDefaultSelectedNotifierRules = $sNotifierRulesName
		endif
	next
	
	GUICtrlSetData($g_idNotifyRulesCombo, $sComboData, $sDefaultSelectedNotifierRules)
	OnChange_NotifyRulesCombo()
endfunc

func OnChange_VolumeSlider()
	SaveGUIVolume()
endfunc

func OnClick_VolumeTest()
	; Hacky way of getting a sound test button's sound index through the Sound # label
	local $sText = GUICtrlRead(@GUI_CtrlId - 1)
	local $asWords = StringSplit($sText, " ")
	local $iIndex = Int($asWords[2])
	NotifierPlaySound($iIndex)
endfunc

func OnClick_Forum()
	ShellExecute("https://forum.median-xl.com/viewtopic.php?f=4&t=3702")
endfunc

func CreateGUI()
	global $g_iGroupLines = 14
	global $g_iGroupWidth = 110
	global $g_iGroupXStart = 8 + $g_iGroupWidth/2
	global $g_iGUIWidth = 16 + 4*$g_iGroupWidth
	global $g_iGUIHeight = 34 + 15*$g_iGroupLines

	local $sTitle = not @Compiled ? "Test" : StringFormat("D2Stats %s - [%s]", FileGetVersion(@AutoItExe, "FileVersion"), FileGetVersion(@AutoItExe, "Comments"))
	
	global $g_hGUI = GUICreate($sTitle, $g_iGUIWidth, $g_iGUIHeight)
	GUISetFont(9 / _GetDPI()[2], 0, 0, "Courier New")
	GUISetOnEvent($GUI_EVENT_CLOSE, "_Exit")
	
	global $g_idReadStats = GUICtrlCreateButton("Read", $g_iGroupXStart-35, $g_iGUIHeight-31, 70, 25)
	GUICtrlSetOnEvent(-1, "OnClick_ReadStats")
	
	global $g_idReadMercenary = GUICtrlCreateCheckbox("Mercenary", $g_iGroupXStart-35 + 78, $g_iGUIHeight-31)

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
	_GUI_NewItem(07, "{079}% G.Find", "Gold Find")
	_GUI_NewItem(08, "{085}% Exp.Gain", "Experience gained")
	_GUI_NewItem(09, "{479} M.Skill", "Maximum Skill Level")
	_GUI_NewItem(10, "{185} Sig.Stat [185:400/400]", "Signets of Learning. Up to 400 can be used||Any sacred unique item x1-25 + Catalyst of Learning ? Signet of Learning x1-25 + Catalyst of Learning|Any set item x1-25 + Catalyst of Learning ? Signet of Learning x1-25 + Catalyst of Learning|Unique ring/amulet/jewel/quiver + Catalyst of Learning ? Signet of Learning + Catalyst of Learning")
	_GUI_NewItem(11, "Veteran tokens [219:1/1]", "On Nightmare and Hell difficulty, you can find veteran monsters near the end of|each Act. There are five types of veteran monsters, one for each Act||[Class Charm] + each of the 5 tokens ? returns [Class Charm] with added bonuses| +1 to [Your class] Skill Levels| +20% to Experience Gained")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Bonus stats")
	_GUI_NewItem(01, "{359}%/{900}", "Strength")
	_GUI_NewItem(02, "{360}%/{901}", "Dexterity")
	_GUI_NewItem(03, "{362}%/{902}", "Vitality")
	_GUI_NewItem(04, "{361}%/{903}", "Energy")
	
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
	_GUI_NewItem(05, "{034} PDR", "Physical Damage Reduction")
	_GUI_NewItem(06, "{035} MDR", "Magic Damage Reduction")
	_GUI_NewItem(07, "{338}% Dodge", "Chance to avoid melee attacks while standing still")
	_GUI_NewItem(08, "{339}% Avoid", "Chance to avoid projectiles while standing still")
	_GUI_NewItem(09, "{340}% Evade", "Chance to avoid any attack while moving")

	_GUI_NewItem(11, "{136}% CB", "Crushing Blow. Chance to deal physical damage based on target's current health")
	_GUI_NewItem(12, "{141}% DS", "Deadly Strike. Chance to double physical damage of attack")
	_GUI_NewItem(13, "{164}% UA", "Uninterruptable Attack")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Resistance")
	_GUI_NewItem(01, "{039}%", "Fire", $g_iColorRed)
	_GUI_NewItem(02, "{043}%", "Cold", $g_iColorBlue)
	_GUI_NewItem(03, "{041}%", "Lightning", $g_iColorGold)
	_GUI_NewItem(04, "{045}%", "Poison", $g_iColorGreen)
	_GUI_NewItem(05, "{037}%", "Magic", $g_iColorPink)
	_GUI_NewItem(06, "{036}%", "Physical")
	
	_GUI_NewText(07, "Damage/Pierce", "Spell damage / -Enemy resist")
	_GUI_NewItem(08, "{329}%/{333}%", "Fire", $g_iColorRed)
	_GUI_NewItem(09, "{331}%/{335}%", "Cold", $g_iColorBlue)
	_GUI_NewItem(10, "{330}%/{334}%", "Lightning", $g_iColorGold)
	_GUI_NewItem(11, "{332}%/{336}%", "Poison", $g_iColorGreen)
	_GUI_NewItem(12, "{431}% PSD", "Poison Skill Duration", $g_iColorGreen)
	_GUI_NewItem(13, "{357}%/0%", "Physical/Magic", $g_iColorPink)
	
	GUICtrlCreateTabItem("Page 2")
	_GUI_GroupFirst()
	_GUI_NewItem(00, "{278} SF", "Strength Factor")
	_GUI_NewItem(01, "{485} EF", "Energy Factor")
	_GUI_NewItem(02, "{904}% F.Cap", "Factor cap. 100% means you don't benefit from more str/ene factor")
	_GUI_NewItem(03, "{409}% Buff.Dur", "Buff/Debuff/Cold Skill Duration")
	_GUI_NewItem(04, "{27}% Mana.Reg", "Mana Regeneration")
	_GUI_NewItem(05, "{109}% CLR", "Curse Length Reduction")
	_GUI_NewItem(06, "{110}% PLR", "Poison Length Reduction")
	_GUI_NewItem(07, "{489} TTAD", "Target Takes Additional Damage")
	
	_GUI_NewText(09, "Slow")
	_GUI_NewItem(10, "{150}%/{376}% Tgt.", "Slows Target / Slows Melee Target")
	_GUI_NewItem(11, "{363}%/{493}% Att.", "Slows Attacker / Slows Ranged Attacker")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Minions")
	_GUI_NewItem(01, "{444}% Life")
	_GUI_NewItem(02, "{470}% Damage")
	_GUI_NewItem(03, "{487}% Resist")
	_GUI_NewItem(04, "{500}% AR", "Attack Rating")
	
	_GUI_NewText(06, "Life/Mana")
	_GUI_NewItem(07, "{060}%/{062}% Leech", "Life/Mana Stolen per Hit")
	_GUI_NewItem(08, "{086}/{138} *aeK", "Life/Mana after each Kill")
	_GUI_NewItem(09, "{208}/{209} *oS", "Life/Mana on Striking")
	_GUI_NewItem(10, "{210}/{295} *oA", "Life/Mana on Attack")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Weapon Damage")
	_GUI_NewItem(01, "{048}-{049}", "Fire", $g_iColorRed)
	_GUI_NewItem(02, "{054}-{055}", "Cold", $g_iColorBlue)
	_GUI_NewItem(03, "{050}-{051}", "Lightning", $g_iColorGold)
	_GUI_NewItem(04, "{057}-{058}/s", "Poison/sec", $g_iColorGreen)
	_GUI_NewItem(05, "{052}-{053}", "Magic", $g_iColorPink)
	_GUI_NewItem(06, "{021}-{022}", "One-hand physical damage. Estimated; may be inaccurate, especially when dual wielding")
	_GUI_NewItem(07, "{023}-{024}", "Two-hand/Ranged physical damage. Estimated; may be inaccurate, especially when dual wielding")
	
	_GUI_GroupNext()
	_GUI_NewText(00, "Abs/Flat", "Absorb / Flat absorb")
	_GUI_NewItem(01, "{142}%/{143}", "Fire", $g_iColorRed)
	_GUI_NewItem(02, "{148}%/{149}", "Cold", $g_iColorBlue)
	_GUI_NewItem(03, "{144}%/{145}", "Lightning", $g_iColorGold)
	_GUI_NewItem(04, "{146}%/{147}", "Magic", $g_iColorPink)
	
	_GUI_NewItem(06, "RIP [108:1/1]", "Slain Monsters Rest In Peace")
#EndRegion

	LoadGUISettings()
	_GUI_GroupX(8)
	
	GUICtrlCreateTabItem("Options")
	local $iOption = 0
	
	for $i = 1 to $g_iGUIOptionsGeneral
		_GUI_NewOption($i-1, $g_avGUIOptionList[$iOption][0], $g_avGUIOptionList[$iOption][3], $g_avGUIOptionList[$iOption][4])
		$iOption += 1
	next
	
	GUICtrlCreateTabItem("Hotkeys")
	for $i = 1 to $g_iGUIOptionsHotkey
		_GUI_NewOption($i-1, $g_avGUIOptionList[$iOption][0], $g_avGUIOptionList[$iOption][3], $g_avGUIOptionList[$iOption][4])
		$iOption += 1
	next
	
	GUICtrlCreateTabItem("Notifier")
	
	local $iButtonWidth = 60
	local $iControlMargin = 4
	local $iComboWidth = $g_iGUIWidth - 3 * $iButtonWidth - 3 * $iControlMargin - 8
	
	global $g_idNotifyRulesCombo = GUICtrlCreateCombo("", $iControlMargin, _GUI_LineY(0) + 1, $iComboWidth, 25, BitOR($CBS_DROPDOWNLIST, $WS_VSCROLL))
	GUICtrlSetOnEvent(-1, "OnChange_NotifyRulesCombo")
	global $g_idNotifyRulesNew = GUICtrlCreateButton("New", $iComboWidth + 2 * $iControlMargin, _GUI_LineY(0), $iButtonWidth, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyNew")
	global $g_idNotifyRulesRename = GUICtrlCreateButton("Rename", $iComboWidth + $iButtonWidth + 3 * $iControlMargin, _GUI_LineY(0), $iButtonWidth, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyRename")
	global $g_idNotifyRulesDelete = GUICtrlCreateButton("Delete", $iComboWidth + 2 * $iButtonWidth + 4 * $iControlMargin, _GUI_LineY(0), $iButtonWidth, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyDelete")
	
	local $iNotifyY = $g_iGUIHeight - 29
	
	global $g_idNotifyEdit = GUICtrlCreateEdit("", 4, _GUI_LineY(2), $g_iGUIWidth - 8, $iNotifyY - _GUI_LineY(2) - 5)
	global $g_idNotifySave = GUICtrlCreateButton("Save", 4 + 0*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifySave")
	global $g_idNotifyReset = GUICtrlCreateButton("Reset", 4 + 1*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyReset")
	global $g_idNotifyTest = GUICtrlCreateButton("Help", 4 + 2*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyHelp")
	GUICtrlCreateButton("Default", 4 + 3*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_NotifyDefault")
	
	OnClick_NotifyReset()
	RefreshNotifyRulesCombo(_GUI_Option("selectedNotifierRulesName"))
	
	GUICtrlCreateTabItem("Sounds")
	for $i = 0 to $g_iNumSounds - 1
		local $iLine = 1 + $i*2
		
		local $id = GUICtrlCreateSlider(60, _GUI_LineY($iLine), 200, 25, BitOR($TBS_TOOLTIPS, $TBS_AUTOTICKS, $TBS_ENABLESELRANGE))
		GUICtrlSetLimit(-1, 10, 0)
		GUICtrlSetOnEvent(-1, "OnChange_VolumeSlider")
		_GUICtrlSlider_SetTicFreq($id, 1)
	
		_GUI_NewTextBasic($iLine, "Sound " & ($i + 1), False)
		
		GUICtrlCreateButton("Test", 260, _GUI_LineY($iLine), 60, 25)
		GUICtrlSetOnEvent(-1, "OnClick_VolumeTest")
		
		if ($i == 0) then $g_idVolumeSlider = $id
		_GUI_Volume($i, 5)
	next
	LoadGUIVolume()
	
	GUICtrlCreateTabItem("About")
	_GUI_GroupX(8)
	_GUI_NewTextBasic(00, "Made by Wojen and Kyromyr, using Shaggi's offsets.", False)
	_GUI_NewTextBasic(01, "Layout help by krys.", False)
	_GUI_NewTextBasic(02, "Additional help by suchbalance and Quirinus.", False)
	_GUI_NewTextBasic(03, "Sounds by MurderManTX and Cromi38.", False)
	
	_GUI_NewTextBasic(05, "If you're unsure what any of the abbreviations mean, all of", False)
	_GUI_NewTextBasic(06, " them should have a tooltip when hovered over.", False)
	
	_GUI_NewTextBasic(08, "Hotkeys can be disabled by setting them to ESC.", False)
	
	GUICtrlCreateButton("Forum", 4 + 0*62, $iNotifyY, 60, 25)
	GUICtrlSetOnEvent(-1, "OnClick_Forum")
	
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
		
		if not ($vOld == $vValue) then
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
			if (_GUI_OptionExists($asIniGeneral[$i][0])) then
				$vValue = $asIniGeneral[$i][1]
				$vValue = _GUI_OptionType($asIniGeneral[$i][0]) == "tx" ? BinaryToString($vValue) : Int($vValue)
				_GUI_Option($asIniGeneral[$i][0], $vValue)
			endif
		next

		local $bConflict = False
		local $iEnd = UBound($g_avGUIOptionList) - 1
		
		for $i = 0 to $iEnd
			if ($g_avGUIOptionList[$i][2] <> "hk" or $g_avGUIOptionList[$i][1] == 0x0000) then continueloop
			
			for $j = $i+1 to $iEnd
				if ($g_avGUIOptionList[$j][2] <> "hk") then continueloop
				
				if ($g_avGUIOptionList[$i][1] == $g_avGUIOptionList[$j][1]) then
					$g_avGUIOptionList[$j][1] = 0
					$bConflict = True
				endif
			next
		next
		
		if ($bConflict) then MsgBox($MB_ICONWARNING, "D2Stats", "Hotkey conflict! One or more hotkeys disabled.")
	endif
endfunc

func SaveGUIVolume()
	local $sWrite = ""
	for $i = 0 to $g_iNumSounds - 1
		$sWrite &= StringFormat("%s=%s%s", $i, _GUI_Volume($i), @LF)
	next
	IniWriteSection(@AutoItExe & ".ini", "Volume", $sWrite)
endfunc

func LoadGUIVolume()
	local $asIniVolume = IniReadSection(@AutoItExe & ".ini", "Volume")
	if (not @error) then
		local $iIndex, $iValue
		for $i = 1 to $asIniVolume[0][0]
			$iIndex = Int($asIniVolume[$i][0])
			$iValue = Int($asIniVolume[$i][1])
			if ($iIndex < $g_iNumSounds) then _GUI_Volume($iIndex, $iValue)
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

func SwapEndian($pAddress)
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
				_MemoryWrite($g_hD2Client + 0x5907E, $g_ahD2Handle, "0xE9" & SwapEndian($pJumpAddress), "byte[5]")
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
	local $sWrite = IsMouseFixEnabled() ? "0xA3" & SwapEndian($g_hD2Client + 0x11C3DC) & "A3" & SwapEndian($g_hD2Client + 0x11C3E0) : "0x90909090909090909090" 
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
	local $sWrite2 = "0x8335" & SwapEndian($g_hD2Client + 0xFADB4) & "01E9B6000000"
	local $sWrite3 = "0xE93EFFFFFF90" ; Jump within same DLL shouldn't require offset fixing
	
	local $bRestore = IsShowItemsEnabled()
	if ($bRestore) then
		$sWrite1 = "0xA3" & SwapEndian($g_hD2Client + 0xFADB4)
		$sWrite2 = "0xCCCCCCCCCCCCCCCCCCCCCCCC"
		$sWrite3 = "0x891D" & SwapEndian($g_hD2Client + 0xFADB4)
	endif
	
	_MemoryWrite($g_hD2Client + 0x3AECF, $g_ahD2Handle, $sWrite1, "byte[5]")
	_MemoryWrite($g_hD2Client + 0x3B224, $g_ahD2Handle, $sWrite2, "byte[12]")
	_MemoryWrite($g_hD2Client + 0x3B2E1, $g_ahD2Handle, $sWrite3, "byte[6]")
	
	_MemoryWrite($g_hD2Client + 0xFADB4, $g_ahD2Handle, 0)
	PrintString($bRestore ? "Hold to show items." : "Toggle to show items.", $ePrintBlue)
endfunc

#cs
D2Client.dll+CDE00 - 53                    - push ebx
D2Client.dll+CDE01 - 68 *                  - push D2Client.dll+CDE20
D2Client.dll+CDE06 - 31 C0                 - xor eax,eax
D2Client.dll+CDE08 - E8 *                  - call D2Client.dll+7D850
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
	local $iPrintOffset = ($g_hD2Client + 0x7D850) - ($g_hD2Client + 0xCDE0D)
	local $sWrite = "0x5368" & SwapEndian($g_pD2InjectString) & "31C0E8" & SwapEndian($iPrintOffset) & "C3"
	local $bPrint = InjectCode($g_pD2InjectPrint, $sWrite)
	
	$sWrite = "0x8BCB31C0BB" & SwapEndian($g_hD2Lang + 0x9450) & "FFD3C3"
	local $bGetString = InjectCode($g_pD2InjectGetString, $sWrite)

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
	$g_hD2Sigma = $hDLLHandle[4]
	
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
	
	global enum $eNotifyFlagsTier, $eNotifyFlagsQuality, $eNotifyFlagsMisc, $eNotifyFlagsNoMask, $eNotifyFlagsColour, $eNotifyFlagsSound, $eNotifyFlagsMatch, $eNotifyFlagsLast
	global $g_asNotifyFlags[$eNotifyFlagsLast][32] = [ _
		[ "0", "1", "2", "3", "4", "sacred" ], _
		[ "low", "normal", "superior", "magic", "set", "rare", "unique", "craft", "honor" ], _
		[ "eth", "socket" ], _
		[], _
		[ "clr_none", "white", "red", "lime", "blue", "gold", "grey", "black", "clr_unk", "orange", "yellow", "green", "purple", "show", "hide" ], _
		[ "sound_none" ] _
	]
	
	global const $g_iNumSounds = 6 ; Max 31
	global $g_idVolumeSlider
	
	for $i = 1 to $g_iNumSounds
		$g_asNotifyFlags[$eNotifyFlagsSound][$i] = "sound" & $i
	next

	global const $g_sNotifierRulesDirectory = @WorkingDir & "\NotifierRules"
	global const $g_sNotifierRulesExtension = ".rules"
	global $g_avNotifyCache[0][3]					; Name, Tier flag, Last line of name
	global $g_avNotifyCompile[0][$eNotifyFlagsLast]	; Flags, Regex
	global $g_bNotifyCache = True
	global $g_bNotifyCompile = True
	global $g_bNotifierChanged = False

	global const $g_iNumStats = 1024
	global $g_aiStatsCache[2][$g_iNumStats]

	global $g_asDLL[] = ["D2Client.dll", "D2Common.dll", "D2Win.dll", "D2Lang.dll", "D2Sigma.dll"]
	global $g_hD2Client, $g_hD2Common, $g_hD2Win, $g_hD2Lang, $g_hD2Sigma
	global $g_ahD2Handle
	
	global $g_iD2pid, $g_iUpdateFailCounter

	global $g_pD2sgpt, $g_pD2InjectPrint, $g_pD2InjectString, $g_pD2InjectGetString

	global $g_bHotkeysEnabled = False
	global $g_hTimerCopyName = 0
	global $g_sCopyName = ""

	global const $g_iGUIOptionsGeneral = 4
	global const $g_iGUIOptionsHotkey = 6

	global const $g_sNotifyTextDefault = BinaryToString("0x3120322033203420756E69717565202020202020202020202020202020232054696572656420756E69717565730D0A73616372656420756E6971756520202020202020202020202020202020232053616372656420756E69717565730D0A2252696E67247C416D756C6574247C4A6577656C2220756E69717565202320556E69717565206A6577656C72790D0A225175697665722220756E697175650D0A7365740D0A2242656C6C61646F6E6E61220D0A22536872696E65205C28313022202020202020202020202020202020202320536872696E65730D0A23225175697665722220726172650D0A232252696E67247C416D756C6574222072617265202020202020202020202320526172652072696E677320616E6420616D756C6574730D0A2373616372656420657468207375706572696F7220726172650D0A0D0A225369676E6574206F66204C6561726E696E67220D0A2247726561746572205369676E6574220D0A22456D626C656D220D0A2254726F706879220D0A224379636C65220D0A22456E6368616E74696E67220D0A2257696E6773220D0A2252756E6573746F6E657C457373656E63652422202320546567616E7A652072756E65730D0A2247726561742052756E6522202020202020202020232047726561742072756E65730D0A224F72625C7C2220202020202020202020202020202320554D4F730D0A224F696C206F6620436F6E6A75726174696F6E220D0A2244696D656E73696F6E616C204B6579220D0A224F6363756C7420456666696779220D0A224D797374696320447965220D0A2252656C6963220D0A225175657374204974656D220D0A232252696E67206F66207468652046697665220D0A0D0A232048696465206974656D730D0A686964652031203220332034206C6F77206E6F726D616C207375706572696F72206D6167696320726172650D0A6869646520225E2852696E677C416D756C6574292422206D616769630D0A68696465202251756976657222206E6F726D616C206D616769630D0A6869646520225E28416D6574687973747C546F70617A7C53617070686972657C456D6572616C647C527562797C4469616D6F6E647C536B756C6C7C4F6E79787C426C6F6F6473746F6E657C54757271756F6973657C416D6265727C5261696E626F772053746F6E652924220D0A6869646520225E466C61776C657373220D0A73686F77202228477265617465727C537570657229204865616C696E6720506F74696F6E220D0A686964652022284865616C696E677C4D616E612920506F74696F6E220D0A6869646520225E4B657924220D0A6869646520225E28456C7C456C647C5469727C4E65667C4574687C4974687C54616C7C52616C7C4F72747C5468756C7C416D6E7C536F6C7C536861656C7C446F6C7C48656C7C496F7C4C756D7C4B6F7C46616C7C4C656D7C50756C7C556D7C4D616C7C4973747C47756C7C5665787C4F686D7C4C6F7C5375727C4265727C4A61687C4368616D7C5A6F64292052756E652422")
	global $g_avGUIOptionList[][5] = [ _
		["nopickup", 0, "cb", "Automatically enable /nopickup"], _
		["mousefix", 0, "cb", "Continue attacking when monster dies under cursor"], _
		["notify-enabled", 1, "cb", "Enable notifier"], _
		["notify-superior", 0, "cb", "Notifier prefixes superior items with 'Superior'"], _
		["copy", 0x002D, "hk", "Copy item text", "HotKey_CopyItem"], _
		["copy-name", 0, "cb", "Only copy item name"], _
		["filter", 0x0124, "hk", "Inject/eject DropFilter", "HotKey_DropFilter"], _
		["toggle", 0x0024, "hk", "Switch Show Items between hold/toggle mode", "HotKey_ToggleShowItems"], _
		["toggleMsg", 1, "cb", "Message when Show Items is disabled in toggle mode"], _
		["readstats", 0x0000, "hk", "Read stats without tabbing out of the game", "HotKey_ReadStats"], _
		["notify-text", $g_sNotifyTextDefault, "tx"], _
		["selectedNotifierRulesName", "Default", "tx"] _
	]
endfunc
#EndRegion
