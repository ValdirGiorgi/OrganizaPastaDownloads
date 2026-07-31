#!/usr/bin/env bash
set -euo pipefail

dart pub get
dart test
dart compile exe bin/organiza_downloads.dart -o build/organiza_downloads_linux
