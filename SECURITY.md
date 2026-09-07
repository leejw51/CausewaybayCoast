# Security and privacy review

This repository is a local gameplay prototype, not an authenticated public service.
Publishing source code does not make the running server safe for Internet access.

## Addressed before staging

- The server defaults to `127.0.0.1`. Set `COAST_HOST` explicitly for other interfaces.
- WebSocket messages and frames are limited to 16 KiB; repeated login messages on
  one connection are rejected.
- Player chat/name markup is escaped for Godot BBCode, and login names reject control
  characters. Demo friend names are reserved so players cannot edit those sample islands.
- Chat transcripts are no longer persisted by default on either client or server.
  `COAST_LOG_CHAT=1` opts a process into logging. Previously saved transcripts remain
  on disk; this change does not delete user data.
- Git excludes local databases, JSONL event/chat/settings files, logs, process files,
  environment files, common private-key formats, caches, generated Blender working
  files, downloaded templates, and release bundles.
- Blender render metadata containing local filesystem paths was removed from the
  character PNG assets without changing image pixels.
- The supplied Blender scene's saved path metadata was normalized before staging;
  original backups and intermediate source versions remain local and ignored.
- Grok generators read API keys from the environment. Only prompts, provider/model
  names and generated image data belong in the repository, never API responses or keys.

## Remaining issues before hosting publicly

- **Account impersonation:** login trusts a display name. Anyone who knows a name
  can reconnect as that player, including access to their island editing permissions.
  Add authentication and bind sessions to authenticated identities before public use.
  Same-name concurrent connections can also interfere with session cleanup.
- **Transport and browser access:** the development endpoint uses plain `ws://` and
  has no browser Origin allowlist. Deploy authenticated TLS (`wss://`) and enforce an
  appropriate Origin policy before accepting browser connections.
- **Resource exhaustion:** outbound queues are unbounded, and there are no connection,
  account creation, or message-rate limits. The frame cap alone does not prevent DoS.
- **Discovery/privacy:** island listings expose display names and room identifiers;
  there are no private islands or friend-only access rules. Demo islands are labeled
  examples, not evidence of a friendship or online presence.
- **Retention:** SQLite stores player names and island layouts; event logs retain
  joins, visits and edits. Client settings retain the chosen name and server URL.
  Default locations are `~/.causewaybaycoast/server` and `~/.causewaybaycoast/client`.
  Do not enter passwords or tokens into server URLs. Retention limits, user deletion,
  restricted data-file permissions and consent controls need further work for hosting.

## Review scope

The additional pre-publication secret scan found no matches in the 189 staged files
(26.1 MiB) or the single reachable Git commit using Gitleaks 8.30.1 with redacted
reports. An independent staged scan checked credential patterns, known credential
values from the process environment, personal paths, and English BIP-39 word-list
sequences, including quoted arrays. The broader word-sequence check found 22
candidates, none with a valid BIP-39 checksum. Other mnemonic languages and
arbitrary encoded/encrypted secrets are not covered by that mnemonic check.

The local filename inventory found no `.env`, wallet or private-key files. The sole
`.pem` match was the ignored formatter environment's public CA certificate bundle.
A local Gitleaks pass also found no matches; installed tooling/compiler/import caches
were excluded, and files over 20 MiB were skipped in that local pass. Local build logs
and backup assets can still contain machine paths and test-player data: keep them
ignored. Redacted scan reports remain local under `build/security/`.

The local review covers source, Git exclusions, credential/path patterns and PNG
metadata, plus the identified server flows. It is not a penetration test or a complete
dependency vulnerability audit, and cannot guarantee absence of secrets in arbitrary
binary assets. Review the staged diff before committing. No commit or push is required
to inspect it: use `git diff --cached --stat` and `git diff --cached`.
Run `python3 tools/public_check.py` to repeat the staged credential/path checks.
The remote's existing commit already contains a copyright holder name; changing a
local file does not remove information from existing public Git history.

Report vulnerabilities privately to the maintainer; do not post credentials or user
data in public GitHub issues.
