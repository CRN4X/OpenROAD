# Query a resistor already stored by test setup or by OpenRCX extraction.
proc get_3dic_rseg { net_name } {
  foreach net [[[ord::get_db] getChip] getChipNets] {
    if { [$net getName] eq $net_name } {
      set segments [psm::get_3d_chip_rsegs $net]
      if { [llength $segments] != 1 } {
        error "Expected one resistor on $net_name"
      }
      return [lindex $segments 0]
    }
  }
  error "Missing assembly net $net_name"
}
