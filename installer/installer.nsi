; Simple installer script for the Flutter application

; Application details
!define APP_NAME "IlkApp"
; Visible name of the desktop shortcut the user sees after installation.
!define SHORTCUT_NAME "NGY App"
!define APP_VERSION "1.0.1"
; APP_EXE is the ACTUAL Flutter application executable produced by the Windows
; build. The on-disk name comes from windows/CMakeLists.txt (BINARY_NAME
; "ngy_app") and pubspec.yaml (name: ngy_app), so the built file is
; build\windows\x64\runner\Release\ngy_app.exe. This is NOT the setup exe
; (IlkApp_Setup_1.0.1.exe) - that one is the installer this script produces.
!define APP_EXE "ngy_app.exe"

; Registry key used to register the app in Add/Remove Programs and to detect a
; previous installation for clean re-installs. It is keyed by APP_NAME so the
; app identity stays stable across versions (needed for upgrade/uninstall
; detection) - treat this like the "AppId" of the installer.
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

; Installer name and output file
Name "${APP_NAME} ${APP_VERSION}"
OutFile "IlkApp_Setup_${APP_VERSION}.exe"

; Default installation folder
InstallDir "$PROGRAMFILES64\${APP_NAME}"

; Request application privileges
RequestExecutionLevel admin

; Simple interface settings
!define MUI_ABORTWARNING

; Installer pages
!include "MUI2.nsh"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

; Uninstaller pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Set UI language
!insertmacro MUI_LANGUAGE "Turkish"
!insertmacro MUI_LANGUAGE "English"

; Installer sections
Section "Install"
    ; -----------------------------------------------------------------
    ; Clean install: always remove any previous installation first, so
    ; every install is a fresh copy with no leftover files from prior
    ; versions.
    ; -----------------------------------------------------------------
    ; 1) If a previous version is registered, run its uninstaller silently.
    ;    This keeps Add/Remove Programs tidy and also removes an old install
    ;    even if the user had installed it into a different folder.
    ReadRegStr $0 HKLM "${UNINST_KEY}" "UninstallString"
    ReadRegStr $1 HKLM "${UNINST_KEY}" "InstallLocation"
    StrCmp $0 "" no_previous_install 0
        ; InstallLocation is stored wrapped in quotes; strip them so the path
        ; can be passed to the uninstaller's _?= parameter.
        StrCpy $2 $1 "" 1     ; drop the leading quote
        StrCpy $2 $2 -1       ; drop the trailing quote
        ; _?= runs the uninstaller in place so ExecWait actually waits for it;
        ; because it runs in place it cannot delete itself, so remove it after.
        ExecWait '$0 /S _?=$2'
        Delete "$2\uninstall.exe"
    no_previous_install:

    ; 2) Wipe the target directory to guarantee a clean install (removes any
    ;    stale files a previous version may have left behind).
    RMDir /r "$INSTDIR"

    ; -----------------------------------------------------------------
    ; Install fresh application files
    ; -----------------------------------------------------------------
    ; SetOutPath (re)creates $INSTDIR and also becomes the working directory
    ; used by the shortcuts created below, which the app needs to locate its
    ; bundled "data" folder.
    SetOutPath "$INSTDIR"

    ; Copy all files from the Flutter Windows build directory
    File /r "..\build\windows\x64\runner\Release\*.*"

    ; Create shortcut in Start Menu (icon taken from the app exe)
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\uninstall.exe"

    ; Create shortcut on desktop pointing at the real application exe.
    ; Named "NGY App" (SHORTCUT_NAME) regardless of the internal APP_NAME.
    CreateShortCut "$DESKTOP\${SHORTCUT_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Add uninstall information to Add/Remove Programs
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$\"$INSTDIR\${APP_EXE}$\""
    WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
    WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"
    WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$\"$INSTDIR$\""
    WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
SectionEnd

; Uninstaller section
Section "Uninstall"
    ; Remove application files
    RMDir /r "$INSTDIR"

    ; Remove Start Menu shortcuts
    RMDir /r "$SMPROGRAMS\${APP_NAME}"

    ; Remove Desktop shortcut
    Delete "$DESKTOP\${SHORTCUT_NAME}.lnk"

    ; Remove registry entries
    DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd

; Simple initialization function without plugin dependencies
Function .onInit
    ; Display a welcome message
    MessageBox MB_OK "IlkApp ${APP_VERSION} kurulumuna hoş geldiniz.$\n$\nDevam etmek için 'Tamam' düğmesine tıklayın."
FunctionEnd
