@echo off
setlocal
cd /d "%~dp0"
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
set ROOT=%~dp0..
set BIN=%ROOT%\bin
set STAGE=%~dp0payload
set ICO=%ROOT%\branding\rightclick-ninja.ico

echo Building RightClickNinja.exe...
"%CSC%" /nologo /target:winexe /optimize+ /win32icon:"%ICO%" /out:"%BIN%\RightClickNinja.exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Core.dll /r:Microsoft.CSharp.dll "%ROOT%\RightClickNinja.cs"
if errorlevel 1 exit /b 1

echo Staging payload...
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"
copy /y "%BIN%\RightClickNinja.exe" "%STAGE%\" >nul
copy /y "%BIN%\exiftool.exe" "%STAGE%\" >nul
xcopy /e /i /y "%BIN%\exiftool_files" "%STAGE%\exiftool_files\" >nul
copy /y "%ICO%" "%STAGE%\RightClickNinja.ico" >nul

echo Compiling installer...
"%ISCC%" "%~dp0RightClickNinja.iss"
if errorlevel 1 exit /b 1
echo.
echo Done: %~dp0dist\
dir /b "%~dp0dist\*.exe"
