#!/usr/bin/env bash
set -euo pipefail

dart pub get
dart test
mkdir -p build
dart compile exe bin/organiza_downloads.dart -o build/organiza_downloads_linux
