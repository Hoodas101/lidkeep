# Security Policy

## Supported versions

Only the latest `v2.x` release receives fixes. Older `v1.x` releases are
end-of-life and are not migrated or patched (the product was renamed to LidKeep
at v2.0.0; v1.x state is not cleaned up automatically).

| Version | Supported |
|---|---|
| 2.2.x (latest) | ✅ |
| 2.0.x – 2.1.x | ⚠️ best effort |
| 1.x | ❌ |

## Reporting a vulnerability

Please **do not** open a public Issue for security-sensitive problems.

Use GitHub's private reporting:

- Go to the repo **Security → Report a vulnerability** tab, or
- Email the maintainer via the address listed on the project's GitHub profile.

You will get an acknowledgement, and we will coordinate a fix and disclosure
timeline with you. We aim to triage within a few days.

## Privileged helper — security design

LidKeep's lid-closed "Keep awake" mode needs `pmset disablesleep`, which must
run as root. This is delegated to a **least-privilege privileged helper**, not
to a blanket `sudo` inside the app. The design:

- **Whitelisted, not arbitrary.** The helper is a script that accepts only
  `on` / `off` / `status` / `detect`. It cannot be coerced into running
  arbitrary commands.
- **Minimal sudoers scope.** The `sudoers` entry grants a single user, as root,
  exactly those four arguments — no shell, no wildcard commands.
- **Safe uninstall.** `sudo lidkeep nosleep uninstall-helper` resets
  `disablesleep 0` *before* removing the helper, so the machine never ends up in
  a "never sleeps again" state.
- **Owner accounting.** `disablesleep` is a single global switch that both
  "blackout-linked anti-sleep" and "manual anti-sleep" may depend on. The helper
  records each owner; when one stops it only unregisters *itself*, never
  disabling the anti-sleep the other still relies on. The ledger lives in
  `/var/db/lidkeep-nosleep`, owned by root, so an unprivileged user cannot forge
  an owner.
- **Coexists with remote-control apps.** ToDesk / Sunlogin / UURemote /
  TeamViewer use the same switch to stay reachable. `lidkeep doctor` reports
  "held by a remote-control app" instead of flagging it as a leftover to fix.
- **Self-heal.** A boot-time LaunchDaemon plus a check on every start resets any
  state left by a crashed process.

## Supply-chain / download integrity

- Releases are **ad-hoc signed, not notarized** — there is no paid Apple
  Developer certificate behind this project, so Gatekeeper treats a downloaded
  copy as untrusted. Clear the quarantine flag once:
  `xattr -dr com.apple.quarantine /Applications/LidKeep.app`.
- Every release publishes `SHA256SUMS` and GitHub **build-provenance
  attestations**. Before installing, verify:
  ```bash
  shasum -a 256 -c SHA256SUMS
  gh attestation verify lidkeep-macos.zip -R Hoodas101/lidkeep
  ```
- The one-line installer (`install-remote.sh`) fetches the latest release,
  verifies `SHA256SUMS`, installs, clears quarantine, and launches. Read it
  before running (`curl … | bash` without the `| bash` to inspect).

## Permissions model (what the app asks for)

- **Global hotkey:** no grant. Uses the Carbon `RegisterEventHotKey` API,
  dispatched by WindowServer — no Accessibility or Input Monitoring entitlement,
  and it survives rebuilds (ad-hoc binaries lose TCC grants on recompile, which
  is the common trap for small tools).
- **Lid-closed "Keep awake":** one-time admin password to install the
  privileged helper above. That is the only privilege the app ever requests.
