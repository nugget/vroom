#!/usr/local/bin/tclsh8.4

set ::debug 0

package require Pgtcl 
package require Tclx
package require csv
package require vroom

proc main {} {
	global env

	global dbh
	set dbh [pg_connect -connlist [array get ::DB]]

	set vehicle_id 1
	
	csv_out $vehicle_id

}

if !$tcl_interactive main
