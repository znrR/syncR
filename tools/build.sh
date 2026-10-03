#!/bin/zsh
# Builds the command line tools into ~/.local/bin (or $BIN).
set -e
cd "${0:A:h}"
BIN=${BIN:-~/.local/bin}
mkdir -p "$BIN"
swiftc -O syncrctl.swift -o "$BIN/syncrctl"
swiftc -O syncr-ltas.swift -o "$BIN/syncr-ltas"
echo "built: $BIN/syncrctl, $BIN/syncr-ltas"
