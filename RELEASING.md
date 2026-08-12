# Releasing Paste

Paste uses Sparkle 2.9.5. Update archives and `appcast.xml` are hosted as GitHub Release assets. The stable feed URL is:

```text
https://github.com/imeelinew/Paste/releases/latest/download/appcast.xml
```

## One-time setup

1. Install a `Developer ID Application` certificate for team `5Q5QT76MJU` in the login Keychain.
2. Store Apple notarization credentials in the login Keychain:

   ```bash
   xcrun notarytool store-credentials Paste-notary \
     --apple-id YOUR_APPLE_ID \
     --team-id 5Q5QT76MJU
   ```

   Enter the app-specific password only at the secure prompt so it is not saved in shell history.

3. Keep the existing Sparkle private key in the login Keychain under account `ed25519`. Never commit or paste an exported private key into an issue, task, shell history, or GitHub Actions secret.
4. Back up the login Keychain securely. If an explicit Sparkle key export is required for disaster recovery, create it only on encrypted storage and delete any unencrypted working copy immediately after the backup is verified.

## Publish

Start from a clean `main` branch, then run:

```bash
./scripts/release.sh 0.1.3 2
```

The script updates both version fields, creates a version commit, archives with Developer ID signing, notarizes and staples the app, creates an EdDSA-signed appcast, pushes `main`, and publishes the ZIP and appcast to GitHub Releases.

The GitHub Release title is the version tag and its description is intentionally empty. The script never generates release notes.

Environment overrides are available when needed:

```text
PASTE_TEAM_ID
PASTE_NOTARY_PROFILE
PASTE_DEVELOPER_ID_IDENTITY
PASTE_SPARKLE_ACCOUNT
PASTE_GITHUB_REPOSITORY
```
