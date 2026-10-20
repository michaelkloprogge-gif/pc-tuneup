# Code signing

PC-TuneUp.exe is not code-signed yet, so Windows SmartScreen shows "Windows protected your PC"
the first time someone runs a downloaded copy (they click **More info > Run anyway**). Signing
the exe removes the "unknown publisher" warning and, as downloads build up reputation, the
SmartScreen prompt itself.

Signing needs a certificate issued to a real, verified person or organisation, so it has to be
applied for by the repository owner. Since June 2023 new code-signing certificates must live on a
hardware token or in a cloud signing service, so a plain `.pfx` file is no longer handed out.

## Options

| Option | Cost | Notes |
|---|---|---|
| **Certum Open Source Code Signing** (recommended now) | about EUR 50-70 a year, plus a card reader | A classic certificate on a smart card, issued to you personally as an open-source developer. Signing then happens on your own PC (not in GitHub Actions), because the card has to be plugged in. Certum also sells a cloud version (SimplySign) that works without a card. |
| **SignPath Foundation** | free for open-source projects | Applied in October 2026 and declined: the Foundation only signs for projects that already show public visibility (stars, forks, contributors, articles, discussions). They invite a new application once the project is better known. Paid SignPath plans are possible meanwhile. |
| **Azure Artifact Signing** (formerly Trusted Signing) | about USD 10 a month | Microsoft's cloud signing. Not available here: individual developers must live in the United States or Canada (organisations in the EU are eligible). |

## What is already in place

`.github/workflows/release.yml` has a **Sign the exe** step that is skipped until the repository
has the secrets `SIGNING_CERT_BASE64` (a base64 `.pfx`) and `SIGNING_CERT_PASSWORD`. That step suits
an older `.pfx` certificate. For SignPath or Azure, replace it with their GitHub action:

- SignPath: `signpath/github-action-submit-signing-request` - upload the unsigned exe as an artifact,
  submit it, and download the signed exe before the "Publish the release" step.
- Azure: `azure/trusted-signing-action` with the endpoint, account and certificate-profile names.

After signing, the release notes need no changes; the self-update checks the SHA-256 that GitHub
publishes for the (now signed) exe, so updating keeps working.
