@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0.."
pushd "%ROOT%" >nul

set "FLUTTER_BIN="
set "FLUTTER_SDK="

if exist "android\local.properties" (
  for /f "usebackq tokens=1,* delims==" %%A in (`findstr /b /c:"flutter.sdk=" "android\local.properties"`) do (
    set "FLUTTER_SDK=%%B"
  )
)

if defined FLUTTER_SDK (
  set "FLUTTER_SDK=!FLUTTER_SDK:\\=\!"
  set "FLUTTER_SDK=!FLUTTER_SDK:/=\!"
  set "FLUTTER_BIN=!FLUTTER_SDK!\bin\flutter.bat"
)

if not defined FLUTTER_BIN set "FLUTTER_BIN=%USERPROFILE%\src\flutter\flutter\bin\flutter.bat"
if not exist "%FLUTTER_BIN%" set "FLUTTER_BIN=%USERPROFILE%\.vscode\flutter\bin\flutter.bat"
if not exist "%FLUTTER_BIN%" set "FLUTTER_BIN=flutter.bat"

call "%FLUTTER_BIN%" build apk --release --dart-define=AI_BACKEND_BASE_URL=https://cropcareai-nxn4.onrender.com %*
if errorlevel 1 (
  popd >nul
  exit /b %errorlevel%
)

if not exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo Build finished but build\app\outputs\flutter-apk\app-release.apk was not found.
  popd >nul
  exit /b 1
)

copy /y "build\app\outputs\flutter-apk\app-release.apk" "CropCareAI-release.apk" >nul
del /f /q "build\app\outputs\flutter-apk\app-release.apk" >nul 2>nul
del /f /q "build\app\outputs\flutter-apk\app-release.apk.sha1" >nul 2>nul

echo.
echo Final APK: %ROOT%\CropCareAI-release.apk

popd >nul
endlocal
