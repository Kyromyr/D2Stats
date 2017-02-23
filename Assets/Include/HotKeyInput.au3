#Region Header

#cs

	Title:			Hotkeys Input Control UDF Library for AutoIt3
	Filename:		HotKeyInput.au3
	Description:	Creates and manages an Hotkey Input control for the GUI
					(see "Shortcut key" input control in Shortcut Properties dialog box for example)
	Author:			Yashied
	Version:		1.3
	Requirements:	AutoIt v3.3 +, Developed/Tested on WindowsXP Pro Service Pack 2
	Uses:			StructureConstants.au3, WinAPI.au3, WindowsConstants.au3
	Notes:			-

	Available functions:

	_GUICtrlHKI_Create
	_GUICtrlHKI_Destroy
	_GUICtrlHKI_GetHotKey
	_GUICtrlHKI_SetHotKey
	_GUICtrlHKI_Release

	Additional functions:

	_KeyLock
	_KeyUnlock
	_KeyLoadName
	_KeyToStr

	Example:

        #Include <GUIConstantsEx.au3>
        #Include <HotKeyInput.au3>

        Global $Form, $HKI1, $HKI2, $Button, $Text

        $Form = GUICreate('Test', 300, 160)
        GUISetFont(8.5, 400, 0, 'Tahoma', $Form)

        $HKI1 = _GUICtrlHKI_Create(0, 56, 55, 230, 20)
        $HKI2 = _GUICtrlHKI_Create(0, 56, 89, 230, 20)

        ; Lock CTRL-ALT-DEL for Hotkey Input control, but not for Windows
        _KeyLock(0x062E)

        GUICtrlCreateLabel('Hotkey1:', 10, 58, 44, 14)
        GUICtrlCreateLabel('Hotkey2:', 10, 92, 44, 14)
        GUICtrlCreateLabel('Click on Input box and hold a combination of keys.' & @CR & 'Press OK to view the code.', 10, 10, 280, 28)
        $Button = GUICtrlCreateButton('OK', 110, 124, 80, 23)
        GUICtrlSetState(-1, BitOR($GUI_DEFBUTTON, $GUI_FOCUS))
        GUISetState()

        While 1
            Switch GUIGetMsg()
                Case $GUI_EVENT_CLOSE
                    Exit
                Case $Button
                    $Text = 'Hotkey1: 0x' & StringRight(Hex(_GUICtrlHKI_GetHotKey($HKI1)), 4) & ' (' & GUICtrlRead($HKI1) & ')' & @CR & @CR & _
                            'Hotkey2: 0x' & StringRight(Hex(_GUICtrlHKI_GetHotKey($HKI2)), 4) & ' (' & GUICtrlRead($HKI2) & ')'
                    MsgBox(0, 'Code', $Text, 0, $Form)
            EndSwitch
        WEnd

#ce

#Include-once

#Include <StructureConstants.au3>
#Include <WinAPI.au3>
#Include <WindowsConstants.au3>

#EndRegion Header

#Region Local Variables and Constants

Global $hkVk = StringSplit('<Disabled>||||||||Backspace|Tab|||Clear|Enter||||||Pause|CapsLosk|||||||Esc|||||Spacebar|PgUp|PgDown|End|Home|Left|Up|Right|Down|Select|Print|Execute|PrtScr|Ins|Del|Help|0|1|2|3|4|5|6|7|8|9||||||||A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P|Q|R|S|T|U|V|W|X|Y|Z|Win|Win|0x5D||Sleep|Num 0|Num 1|Num 2|Num 3|Num 4|Num 5|Num 6|Num 7|Num 8|Num 9|Num *|Num +|0x6C|Num -|Num .|Num /|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12|F13|F14|F15|F16|F17|F18|F19|F20|F21|F22|F23|F24|||||||||NumLock|ScrollLock|||||||||||||||Shift|Shift|Ctrl|Ctrl|Alt|Alt|BrowserBack|BrowserForward|BrowserRefresh|BrowserStop|BrowserSearch|BrowserFavorites|BrowserStart|VolumeMute|VolumeDown|VolumeUp|NextTrack|PreviousTrack|StopMedia|Play|Mail|Media|0xB6|0xB7|||;|+|,|-|.|/|~|||||||||||||||||||||||||||[|\|]|"|0xDF|||0xE2|||0xE5||0xE7|||||0xEC||||||||||0xF6|0xF7|0xF8|0xF9|0xFA|0xFB|0xFC|0xFD|0xFE|', '|', 2)

Global $hkId[1][10] = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]

#cs

DO NOT USE THIS ARRAY IN THE SCRIPT, INTERNAL USE ONLY!

$hkId[0][0]   - Count item of array
     [0][1]   - Interruption control flag (need to set this flag before changing $hkId array)
     [0][2]   - Last key pressed (16-bit code)
     [0][3]   - SCAW status (8-bit)
     [0][4]   - Handle to the user-defined DLL callback function (Keyboard)
     [0][5]   - Handle to the hook procedure (Keyboard)
     [0][6]   - Index in array of the last control with the keyboard focus (don't change it)
     [0][7]   - Hold down key control flag
     [0][8]   - Release key control flag
     [0][9]   - Handle to the hook procedure (Event)

$hkId[i][0]   - The control identifier (controlID) as returned by GUICtrlCreateInput()
     [i][1]   - Handle to the control
     [i][2]   - Last hotkey code for Hotkey Input control
     [i][3]   - Separating characters
     [i][4-9] - Reserved

#ce

Global $hkLock[1] = [0]

#cs

DO NOT USE THIS ARRAY IN THE SCRIPT, INTERNAL USE ONLY!

$hkLock[0] - Count item of array
	   [i] - Lock keys, these keys will not be blocked (16-bit code)

#ce

#EndRegion Local Variables and Constants

#Region Initialization

; Resets the hook state and Hotkey Input control parameters to avoid conflict with the UAC elevated windows (Windows Vista+)
If __HKI_WinVer() >= 0x0600 Then
	$hkId[0][9] = __HKI_SetWinEventHook(0x0020, 0x0020, DllCallbackGetPtr(DllCallbackRegister('__HKI_Event', 'none', 'ptr;dword;hwnd;long;long;dword;dword')))
	If @error Then
		; Nothing
	EndIf
EndIf

OnAutoItExitRegister('__HKI_AutoItExit')

#EndRegion Initialization

#Region Public Functions

; #FUNCTION# ========================================================================================================================
; Function Name:	_GUICtrlHKI_Create
; Description:		Creates a Hotkey Input control for the GUI.
; Syntax:			_GUICtrlHKI_Create ( $iKey, $iLeft, $iTop [, $iWidth [, $iHeight [, $iStyle [, $iExStyle [, $sSeparator]]]]] )
; Parameter(s):		$iKey       - Combined 16-bit hotkey code which consists of upper and lower bytes. Value of bits shown in the following table.
;
;								  Hotkey code bits:
;
;								  0-7   - Specifies the virtual-key (VK) code of the key. Codes for the mouse buttons (0x01 - 0x06) are not supported.
;										 (http://msdn.microsoft.com/en-us/library/dd375731(VS.85).aspx)
;
;								  8     - SHIFT key
;								  9     - CONTROL key
;								  10    - ALT key
;								  11    - WIN key
;								  12-15 - Don't used
;
;					$iLeft, $iTop, $iWidth, $iHeight, $iStyle, $iExStyle - See description for the GUICtrlCreateInput() function.
;					(http://www.autoitscript.com/autoit3/docs/functions/GUICtrlCreateInput.htm)
;
;					$sSeparator - Separating characters. Default is "-".
;
; Return Value(s):	Success: The identifier (controlID) of the new control.
;					Failure: 0.
; Author(s):		Yashied
;
; Note(s):			Use _GUICtrlHKI_Destroy() to delete the Hotkey Input control. DO NOT USE GUICtrlDelete()! To work with the Hotkey Input
;					controls you can use GUICtrl... functions. If you set the GUI_DISABLE state for the Hotkey Input control, it will not work
;                   until the state not to be set to GUI_ENABLE. Before calling GUIDelete(), you must delete all previously created
;                   Hotkey Input controls by using _GUICtrlHKI_Release().
;====================================================================================================================================

Func _GUICtrlHKI_Create($iKey, $iLeft, $iTop, $iWidth = -1, $iHeight = -1, $iStyle = -1, $iExStyle = -1, $sSeparator = '-')

	Local $ID, $Color[2]

	$iKey = BitAND($iKey, 0x0FFF)
	If BitAND($iKey, 0x00FF) = 0 Then
		$iKey = 0
	EndIf
	If $iStyle < 0 Then
		$iStyle = 0x0080
	EndIf
	If ($hkId[0][0] = 0) And ($hkId[0][5] = 0) Then
		$hkId[0][4] = DllCallbackRegister('__HKI_Hook', 'long', 'int;wparam;lparam')
		$hkId[0][5] = _WinAPI_SetWindowsHookEx($WH_KEYBOARD_LL, DllCallbackGetPtr($hkId[0][4]), _WinAPI_GetModuleHandle(0), 0)
		If (@error) Or ($hkId[0][5] = 0) Then
			Return 0
		EndIf
	EndIf
	$ID = GUICtrlCreateInput('', $iLeft, $iTop, $iWidth, $iHeight, BitOR($iStyle, 0x0800), $iExStyle)
	If $ID = 0 Then
		If $hkId[0][0] = 0 Then
			If _WinAPI_UnhookWindowsHookEx($hkId[0][5]) Then
				DllCallbackFree($hkId[0][4])
				$hkId[0][5] = 0
			EndIf
		EndIf
		Return 0
	EndIf
	$Color[0] = _WinAPI_GetSysColor($COLOR_WINDOW)
	$Color[1] = _WinAPI_GetSysColor($COLOR_WINDOWTEXT)
	For $i = 0 To 1
		$Color[$i] = BitOR(BitAND($Color[$i], 0x00FF00), BitShift(BitAND($Color[$i], 0x0000FF), -16), BitShift(BitAND($Color[$i], 0xFF0000), 16))
	Next
	GUICtrlSetBkColor($ID, $Color[0])
	GUICtrlSetColor($ID, $Color[1])
	GUICtrlSetData($ID, _KeyToStr($iKey, $sSeparator))
	ReDim $hkId[$hkId[0][0] + 2][UBound($hkId, 2)]
	$hkId[$hkId[0][0] + 1][0] = $ID
	$hkId[$hkId[0][0] + 1][1] = GUICtrlGetHandle($ID)
	$hkId[$hkId[0][0] + 1][2] = $iKey
	$hkId[$hkId[0][0] + 1][3] = $sSeparator
	For $i = 4 To 9
		$hkId[$hkId[0][0] + 1][$i] = 0
	Next
	$hkId[0][0] += 1
	Return $ID
EndFunc   ;==>_GUICtrlHKI_Create

; #FUNCTION# ========================================================================================================================
; Function Name:	_GUICtrlHKI_Destroy
; Description:		Deletes a Hotkey Input control.
; Syntax:			_GUICtrlHKI_Destroy ( $controlID )
; Parameter(s):		$controlID - The control identifier (controlID) as returned by a _GUICtrlHKI_Create() function.
; Return Value(s):	Success: 1.
;					Failure: 0.
; Author(s):		Yashied
; Note(s):			-
;====================================================================================================================================

Func _GUICtrlHKI_Destroy($controlID)

	Local $Index = __HKI_Focus(_WinAPI_GetFocus())

	For $i = 1 To $hkId[0][0]
		If $controlID = $hkId[$i][0] Then
			$hkId[0][1] = 1
			If Not GUICtrlDelete($hkId[$i][0]) Then
;~				$hkId[0][1] = 0
;~				Return 0
			EndIf
			For $j = $i To $hkId[0][0] - 1
				For $k = 0 To UBound($hkId, 2) - 1
					$hkId[$j][$k] = $hkId[$j + 1][$k]
				Next
			Next
			$hkId[0][0] -= 1
			ReDim $hkId[$hkId[0][0] + 1][UBound($hkId, 2)]
			If $hkId[0][0] = 0 Then
				If _WinAPI_UnhookWindowsHookEx($hkId[0][5]) Then
					DllCallbackFree($hkId[0][4])
					$hkId[0][2] = 0
					$hkId[0][3] = 0
					$hkId[0][5] = 0
					$hkId[0][6] = 0
					$hkId[0][7] = 0
					$hkId[0][8] = 0
				EndIf
			EndIf
			If $i = $hkId[0][6] Then
				$hkId[0][6] = 0
			EndIf
			If $i = $Index Then
				$hkId[0][2] = 0
				$hkId[0][7] = 0
				$hkId[0][8] = 0
			EndIf
			$hkId[0][1] = 0
			Return 1
		EndIf
	Next
	Return 0
EndFunc   ;==>_GUICtrlHKI_Destroy

; #FUNCTION# ========================================================================================================================
; Function Name:	_GUICtrlHKI_GetHotKey
; Description:		Reads a hotkey code from Hotkey Input control.
; Syntax:			_GUICtrlHKI_GetHotKey ( $controlID )
; Parameter(s):		$controlID - The control identifier (controlID) as returned by a _GUICtrlHKI_Create() function.
; Return Value(s):	Success: Combined 16-bit hotkey code (see _GUICtrlHKI_Create()).
;					Failure: 0.
; Author(s):		Yashied
; Note(s):			Use the GUICtrlRead() to obtain a string of the hotkey.
;====================================================================================================================================

Func _GUICtrlHKI_GetHotKey($controlID)
	For $i = 1 To $hkId[0][0]
		If $controlID = $hkId[$i][0] Then
			Return $hkId[$i][2]
		EndIf
	Next
	Return 0
EndFunc   ;==>_GUICtrlHKI_GetHotKey

; #FUNCTION# ========================================================================================================================
; Function Name:	_GUICtrlHKI_SetHotKey
; Description:		Modifies a data for a Hotkey Input control.
; Syntax:			_GUICtrlHKI_SetHotKey ( $controlID, $iKey )
; Parameter(s):		$controlID - The control identifier (controlID) as returned by a _GUICtrlHKI_Create() function.
;					$iKey      - Combined 16-bit hotkey code (see _GUICtrlHKI_Create()).
; Return Value(s):	Success: 1.
;					Failure: 0.
; Author(s):		Yashied
; Note(s):			-
;====================================================================================================================================

Func _GUICtrlHKI_SetHotKey($controlID, $iKey)

	Local $Ret = 0

	$iKey = BitAND($iKey, 0x0FFF)
	If BitAND($iKey, 0x00FF) = 0 Then
		$iKey = 0
	EndIf
	For $i = 1 To $hkId[0][0]
		If $controlID = $hkId[$i][0] Then
			$hkId[0][1] = 1
			If GUICtrlSetData($hkId[$i][0], _KeyToStr($iKey, $hkId[$i][3])) Then
				If ($i = __HKI_Focus(_WinAPI_GetFocus())) And ($hkId[0][8] = 1) And (BitAND(BitXOR($iKey, $hkId[$i][2]), 0x00FF) > 0) Then
					$hkId[0][8] = 0
				EndIf
				$hkId[$i][2] = $iKey
				$Ret = 1
			EndIf
			ExitLoop
		EndIf
	Next
	$hkId[0][1] = 0
	Return $Ret
EndFunc   ;==>_GUICtrlHKI_SetHotKey

; #FUNCTION# ========================================================================================================================
; Function Name:	_GUICtrlHKI_Release
; Description:		Deletes all Hotkey Input control that created by using _GUICtrlHKI_Create() function.
; Syntax:			_GUICtrlHKI_Release (  )
; Parameter(s):		None.
; Return Value(s):	Success: 1.
;					Failure: 0.
; Author(s):		Yashied
; Note(s):			Use this function before calling GUIDelete() to remove all previously created Hotkey Input controls.
;====================================================================================================================================

Func _GUICtrlHKI_Release()

	Local $Ret = 1, $Count = $hkId[0][0]

	While $Count > 0
		If Not _GUICtrlHKI_Destroy($hkId[$Count][0]) Then
			$Ret = 0
		EndIf
		$Count -= 1
	WEnd
	Return $Ret
EndFunc   ;==>_GUICtrlHKI_Release

; #FUNCTION# ========================================================================================================================
; Function Name:	_KeyLock
; Description:		Locks a specified key combination for a Hotkey Input control.
; Syntax:			_KeyLock ( $iKey )
; Parameter(s):		$iKey - Combined 16-bit hotkey code (see _GUICtrlHKI_Create()).
; Return Value(s):	None.
; Author(s):		Yashied
;
; Note(s):			This function is independent and can be called at any time. The keys are blocked only for the Hotkey Input controls
;					and will be available for other applications. Using this function, you can not lock the key, but only with the combination
;					of this key. To completely lock the keys, use _KeyLoadName(). For example, this function can be used to lock for
;					Hotkey Input control "ALT-TAB". In this case, "ALT-TAB" will work as always. You can block any number of keys,
;					but no more than one in one function call.
;====================================================================================================================================

Func _KeyLock($iKey)
	$iKey = BitAND($iKey, 0x0FFF)
	For $i = 1 To $hkLock[0]
		If $hkLock[$i] = $iKey Then
			Return
		EndIf
	Next
	ReDim $hkLock[$hkLock[0] + 2]
	$hkLock[$hkLock[0] + 1] = $iKey
	$hkLock[0] += 1
EndFunc   ;==>_KeyLock

; #FUNCTION# ========================================================================================================================
; Function Name:	_KeyUnlock
; Description:		Unlocks a specified key combination for a Hotkey Input control.
; Syntax:			_KeyUnlock ( $iKey )
; Parameter(s):		$iKey - Combined 16-bit hotkey code (see _GUICtrlHKI_Create()).
; Return Value(s):	None.
; Author(s):		Yashied
; Note(s):			This function is inverse to _KeyLock().
;====================================================================================================================================

Func _KeyUnlock($iKey)
	$iKey = BitAND($iKey, 0x0FFF)
	For $i = 1 To $hkLock[0]
		If $hkLock[$i] = $iKey Then
			For $j = $i To $hkLock[0] - 1
				$hkLock[$j] = $hkLock[$j + 1]
			Next
			$hkLock[0] -= 1
			ReDim $hkLock[$hkLock[0] + 1]
			Return
		EndIf
	Next
EndFunc   ;==>_KeyUnlock

; #FUNCTION# ========================================================================================================================
; Function Name:	_KeyLoadName
; Description:		Loads a names of the keys.
; Syntax:			_KeyLoadName ( $aKeyName )
; Parameter(s):		$aKeyName - 256-string array that contains the name for each virtual key code. If the name is not specified ("")
;                               in the array then this key will be ignored.
;
; Return Value(s):	Success: 1.
;					Failure: 0 and sets the @error flag to non-zero.
; Author(s):		Yashied
;
; Note(s):			You can use this function to replace the names of the keys in the Hotkey Input control, such as "Shift" => "SHIFT".
;					Also, through this program can lock the keys.
;====================================================================================================================================

Func _KeyLoadName(ByRef $aKeyName)
	If (Not IsArray($aKeyName)) Or (UBound($aKeyName) < 256) Or (UBound($aKeyName, 2)) Then
		Return SetError(1, 0, 0)
	EndIf
	For $i = 0 To 255
		$hkVk[$i] = $aKeyName[$i]
	Next
	For $i = 0 To $hkId[0][0]
		GUICtrlSetData($hkId[$i][0], _KeyToStr($hkId[$i][2], $hkId[$i][3]))
	Next
	Return SetError(1, 0, 0)
EndFunc   ;==>_KeyLoadName

; #FUNCTION# ========================================================================================================================
; Function Name:	_KeyToStr
; Description:		Converts a key names of the hotkey into a single string separated by the specified characters.
; Syntax:			_KeyToStr ( $iKey [, $sSeparator] )
;					$iKey       - Combined 16-bit hotkey code (see _GUICtrlHKI_Create()).
;					$sSeparator - Separating characters. Default is "-".
; Return Value(s):	A string that contains a combination of the key names and separating characters, eg. "Alt-Shift-D".
; Author(s):		Yashied
; Note(s):			Use _KeyLoadName() to change the names of the keys in the Hotkey Input control.
;====================================================================================================================================

Func _KeyToStr($iKey, $sSeparator = '-')

	Local $Ret = '', $Lenght = StringLen($sSeparator)

	If BitAND($iKey, 0x0200) = 0x0200 Then
		$Ret &= $hkVk[0xA2] & $sSeparator
	EndIf
	If BitAND($iKey, 0x0100) = 0x0100 Then
		$Ret &= $hkVk[0xA0] & $sSeparator
	EndIf
	If BitAND($iKey, 0x0400) = 0x0400 Then
		$Ret &= $hkVk[0xA4] & $sSeparator
	EndIf
	If BitAND($iKey, 0x0800) = 0x0800 Then
		$Ret &= $hkVk[0x5B] & $sSeparator
	EndIf
	If BitAND($iKey, 0x00FF) > 0 Then
		$Ret &= $hkVk[BitAND($iKey, 0x00FF)]
	Else
		If StringRight($Ret, $Lenght) = $sSeparator Then
			$Ret = StringTrimRight($Ret, $Lenght)
		EndIf
	EndIf
	If $Ret = '' Then
		$Ret = $hkVk[0x00]
	EndIf
	Return $Ret
EndFunc   ;==>_KeyToStr

#EndRegion Public Functions

#Region Internal Functions

Func __HKI_Check($ID)
	If ($hkId[0][6] > 0) And ($ID <> $hkId[0][6]) Then
;~		If (($hkId[0][3] > 0) And ($hkId[$hkId[0][6]][2] = 0)) Or (($ID > 0) And ($hkId[0][7] = 1) And ($hkId[0][8] = 1)) Then
		If ($hkId[0][3] > 0) And ($hkId[$hkId[0][6]][2] = 0) Then
			GUICtrlSetData($hkId[$hkId[0][6]][0], $hkVk[0x00])
		EndIf
		$hkId[0][2] = 0
		$hkId[0][7] = 0
		$hkId[0][8] = 0
	EndIf
	$hkId[0][6] = $ID
EndFunc   ;==>__HKI_Check

Func __HKI_Event($hEventHook, $iEvent, $hWnd, $iObjectID, $iChildID, $iThreadID, $iEventTime)

	#forceref $hEventHook, $iEvent, $hWnd, $iObjectID, $iChildID, $iThreadID, $iEventTime

	If $hkId[0][0] Then
		__HKI_Check(0)
		If __HKI_IsElevated() Then
			$hkId[0][3] = 0
		EndIf
	EndIf
EndFunc   ;==>__HKI_Event

Func __HKI_Focus($Focus)
	For $i = 1 To $hkId[0][0]
		If $Focus = $hkId[$i][1] Then
			Return $i
		EndIf
	Next
	Return 0
EndFunc   ;==>__HKI_Focus

Func __HKI_IsElevated()

	Local $Ret = DllCall('user32.dll', 'short', 'GetAsyncKeyState', 'int', 0)

	If @error Then
		Return SetError(1, 0, 0)
	Else
		If (Not $Ret[0]) And (_WinAPI_GetLastError()) Then
			Return 1
		Else
			Return 0
		EndIf
	EndIf
EndFunc   ;==>__HKI_IsElevated

Func __HKI_Hook($iCode, $wParam, $lParam)

	If ($iCode < 0) Or ($hkId[0][1] = 1) Then
		Switch $wParam
			Case $WM_KEYDOWN, $WM_SYSKEYDOWN
				If $iCode < 0 Then
					ContinueCase
				EndIf
				Return -1
			Case Else
				Return _WinAPI_CallNextHookEx($hkId[0][5], $iCode, $wParam, $lParam)
		EndSwitch
	EndIf

	Local $vkCode = DllStructGetData(DllStructCreate($tagKBDLLHOOKSTRUCT, $lParam), 'vkCode')
	Local $Index = __HKI_Focus(_WinAPI_GetFocus())
	Local $Key, $Return = True

	__HKI_Check($Index)

	Switch $wParam
		Case $WM_KEYDOWN, $WM_SYSKEYDOWN
			Switch $vkCode
				Case 0xA0, 0xA1
					$hkId[0][3] = BitOR($hkId[0][3], 0x01)
				Case 0xA2, 0xA3
					$hkId[0][3] = BitOR($hkId[0][3], 0x02)
				Case 0xA4, 0xA5
					$hkId[0][3] = BitOR($hkId[0][3], 0x04)
				Case 0x5B, 0x5C
					$hkId[0][3] = BitOR($hkId[0][3], 0x08)
			EndSwitch
			If $Index > 0 Then
				If $vkCode = $hkId[0][2] Then
					Return -1
				EndIf
				$hkId[0][2] = $vkCode
				Switch $vkCode
					Case 0xA0 To 0xA5, 0x5B, 0x5C
						If $hkId[0][7] = 1 Then
							Return -1
						EndIf
						if ($hkId[$Index][2]) then _KeyUnlock($hkId[$Index][2])
						GUICtrlSetData($hkId[$Index][0], _KeyToStr(BitShift($hkId[0][3], -8), $hkId[$Index][3]))
						$hkId[$Index][2] = 0
					Case Else
						If $hkId[0][7] = 1 Then
							Return -1
						EndIf
						Switch $vkCode
							Case 0x08, 0x1B
								If $hkId[0][3] = 0 Then
									If $hkId[$Index][2] > 0 Then
										_KeyUnlock($hkId[$Index][2])
										GUICtrlSetData($hkId[$Index][0], $hkVk[0x00])
										$hkId[$Index][2] = 0
									EndIf
									Return -1
								EndIf
						EndSwitch
						If $hkVk[$vkCode] > '' Then
							$Key = BitOR(BitShift($hkId[0][3], -8), $vkCode)
							If Not __HKI_Lock($Key) Then
								if ($hkId[$Index][2]) then _KeyUnlock($hkId[$Index][2])
								if ($Key) then _KeyLock($Key)
								
								GUICtrlSetData($hkId[$Index][0], _KeyToStr($Key, $hkId[$Index][3]))
								$hkId[$Index][2] = $Key
								$hkId[0][7] = 1
								$hkId[0][8] = 1
							Else
								$Return = 0
							EndIf
						EndIf
				EndSwitch
				If $Return Then
					Return -1
				EndIf
			EndIf
		Case $WM_KEYUP, $WM_SYSKEYUP
			Switch $vkCode
				Case 0xA0, 0xA1
					$hkId[0][3] = BitAND($hkId[0][3], 0xFE)
				Case 0xA2, 0xA3
					$hkId[0][3] = BitAND($hkId[0][3], 0xFD)
				Case 0xA4, 0xA5
					$hkId[0][3] = BitAND($hkId[0][3], 0xFB)
				Case 0x5B, 0x5C
					$hkId[0][3] = BitAND($hkId[0][3], 0xF7)
			EndSwitch
			If $Index > 0 Then
				If $hkId[$Index][2] = 0 Then
					Switch $vkCode
						Case 0xA0 To 0xA5, 0x5B, 0x5C
							GUICtrlSetData($hkId[$Index][0], _KeyToStr(BitShift($hkId[0][3], -8), $hkId[$Index][3]))
					EndSwitch
				EndIf
			EndIf
			$hkId[0][2] = 0
			If $vkCode = BitAND($hkId[$Index][2], 0x00FF) Then
				$hkId[0][8] = 0
			EndIf
			If $hkId[0][3] = 0 Then
				If $hkId[0][8] = 0 Then
					$hkId[0][7] = 0
				EndIf
			EndIf
	EndSwitch
	Return _WinAPI_CallNextHookEx(0, $iCode, $wParam, $lParam)
EndFunc   ;==>__HKI_Hook

Func __HKI_Lock($iKey)
	For $i = 1 To $hkLock[0]
		If $iKey = $hkLock[$i] Then
			Return 1
		EndIf
	Next
	Return 0
EndFunc   ;==>__HKI_Lock

Func __HKI_SetWinEventHook($iEventMin, $iEventMax, $pEventProc, $iProcessID = 0, $iThreadID = 0, $iFlags = 0)

	Local $Ret = DllCall('user32.dll', 'ptr', 'SetWinEventHook', 'uint', $iEventMin, 'uint', $iEventMax, 'ptr', 0, 'ptr', $pEventProc, 'dword', $iProcessID, 'dword', $iThreadID, 'uint', $iFlags)

	If (@error) Or (Not $Ret[0]) Then
		Return SetError(1, 0, 0)
	EndIf
	Return $Ret[0]
EndFunc   ;==>__HKI_SetWinEventHook

Func __HKI_UnhookWinEvent($hEventHook)

	Local $Ret = DllCall('user32.dll', 'int', 'UnhookWinEvent', 'ptr', $hEventHook)

	If (@error) Or (Not $Ret[0]) Then
		Return SetError(1, 0, 0)
	EndIf
	Return 1
EndFunc   ;==>__HKI_UnhookWinEvent

Func __HKI_WinVer()

	Local $tOSVI, $Ret

	$tOSVI = DllStructCreate('dword Size;dword MajorVersion;dword MinorVersion;dword BuildNumber;dword PlatformId;wchar CSDVersion[128]')
	DllStructSetData($tOSVI, 'Size', DllStructGetSize($tOSVI))
	$Ret = DllCall('kernel32.dll', 'int', 'GetVersionExW', 'ptr', DllStructGetPtr($tOSVI))
	If (@error) Or (Not $Ret[0]) Then
		Return SetError(1, 0, 0)
	EndIf
	Return BitOR(BitShift(DllStructGetData($tOSVI, 'MajorVersion'), -8), DllStructGetData($tOSVI, 'MinorVersion'))
EndFunc   ;==>__HKI_WinVer

#EndRegion Internal Functions

#Region AutoIt Exit Functions

Func __HKI_AutoItExit()
	If $hkId[0][5] Then
		_WinAPI_UnhookWindowsHookEx($hkId[0][5])
	Endif
	If $hkId[0][9] Then
		__HKI_UnhookWinEvent($hkId[0][9])
	EndIf
EndFunc   ;==>__HKI_AutoItExit

#EndRegion AutoIt Exit Functions
