#!/usr/bin/env bash
# Links the collector and the Dux Shell (dms) plugin, and creates the config.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
bin_dir="$HOME/.local/bin"
app_config_dir="$config_root/dux-ai-usage"
# Dux Shell keeps its config in ~/.config/dms (older DankMaterialShell: ~/.config/DankMaterialShell).
shell_conf="$config_root/dms"
[[ -d "$shell_conf" ]] || shell_conf="$config_root/DankMaterialShell"
plugins_dir="$shell_conf/plugins"

# This project used to be called dms-ai-usage: bring its config and cache along
# and drop the old links.
for root in "$config_root" "$cache_root"; do
  if [[ -d "$root/dms-ai-usage" && ! -e "$root/dux-ai-usage" ]]; then
    mv "$root/dms-ai-usage" "$root/dux-ai-usage"
  fi
done
for old in "$bin_dir/dms-ai-usage" "$plugins_dir/dmsAiUsage"; do
  if [[ -L "$old" ]]; then
    rm "$old"
  fi
done

mkdir -p "$bin_dir" "$app_config_dir" "$plugins_dir"

link_safely() {
  local source="$1"
  local target="$2"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "Refusing to replace existing path: $target" >&2
    exit 1
  fi
  ln -sfn "$source" "$target"
}

link_safely "$repo_dir/bin/dux-ai-usage" "$bin_dir/dux-ai-usage"
link_safely "$repo_dir/dms-plugin" "$plugins_dir/aiUsage"

if [[ ! -e "$app_config_dir/config.json" ]]; then
  cp "$repo_dir/config.example.json" "$app_config_dir/config.json"
fi
chmod 600 "$app_config_dir/config.json"

echo "Installed dux-ai-usage."
echo "Edit $app_config_dir/config.json, then enable AI Usage in the shell's Settings → Plugins"
echo "and add it to a bar (its id is aiUsage)."
