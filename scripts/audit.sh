#!/bin/bash
# Verifies Vigil's safety claims from the source (and the built app, if present).
# Anyone can run this before trusting a build. Exit code is non-zero if any check fails.
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; shift; for l in "$@"; do echo "          $l"; done; FAIL=1; }
note() { printf "  \033[33mINFO\033[0m  %s\n" "$1"; }

# Matches in code only (comment-only lines are ignored).
code_grep() { grep -rnE --include='*.swift' --include='*.m' --include='*.h' "$1" Sources 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|///)' || true; }

check_none() { # <description> <regex> [allowed-file]
  local hits; hits="$(code_grep "$2")"
  [ -n "${3:-}" ] && hits="$(echo "$hits" | grep -v "$3" || true)"
  if [ -z "$hits" ]; then pass "$1"; else fail "$1" "$hits"; fi
}

echo "Source checks"
check_none "No network APIs (URLSession, sockets, Network.framework, WebKit)" \
  'import Network|import WebKit|URLSession|URLRequest|NWConnection|NWListener|NWPathMonitor|CFNetwork|CFSocket|socket\(|WKWebView|MultipeerConnectivity'
check_none "No privilege escalation (sudo, osascript, helpers, daemons, setuid)" \
  'SMJobBless|SMAppService\.(daemon|agent|loginItem)|AuthorizationExecute|osascript|NSAppleScript|sudo|setuid|launchctl'
check_none "No shell invocation (/bin/sh, /bin/zsh, /bin/bash)" \
  '/bin/(sh|zsh|bash)\b'
check_none "No private APIs or dynamic code loading (dlopen, NSClassFromString, ...)" \
  'dlopen|dlsym|NSClassFromString|NSSelectorFromString|performSelector|objc_getClass|PrivateFrameworks'
check_none "Subprocesses only in EnergyReader (fixed /usr/bin/top)" \
  'Process\(\)|NSTask|posix_spawn|popen\(|[^a-zA-Z_.]system\(' 'Sources/VigilSystem/EnergyReader.swift'
check_none "Signals only sent by HolderControl (to your own caffeinate)" \
  '\bkill\(' 'Sources/VigilSystem/HolderReader.swift'

if grep -qE '^\s*\.package\(' Package.swift; then
  fail "No third-party dependencies" "$(grep -nE '^\s*\.package\(' Package.swift)"
else
  pass "No third-party dependencies (Package.swift has no .package entries)"
fi
[ -e Package.resolved ] && fail "No lockfile of external packages" "Package.resolved exists" || pass "No Package.resolved (nothing external to pin)"

echo
echo "Built app checks"
APP="dist/Vigil.app"
if [ ! -d "$APP" ]; then
  note "dist/Vigil.app not found; run scripts/build-app.sh to check the binary too"
else
  if codesign --verify --strict "$APP" 2>/dev/null; then pass "Code signature is valid and strict"; else fail "Code signature is valid and strict"; fi

  flags="$(codesign -dv "$APP" 2>&1 | grep -E 'flags=' || true)"
  echo "$flags" | grep -q 'runtime' && pass "Hardened runtime enabled ($flags)" || fail "Hardened runtime enabled" "$flags"

  ents="$(codesign -d --entitlements - "$APP" 2>/dev/null | grep -vE '^Executable=' | tr -d '[:space:]')"
  [ -z "$ents" ] && pass "No entitlements requested" || fail "No entitlements requested" "$ents"

  plist="$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$plist" >/dev/null 2>&1 \
    && fail "No custom URL scheme (nothing a web page can trigger)" || pass "No custom URL scheme (nothing a web page can trigger)"
  usage="$(/usr/libexec/PlistBuddy -c 'Print' "$plist" 2>/dev/null | grep -E 'UsageDescription' || true)"
  [ -z "$usage" ] && pass "No privacy permissions requested (no *UsageDescription keys)" || fail "No privacy permissions requested" "$usage"
  [ -z "$(find "$APP" -path '*LaunchDaemons*' -o -path '*LaunchAgents*' -o -name '*.plist' -path '*Library*' 2>/dev/null)" ] \
    && pass "No launchd daemon/agent plists bundled" || fail "No launchd daemon/agent plists bundled"
  [ -z "$(find "$APP" -name '*.framework' -o -name '*.dylib' 2>/dev/null)" ] \
    && pass "No bundled frameworks or dylibs (nothing to swap or update)" || fail "No bundled frameworks or dylibs" "$(find "$APP" -name '*.framework' -o -name '*.dylib')"

  extra="$(find "$APP/Contents/Resources" -type f ! -name 'AppIcon.icns' 2>/dev/null)"
  [ -z "$extra" ] && pass "Resources contain only the app icon" || fail "Resources contain only the app icon" "$extra"

  net="$(otool -L "$APP/Contents/MacOS/Vigil" | grep -E 'WebKit|Network\.framework|MultipeerConnectivity' || true)"
  [ -z "$net" ] && pass "Executable does not link WebKit or Network.framework" || fail "Executable does not link WebKit or Network.framework" "$net"

  urls="$(strings -a "$APP/Contents/MacOS/Vigil" "$APP/Contents/Helpers/vigil" 2>/dev/null \
    | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' \
    | grep -vE 'apple\.com|w3\.org|swift\.org|schemas\.|ns\.adobe|purl\.org' | sort -u || true)"
  [ -z "$urls" ] && pass "No hard-coded URLs in the binaries (beyond Apple/standards namespaces)" \
    || fail "No hard-coded URLs in the binaries" "$urls"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; else echo "Some checks FAILED."; fi
exit "$FAIL"
