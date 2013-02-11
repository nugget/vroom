package require Tclx
package require Pgtcl


namespace eval ::vroom {

	proc init {} {
		set ::vroomdb [::vroom::dbconnect ::vroom::DB]
	}

	proc dbconnect {DB} {
		if {[catch {set db [pg_connect -connlist [array get ::$DB]]} result] == 1} {
			puts "Unable to connect to database: $result"

		} else {
			return $db
		}
	}

	proc vehicle_id_from_tag {tag} {
		pg_select $::vroomdb "SELECT vehicle_id FROM vehicles WHERE tag ilike [pg_quote $tag]" buf {
			return $buf(vehicle_id)
		}
		return
	}

	proc vehicle_array {id} {
		array set vehicle {}

		pg_select $::vroomdb "SELECT * FROM vehicles WHERE vehicle_id = $id" buf {
			array set vehicle [array get buf]
		}
		pg_select $::vroomdb "SELECT count(*) as fillups,
		                             min(odometer) as min_odometer, max(odometer) as max_odometer,
									 min(fillup_date) as min_date, max(fillup_date) as max_date
							  FROM fillups WHERE vehicle_id = $id" buf {
			array set vehicle [concat [array get vehicle] [array get buf]]
		}

		return [array get vehicle]
	}

}

package provide vroom 1.0
