#!/usr/bin/env bash
set -euo pipefail
export CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
if [[ -n "${FLUTTER_ROOT:-}" ]]; then exec "$FLUTTER_ROOT/bin/flutter" "$@"; fi
exec flutter "$@"
