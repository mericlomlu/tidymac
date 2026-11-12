#!/bin/zsh
# Refreshes Resources/Localizable.xcstrings from the source code.
# The compiler reports every localisable string; new ones are added to the catalog, unused ones are marked stale.
# Run it after changing any user-facing text, then fill in the missing translations (the tests list them).
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
OUT=.build/stringsdata
# A separate build folder, rebuilt from scratch: an incremental build only reports the files it recompiled,
# and the sync below would then drop every string from the files it skipped.
rm -rf "$OUT" .build/localize; mkdir -p "$OUT"
swift build --build-path .build/localize -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/$OUT" >/dev/null
CATALOG=Resources/Localizable.xcstrings
[ -f "$CATALOG" ] || echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > "$CATALOG"
xcrun xcstringstool sync "$CATALOG" --stringsdata "$OUT"/*.stringsdata
echo "Synced $CATALOG: $(xcrun xcstringstool print "$CATALOG" | wc -l | tr -d ' ') strings"
