# Focus Tool 37: build and release tasks.
#
#   just release 0.1.0   test, sign with Developer ID, notarize, staple, zip
#
# One-time setup on the release machine:
#   1. A "Developer ID Application" certificate for the team in the keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + ).
#   2. A team App Store Connect API key (Users and Access > Integrations >
#      App Store Connect API > Team Keys, "Developer" access), stored in the
#      keychain under the profile name below:
#        just notary-setup path/to/AuthKey_XXXXXXXXXX.p8 XXXXXXXXXX <issuer-id>
#
# The result opens on any Mac without Gatekeeper warnings.

set shell := ["bash", "-euo", "pipefail", "-c"]

project := "FocusTool37.xcodeproj"
scheme := "FocusTool37"
app := "FocusTool37.app"
team := "3BR2673AY9"
out := "build/release"

# Keychain profile created by `just notary-setup`; override with NOTARY_PROFILE.
notary_profile := env("NOTARY_PROFILE", "focustool37-notary")

default:
    @just --list

# Run the unit tests
test:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -derivedDataPath build/DerivedData -quiet test

# Store a team API key for notarization in the keychain (the .p8 can be deleted afterwards)
notary-setup key key_id issuer:
    #!/usr/bin/env bash
    set -euo pipefail

    [[ -f "{{ key }}" ]] || { echo "No key file at {{ key }}"; exit 1; }

    # Validates the key with Apple before saving it.
    xcrun notarytool store-credentials "{{ notary_profile }}" \
        --key "{{ key }}" \
        --key-id "{{ key_id }}" \
        --issuer "{{ issuer }}"

# Test, archive, sign with Developer ID, notarize, staple and zip VERSION (e.g. 0.1.0)
release version: (_check version) test
    #!/usr/bin/env bash
    set -euo pipefail

    dir="{{ out }}/{{ version }}"
    archive="$dir/FocusTool37.xcarchive"
    exported="$dir/export"
    zip="{{ out }}/FocusTool37-{{ version }}.zip"
    rm -rf "$dir" "$zip" "$zip.sha256"
    mkdir -p "$dir"

    # Version and build number are passed in, so the project file stays untouched.
    # The build number is the commit count: always increasing, reproducible from the tag.
    echo "==> Archiving {{ version }}"
    xcodebuild archive \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$archive" \
        -quiet \
        MARKETING_VERSION={{ version }} \
        CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"

    # Re-signs the archived app with the Developer ID certificate. Development
    # signing (what Run and the archive use) is rejected by Gatekeeper elsewhere.
    echo "==> Exporting with Developer ID"
    cat > "$dir/ExportOptions.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>method</key>
        <string>developer-id</string>
        <key>teamID</key>
        <string>{{ team }}</string>
        <key>signingStyle</key>
        <string>automatic</string>
    </dict>
    </plist>
    PLIST
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportPath "$exported" \
        -exportOptionsPlist "$dir/ExportOptions.plist" \
        -allowProvisioningUpdates \
        -quiet

    built="$exported/{{ app }}"
    codesign --verify --deep --strict "$built"

    # notarytool takes a zip, but the ticket gets stapled to the app itself,
    # so the zip for distribution is made afterwards from the stapled app.
    echo "==> Notarizing (usually a few minutes)"
    ditto -c -k --keepParent "$built" "$dir/notarize.zip"
    xcrun notarytool submit "$dir/notarize.zip" \
        --keychain-profile "{{ notary_profile }}" \
        --wait

    echo "==> Stapling"
    xcrun stapler staple "$built"
    xcrun stapler validate "$built"

    # The check a downloaded copy goes through on first launch.
    spctl --assess --type execute "$built"

    # ditto keeps the bundle's symlinks and extended attributes intact, plain zip doesn't
    ditto -c -k --keepParent "$built" "$zip"
    (cd "{{ out }}" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

    echo
    echo "Built $zip (signed, notarized, stapled)"
    cat "$zip.sha256"

# Release preconditions: a plain x.y.z version, a committed tree, an unused tag,
# and a Developer ID certificate to sign with
_check version:
    #!/usr/bin/env bash
    set -euo pipefail

    [[ "{{ version }}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3, got '{{ version }}'"; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "Uncommitted changes: a release has to match a commit"; exit 1; }
    ! git rev-parse -q --verify "refs/tags/v{{ version }}" >/dev/null || { echo "Tag v{{ version }} already exists"; exit 1; }
    security find-identity -v -p codesigning | grep -q "Developer ID Application:.*({{ team }})" || {
        echo "No 'Developer ID Application' certificate for team {{ team }} in the keychain."
        echo "Create one in Xcode > Settings > Accounts > Manage Certificates."
        exit 1
    }
