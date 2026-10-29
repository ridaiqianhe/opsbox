#!/usr/bin/env bash
set -euo pipefail

# Installs source files only. Service installation is a separate menu action.
ref=${OPSBOX_REF:-main}
destination=${OPSBOX_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/opsbox}
case "$destination" in
    /*) ;; *) echo 'OPSBOX_DIR 必须是绝对路径。' >&2; exit 1 ;;
esac
if [[ -e "$destination" && ! -f "$destination/opsbox.sh" ]]; then
    echo '目标目录已存在且不是 OpsBox，请设置另一个 OPSBOX_DIR。' >&2
    exit 1
fi
if [[ -d "$destination/.git" ]]; then
    echo '这是 Git 工作副本，请使用 git pull 更新，以保留本地改动。' >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
url="https://codeload.github.com/ridaiqianhe/opsbox/tar.gz/$ref"
if command -v curl >/dev/null 2>&1; then
    curl -fSL --retry 2 --connect-timeout 15 --max-time 180 "$url" -o "$work/source.tar.gz"
elif command -v wget >/dev/null 2>&1; then
    wget --timeout=30 -O "$work/source.tar.gz" "$url"
else
    echo '请先安装 curl 或 wget。' >&2
    exit 1
fi
mkdir "$work/source"
tar -xzf "$work/source.tar.gz" --strip-components=1 -C "$work/source"
test -f "$work/source/opsbox.sh"
test -f "$work/source/lib/ui.sh"
test -f "$work/source/lib/catalog.sh"
test -f "$work/source/modules/random-ipv6-socks/manage.sh"
mkdir -p "$destination"
# .env and data/ are not distributed, so upgrades preserve runtime state.
cp -R "$work/source/." "$destination/"
chmod +x "$destination/opsbox.sh"
if [[ -n "${OPSBOX_BIN_DIR:-}" ]]; then
    bin_dir=$OPSBOX_BIN_DIR
elif (( EUID == 0 )); then
    bin_dir=/usr/local/bin
else
    bin_dir="$HOME/.local/bin"
fi
mkdir -p "$bin_dir"
if [[ -L "$bin_dir/opsbox" ]] || { [[ -e "$bin_dir/opsbox" ]] && ! grep -q '^# OpsBox launcher$' "$bin_dir/opsbox"; }; then
    echo "已安装到 $destination；$bin_dir/opsbox 已存在，未覆盖。"
else
    # A wrapper keeps source-relative module paths valid.
    printf '#!/usr/bin/env bash\n# OpsBox launcher\nexec bash %q "$@"\n' "$destination/opsbox.sh" > "$work/launcher"
    chmod 0755 "$work/launcher"
    mv "$work/launcher" "$bin_dir/opsbox"
    printf '已安装 OpsBox：%s\n运行：%s/opsbox\n' "$destination" "$bin_dir"
fi
