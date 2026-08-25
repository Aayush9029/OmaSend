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

A `history_clear` message carries no content. The receiver deletes its entire clipboard history and does not rebroadcast, so a clear started on one device empties every connected device exactly once.

## Files

Files use a separate direct TCP stream and are not subject to the clipboard item limit. The sender opens with an encrypted `file_offer` containing the safe file name and 64-bit size. The receiver keeps a private partial file and answers with its current byte offset.

File contents are split into 1 MiB binary chunks. Each chunk is encrypted independently with AES-256-GCM, a fresh nonce, and authenticated data containing `omasend-file-v1`, the transfer ID, and the 64-bit byte offset. Binary chunks avoid base64 overhead. A dropped connection is retried from the receiver's saved offset.

After the final chunk, the sender provides the full SHA-256 digest in an encrypted `file_complete` message. The receiver verifies it before moving the file into `Downloads/OmaSend` and acknowledging completion.

## Limits

- Text or image clipboard item: 10 MiB decoded
- File: 64-bit streamed size, bounded by available disk space
- History: 50 items
- Persisted history data: 50 MiB
- Accepted images: PNG, JPEG, and GIF on Linux; images are normalized to PNG on macOS

The configuration and history file is stored with user-only permissions. A device that does not know the pairing code cannot authenticate or decrypt a message.
