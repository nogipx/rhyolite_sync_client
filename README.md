# Rhyolite Sync

Syncs your vault across devices using end-to-end encryption.

> **An account is required for full access.**
> **Payment is required for full access** (subscription).

---

## Features

- **End-to-end encrypted sync** — your notes are encrypted on-device before being sent to the server. The server never sees plaintext content.
- **Multi-device support** — keep your vault in sync across desktop and mobile.
- **Conflict resolution** — choose between Last Write Wins or Conflict Copy strategies.
- **Passphrase-based encryption** — your encryption key never leaves your device.

## Requirements

- A Rhyolite Sync account — sign up at [rhyolite.nogipx.dev](https://rhyolite.nogipx.dev)
- An active subscription

## Installation

1. Open Settings → Community plugins → Browse.
2. Search for **Rhyolite Sync** and install it.
3. Enable the plugin.
4. Open the plugin settings, create an account or sign in.
5. Subscribe to activate sync.
6. Connect or create a vault and enter your passphrase.

## Network services

This plugin connects to the **Rhyolite Sync backend** (hosted at `rhyolite.nogipx.dev`) for the following purposes:

| Service            | Purpose                                             |
|--------------------|-----------------------------------------------------|
| Authentication     | Account sign-in and session management              |
| Vault sync         | Uploading and downloading encrypted file changes    |
| Subscription check | Verifying active subscription status                |

No plaintext note content is ever sent to the server. All data is encrypted on your device using your passphrase before transmission.

## Privacy

See our [Privacy Policy](https://rhyolite.nogipx.dev/privacy) for full details on data collection and handling.

## FAQ

**Does it work on mobile (iOS/Android)?**
Yes, the plugin works on both desktop and mobile.

**Do I need to enter my passphrase on every device?**
Yes, once per device when connecting to a vault. After that, you can enable "Remember on this device" to store the derived key in Obsidian's secret storage — so you won't be prompted again on subsequent launches.

**What happens if I forget my passphrase?**
Your local files on disk are not affected — they are never deleted by the plugin. If you forget your passphrase, you lose access to the encrypted copies stored on the server, but your original notes remain intact on every device where they exist. The passphrase is never sent to the server and cannot be recovered, so store it somewhere safe.

**Can I change my passphrase?**
Not currently supported.

**What happens to my files if I disconnect the vault?**
Files on disk are not affected. The plugin removes the vault configuration and remembered key from the device. Your data on the server remains intact.

**What happens to my data on the server if I cancel my subscription?**
Your data is not deleted from the server when a subscription expires. Sync will stop until the subscription is renewed.

**What is the difference between Last Write Wins and Conflict Copy?**
For text files (`.md`, `.txt`, etc.), the plugin first attempts an automatic 3-way merge — if successful, the conflict is resolved silently with no duplicates.

If automatic merge fails:
- **Last Write Wins** — the version with the later timestamp is kept, the other is discarded.
- **Conflict Copy** — your local version stays in place, and the remote version is saved as a separate file named `filename (conflict copy YYYY-MM-DD).ext`.

## Support

- Website: [rhyolite.nogipx.dev](https://rhyolite.nogipx.dev)
- Telegram: [t.me/nogipx](https://t.me/nogipx)
- Issues: open a GitHub issue in this repository
