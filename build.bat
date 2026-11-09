@echo off
rem Shortcut: build.bat [debug|release] is classeurtool build.
rem Every other step: odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- <command> (help lists them).
cd /d "%~dp0"
if not exist build mkdir build
odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -keep-executable -- build %*
