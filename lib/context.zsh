# What the model is told about the situation, as comment lines that sit
# above the command being typed. M2: operating system and directory. M3 adds
# git, history, file names and redaction.

typeset -g _ZGA_OS=""

_zga_os() {
  if [[ -z $_ZGA_OS ]]; then
    local line
    if [[ -r /etc/os-release ]]; then
      for line in "${(@f)$(</etc/os-release)}"; do
        [[ $line == PRETTY_NAME=* ]] && { _ZGA_OS=${${line#PRETTY_NAME=}//\"/}; break; }
      done
    fi
    : ${_ZGA_OS:=$(uname -s)}
  fi
  REPLY=$_ZGA_OS
}

# _zga_context  → REPLY = context lines, each starting with "# "
_zga_context() {
  local -a lines
  _zga_os
  lines+=("# zsh on $REPLY")
  lines+=("# cwd: ${(D)PWD}")
  REPLY=${(F)lines}
}
