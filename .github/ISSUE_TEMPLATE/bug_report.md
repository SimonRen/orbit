---
name: Bug report
about: Something isn't working as expected
title: ''
labels: bug
assignees: ''
---

## Describe the bug

A clear, concise description of what's wrong.

## To reproduce

Steps:

1. Open Orbit
2. ...
3. ...
4. See error

## Expected behavior

What you expected to happen.

## Actual behavior

What actually happened. Include screenshots if helpful.

## Environment

- **Orbit version**: (Orbit → About Orbit)
- **macOS version**: (Apple menu → About This Mac)
- **Machine**: Apple Silicon / Intel
- **Privileged helper installed**: yes / no

## Logs

If applicable, run the following and paste the relevant output:

```bash
log show --predicate 'subsystem == "com.orbit.app" OR subsystem == "com.orbit.helper"' --last 10m
```

## Additional context

Anything else that might help — config snippets, related issues, what you'd already tried, etc.
