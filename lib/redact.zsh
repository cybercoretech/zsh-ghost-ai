# Ignore patterns and secret redaction. M1: the ignore pattern only (M3 adds
# redaction).

# _zga_ignored <line>: true when the line must never be sent or completed.
_zga_ignored() {
  emulate -L zsh
  setopt extendedglob
  _zga_get ignore
  [[ -n $REPLY && $1 == (#i)${~REPLY} ]]
}
