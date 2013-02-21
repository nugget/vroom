#!/usr/local/bin/tclsh8.6

set ::debug 0

package require Pgtcl
package require Tclx
package require csv
package require vroom

proc main {} {
	global env

	::vroom::init

	set vehicle_id 1

	csv_out $vehicle_id

}

if !$tcl_interactive main
