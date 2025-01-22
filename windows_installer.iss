[Setup]
AppName="Runic"
AppVersion=0.6
DefaultDirName={autopf}\runic
OutputDir=build\package
OutputBaseFilename=runic.win64.installer

[Files]
Source: "build\runic.exe";                                 DestDir: {app}
Source: "shared\libclang\lib\windows\x86_64\libclang.dll"; DestDir: {app}

[Registry]
Root: HKA; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{reg:HKA\Environment,Path};{app}"; Flags: preservestringtype
