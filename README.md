# Dux AI Usage

A small [Dux Shell](https://github.com/duxlabs-dev/dux-shell) widget (the `dms` command, once DankMaterialShell) for Claude and Codex subscriptions managed by your own CLIProxyAPI server.

The bar shows a single agent icon; it turns red when usage can't be refreshed. The popup shows each provider icon with the full account email and usage beneath it. Accounts whose usage cannot be loaded stay visible; the popup explains their status. Claude's popup shows five-hour and weekly limits; Codex shows its weekly limit. Model-specific quotas are hidden.

## Install

Requirements: Python 3.11+ on your desktop and proxy server, Dux Shell (`dms` 1.5+), SSH access without interactive prompts, and CLIProxyAPI with its management API enabled.

```bash
git clone https://github.com/ivokosir/dux-ai-usage.git
cd dux-ai-usage
./install.sh
```

Edit `~/.config/dux-ai-usage/config.json`, then enable **AI Usage** in the shell's Settings → Plugins and add `aiUsage` to a bar.

Coming from `dms-ai-usage`? Run `./install.sh` again: it moves your config and cache to the new names and relinks. Then enable **AI Usage** again and swap `dmsAiUsage` for `aiUsage` in your bar.

## Connect your proxy

The installed example uses placeholders. Replace them locally; never commit your real configuration or credentials.

```json
{
  "refresh_seconds": 600,
  "timeout_seconds": 8,
  "cliproxyapi": {
    "ssh_host": "my-server",
    "base_url": "http://127.0.0.1:8317",
    "management_key_file": "~/.config/cliproxyapi/management.key"
  }
}
```

All Claude and Codex accounts in CLIProxyAPI are discovered at every refresh, including disabled or disconnected accounts. Adding or removing a subscription in the proxy updates the widget on its next poll. Other provider types are not currently supported.

No account lists or friendly names are required. The popup uses the email returned by CLIProxyAPI, with a neutral **Account 1** fallback when no email is available. Auth filenames stay on the proxy server. Stable account identifiers and a fingerprint of the proxy configuration prevent cached usage from being assigned to another account or server.

Optional `claude` and `codex` arrays can provide fallback labels or select accounts when discovery is disabled, using the exact auth-file names from your proxy's management panel:

```json
"claude": [{"label": "Personal", "proxy_auth_file": "claude-personal.json"}],
"codex": [{"label": "Work", "proxy_auth_file": "codex-work.json"}]
```

These are aliases, not an allowlist: unlisted accounts are still discovered. Keep real aliases in your private configuration. Labels must be unique within each provider. For an intentionally restricted widget, set `cliproxyapi.discover_accounts` to `false` and supply explicit account lists.

Store the existing CLIProxyAPI **management key** in the specified private text file on the server, with mode `0600`. A client API key will not work. The key-file path and base URL are resolved on the server. HTTP is accepted only for loopback addresses; use HTTPS for other hosts. The desktop needs no copy of the management key or provider tokens, and no public API port is needed.

The widget sends a small Python worker over one SSH connection per refresh. It reads `GET /v0/management/auth-files` and uses `POST /v0/management/api-call` to obtain subscription quotas. No helper installation or extra server is needed. Proxy `/usage` request counts are not subscription capacity.

This widget's configuration requires CLIProxyAPI accounts. Local `CLAUDE_CONFIG_DIR` and `CODEX_HOME` profiles are not supported by the widget. The proxy owns token renewal; reconnect expired subscriptions there.

## Refresh and troubleshooting

```bash
dux-ai-usage --pretty
dms ipc call plugin-scan scan
dms ipc call plugins enable aiUsage
dms ipc call plugin-scan reload aiUsage
```

The default polling interval is ten minutes, and opening the popup refreshes too. Network and provider failures retain the last sanitized reading with a stale status that says why and how old it is; when nothing can be read the bar icon turns red. Accounts without a previous reading remain in the popup, so an expired subscription does not disappear. Bars that ask within 30 seconds of each other share one refresh through a locked cache.

The provider quota endpoints used by CLIProxyAPI are not documented public APIs and may change. See CLIProxyAPI's [API-call handler](https://github.com/router-for-me/CLIProxyAPI/blob/main/internal/api/handlers/management/api_tools.go) and the management panel's [quota endpoints](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/blob/main/src/utils/quota/constants.ts).

## Privacy

Management keys and provider credentials stay on the proxy server. Account emails are intentionally returned for local popup display and included in the private cache and CLI output. Display labels, opaque account identifiers, quota numbers, reset times, and sanitized statuses also return. Management keys, provider credentials, auth filenames, and raw provider responses are never returned or cached. Do not publish live CLI output or screenshots containing account emails. The cache is mode `0600` under `~/.cache/dux-ai-usage/usage.json`.

Real configuration lives outside this repository. Both committed example files contain placeholders. Local configuration, usage caches, environment files, private keys, and UI captures are ignored by Git. Review staged changes before publishing; ignore rules cannot remove data from earlier commits.

## Development

```bash
python3 -m unittest discover -s tests -v
```

The optional `scripts/capture-ui.sh` captures cropped widget previews locally. Do not commit captures containing personal account labels.

MIT licensed.
