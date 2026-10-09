# shellcheck shell=bash
# shellcheck disable=SC2034
# Shared Obsidian helpers. Source after _brew-i9.sh.
#
# Sets: OBSIDIAN_APPIMAGE_DIR, OBSIDIAN_APPIMAGE, OBSIDIAN_BREW_FLAGS (array)
# Functions: obsidian_prepare_appimage_dir, obsidian_write_launcher
#
# On the i9 brew runs as brewuser (home not readable by us), so the AppImage goes into the
# brew prefix. Override with OBSIDIAN_APPIMAGE_DIR.

_obsidian_dir_given="${OBSIDIAN_APPIMAGE_DIR+yes}"
_obsidian_dir_given="${OBSIDIAN_APPIMAGE_DIR+yes}"
if [ -n "${IS_I9:-}" ]; then
  OBSIDIAN_APPIMAGE_DIR="${OBSIDIAN_APPIMAGE_DIR:-/home/linuxbrew/.linuxbrew/share/appimages}"
  OBSIDIAN_BREW_FLAGS=("--appimagedir=$OBSIDIAN_APPIMAGE_DIR")
else
  OBSIDIAN_APPIMAGE_DIR="${OBSIDIAN_APPIMAGE_DIR:-$HOME/Applications}"
  OBSIDIAN_BREW_FLAGS=()
  [ -n "$_obsidian_dir_given" ] && OBSIDIAN_BREW_FLAGS=("--appimagedir=$OBSIDIAN_APPIMAGE_DIR")
fi
OBSIDIAN_APPIMAGE="$OBSIDIAN_APPIMAGE_DIR/Obsidian.AppImage"

obsidian_prepare_appimage_dir() {
  # Only the i9 needs a directory created as brewuser (via `brew sh`; plain mkdir is not sudo-allowed).
  if [ -n "${IS_I9:-}" ]; then
    printf 'mkdir -p "%s"\n' "$OBSIDIAN_APPIMAGE_DIR" | $BREW sh >/dev/null 2>&1 || true
  else
    mkdir -p "$OBSIDIAN_APPIMAGE_DIR"
  fi
}

obsidian_write_launcher() {
  if [ ! -x "$OBSIDIAN_APPIMAGE" ]; then
    echo "WARNING: $OBSIDIAN_APPIMAGE missing or not executable — launcher not written" >&2
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/obsidian" <<LAUNCHER
#!/usr/bin/env bash
# Launcher written by tools/obsidian-install.sh
exec "$OBSIDIAN_APPIMAGE" "\$@"
LAUNCHER
  chmod +x "$HOME/.local/bin/obsidian"
  echo "launcher: $HOME/.local/bin/obsidian -> $OBSIDIAN_APPIMAGE"
}
