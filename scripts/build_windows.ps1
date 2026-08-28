$ErrorActionPreference = "Stop"

dart pub get
dart test
New-Item -ItemType Directory -Force -Path build | Out-Null
dart compile exe bin/organiza_downloads.dart -o build\organiza_downloads.exe
