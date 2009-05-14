package require Tclx
package require Pgtcl


namespace eval ::vroom {

	proc init {} {
		global dbh
		set dbh [::vroom::dbconnect ::vroom::DB]
	}

	proc dbconnect {DB} {
		if {[catch {set db [pg_connect -connlist [array get ::$DB]]} result] == 1} {
			puts "Unable to connect to database: $result"

		} else {
			return $db
		}
	}

}

package provide vroom 1.0
