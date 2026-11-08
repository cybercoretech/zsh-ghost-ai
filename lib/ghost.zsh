# Ghost text display, keys and ZLE hooks. Filled in by M1.

_zga_init() {
  typeset -gi _ZGA_ENABLED=1
  _zga_is enabled || _ZGA_ENABLED=0
}
