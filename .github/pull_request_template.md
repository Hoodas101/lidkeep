# Pull Request

Thanks for sending a patch. Please skim the checklist below — it makes review
fast and avoids the same back-and-forth every time.

## What & why
<!-- One or two sentences. What the PR changes and why. -->

Fixes #<issue> (if applicable)

## How to verify
<!-- Concrete steps a reviewer can copy-paste. Example:

```
cd lidkeep
make test
SMOKE_FULL=1 make test
```

If you need a real black-out to verify, say so — smoke can be run in
two passes (App resident and App not resident).
-->

## Checklist
- [ ] `make all` runs without errors (`codesign` self-lock on `*.cstemp`
      leftovers is a known trap — wipe them before signing)
- [ ] `make test` passes locally; `SMOKE_FULL=1 make test` passes for the
      cases this PR can affect
- [ ] `python3 dev-tools/check-l10n.py .` reports "✓ 双向对齐"
      if you added or changed any `L("…")` call
- [ ] Both `README.md` and `README.zh-CN.md` updated if user-visible strings
      or behavior changed
- [ ] `Sources/Info.plist` rewrite is left as-is if your change affects the
      version (the maintainer bumps it as part of release; fighting it just
      creates noise)
- [ ] No unrelated drive-by reformatting or refactors
- [ ] New code follows the existing style — Swift, no third-party deps,
      the Shared/ files compile into both CLI and Bar targets

## Risk
<!-- Low / Medium / High and why. Does it touch power management,
ownership accounting, hotkey registration, or privileged helper? -->