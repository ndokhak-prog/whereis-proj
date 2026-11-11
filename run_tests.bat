@echo off
setlocal
rem TEMP 경로에 한글 등 비ASCII 문자가 포함되면(예: C:\Users\쑤\...)
rem flutter_tester가 "Connection closed before test suite loaded"로 크래시한다.
rem ASCII 경로를 TEMP로 지정해 우회한다. 인자는 flutter test에 그대로 전달된다.
rem 예) run_tests.bat --update-goldens
set "TEMP=%SystemDrive%\.whereis_test_tmp"
set "TMP=%TEMP%"
if not exist "%TEMP%" mkdir "%TEMP%"
where flutter >nul 2>nul || set "PATH=%PATH%;C:\tools\flutter\bin"
call flutter test %*
endlocal & exit /b %ERRORLEVEL%
