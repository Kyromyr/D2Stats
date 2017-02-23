#Region Header

#cs

	Title:			Management of Hotkeys UDF Library for AutoIt3
	Filename:		HotKey.au3
	Description:	Sets a hot key that calls a user function
	Author:			Yashied
	Version:		1.8
	Requirements:	AutoIt v3.3 +, Developed/Tested on WindowsXP Pro Service Pack 2
	Uses:			StructureConstants.au3, WinAPI.au3, WindowsConstants.au3
	Notes:			The library registers the following window message:

                    WM_ACTIVATE
                    WM_INPUT

	Available functions:

	_HotKey_Assign
	_HotKey_Enable
	_HotKey_Disable
	_HotKey_Release

	Example1:

		#Include <HotKey.au3>

		Global Const $VK_ESCAPE = 0x1B
		Global Const $VK_F12 = 0x7B

		; Assign "F12" with Message() and set extended function call
		_HotKey_Assign($VK_F12, 'Message', BitOR($HK_FLAG_DEFAULT, $HK_FLAG_EXTENDEDCALL))

		; Assign "CTRL-ESC" with Quit()
		_HotKey_Assign(BitOR($CK_CONTROL, $VK_ESCAPE), 'Quit')

		While 1
			Sleep(10)
		WEnd

		Func Message($iKey)
			MsgBox(0, 'Hot key Test Message', 'F12 (0x' & Hex($iKey, 4) & ') has been pressed!')
		EndFunc   ;==>Message

		Func Quit()
			Exit
		EndFunc   ;==>Quit

	Example2:

		#Include <HotKey.au3>

		Global Const $VK_OEM_PLUS = 0xBB
		Global Const $VK_OEM_MINUS = 0xBD

		Global $Form, $Label
		Global $i = 0

		$Form = GUICreate('MyGUI', 200, 200)
		$Label = GUICtrlCreateLabel($i, 20, 72, 160, 52, 0x01)
		GUICtrlSetFont(-1, 32, 400, 0, 'Tahoma')
		GUISetState()

		; Assign "CTRL-(+)" with MyFunc1() and "CTRL-(-)" with MyFunc2() for created window only
		_HotKey_Assign(BitOR($CK_CONTROL, $VK_OEM_PLUS), 'MyFunc1', 0, $Form)
		_HotKey_Assign(BitOR($CK_CONTROL, $VK_OEM_MINUS), 'MyFunc2', 0, $Form)

		Do
		Until GUIGetMsg() = -3

		Func MyFunc1()
			$i += 1
			GUICtrlSetData($Label, $i)
		EndFunc   ;==>MyFunc1

		Func MyFunc2()
			$i -= 1
			GUICtrlSetData($Label, $i)
		EndFunc   ;==>MyFunc2

#ce

#Include-once

#Include <StructureConstants.au3>
#Include <WinAPI.au3>
#Include <WindowsConstants.au3>

#EndRegion Header

#Region Global Variables and Constants

; $HK_FLAG_NOBLOCKHOTKEY
; Prevents lock specified hot keys for other applications at the lower levels in the hook chain. For example, if you want to get just the fact
; of pressing a hot key, but leave the event to other applications. Ie specified hot key will work like before you set it.
; Only the _HotKey_Assign() function uses this flag.

; $HK_FLAG_NOUNHOOK
; Prevents an unhook application-defined hook procedure from the hook chain. It makes sense only if you want to keep order in the chain of hook
; procedures. For example, two applications have reserved the same hot keys and your application is not at the top in this chain. In this case,
; if the call _HotKey_Disable() without this flag and then call _HotKey_Enable(), then your application will receive priority over the re-defined
; hot keys. In some cases this is not required, then you must use this flag.
; This flag can be used by _HotKey_Assign() - unset hot keys only, _HotKey_Disable(), and _HotKey_Release().

; $HK_FLAG_NOOVERLAPCALL
; Prevents a call the user function if it has not complete. This flag is primarily to be set if the user function uses the MsgBox() and similar to it.
; Remember that your specified function is an interrupt function to the program and should not suspend the program or the program may hang. However,
; it is not recommended to use the MsgBox() inside your function, it is better to define the control flag which will test the main program loop.
; Only the _HotKey_Assign() function uses this flag.

; $HK_FLAG_NOREPEAT
; Prevents a repeat characters when you hold down a key. If this flag is set hotkey will only work once until you can not release. Used if needed to
; avoid repeated alarms keys, for example when you install the hot keys to increase, decrease, or mute the volume.
; Only the _HotKey_Assign() function uses this flag.

; $HK_FLAG_NOERROR
; Prevents a return of error if one of the functions from this library was called from user function which has been defined by the _HotKey_Assign().
; Without this flag, in such cases will always return an error and @extended flag will be set to (-1). Be careful when using this flag, because
; improper use may cause a malfunction of your program, or to hang it.
; This flag can be used by _HotKey_Assign(), _HotKey_Disable(), and _HotKey_Release().

; $HK_FLAG_EXTENDEDCALL
; Adds a hot key code as a parameter when calling a user function. If you set this flag, 16-bit hot key code will be pass as a parameter to the user
; function. This can be useful if you assign multiple hot keys with the same function. If the flag was set, the function must have the header
; with one parameter (see _HotKey_Assign()).
; Only the _HotKey_Assign() function uses this flag.

; $HK_FLAG_WAIT
; Forces wait to return the user function inside the hook procedure. When using this flag, $HK_FLAG_NOOVERLAPCALL does not make sense. This flag is
; used mainly for compatibility with the library version 1.5 and below. In most cases, it is not required.
; Only the _HotKey_Assign() function uses this flag.

; $HK_FLAG_DEFAULT
; The combination of the $HK_FLAG_NOOVERLAPCALL and $HK_FLAG_NOREPEAT.

Global Const $HK_FLAG_NOBLOCKHOTKEY = 0x0001
Global Const $HK_FLAG_NOUNHOOK = 0x0002
Global Const $HK_FLAG_NOOVERLAPCALL = 0x0004
Global Const $HK_FLAG_NOREPEAT = 0x0008
Global Const $HK_FLAG_NOERROR = 0x0010
Global Const $HK_FLAG_EXTENDEDCALL = 0x0040
Global Const $HK_FLAG_WAIT = 0x0080
Global Const $HK_FLAG_DEFAULT = BitOR($HK_FLAG_NOOVERLAPCALL, $HK_FLAG_NOREPEAT)

Global Const $CK_SHIFT = 0x0100
Global Const $CK_CONTROL = 0x0200
Global Const $CK_ALT = 0x0400
Global Const $CK_WIN = 0x0800

#EndRegion Global Variables and Constants

#Region Local Variables and Constants

Global Const $HK_RID = True

Global Const $HK_WM_ACTIVATE = 0x0006
Global Const $HK_WM_HOTKEY = _WinAPI_RegisterWindowMessage('{509ADA08-BDC8-45BC-8082-1FFA4CB8D1C8}')
Global Const $HK_WM_INPUT = 0x00FF

Global $hkTb[1][12] = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, GUICreate('')]]

#cs

DO NOT USE THIS ARRAY IN THE SCRIPT, INTERNAL USE ONLY!

$hkTb[0][0 ]   - Count item of array
     [0][1 ]   - Interruption control flag (need to set this flag before changing $hkTb array)
     [0][2 ]   - Last hot key pressed (16-bit)
     [0][3 ]   - Disable hot keys control flag (_HotKey_Disable(), _HotKey_Enable())
     [0][4 ]   - Handle to the user-defined DLL callback function
     [0][5 ]   - Handle to the hook procedure
     [0][6 ]   - General counter of calls user functions
     [0][7 ]   - Block hot key flag for last pressed ($hkTb[i][3])
     [0][8 ]   - Hold down control flag
     [0][9 ]   - SCAW status (SHIFT-CTRL-ALT-WIN, 8-bit)
     [0][10]   - Handle to "Hot" window
     [0][11]   - Don't used

$hkTb[i][0 ]   - Combined hot key code (see _HotKey_Assign)
     [i][1 ]   - User function name
     [i][2 ]   - The title of the window to allow the hot key
     [i][3 ]   - Block hot key flag
     [i][4 ]   - Block overlapping user function flag
     [i][5 ]   - Block repeat flag
     [i][6 ]   - Extended function call flag
     [i][7 ]   - Waiting for return flag
     [i][8 ]   - Counter of calls user function
	 [i][9-11] - Reserved

#ce

Global $hkRt[256]

#EndRegion Local Variables and Constants

#Region Initialization

; IMPORTANT! If you register the ACTIVATE window messages in your code, you should call handlers from this library until
; you return from your handlers, otherwise the hot key will not work properly. For example:
;
; Func MY_WM_ACTIVATE($hWnd, $iMsg, $wParam, $lParam)
;   HK_WM_ACTIVATE($hWnd, $iMsg, $wParam, $lParam)
;   ...
; EndFunc   ;==>MY_WM_ACTIVATE

GUIRegisterMsg($HK_WM_ACTIVATE, 'HK_WM_ACTIVATE')
GUIRegisterMsg($HK_WM_HOTKEY, 'HK_WM_HOTKEY')
If $HK_RID Then
	GUIRegisterMsg($HK_WM_INPUT, 'HK_WM_INPUT')
	If Not __HK_Raw() Then

	EndIf
EndIf

OnAutoItExitRegister('__HK_AutoItExit')

#EndRegion Initialization

#Region Public Functions

; #FUNCTION# ========================================================================================================================
; Function Name:	_HotKey_Assign
; Description:		Sets a hot key that calls a user function.
; Syntax:			_HotKey_Assign ( $iKey [, $sFunction [, $iFlags [, $sTitle]]] )
; Parameter(s):		$iKey      - Combined 16-bit hot key code which consists of upper and lower bytes. Value of bits shown in the following table.
;
;								 Hot key code bits:
;
;								 0-7   - Specifies the virtual-key (VK) code of the key. Codes for the mouse buttons (0x01 - 0x06) are not supported.
;										 (http://msdn.microsoft.com/en-us/library/dd375731(VS.85).aspx)
;
;								 8     - SHIFT key
;								 9     - CONTROL key
;								 10    - ALT key
;								 11    - WIN key
;								 12-15 - Don't used (must be set to zero).
;
;								 The combination of keys can be composed of one function key (VK) and some system keys (CK). This code can not consist
;								 only of the system keys. To combine system keys with the function key use BitOR(). See following examples.
;								 (VK-constants are used in the vkConstants.au3)
;
;								 SHIFT-F12    - BitOR($CK_SHIFT, $VK_F12)
;								 SHIFT-A      - BitOR($CK_SHIFT, $VK_A)
;								 CTRL-ALT-TAB - BitOR($CK_CONTROL, $CK_ALT, $VK_TAB)
;								 etc.
;
;								 Not acceptable combinations:
;
;								 SHIFT-WIN    - BitOR($CK_SHIFT, $CK_WIN)
;								 CTRL-Q-W     - BitOR($CK_CONTROL, $VK_Q, $VK_W)
;								 etc.
;
;								 Do not attempt to define as hot keys SHIFT, CONTROL, ALT, and WIN follows.
;
;								 $VK_SHIFT, $VK_LSHIFT, $VK_RSHIFT etc.
;
;								 It still will not work. These keys can not be defined as "hot" in this library. Also, there are no differences
;								 between left and right system keys.
;
;					$sFunction - [optional] The name of the function to call when the key is pressed. The function cannot be a built-in AutoIt
;								 function or plug-in function and must have the following header:
;
;								 Func _MyFunc()
;
;								 Do not try to call _HotKey_Assign(), _HotKey_Enable(), _HotKey_Disable(), or _HotKey_Release() from this function. This is
;								 not a good idea. In this cases the error will be returned. In doing so, @extended will be set to (-1). Do not use inside
;								 the function MsgBox() and any other functions of stopping the operation of your script. This may cause the script to hang.
;								 Your function should not introduce significant delays in the main script. Not specifying this parameter or set to zero
;								 will unset a previous hot key. If there are no designated hot keys, the hook procedure will be unhook from the hook chain.
;
;					$iFlags    - [optional] Hot key control flag(s). This parameter can be a combination of the following values.
;
;								 $HK_FLAG_NOBLOCKHOTKEY
;								 $HK_FLAG_NOUNHOOK
;								 $HK_FLAG_NOOVERLAPCALL
;								 $HK_FLAG_NOREPEAT
;								 $HK_FLAG_NOERROR
;								 $HK_FLAG_EXTENDEDCALL
;								 $HK_FLAG_WAIT
;
;								 (See constants section in this library)
;
;								 $HK_FLAG_NOUNHOOK here is valid if you delete a hotkey only (_HotKey_Assign($iKey)).
;
;								 $HK_FLAG_EXTENDEDCALL it makes sense to set if you assign multiple hot keys with the same function. If the flag was set,
;								 the function must have following header:
;
;								 Func _MyFunc($Code)
;
;					$sTitle    - [optional] The title of the window to allow the hot key. This parameter is the same as the WinActive() function.
;								 The default is 0, which is allow hot key for all window.
;
; Return Value(s):	Success: 1.
;					Failure: 0 and sets the @error flag to non-zero.
; Author(s):		Yashied
; Note(s):			This function does not affect the _HotKey_Enable() and _HotKey_Disable() and can be called at any time.
;====================================================================================================================================

Func _HotKey_Assign($iKey, $sFunction = 0, $iFlags = -1, $sTitle = 0)

	Local $Index = 0, $Redim = False

	If $iFlags < 0 Then
		$iFlags = $HK_FLAG_DEFAULT
	EndIf
	If (BitAND($iFlags, $HK_FLAG_NOERROR) = 0) And ($hkTb[0][6] > 0) Then
		Return SetError(1,-1, 0)
	EndIf
	If (Not IsString($sFunction)) And ($sFunction = 0) Then
		$sFunction = ''
	EndIf
	$sFunction = StringStripWS($sFunction, 3)
	$iKey = BitAND($iKey, 0x0FFF)
	If BitAND($iKey, 0x00FF) = 0 Then
		Return SetError(1, 0, 0)
	EndIf
	For $i = 1 To $hkTb[0][0]
		If $hkTb[$i][0] = $iKey Then
			$Index = $i
			ExitLoop
		EndIf
	Next
	If Not $sFunction Then
		If $Index = 0 Then
			Return SetError(0, 0, 1)
		EndIf
		If (BitAND($iFlags, $HK_FLAG_NOUNHOOK) = 0) And ($hkTb[0][5]) And ($hkTb[0][0] = 1) Then
			If Not _WinAPI_UnhookWindowsHookEx($hkTb[0][5]) Then
				Return SetError(1, 0, 0)
			EndIf
			DllCallbackFree($hkTb[0][4])
			$hkTb[0][5] = 0
			__HK_Reset()
		EndIf
		$hkTb[0][8] = 1
		For $i = $Index To $hkTb[0][0] - 1
			For $j = 0 To UBound($hkTb, 2) - 1
				$hkTb[$i][$j] = $hkTb[$i + 1][$j]
			Next
		Next
		ReDim $hkTb[$hkTb[0][0]][UBound($hkTb, 2)]
		$hkTb[0][0] -= 1
		If $iKey = $hkTb[0][2] Then
			__HK_Reset()
		EndIf
		$hkTb[0][8] = 0
	Else
		If $Index = 0 Then
			If ($hkTb[0][5] = 0) And ($hkTb[0][3] = 0) Then
				For $i = 0 To 0xFF
					$hkRt[$i] = 0
				Next
				$hkTb[0][4] = DllCallbackRegister('__HK_Hook', 'long', 'int;wparam;lparam')
				$hkTb[0][5] =_WinAPI_SetWindowsHookEx($WH_KEYBOARD_LL, DllCallbackGetPtr($hkTb[0][4]), _WinAPI_GetModuleHandle(0), 0)
				If (@error) Or ($hkTb[0][5] = 0) Then
					Return SetError(1, 0, 0)
				EndIf
			EndIf
			$Index = $hkTb[0][0] + 1
			ReDim $hkTb[$Index + 1][UBound($hkTb, 2)]
			$Redim = 1
		EndIf
		$hkTb[$Index][0] = $iKey
		$hkTb[$Index][1] = $sFunction
		$hkTb[$Index][2] = $sTitle
		$hkTb[$Index][3] = (BitAND($iFlags, $HK_FLAG_NOBLOCKHOTKEY) = $HK_FLAG_NOBLOCKHOTKEY)
		$hkTb[$Index][4] = (BitAND($iFlags, $HK_FLAG_NOOVERLAPCALL) = $HK_FLAG_NOOVERLAPCALL)
		$hkTb[$Index][5] = (BitAND($iFlags, $HK_FLAG_NOREPEAT) = $HK_FLAG_NOREPEAT)
		$hkTb[$Index][6] = (BitAND($iFlags, $HK_FLAG_EXTENDEDCALL) = $HK_FLAG_EXTENDEDCALL)
		$hkTb[$Index][7] = (BitAND($iFlags, $HK_FLAG_WAIT) = $HK_FLAG_WAIT)
		$hkTb[$Index][8] = 0
		For $i = 9 To 11
			$hkTb[$Index][$i] = 0
		Next
		If $Redim Then
			$hkTb[0][0] += 1
		EndIf
	EndIf
	Return 1
EndFunc   ;==>_HotKey_Assign

; #FUNCTION# ========================================================================================================================
; Function Name:	_HotKey_Enable
; Description:		Enables all the hot keys that were defined by _HotKey_Assign() and installs a hook procedure into a hook chain.
; Syntax:			_HotKey_Enable (  )
; Parameter(s):		None.
; Return Value(s):	Success: 1.
;					Failure: 0 and sets the @error flag to non-zero. Also, can be sets @extended flag to (-1).
; Author(s):		Yashied
; Note(s):			Do not call this function from user function which has been defined by the _HotKey_Assign(). This will always
;					return an error and sets @extended flag to (-1).
;====================================================================================================================================

Func _HotKey_Enable()
	If $hkTb[0][6] > 0 Then
		Return SetError(1,-1, 0)
	EndIf
	If ($hkTb[0][5] = 0) And ($hkTb[0][0] > 0) Then
		For $i = 0 To 0xFF
			$hkRt[$i] = 0
		Next
		$hkTb[0][4] = DllCallbackRegister('__HK_Hook', 'long', 'int;wparam;lparam')
		$hkTb[0][5] =_WinAPI_SetWindowsHookEx($WH_KEYBOARD_LL, DllCallbackGetPtr($hkTb[0][4]), _WinAPI_GetModuleHandle(0), 0)
		If (@error) Or ($hkTb[0][5] = 0) Then
			Return SetError(1, 0, 0)
		EndIf
	EndIf
	$hkTb[0][3] = 0
	Return 1
EndFunc   ;==>_HotKey_Enable

; #FUNCTION# ========================================================================================================================
; Function Name:	_HotKey_Disable
; Description:		Disables all the hot keys that were defined by _HotKey_Assign() and unhooks a hook procedure from the hook chain.
; Syntax:			_HotKey_Disable ( [$iFlags] )
; Parameter(s):		$iFlags - [optional] Hot key control flag(s). This parameter can be a combination of the following values.
;
;							  $HK_FLAG_NOUNHOOK
;							  $HK_FLAG_NOERROR
;
;							  (See constants section in this library)
;
; Return Value(s):	Success: 1.
;					Failure: 0 and sets the @error flag to non-zero. Also, can be sets @extended flag to (-1).
; Author(s):		Yashied
; Note(s):			Do not call this function from user function which has been defined by the _HotKey_Assign(). The function does not
;					remove installed hot keys.
;====================================================================================================================================

Func _HotKey_Disable($iFlags = -1)
	If $iFlags < 0 Then
		$iFlags = 0
	EndIf
	If (BitAND($iFlags, $HK_FLAG_NOERROR) = 0) And ($hkTb[0][6] > 0) Then
		Return SetError(1,-1, 0)
	EndIf
	If (BitAND($iFlags, $HK_FLAG_NOUNHOOK) = 0) And ($hkTb[0][5]) Then
		If Not _WinAPI_UnhookWindowsHookEx($hkTb[0][5]) Then
			If Not BitAND($iFlags, 0x00010000) Then
				Return SetError(1, 0, 0)
			EndIf
		EndIf
		DllCallbackFree($hkTb[0][4])
		$hkTb[0][5] = 0
	EndIf
	$hkTb[0][3] = 1
	__HK_Reset()
	Return 1
EndFunc   ;==>_HotKey_Disable

; #FUNCTION# ========================================================================================================================
; Function Name:	_HotKey_Release
; Description:		Removes all the hot keys that were defined by _HotKey_Assign() and unhooks a hook procedure from the hook chain.
; Syntax:			_HotKey_Release ( [$iFlags] )
; Parameter(s):		$iFlags - [optional] Hot key control flag(s). This parameter can be a combination of the following values.
;
;							  $HK_FLAG_NOUNHOOK
;							  $HK_FLAG_NOERROR
;
;							  (See constants section in this library)
;
; Return Value(s):	Success: 1.
;					Failure: 0 and sets the @error flag to non-zero. Also, can be sets @extended flag to (-1).
; Author(s):		Yashied
; Note(s):			Do not call this function from user function which has been defined by the _HotKey_Assign().
;====================================================================================================================================

Func _HotKey_Release($iFlags = -1)
	If $iFlags < 0 Then
		$iFlags = 0
	EndIf
	If (BitAND($iFlags, $HK_FLAG_NOERROR) = 0) And ($hkTb[0][6] > 0) Then
		Return SetError(1,-1, 0)
	EndIf
	If (BitAND($iFlags, $HK_FLAG_NOUNHOOK) = 0) And ($hkTb[0][5]) Then
		If Not _WinAPI_UnhookWindowsHookEx($hkTb[0][5]) Then
			Return SetError(1, 0, 0)
		EndIf
		DllCallbackFree($hkTb[0][4])
		$hkTb[0][5] = 0
		__HK_Reset()
	EndIf
	$hkTb[0][0] = 0
	ReDim $hkTb[1][UBound($hkTb, 2)]
	Return 1
EndFunc   ;==>_HotKey_Release

#EndRegion Public Functions

#Region Internal Functions

Func __HK_Active($hWnd)
	If (IsInt($hWnd)) And ($hWnd = 0) Then
		Return 1
	Else
		If WinActive($hWnd) Then
			Return 1
		EndIf
	EndIf
	Return 0
EndFunc   ;==>__HK_Active

Func __HK_Call($iIndex)
	If ($hkTb[$iIndex][4] = 0) Or ($hkTb[$iIndex][8] = 0) Then
		If $hkTb[$iIndex][7] = 0 Then
			DllCall('user32.dll', 'int', 'PostMessage', 'hwnd', $hkTb[0][10], 'uint', $HK_WM_HOTKEY, 'int', $iIndex, 'int', 0xAFAF)
		Else
			DllCall('user32.dll', 'int', 'SendMessage', 'hwnd', $hkTb[0][10], 'uint', $HK_WM_HOTKEY, 'int', $iIndex, 'int', 0xAFAF)
		EndIf
	EndIf
EndFunc   ;==>__HK_Call

Func __HK_Error($sMessage)
	$hkTb[0][3] = 1
	__HK_Reset()
	_WinAPI_ShowError($sMessage)
EndFunc   ;==>__HK_Error

Func __HK_IsPressed($vkCode)

	Local $Ret = DllCall('user32.dll', 'short', 'GetAsyncKeyState', 'int', $vkCode)

	If (@error) Or ((Not $Ret[0]) And (_WinAPI_GetLastError())) Then
		Return SetError(1, 0, 0)
	EndIf
	Return BitAND($Ret[0], 0x8000)
EndFunc   ;==>__HK_IsPressed

Func __HK_Hook($iCode, $wParam, $lParam)

	If ($iCode > -1) And ($hkTb[0][1] = 0) And ($hkTb[0][3] = 0) Then

		Local $vkCode = BitAND(DllStructGetData(DllStructCreate($tagKBDLLHOOKSTRUCT, $lParam), 'vkCode'), 0xFF)
		Local $Return = False

		Switch $wParam
			Case $WM_KEYDOWN, $WM_SYSKEYDOWN
				If $hkTb[0][8] = 1 Then
					Return -1
				EndIf
				Switch $vkCode
					Case 0xA0 To 0xA5, 0x5B, 0x5C
						Switch $vkCode
							Case 0xA0, 0xA1
								$hkTb[0][9] = BitOR($hkTb[0][9], 0x01)
							Case 0xA2, 0xA3
								$hkTb[0][9] = BitOR($hkTb[0][9], 0x02)
							Case 0xA4, 0xA5
								$hkTb[0][9] = BitOR($hkTb[0][9], 0x04)
							Case 0x5B, 0x5C
								$hkTb[0][9] = BitOR($hkTb[0][9], 0x08)
						EndSwitch
						If $hkTb[0][2] > 0 Then
							$hkTb[0][2] = 0
						EndIf
					Case Else
						If $hkTb[0][9] Then
							__HK_Resolve()
						EndIf

						Local $Key = BitOR(BitShift($hkTb[0][9], -8), $vkCode)
						Local $Int = False

						If ($hkTb[0][2] = 0) Or ($hkTb[0][2] = $Key) Then
							For $i = 1 To $hkTb[0][0]
								If (__HK_Active($hkTb[$i][2])) And ($hkTb[$i][0] = $Key) Then
									If $hkTb[0][2] = $hkTb[$i][0] Then
										If $hkTb[$i][5] = 0 Then
											$Int = 1
										EndIf
									Else
										$hkTb[0][2] = $hkTb[$i][0]
										$hkTb[0][7] = $hkTb[$i][3]
										$Int = 1
									EndIf
									If $hkTb[$i][3] = 0 Then
										$Return = 1
									EndIf
									If $Int Then
										__HK_Call($i)
									EndIf
									ExitLoop
								EndIf
							Next
						Else
							$Return = 1
						EndIf
				EndSwitch
				If $Return Then
					Return -1
				EndIf
			Case $WM_KEYUP, $WM_SYSKEYUP
				Switch $vkCode
					Case 0xA0 To 0xA5, 0x5B, 0x5C
						Switch $vkCode
							Case 0xA0, 0xA1
								$hkTb[0][9] = BitAND($hkTb[0][9], 0xFE)
							Case 0xA2, 0xA3
								$hkTb[0][9] = BitAND($hkTb[0][9], 0xFD)
							Case 0xA4, 0xA5
								$hkTb[0][9] = BitAND($hkTb[0][9], 0xFB)
							Case 0x5B, 0x5C
								$hkTb[0][9] = BitAND($hkTb[0][9], 0xF7)
						EndSwitch
						If ($hkTb[0][2] > 0) And ($hkTb[0][7] = 0) And ($hkTb[0][9] = 0) Then
							$hkTb[0][1] = 1
							__HK_KeyUp($vkCode)
							$hkTb[0][1] = 0
							Return -1
						EndIf
					Case BitAND($hkTb[0][2], 0x00FF)
						$hkRt[$vkCode] += 1
						$hkTb[0][2] = 0
					Case Else
						$hkRt[$vkCode] += 1
				EndSwitch
		EndSwitch
	EndIf
	Return _WinAPI_CallNextHookEx(0, $iCode, $wParam, $lParam)
EndFunc   ;==>__HK_Hook

Func __HK_KeyUp($vkCode)
	DllCall('user32.dll', 'int', 'keybd_event', 'int', 0x88, 'int', 0, 'int', 0, 'ptr', 0)
	DllCall('user32.dll', 'int', 'keybd_event', 'int', $vkCode, 'int', 0, 'int', 2, 'ptr', 0)
	DllCall('user32.dll', 'int', 'keybd_event', 'int', 0x88, 'int', 0, 'int', 2, 'ptr', 0)
EndFunc   ;==>__HK_KeyUp

Func __HK_Raw($fRemove = 0)

	Local $tRID = DllStructCreate('ushort UsagePage;ushort Usage;dword Flags;hwnd hTarget')
	Local $Ret, $Length

	If @AutoItX64 Then
		$Length = 16
	Else
		$Length = 12
	EndIf
	DllStructSetData($tRID, 'UsagePage', 0x01)
	DllStructSetData($tRID, 'Usage', 0x06)
	If $fRemove Then
		DllStructSetData($tRID, 'Flags', 0x00000001)
		DllStructSetData($tRID, 'hTarget', 0)
	Else
		DllStructSetData($tRID, 'Flags', 0x00000100)
		DllStructSetData($tRID, 'hTarget', $hkTb[0][10])
	EndIf
	$Ret = DllCall('user32.dll', 'int', 'RegisterRawInputDevices', 'ptr', DllStructGetPtr($tRID), 'uint', 1, 'uint', $Length)
	If (@error) Or (Not $Ret[0]) Then
		Return 0
	Else
		Return 1
	EndIf
EndFunc   ;==>__HK_Raw

Func __HK_Reset()
	$hkTb[0][2] = 0
	$hkTb[0][7] = 0
	$hkTb[0][9] = 0
	For $i = 0 To 0xFF
		$hkRt[$i] = 0
	Next
EndFunc   ;==>__HK_Reset

Func __HK_Resolve()

	Local $Key = 0

	If __HK_IsPressed(0x10) Then
		If Not @error Then
			$Key = BitOR($Key, 0x01)
		Else
			Return
		EndIf
	EndIf
	If __HK_IsPressed(0x11) Then
		If Not @error Then
			$Key = BitOR($Key, 0x02)
		Else
			Return
		EndIf
	EndIf
	If __HK_IsPressed(0x12) Then
		If Not @error Then
			$Key = BitOR($Key, 0x04)
		Else
			Return
		EndIf
	EndIf
	If __HK_IsPressed(0x5B) Or __HK_IsPressed(0x5C) Then
		If Not @error Then
			$Key = BitOR($Key, 0x08)
		Else
			Return
		EndIf
	EndIf
	$hkTb[0][9] = $Key
EndFunc   ;==>__HK_Resolve

#EndRegion Internal Functions

#Region Windows Message Functions

Func HK_WM_ACTIVATE($hWnd, $iMsg, $wParam, $lParam)

	#forceref $hWnd, $iMsg, $lParam

	If $HK_RID Then
		Switch $wParam
			Case 0
				__HK_Raw(0)
			Case 1, 2
				__HK_Raw(1)
			Case Else

		EndSwitch
	EndIf
	Return 'GUI_RUNDEFMSG'
EndFunc   ;==>HK_WM_ACTIVATE

Func HK_WM_HOTKEY($hWnd, $iMsg, $wParam, $lParam)

	#forceref $iMsg

	Switch $hWnd
		Case $hkTb[0][10]
			Switch $lParam
				Case 0xAFAF
					$hkTb[0][6] += 1
					$hkTb[$wParam][8] += 1
					If $hkTb[$wParam][6] = 1 Then
						Call($hkTb[$wParam][1], $hkTb[$wParam][0])
					Else
						Call($hkTb[$wParam][1])
					EndIf
					$hkTb[$wParam][8] -= 1
					$hkTb[0][6] -= 1
;~					If (@error = 0xDEAD) And (@extended = 0xBEEF) Then
;~						__HK_Error($hkTb[$wParam][1] & '(): Function does not exist or invalid number of parameters.')
;~					EndIf
			EndSwitch
	EndSwitch
EndFunc   ;==>HK_WM_HOTKEY

Func HK_WM_INPUT($hWnd, $iMsg, $wParam, $lParam)

	#forceref $iMsg, $wParam

	If Not $HK_RID Then
		Return 'GUI_RUNDEFMSG'
	EndIf

	Switch $hWnd
		Case $hkTb[0][10]
			If ($hkTb[0][1] = 0) And ($hkTb[0][3] = 0) And ($hkTb[0][5]) Then

				Local $tRIKB = DllStructCreate('dword Type;dword Size;ptr hDevice;wparam wParam;ushort MakeCode;ushort Flags;ushort Reserved;ushort VKey;ushort;uint Message;ulong ExtraInformation')
				Local $ID, $Ret, $Length

				If @AutoItX64 Then
					$Length = 24
				Else
					$Length = 16
				EndIf
				$Ret = DllCall('user32.dll', 'uint', 'GetRawInputData', 'ptr', $lParam, 'uint', 0x10000003, 'ptr', DllStructGetPtr($tRIKB), 'uint*', DllStructGetSize($tRIKB), 'uint', $Length)
				If (@error) Or ($Ret[0] = 0) Or ($Ret[0] = 4294967295) Then

				Else
					If BitAND(DllStructGetData($tRIKB, 'Flags'), 0x01) Then
						$ID = DllStructGetData($tRIKB, 'VKey')
						Switch $ID
							Case 0x10, 0x11, 0x12, 0x5B, 0x5C

							Case Else
								$hkRt[$ID] -= 1
								If $hkRt[$ID] < 0 Then
									_HotKey_Disable(0x00010000)
									_HotKey_Enable()
									If @error Then

									EndIf
								EndIf
						EndSwitch
					EndIf
				EndIf
			EndIf
	EndSwitch
	Return 'GUI_RUNDEFMSG'
EndFunc   ;==>HK_WM_INPUT

#EndRegion Windows Message Functions

#Region AutoIt Exit Functions

Func __HK_AutoItExit()
	If $hkTb[0][5] Then
		_WinAPI_UnhookWindowsHookEx($hkTb[0][5])
		DllCallbackFree($hkTb[0][4])
	EndIf
EndFunc   ;==>__HK_AutoItExit

#EndRegion AutoIt Exit Functions
