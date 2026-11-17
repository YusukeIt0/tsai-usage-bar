# TSAI UsageBar

A lightweight macOS menu bar app that shows how much of your **Claude Code** and **Codex** usage limits is left and when they reset, plus your **GitHub Actions** free usage for private repositories.

Claude Code・Codexの利用枠の残量とリセット時刻、GitHub Actionsの無料枠（非公開リポジトリ）を、メニューバーで確認できる軽量なmacOSアプリです。（[日本語](#日本語)）

<p>
  <img src="docs/images/icons-light.png" alt="Menu bar icons on a light menu bar" width="640"><br>
  <img src="docs/images/icons-dark.png" alt="Menu bar icons on a dark menu bar" width="640">
</p>

<p>
  <img src="docs/images/popover-claude.png" alt="Claude Code panel with 5-hour and 7-day bars and reset times" width="280">
  <img src="docs/images/popover-codex.png" alt="Codex panel" width="280">
  <img src="docs/images/popover-github.png" alt="GitHub Actions panel showing free usage for private repositories" width="280">
</p>

> **Unofficial.** Not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI or GitHub. Claude and Claude Code are trademarks of Anthropic, PBC. Codex and OpenAI are trademarks of OpenAI. GitHub and the Octocat are trademarks of GitHub, Inc. The icons are simplified silhouettes used only to tell the services apart.

## What it shows

| Item | Meaning |
|---|---|
| `H42%` | 5-hour limit (Claude Code, Codex) |
| `W68%` | 7-day limit (Claude Code, Codex) |
| `M42%` | This month's free GitHub Actions usage for private repositories |
| `H—` | No current value (never received, or the reset time passed and no new value has arrived yet) |

- Numbers show **remaining** by default (100 − used). Switch to **used** in Settings.
- Each icon fills like a battery: the solid part matches the number shown, and the rest is faint. With no value, the whole icon is faint.
- Up to five items: Claude Code H/W, Codex H/W and GitHub Actions M. Turn each on or off in Settings; hold ⌘ and drag to reorder. Turning off all of a service's items pauses it.
- Click an item to see that service's bars, reset times (in your Mac's time zone) and time remaining.
- Windows your plan doesn't have (for example, plans without a 5-hour limit) are hidden automatically.
- Values are never guessed. Reaching a reset time doesn't turn a value into 100%; the app waits for the next official value.
- Languages: English, 日本語, 繁體中文, 简体中文, 한국어, Français, Deutsch and ไทย. Automatic picks the first supported macOS language (otherwise English), or choose one in Settings.

<img src="docs/images/settings.png" alt="Settings window" width="360">

## Install

Requires macOS 14 or later (Apple silicon or Intel). No sudo, Homebrew, or SwiftBar.

```sh
curl -fsSL https://raw.githubusercontent.com/YusukeIt0/tsai-usage-bar/main/install.sh | sh
```

The installer picks your CPU's build from the latest GitHub Release, checks its SHA-256 checksum and code signature, installs it to `~/Applications`, and starts it.

> Builds are currently **not notarized by Apple** (no Developer ID signing yet). The checksum and signature checks above confirm the download is intact.

**Updates:** about once a day the app checks this repository's releases. When a newer version exists, the panel and Settings show **Update**, which installs it and keeps your settings. Settings → **Check** checks right away.

**Uninstall** (also restores your Claude Code status line):

```sh
curl -fsSL https://raw.githubusercontent.com/YusukeIt0/tsai-usage-bar/main/install.sh | sh -s -- --uninstall
```

## Connect

**Codex** works automatically if you've signed in to the Codex CLI. If not, the app offers **Sign in to Codex in browser**, the official Codex sign-in.

**Claude Code** sends usage limits to its official `statusLine` command. Open Settings → **Connect**. After you confirm, the app:

1. backs up `~/.claude/settings.json`,
2. points `statusLine` at a small relay that saves only the limit percentages and reset times,
3. keeps running your previous status line command, so your status line looks the same.

**Disconnect** or uninstall puts the previous setting back. Values update with each Claude Code response. If you aren't signed in to Claude Code, the app offers **Sign in to Claude Code in browser** (`claude auth login`).

**GitHub Actions**: Settings → **Connect GitHub**. The app copies a one-time code and opens GitHub; paste it and authorize the *TSAI UsageBar* GitHub App. It can only read your plan and billing usage ("Plan: read"). Standard runners on public repositories are free with no limit, so the app shows the monthly included usage that private repositories consume (Free: 12 USD, Pro: 18 USD of compute; other plans show "—"). It resets at 00:00 UTC on the 1st, and GitHub's totals can lag by a few hours. **Disconnect** forgets the token on this Mac; revoke the authorization anytime under GitHub → Settings → Applications.

## How it gets data

| | Source | When |
|---|---|---|
| Codex | Official `codex app-server`: `account/rateLimits/read` (`usedPercent`, `windowDurationMins`, `resetsAt`) | About every 3 minutes, every minute while its panel is open, right after a reset time, on wake and network recovery, and on ↻ |
| Claude Code | Official `statusLine` JSON: `rate_limits.five_hour` / `seven_day` (`used_percentage`, `resets_at`) | Immediately whenever Claude Code updates its status line |
| GitHub Actions | Official billing usage summary (`/users/{user}/settings/billing/usage/summary`, Actions) minus each public repository's usage; plan from `/user` | About hourly, when its panel opens (if older than 10 minutes), after wake, and on ↻ |

- Codex windows are matched by duration (300 min = H, 10080 min = W). Other buckets or durations are never substituted.
- Each Codex query starts `codex app-server`, reads, and stops it. Only read requests are sent: no sessions, model runs, purchases, or reset-credit use.
- Overlapping requests are merged and failures back off. Nothing is polled during sleep.
- Idle: about 17 MB memory and ~0% CPU on an Apple silicon Mac. The status line relay adds about 6 ms.

## Privacy

- No servers of its own and no analytics. The app's own network requests are the daily update check against this repository's releases and, only if you connect GitHub, read-only GitHub API requests (your plan, public repository list and Actions usage). Codex and Claude Code talk to their own services.
- Stored locally in `~/Library/Application Support/TSAI UsageBar/`: limit percentages and reset times, and, if you connect GitHub, its access token in a file readable only by your user (like the Codex CLI's login file). The Keychain isn't used because ad-hoc signed updates would make macOS ask for access again each time. Preferences are in the app's defaults.
- Never stored or logged: Codex or Claude Code credentials, prompts, conversations, transcript paths, or session IDs. The app doesn't read the Keychain or call private endpoints.

## Build from source

```sh
swift test                   # unit tests
scripts/build-app.sh         # dist/TSAI UsageBar.app + per-arch zips + SHA256SUMS
scripts/release.sh           # tag and publish a GitHub Release (maintainers)
```

Swift 5.10+ / Xcode 16+. Set `SIGN_IDENTITY` to a Developer ID Application identity to sign; otherwise builds are ad-hoc signed.

---

## 日本語

- **表示:** `H` は5時間、`W` は7日間の利用枠（Claude Code・Codex）、`M` はGitHub Actionsの今月の無料枠（非公開リポジトリ）。初期設定は残量（100 − 使用率）で、設定から使用率に切り替えられます。値がない、またはリセット後に新しい値がまだ届いていないときは `H—` と表示します。
- **アイコン:** バッテリーのように、表示中の数値の分だけ濃く塗られ、残りは薄く表示されます。値がないときは全体が薄くなります。
- **項目:** Claude Code H/W・Codex H/W・GitHub Actions M の最大5つ。設定で個別にON/OFF、⌘ドラッグで並べ替え。プランにない枠は自動で非表示。あるサービスの項目をすべてOFFにすると、そのサービスの取得を止めます。
- **クリック:** そのサービスの棒グラフ、リセット時刻（Macのタイムゾーン）、残り時間を表示します。
- **言語:** 英語・日本語・繁体字中国語・簡体字中国語・韓国語・フランス語・ドイツ語・タイ語。自動ではmacOSの優先言語のうち最初の対応言語（なければ英語）。設定から選択も可能。
- **インストール:** 上記の `curl … | sh`（sudo不要、`~/Applications` に導入）。現在のビルドはApple公証前です。
- **アップデート:** 1日1回確認し、新しい版があればポップアップと設定に「アップデート」が出ます（設定は保持）。設定の「確認」ですぐ確認もできます。
- **Codex:** Codex CLIにサインイン済みならそのまま使えます。未サインインなら「ブラウザでCodexにサインイン」から。
- **Claude Code:** 設定の「連携する」から。`~/.claude/settings.json` をバックアップし、既存のstatusLine表示を保ったまま中継します。「連携を解除」やアンインストールで元に戻ります。
- **GitHub Actions:** 設定の「GitHubと連携」から（コードはコピー済みでブラウザが開くので、貼り付けて承認）。権限はプランと利用量の読み取りのみ。公開リポジトリは無料・上限なしのため、非公開リポジトリが使う月の無料枠（Free 12ドル・Pro 18ドル分、他のプランは「—」）を表示。毎月1日 00:00（UTC）にリセット。GitHubの集計は数時間遅れることがあります。
- **プライバシー:** 独自サーバー・分析なし。アプリ自身の通信は1日1回の更新確認と、GitHub連携時の読み取りだけです。保存するのは利用率・リセット時刻・設定と、GitHub連携時のトークン（本人だけが読めるファイル）です。

## License

MIT
