<!-- Thanks for contributing. Please fill in the sections below. -->

## Summary

<!-- 1-3 bullet points describing the change. -->

-

## Motivation

<!-- What symptom does this fix? Why does this change make the template better? -->

## Test plan

<!-- Checklist of how a reviewer can verify the change works. -->

- [ ] `docker compose config -q` exits 0
- [ ] `docker compose up -d` brings the stack up cleanly
- [ ] Affected target is `up` in Prometheus (`http://127.0.0.1:9090/targets`)
- [ ] Relevant dashboard panel shows data
- [ ]

## Hardware tested on

| | |
|---|---|
| **CPU arch** | |
| **GPU** | |
| **Kernel** | |
| **Docker** | |

## Changelog entry

<!-- One line for `## [Unreleased]` in CHANGELOG.md. -->

```
- ...
```

## License

- [ ] I confirm my contribution is released under the MIT license.
