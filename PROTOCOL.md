# OmaSend protocol

OmaSend version 1 sends length-prefixed encrypted JSON messages over TCP port 53317.

## Discovery

On a local network, each app publishes and browses `_omasend._tcp` through Bonjour or compatible mDNS. The TXT record contains the protocol version, device ID, and display name.

When the Tailscale CLI is available, OmaSend also reads online IPv4 peers from `tailscale status --json` and probes port 53317 directly. Clipboard data never passes through an OmaSend server.

## Framing

Each TCP frame begins with a four-byte unsigned big-endian payload length followed by one encrypted envelope. Frames are limited to 14 MiB.

## Encryption

The shared pairing code is hashed with SHA-256 to produce an AES-256 key. Messages use AES-GCM with a random 96-bit nonce and the authenticated additional data `omasend-v1`.

The outer JSON envelope is:

```json
{
  "version": 1,
  "nonce": "base64",
  "ciphertext": "base64"
}
```

The authenticated plaintext includes a unique item ID, sender ID and name, timestamp, optional UTF-8 text, optional MIME type, and optional base64 image data.

## Limits

- Clipboard item: 10 MiB decoded
- History: 50 items
- Persisted history data: 50 MiB
- Accepted images: PNG, JPEG, and GIF on Linux; images are normalized to PNG on macOS

The configuration and history file is stored with user-only permissions. A device that does not know the pairing code cannot authenticate or decrypt a message.
