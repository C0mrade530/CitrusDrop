#!/bin/bash
# CitrusDrop installer: macOS built-ins only. Review before executing.
set -euo pipefail

app_only=false
no_open=false
for argument in "$@"; do
  case "$argument" in
    --app-only) app_only=true ;;
    --no-open) no_open=true ;;
    --help|-h)
      printf '%s\n' 'Usage: install.sh [--app-only] [--no-open]' \
        'Installs the latest CitrusDrop release into ~/Applications.' \
        'CITRUSDROP_INSTALL_DIR overrides that directory for testing.'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

fail() { printf 'CitrusDrop: %s\n' "$*" >&2; exit 1; }
[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail 'This installer requires macOS.'
mac_version="$(/usr/bin/sw_vers -productVersion)"
major="${mac_version%%.*}"
[[ "$major" =~ ^[0-9]+$ && "$major" -ge 13 ]] || fail 'macOS 13 or later is required.'
case "$(/usr/bin/uname -m)" in
  arm64|x86_64) ;;
  *) fail 'Only Apple silicon and Intel 64-bit Macs are supported.' ;;
esac

install_dir="${CITRUSDROP_INSTALL_DIR:-$HOME/Applications}"
[[ "$install_dir" == /* ]] || fail 'CITRUSDROP_INSTALL_DIR must be an absolute path.'
/bin/mkdir -p "$install_dir"
destination="$install_dir/CitrusDrop.app"
if [[ -e "$destination" || -L "$destination" ]]; then
  if /usr/bin/pgrep -x CitrusDrop >/dev/null; then
    fail 'CitrusDrop is running. Quit it yourself, then run this installer again; it will keep a backup.'
  fi
fi

staging="$(/usr/bin/mktemp -d "$install_dir/.citrusdrop-install.XXXXXX")"
cleanup() { /bin/rm -rf "$staging"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

download() {
  local address="$1" target="$2"
  /usr/bin/curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
    --connect-timeout 20 --max-time 600 --output "$target" "$address" \
    || fail "Download failed: $address. Check the connection and GitHub availability."
}

printf 'Finding the latest CitrusDrop release…\n'
metadata="$staging/release.json"
download 'https://api.github.com/repos/C0mrade530/CitrusDrop/releases/latest' "$metadata"
release_tag="$(/usr/bin/plutil -extract tag_name raw -o - "$metadata" 2>/dev/null)" \
  || fail 'GitHub did not return a release. A public release must exist before installation.'

zip_url=''
sums_url=''
index=0
while name="$(/usr/bin/plutil -extract "assets.$index.name" raw -o - "$metadata" 2>/dev/null)"; do
  case "$name" in
    CitrusDrop-macOS.zip)
      zip_url="$(/usr/bin/plutil -extract "assets.$index.browser_download_url" raw -o - "$metadata")" ;;
    SHA256SUMS)
      sums_url="$(/usr/bin/plutil -extract "assets.$index.browser_download_url" raw -o - "$metadata")" ;;
  esac
  index=$((index + 1))
done
[[ -n "$zip_url" && -n "$sums_url" ]] || fail 'The release is missing CitrusDrop-macOS.zip or SHA256SUMS.'
for address in "$zip_url" "$sums_url"; do
  case "$address" in
    https://github.com/C0mrade530/CitrusDrop/releases/download/*) ;;
    *) fail 'The release contains an unexpected asset URL.' ;;
  esac
done

printf 'Downloading CitrusDrop %s…\n' "$release_tag"
archive="$staging/CitrusDrop-macOS.zip"
download "$zip_url" "$archive"
download "$sums_url" "$staging/SHA256SUMS"
expected="$(/usr/bin/awk '{ name=$2; sub(/^\*/, "", name); if (name == "CitrusDrop-macOS.zip" || name == "dist/CitrusDrop-macOS.zip" || name == "./CitrusDrop-macOS.zip" || name == "./dist/CitrusDrop-macOS.zip") print $1 }' "$staging/SHA256SUMS")"
[[ ${#expected} -eq 64 && "$expected" != *[!0-9a-f]* ]] || fail 'The release checksum manifest is missing one unambiguous SHA-256 for the app ZIP.'
actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
[[ "$actual" == "$expected" ]] || fail 'SHA-256 verification failed. Nothing has been installed.'

/usr/bin/unzip -Z1 "$archive" > "$staging/entries.txt" || fail 'Cannot read the verified ZIP.'
while IFS= read -r entry; do
  case "$entry" in
    CitrusDrop.app|CitrusDrop.app/*) ;;
    *) fail 'The ZIP contains a path outside CitrusDrop.app.' ;;
  esac
  case "/$entry/" in
    */../*|*/./*|*\\*) fail 'The ZIP contains an unsafe path.' ;;
  esac
done < "$staging/entries.txt"

/usr/bin/ditto -x -k "$archive" "$staging/unpacked" || fail 'Could not unpack the app.'
app="$staging/unpacked/CitrusDrop.app"
binary="$app/Contents/MacOS/CitrusDrop"
[[ -d "$app" && ! -L "$app" && -x "$binary" && ! -L "$binary" ]] || fail 'The ZIP does not contain the expected application.'
identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
[[ "$identifier" == org.citrusdrop.mac ]] || fail 'Unexpected application bundle identifier.'
/usr/bin/codesign --verify --deep --strict "$app" || fail 'Application signature verification failed. Nothing has been installed.'

backup=''
if [[ -e "$destination" || -L "$destination" ]]; then
  # Check again after downloading, without terminating any user process.
  /usr/bin/pgrep -x CitrusDrop >/dev/null && fail 'CitrusDrop started during setup. Quit it and run the installer again.'
  backup="$install_dir/CitrusDrop.backup-$(/bin/date +%Y%m%d-%H%M%S)-$$.app"
  /bin/mv "$destination" "$backup" || fail 'Could not preserve the existing app.'
fi
if ! /bin/mv "$app" "$destination"; then
  if [[ -n "$backup" && ! -e "$destination" && ! -L "$destination" ]]; then /bin/mv "$backup" "$destination"; fi
  fail 'Could not install the new app. The existing app or its dated backup has been preserved.'
fi
printf 'Installed: %s\n' "$destination"
[[ -z "$backup" ]] || printf 'Previous app preserved: %s\n' "$backup"

if [[ "$app_only" == false ]]; then
  printf 'Setting up missing free media and Office engines…\n'
  if ! "$destination/Contents/MacOS/CitrusDrop" --install-engines; then
    fail "The app is installed, but engine setup did not finish. If macOS blocked launch, use Privacy & Security → Open Anyway, then open Formats & engines in CitrusDrop and retry. App: $destination"
  fi
fi
if [[ "$no_open" == false ]]; then
  /usr/bin/open "$destination" || fail "The app is installed but could not open. Check Privacy & Security → Open Anyway. App: $destination"
fi
printf 'Ready. macOS may ask for approval on the first launch.\n'
