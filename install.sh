#!/usr/bin/env bash
# Links `ai` and `cla` into ~/.local/bin (or the folder you pass). Run it again if you move this folder.
#   bash install.sh
#   bash install.sh /usr/local/bin
here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
dest=${1:-$HOME/.local/bin}
mkdir -p "$dest" || exit 1

# files uploaded through the GitHub website lose their executable bit
chmod +x "$here/bin/ai" "$here/bin/cla" "$here/scripts/statusline-usage.sh" "$here/tests/run.sh" "$here/install.sh"

for n in ai cla; do
  if [ -e "$dest/$n" ] && [ ! -L "$dest/$n" ]; then
    echo "skipped $dest/$n: a file (not a link) is already there" >&2
    continue
  fi
  if [ -L "$dest/$n" ] && [ "$(readlink "$dest/$n")" != "$here/bin/$n" ]; then
    echo "replacing $dest/$n (was -> $(readlink "$dest/$n"))"
  fi
  ln -sf "$here/bin/$n" "$dest/$n" && echo "linked $dest/$n"
done

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "add this to ~/.zshrc or ~/.bashrc, then open a new terminal:  export PATH=\"$dest:\$PATH\"" ;;
esac
command -v jq >/dev/null 2>&1 || echo "optional: install jq for usage bars, shared trust and failover"
command -v fzf >/dev/null 2>&1 || echo "optional: install fzf for a searchable picker"
