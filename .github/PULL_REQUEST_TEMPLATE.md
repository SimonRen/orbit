## Summary

<!-- One or two sentences: what changed and why. Reference the issue it closes, if any. -->

Fixes #

## Changes

<!-- Bulleted list of what this PR does. -->

-

## Test plan

<!-- How you verified the change. Be specific. -->

- [ ] `make test` passes
- [ ] Manually verified in the UI (describe steps)
- [ ] Release build still succeeds (`make release`) — only if touching build settings or signing

## Screenshots

<!-- Required for UI changes. Before/after if possible. -->

## Notes for reviewers

<!-- Anything reviewers should pay extra attention to: tricky logic, intentional tradeoffs, follow-ups deferred. -->

## Checklist

- [ ] Code follows the conventions in `CONTRIBUTING.md`
- [ ] New code uses `os.Logger`, not `print()` / `NSLog`
- [ ] Validation goes through `ValidationService` where applicable
- [ ] Tests added/updated when behavior changed
- [ ] No commits include personal team-ID overrides from `Config/Project.local.xcconfig`
