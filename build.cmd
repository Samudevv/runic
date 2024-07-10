@set SCRIPT_DIR=%~dp0
@mkdir %SCRIPT_DIR%\build

odin build %SCRIPT_DIR% -collection:root=%SCRIPT_DIR% -collection:shared=%SCRIPT_DIR%\shared -out:%SCRIPT_DIR%\build\runic.exe -o:speed -define:YAML_STATIC=true -thread-count:4