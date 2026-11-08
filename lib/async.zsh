# Requests. M1: synchronous, so the display layer can be built and tested
# with an instant fake provider. M2 replaces this with background workers.

_zga_cancel() { :; }

_zga_request() {
  local buffer=$BUFFER
  _zga_complete "$buffer" && _zga_apply "$buffer" "$REPLY"
}
