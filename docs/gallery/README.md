# Alfred Gallery submission kit

Getting Insomniac into the [Alfred Gallery](https://alfred.app). The Gallery is **invite-only**, and the form at [alfredapp/gallery-edits](https://github.com/alfredapp/gallery-edits) says to submit only after the Alfred team asks.

## 1. Share on the Alfred Forum (now)

Post [`forum-post.md`](forum-post.md) in [Share your Workflows](https://www.alfredforum.com/forum/3-share-your-workflows/). The Alfred team invites workflows that are stable and trusted by users.

## 2. When invited

1. **Screenshots:** capture the two PNGs listed in [`nadavshatz/insomniac/images/SCREENSHOTS.md`](nadavshatz/insomniac/images/SCREENSHOTS.md).
2. **Pull request:** fork `alfredapp/gallery-edits` and copy the folder [`nadavshatz/insomniac/`](nadavshatz/insomniac) (`readme.md`, `icon.png` 256×256, `images/`) to `workflows/nadavshatz/insomniac/`. Open a PR.
3. **Turn off the updater for releases:** set the repository variable `GALLERY_LISTED` to `true` (*Settings → Secrets and variables → Actions → Variables*). From then on, CI releases the Gallery build, which has no self-updater. That's required, because Alfred updates every copy, including ones installed from GitHub. Then publish a release (*Actions → CI → Run workflow*, version `X.Y.Z`).
4. **Issue:** open *Submit New Workflow* on gallery-edits and answer:

| Field | Answer |
| --- | --- |
| Invited | ✔ (only if you were) |
| Separate PR with instructions | ✔ link the PR from step 2 |
| Keywords ≥ 3 characters | ✔ `awake`, user-configurable |
| Icon ≥ 256×256 | ✔ |
| No auto-updater | ✔ the Gallery build (`scripts/build.sh --gallery`) has none, verified by `tests/build_test.sh` |
| Doesn't download extra software | ✔ |
| No unsigned binaries | ✔ scripts only (zsh, JXA) |
| Homepage | https://github.com/nadavshatz/insomniac |
| Alfred Forum page | the link from step 1 |
| Tags | `caffeinate, sleep, power, amphetamine, timer, menu-bar, productivity` |
| Homebrew dependencies | none |

## Why two builds?

| | GitHub build (default) | Gallery build (`--gallery`) |
| --- | --- | --- |
| Update check against GitHub Releases | ✔ | removed (code, setting, icon) |
| Everything else | identical | identical |
