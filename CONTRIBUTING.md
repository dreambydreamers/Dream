# Contributing to Dream

Thank you for wanting to build Dream. The app exists because people are willing to help each other make unfinished ideas real, and the repo should work the same way.

This guide covers contribution flow. For local setup, build commands, backend notes, and verification, read [DEVELOPERS.md](DEVELOPERS.md).

## Ways To Help

- iOS product work: SwiftUI screens, interaction design, navigation, accessibility, performance.
- Media work: capture, upload, transcoding, playback, signed URL caching, poster rendering.
- Supabase work: migrations, RLS policies, RPC workflows, Realtime, search, storage.
- Design work: flows, visual polish, iconography, empty states, motion, accessibility.
- Documentation: setup guides, architecture notes, screenshots, troubleshooting.
- QA: bug reports, device testing, regression checks, screenshots, reproduction steps.

## Before You Start

1. Search existing [issues](https://github.com/dreambydreamers/Dream/issues) and pull requests.
2. Comment on the issue you want to work on so others know there is active effort.
3. For larger features or product direction changes, open an issue or discussion before writing code.
4. Read [AGENTS.md](AGENTS.md) before changing feed, video, navigation, messaging, or Supabase code.

## Issues

Good bug reports include:

- What happened.
- What you expected to happen.
- Steps to reproduce.
- Device or simulator details.
- Screenshots or screen recordings for UI issues.
- Console logs when they are relevant and do not include secrets.

Good feature requests include:

- The user problem.
- The proposed behavior.
- Any alternatives you considered.
- Screenshots, sketches, or references when useful.

## Pull Requests

1. Fork the repo.
2. Create a focused branch:

```bash
git checkout -b feature/short-description
```

3. Make the smallest coherent change that solves the issue.
4. Build locally.
5. Include screenshots for UI changes.
6. Open a pull request with a clear problem statement and solution summary.

Pull requests should include:

- A short summary of the change.
- The issue or discussion it relates to, if any.
- Verification steps you ran.
- Screenshots or recordings for visual changes.
- Notes about migrations, RLS, storage, or Realtime behavior when touched.

## Preflight Checklist

Before requesting review:

- The app builds with `xcodebuild -project Dream.xcodeproj -scheme Dream`.
- UI changes have simulator screenshots.
- Supabase changes include migrations and relevant docs updates.
- No service role keys, private keys, certificates, profiles, or local `.env` files are committed.
- Existing user changes outside your work are left alone.
- Feed and video code still keys video-scoped state by `Dream.feedID`.
- Storage paths still use lowercased user ids.
- Cross-user writes still go through RPCs rather than direct client inserts.

## Review Style

Dream values small, thoughtful pull requests. Reviewers should prioritize correctness, user experience, security, privacy, and maintainability. Contributors should expect questions and iteration; that is part of making the product stronger.

## License

By contributing to Dream, you agree that your contributions are licensed under the same license as the project: [AGPL-3.0](LICENSE).
