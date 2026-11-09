#!/usr/bin/env bash
# Shortcut: ./build.sh [debug|release] is classeurtool build.
# Every other step: odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- <command> (help lists them).
cd "$(dirname "$0")" && mkdir -p build && exec odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -keep-executable -- build "$@"
