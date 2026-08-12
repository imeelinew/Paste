#!/bin/zsh
set -euo pipefail
umask 077

if [[ $# -ne 2 ]]; then
    print -u2 "Usage: $0 <marketing-version> <build-number>"
    exit 64
fi

version="$1"
build="$2"
tag="v${version}"
script_dir="${0:A:h}"
repo_root="${script_dir:h}"
github_repo="${PASTE_GITHUB_REPOSITORY:-imeelinew/Paste}"
team_id="${PASTE_TEAM_ID:-5Q5QT76MJU}"
notary_profile="${PASTE_NOTARY_PROFILE:-Paste-notary}"
sparkle_account="${PASTE_SPARKLE_ACCOUNT:-ed25519}"
work_dir=$(mktemp -d /tmp/paste-release.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

cd "$repo_root"

for required_command in git gh xcodebuild xcrun security codesign spctl ditto ruby curl grep sed; do
    command -v "$required_command" >/dev/null || {
        print -u2 "Missing command: $required_command"
        exit 69
    }
done

[[ "$(git branch --show-current)" == "main" ]] || {
    print -u2 "Release must run from main"
    exit 65
}
[[ -z "$(git status --porcelain)" ]] || {
    print -u2 "Commit or discard local changes before releasing"
    exit 65
}
gh auth status >/dev/null
if gh release view "$tag" --repo "$github_repo" >/dev/null 2>&1; then
    print -u2 "Release already exists: $tag"
    exit 65
fi

developer_id_identity="${PASTE_DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$developer_id_identity" ]]; then
    developer_id_identity=$(
        security find-identity -v -p codesigning \
            | grep 'Developer ID Application:' \
            | grep "($team_id)" \
            | head -n 1 \
            | sed -E 's/^[^"]*"(.*)"$/\1/'
    ) || true
fi
[[ -n "$developer_id_identity" ]] || {
    print -u2 "No Developer ID Application certificate found for team $team_id"
    exit 66
}
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null

"$script_dir/set-version.sh" "$version" "$build"
git add Paste.xcodeproj/project.pbxproj
if ! git diff --cached --quiet; then
    git commit -m "Release $tag"
fi

archive_path="$work_dir/Paste.xcarchive"
export_path="$work_dir/export"
derived_data="$work_dir/DerivedData"
export_options="$work_dir/ExportOptions.plist"
release_dir="$work_dir/release"
mkdir -p "$release_dir"

/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $team_id" "$export_options"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$export_options"

xcodebuild archive \
    -project Paste.xcodeproj \
    -scheme Paste \
    -configuration Release \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    -destination 'generic/platform=macOS' \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_IDENTITY="$developer_id_identity" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build"

xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates

app_path="$export_path/Paste.app"
[[ -d "$app_path" ]] || {
    print -u2 "Exported app not found"
    exit 70
}
codesign --verify --deep --strict --verbose=2 "$app_path"

notary_zip="$work_dir/Paste-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_zip"
xcrun notarytool submit "$notary_zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

archive_name="Paste-${version}.zip"
archive_file="$release_dir/$archive_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_file"

sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
generate_appcast="$sparkle_tools/generate_appcast"
[[ -x "$generate_appcast" ]] || {
    print -u2 "Sparkle generate_appcast tool not found at $generate_appcast"
    exit 69
}

download_prefix="https://github.com/${github_repo}/releases/download/${tag}"
"$generate_appcast" \
    --account "$sparkle_account" \
    --download-url-prefix "$download_prefix/" \
    --link "https://github.com/${github_repo}" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o appcast.xml \
    "$release_dir"

appcast_file="$release_dir/appcast.xml"
[[ -s "$appcast_file" ]] || {
    print -u2 "appcast.xml was not generated"
    exit 70
}
grep -q 'sparkle:edSignature=' "$appcast_file" || {
    print -u2 "appcast.xml does not contain an EdDSA signature"
    exit 70
}

git fetch origin main
git merge-base --is-ancestor origin/main HEAD || {
    print -u2 "Local main does not contain origin/main; integrate remote changes first"
    exit 65
}
git push origin HEAD:main

# Intentionally blank release description. Never add --generate-notes or a notes file.
gh release create "$tag" \
    "$archive_file" \
    "$appcast_file" \
    --repo "$github_repo" \
    --target "$(git rev-parse HEAD)" \
    --title "$tag" \
    --notes '' \
    --latest

feed_url="https://github.com/${github_repo}/releases/latest/download/appcast.xml"
curl --fail --location --silent --show-error "$feed_url" >/dev/null
print "Published $tag with an empty GitHub Release description"
