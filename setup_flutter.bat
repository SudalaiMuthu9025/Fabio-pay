@echo off
REM ═══════════════════════════════════════════════════════════════════
REM  Fabio — Flutter Project Setup Script (Windows)
REM  Run this ONCE to scaffold the Flutter project and configure it.
REM ═══════════════════════════════════════════════════════════════════

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║     Fabio — Flutter Project Setup        ║
echo  ╚══════════════════════════════════════════╝
echo.

REM 1. Backup our custom source files
echo [1/5] Backing up custom source files...
if exist frontend\lib_custom rd /s /q frontend\lib_custom
xcopy frontend\lib frontend\lib_custom\ /E /I /Y >nul
copy frontend\pubspec.yaml frontend\pubspec_custom.yaml >nul

REM 2. Scaffold Flutter project
echo [2/5] Running flutter create...
cd frontend
flutter create --project-name fabio --org com.fabiopay .
cd ..

REM 3. Restore our source files
echo [3/5] Restoring Fabio source code...
rd /s /q frontend\lib
xcopy frontend\lib_custom frontend\lib\ /E /I /Y >nul
copy /y frontend\pubspec_custom.yaml frontend\pubspec.yaml >nul

REM 4. Copy Android manifest
echo [4/5] Applying Android permissions...
if exist frontend\android\app\src\main\AndroidManifest.xml (
    copy /y frontend\android_manifest_template.xml frontend\android\app\src\main\AndroidManifest.xml >nul
    echo    AndroidManifest.xml updated with camera + internet permissions.
)

REM 5. Install dependencies
echo [5/5] Installing Flutter dependencies...
cd frontend
flutter pub get
cd ..

REM Cleanup
rd /s /q frontend\lib_custom 2>nul
del frontend\pubspec_custom.yaml 2>nul

echo.
echo  ═══════════════════════════════════════════
echo   Setup complete! Run: cd frontend ^&^& flutter run
echo  ═══════════════════════════════════════════
echo.
echo  IMPORTANT: Manually add these to ios/Runner/Info.plist:
echo    - NSCameraUsageDescription (camera permission)
echo    - See ios_plist_additions.xml for details
echo.
pause
