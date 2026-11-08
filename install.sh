#!/bin/sh
# zsh-ghost-ai installer.
#
#   curl -fsSL https://raw.githubusercontent.com/cybercoretech/zsh-ghost-ai/main/install.sh | sh
#
# Options (after `sh -s --` when piped):
#   --version <tag>   install this release (default: the latest); "main" = the
#                     development branch, unverified
#   --yes             don't ask anything; use defaults and ZGA_* variables
#   --provider <p>    ollama (default), anthropic or openai
#   --pull            download the default Ollama model if it's missing (~1 GB)
#   --dir <path>      where to install (default ~/.local/share/zsh-ghost-ai)
#   --no-rc           don't touch ~/.zshrc; print the line to add instead
#   --from <file>     install from a local release tarball (for testing)
#
# What it does: checks for zsh 5.8+, curl and jq; downloads a release tarball
# and verifies its SHA-256; installs it without sudo; adds a marked block to
# ~/.zshrc (rerunning replaces it, uninstall removes it); helps set up a
# model; runs `ghost-ai doctor`.

set -u

REPO="cybercoretech/zsh-ghost-ai"
OLLAMA_MODEL="qwen2.5-coder:1.5b"
MARK_BEGIN="# >>> zsh-ghost-ai >>>"
MARK_END="# <<< zsh-ghost-ai <<<"

say()  { printf '%s\n' "$*"; }
info() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ask <question> <default y|n>: true for yes. Reads the terminal, since stdin
# is the script itself when piped from curl. Defaults when there's no terminal
# or --yes was given.
ask() {
  if [ "$YES" = 1 ] || ! [ -r /dev/tty ] || ! (: </dev/tty) 2>/dev/null; then
    [ "$2" = y ]
    return
  fi
  if [ "$2" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '%s %s ' "$1" "$hint" >/dev/tty
  read -r reply </dev/tty || reply=""
  case $reply in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) [ "$2" = y ] ;;
  esac
}

# prompt <question> <default>: free-text answer from the terminal.
prompt() {
  if [ "$YES" = 1 ] || ! [ -r /dev/tty ] || ! (: </dev/tty) 2>/dev/null; then
    printf '%s' "$2"
    return
  fi
  printf '%s [%s] ' "$1" "$2" >/dev/tty
  read -r reply </dev/tty || reply=""
  printf '%s' "${reply:-$2}"
}

install_hint() {
  if command -v pacman >/dev/null 2>&1; then say "  sudo pacman -S --needed $*"
  elif command -v apt-get >/dev/null 2>&1; then say "  sudo apt-get install $*"
  elif command -v dnf >/dev/null 2>&1; then say "  sudo dnf install $*"
  elif command -v brew >/dev/null 2>&1; then say "  brew install $*"
  else say "  install: $*"; fi
}

check_requirements() {
  missing=""
  for tool in zsh curl jq tar; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  if [ -n "$missing" ]; then
    say "zsh-ghost-ai needs:$missing"
    install_hint "$missing"
    die "missing requirements"
  fi
  zsh -fc 'autoload -Uz is-at-least; is-at-least 5.8' ||
    die "zsh 5.8 or newer is needed (found $(zsh --version))"
  if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then SHA="shasum -a 256"
  else die "need sha256sum or shasum to verify the download"; fi
}

latest_version() {
  curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
    jq -r '.tag_name // empty' 2>/dev/null
}

# fetch_release <tmpdir>: download (or copy) the tarball into tmpdir and
# verify it; sets TARBALL.
fetch_release() {
  tmp=$1
  if [ -n "$FROM" ]; then
    [ -f "$FROM" ] || die "no such file: $FROM"
    TARBALL="$tmp/${FROM##*/}"
    cp "$FROM" "$TARBALL"
    sums="${FROM%/*}/SHA256SUMS"
    if [ -f "$sums" ]; then
      verify "$TARBALL" "$sums"
    else
      warn "no SHA256SUMS next to $FROM; not verified"
    fi
    return
  fi

  if [ -z "$VERSION" ]; then
    VERSION=$(latest_version)
    if [ -z "$VERSION" ]; then
      warn "no release published yet; installing the development branch (unverified)"
      VERSION=main
    fi
  fi

  if [ "$VERSION" = main ]; then
    TARBALL="$tmp/zsh-ghost-ai-main.tar.gz"
    info "Downloading the main branch"
    curl -fsSL -o "$TARBALL" "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" ||
      die "download failed"
    return
  fi

  base="https://github.com/$REPO/releases/download/$VERSION"
  TARBALL="$tmp/zsh-ghost-ai-$VERSION.tar.gz"
  info "Downloading zsh-ghost-ai $VERSION"
  curl -fsSL -o "$TARBALL" "$base/zsh-ghost-ai-$VERSION.tar.gz" ||
    die "download failed: $base/zsh-ghost-ai-$VERSION.tar.gz"
  curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" ||
    die "couldn't download SHA256SUMS for $VERSION"
  verify "$TARBALL" "$tmp/SHA256SUMS"
}

verify() {
  want=$(awk -v f="${1##*/}" '$2 == f || $2 == "*"f {print $1}' "$2")
  [ -n "$want" ] || die "${1##*/} isn't listed in SHA256SUMS"
  got=$($SHA "$1" | awk '{print $1}')
  [ "$want" = "$got" ] || die "checksum mismatch for ${1##*/} (expected $want, got $got)"
  info "Checksum verified"
}

# Unpack into DIR atomically: a failed install leaves the old one in place.
install_files() {
  tmp=$1
  mkdir -p "$tmp/x"
  tar -xzf "$TARBALL" -C "$tmp/x" || die "couldn't unpack the tarball"
  src=$(find "$tmp/x" -name zsh-ghost-ai.plugin.zsh -maxdepth 2 | head -n1)
  [ -n "$src" ] || die "the tarball has no zsh-ghost-ai.plugin.zsh"
  src=${src%/*}
  parent=${DIR%/*}
  mkdir -p "$parent"
  rm -rf "$DIR.new"
  cp -R "$src" "$DIR.new"
  if [ -d "$DIR" ]; then rm -rf "$DIR.old" && mv "$DIR" "$DIR.old"; fi
  mv "$DIR.new" "$DIR"
  rm -rf "$DIR.old"
  info "Installed to $DIR"
}

zshrc_path() {
  printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"
}

# The block that loads the plugin, plus provider settings when not default.
rc_block() {
  say "$MARK_BEGIN"
  if [ "$PROVIDER" != ollama ]; then
    say "zstyle ':ghost-ai:*' provider $PROVIDER"
  fi
  if [ -n "$RC_EXTRA" ]; then printf '%s\n' "$RC_EXTRA"; fi
  say "source \"$DIR/zsh-ghost-ai.plugin.zsh\""
  say "$MARK_END"
}

# Add or replace the block. It goes before zsh-syntax-highlighting if that's
# loaded (it must come last), else at the end.
write_rc() {
  rc=$(zshrc_path)
  [ -f "$rc" ] || : >"$rc"
  block=$(rc_block)
  tmprc="$rc.zga.$$"
  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
    $0 == begin { skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip       { print }
  ' "$rc" >"$tmprc.clean" || die "couldn't read $rc"
  if grep -n 'zsh-syntax-highlighting' "$tmprc.clean" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
    line=$(grep -n 'zsh-syntax-highlighting' "$tmprc.clean" | grep -v '^[0-9]*:[[:space:]]*#' | head -n1 | cut -d: -f1)
    {
      head -n $((line - 1)) "$tmprc.clean"
      printf '%s\n' "$block"
      tail -n +"$line" "$tmprc.clean"
    } >"$tmprc"
  else
    {
      cat "$tmprc.clean"
      [ -s "$tmprc.clean" ] && [ -n "$(tail -c1 "$tmprc.clean")" ] && echo
      printf '%s\n' "$block"
    } >"$tmprc"
  fi
  rm -f "$tmprc.clean"
  cat "$tmprc" >"$rc" && rm -f "$tmprc"
  info "Added zsh-ghost-ai to $rc"
}

detect_manager() {
  if [ -n "${ZSH:-}" ] && [ -d "${ZSH}" ] || [ -d "$HOME/.oh-my-zsh" ]; then echo oh-my-zsh
  elif grep -qs 'zinit' "$(zshrc_path)"; then echo zinit
  elif grep -qs 'antidote' "$(zshrc_path)"; then echo antidote
  fi
}

setup_provider() {
  if [ "$PROVIDER" = ollama ]; then
    if curl -s -m 2 "http://localhost:11434/api/tags" >/dev/null 2>&1; then
      if curl -s -m 2 "http://localhost:11434/api/tags" | jq -e --arg m "$OLLAMA_MODEL" \
          '[.models[]? | select(.name == $m)] | length > 0' 2>/dev/null | grep -q true; then
        info "Ollama has $OLLAMA_MODEL"
      elif [ "$PULL" = 1 ] || ask "Download the default model $OLLAMA_MODEL (about 1 GB) with Ollama?" y; then
        info "ollama pull $OLLAMA_MODEL"
        ollama pull "$OLLAMA_MODEL" || warn "the pull failed; run later: ollama pull $OLLAMA_MODEL"
      else
        say "Later: ollama pull $OLLAMA_MODEL"
      fi
      return
    fi
    if [ "$YES" = 1 ]; then
      warn "Ollama isn't running. Install it from https://ollama.com, then: ollama pull $OLLAMA_MODEL"
      return
    fi
    say ""
    say "Ollama (the default, a local model) isn't running here. Pick a model:"
    say "  1) Ollama: I'll install it from https://ollama.com myself"
    say "  2) Claude (needs ANTHROPIC_API_KEY; the line and context are sent to Anthropic)"
    say "  3) An OpenAI-compatible server (llama.cpp, LM Studio, vLLM, OpenRouter...)"
    choice=$(prompt "Choice" 1)
    case $choice in
      2) PROVIDER=anthropic
         [ -n "${ANTHROPIC_API_KEY:-}" ] || warn "ANTHROPIC_API_KEY isn't set; export it in ~/.zshrc or use: zstyle ':ghost-ai:*' key-cmd '<command>'" ;;
      3) PROVIDER=openai
         url=$(prompt "Server URL (without /v1)" "http://localhost:8080")
         model=$(prompt "Model name" "")
         RC_EXTRA="zstyle ':ghost-ai:*' endpoint $url"
         [ -n "$model" ] && RC_EXTRA="$RC_EXTRA
zstyle ':ghost-ai:*' model $model" ;;
      *) say "After installing Ollama: ollama pull $OLLAMA_MODEL" ;;
    esac
  fi
}

main() {
  VERSION="${ZGA_VERSION:-}"
  YES="${ZGA_YES:-0}"
  PROVIDER="${ZGA_PROVIDER:-ollama}"
  DIR="${ZGA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-ghost-ai}"
  PULL=0 NO_RC=0 FROM="" RC_EXTRA=""

  while [ $# -gt 0 ]; do
    case $1 in
      --version)  VERSION=${2:?--version needs a tag}; shift ;;
      --yes|-y)   YES=1 ;;
      --provider) PROVIDER=${2:?--provider needs a name}; shift ;;
      --pull)     PULL=1 ;;
      --dir)      DIR=${2:?--dir needs a path}; shift ;;
      --no-rc)    NO_RC=1 ;;
      --from)     FROM=${2:?--from needs a file}; shift ;;
      -h|--help)  sed -n '2,23p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
  case $PROVIDER in ollama|anthropic|openai) ;; *) die "unknown provider: $PROVIDER" ;; esac

  check_requirements
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/zga-install.XXXXXX") || die "mktemp failed"
  trap 'rm -rf "$tmp"' EXIT INT TERM

  fetch_release "$tmp"
  install_files "$tmp"
  setup_provider

  manager=$(detect_manager)
  if [ "$NO_RC" = 1 ]; then
    say ""
    say "Add this to $(zshrc_path):"
    rc_block
  elif [ "$manager" = oh-my-zsh ]; then
    custom="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins"
    mkdir -p "$custom" && ln -sfn "$DIR" "$custom/zsh-ghost-ai"
    info "Linked into oh-my-zsh: $custom/zsh-ghost-ai"
    say "Add zsh-ghost-ai to plugins=(...) in $(zshrc_path), before zsh-syntax-highlighting."
    if [ "$PROVIDER" != ollama ] || [ -n "$RC_EXTRA" ]; then
      say "And above that line:"
      [ "$PROVIDER" != ollama ] && say "  zstyle ':ghost-ai:*' provider $PROVIDER"
      [ -n "$RC_EXTRA" ] && printf '  %s\n' "$RC_EXTRA"
    fi
  else
    if [ -n "$manager" ]; then
      say "Found $manager; adding a plain source line (you can move it to $manager: cybercoretech/zsh-ghost-ai)."
    fi
    write_rc
  fi

  say ""
  info "Checking the setup"
  zsh -fic "zstyle ':ghost-ai:*' provider $PROVIDER; $(printf '%s' "$RC_EXTRA" | tr '\n' ';') source '$DIR/zsh-ghost-ai.plugin.zsh' && ghost-ai doctor" </dev/null || true
  say ""
  say "Done. Start a new shell to use it:  exec zsh"
  say "Type a command and wait a moment; press → to accept the ghost text."
}

main "$@"
