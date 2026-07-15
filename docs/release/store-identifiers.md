# Clovery Store Identity Registry

This file records identifiers that must remain stable after a store release.
Private keys, passwords, provisioning profiles, and recovery codes must never be
stored in Git.

## Apple App Store

The iOS V2 app is an upgrade of the existing App Store application.

| Identity | Value |
| --- | --- |
| Main bundle ID | `com.clovery.app` |
| Widget bundle ID | `com.clovery.app.CloveryWidget` |
| Apple development team | `M92TBSSR2R` |
| iCloud container | `iCloud.com.clovery.app` |
| App Group | `group.com.clovery.app` |
| iCloud KVS suffix | `com.clovery.app` |

Changing any value above would break the existing App Store upgrade path or V1
data migration. Release builds must use an App Store version and build number
greater than the current production release.

## Android Stores

Android has not been published. Its first release uses application ID
`com.clovery.app` across Google Play and supported Android stores. Before the
first production upload, generate a dedicated long-term release key, record its
certificate fingerprints, and store encrypted backups and recovery instructions
in two independently controlled locations. The keystore and passwords are not
repository files.

## Huawei And HarmonyOS

Huawei AppGallery and HarmonyOS have not been published. Their first listing
uses `com.clovery.app` as the application identifier where the platform permits.
The final identifier, signing certificate fingerprint, and store application ID
must be added to this registry before W5 can produce a release artifact.

## Release Rule

Development builds may use local signing. Store release jobs must fail when an
identifier differs from this registry, release signing is unavailable, or the
requested version is not greater than the current store version.
