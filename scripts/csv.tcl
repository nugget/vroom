#!/usr/local/bin/tclsh8.4

set ::debug 0

package require Pgtcl 
package require Tclx
package require csv

source functions.tcl

proc main {} {
	global env

	source vroom.cfg

	global dbh
	set dbh [pg_connect -connlist [array get ::DB]]

	set vehicle_id 1
	
	csv_out $vehicle_id

}

if !$tcl_interactive main
