# OpenAI usage

`openai.py` shows the ChatGPT plan usage reported by
<https://chatgpt.com/settings/usage?tab=overview>. It uses the Codex CLI's
ChatGPT login in `~/.codex/auth.json`, not an OpenAI API key. Requires Python 3
with no third-party packages. Sign in with `codex login` first.

Waybar runs this module with `--waybar --cache 240` every 60 seconds. The bar
shows the five-hour window's used percentage and reset countdown; hover for
all windows, or left-click for a terminal breakdown. Cached data displays
immediately and refreshes in the background. Data older than 15 minutes is
marked stale. Cache and refresh locks stay in `~/.cache/openai-usage/`.

```bash
~/.config/waybar/modules/openai.py --detail
~/.config/waybar/modules/openai.py --watch 60
~/.config/waybar/modules/openai.py --json
~/.config/waybar/modules/openai.py --help
```

The script can refresh expired tokens and saves them back to the local Codex
auth file. Never commit that file or usage caches. If authentication breaks,
run `codex login` again.

## Logo font

`../fonts/openai-logo.ttf` contains the OpenAI knot at `U+E000`, under the font
family **OpenAI Usage Logo**. `fontconfig/fonts.conf` loads this bundled folder
relative to its own location, so no project-directory path is required.
After restoring both the Waybar and Fontconfig dotfiles, run `fc-cache -f` and
restart Waybar. When installing only the module, copy the font to
`~/.local/share/fonts/` instead.

The source artwork is `../fonts/openai.svg`, from
[Simple Icons 13.21.0](https://github.com/simple-icons/simple-icons/blob/13.21.0/icons/openai.svg),
distributed under [CC0](https://github.com/simple-icons/simple-icons/blob/13.21.0/LICENSE.md).
