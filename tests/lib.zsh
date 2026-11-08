# Test harness: drives a real interactive zsh through zpty.
#
# The shell under test gets a .zshrc that loads the plugin plus a "dump"
# widget bound to ^X^T, which writes BUFFER / POSTDISPLAY / CURSOR to a file.
# Tests type keys, press the dump key and assert on what the line editor holds.

zmodload zsh/zpty zsh/datetime zsh/zselect

typeset -g ZGA_ROOT=${ZGA_ROOT:-${0:A:h:h}}
typeset -gi T_PASS=0 T_FAIL=0
typeset -g T_DIR T_NAME=""

# t_start [rc lines...]: start a shell. Extra args are added to its .zshrc
# before the plugin loads (zstyles, a fake provider, ...).
t_start() {
  T_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zga-test.XXXXXX")
  {
    print -r -- 'PS1="> "; RPS1=""; unsetopt beep'
    print -r -- 'export XDG_STATE_HOME='${(q)T_DIR}/state
    print -rl -- "$@"
    print -r -- "source ${(q)ZGA_ROOT}/zsh-ghost-ai.plugin.zsh"
    print -r -- 'typeset -gi _T_SEQ=0'
    print -r -- '_t_dump() { (( ++_T_SEQ )); print -r -- "$_T_SEQ"$'"'"'\x1f'"'"'"$BUFFER"$'"'"'\x1f'"'"'"$POSTDISPLAY"$'"'"'\x1f'"'"'"$CURSOR" >| '${(q)T_DIR}'/dump; }'
    print -r -- 'zle -N _t_dump; bindkey "^X^T" _t_dump'
  } > $T_DIR/.zshrc
  T_SEQ=0
  zpty -b t "env -u ZDOTDIR TERM=xterm-256color ZDOTDIR=${(q)T_DIR} HOME=${(q)T_DIR} zsh -i"
  t_settle 0.4
}

t_stop() {
  zpty -d t 2>/dev/null
  [[ -n $T_DIR && -d $T_DIR ]] && rm -rf -- $T_DIR
}

# Read and discard whatever the shell printed, so the pty never fills up.
t_drain() {
  local chunk
  while zpty -rt t chunk 2>/dev/null; do :; done
}

# t_settle <seconds>: wait while draining output.
t_settle() {
  local end=$(( EPOCHREALTIME + ${1:-0.2} ))
  while (( EPOCHREALTIME < end )); do
    t_drain
    zselect -t 2
  done
}

# t_type <text>: send keys exactly as given (no newline).
t_type() {
  zpty -w -n t "$1"
  t_settle 0.05
}

typeset -g D_BUFFER D_POST D_CURSOR
typeset -gi T_SEQ=0

# t_dump: press the dump key and load BUFFER/POSTDISPLAY/CURSOR into D_*.
t_dump() {
  zpty -w -n t $'\C-x\C-t'
  local end=$(( EPOCHREALTIME + 3 )) line
  while (( EPOCHREALTIME < end )); do
    t_drain
    if [[ -r $T_DIR/dump ]]; then
      line=$(<$T_DIR/dump)
      if (( ${line%%$'\x1f'*} > T_SEQ )); then
        local -a f=("${(@ps:\x1f:)line}")
        T_SEQ=${f[1]} D_BUFFER=${f[2]} D_POST=${f[3]} D_CURSOR=${f[4]}
        return 0
      fi
    fi
    zselect -t 2
  done
  t_fail "dump key got no answer (shell hung?)"
  return 1
}

# t_wait_post <expected> [seconds]: dump until POSTDISPLAY equals expected.
t_wait_post() {
  local want=$1 end=$(( EPOCHREALTIME + ${2:-3} ))
  while (( EPOCHREALTIME < end )); do
    t_dump || return 1
    [[ $D_POST == "$want" ]] && return 0
    t_settle 0.1
  done
  return 1
}

t_ok()   { (( ++T_PASS )); print -r -- "  ok    $T_NAME: $1"; }
t_fail() { (( ++T_FAIL )); print -r -- "  FAIL  $T_NAME: $1"; }

# t_eq <actual> <expected> <what>
t_eq() {
  if [[ $1 == "$2" ]]; then t_ok "$3"
  else t_fail "$3 (got ${(qqq)1}, want ${(qqq)2})"; fi
}

# t_case <name>: label the following assertions.
t_case() { T_NAME=$1; }
