#!/usr/local/bin/tclsh8.6

package require vroom
package require base64

# curl -s -o - http://dl.dropbox.com/u/8880838/Nugget%27s%20iPhone/Current%20Backup/2007%20GT3%20RS.roadtrip | ./import_backup.tcl

proc logmsg {buf} {
	puts $buf
}

proc debug {buf} {
	# puts $buf
}

proc main {} {
	global vroomdb

	set csvbuf ""

	::vroom::init

    set infile [lindex $::argv 0]

	if {$infile != ""} {
		if {![file exists $infile]} {
			puts "$infile does not exist"
			exit -1
		}
		set fh [open $infile "r"]
	} else {
		set fh "stdin"
	}

	while {1} {
		set line [gets $fh]

		if {[regexp {Data:(.*)} $line _ bbuf]} {
			append csvbuf [::base64::decode $bbuf]
		}

		if {[eof $fh]} {
			break
		}
	}

	# $csvbuf now contains the undecoded backup csv file
	# puts $csvbuf

	foreach line [split $csvbuf "\n"] {
		unset -nocomplain buf
		array set buf [::vroom::parse_backup_line $line]

		if {[info exists buf(rowtype)]} {
			if {[regexp {Records$} $buf(rowtype)]} {
				::vroom::import_row_recordcounts [array get buf]
			} elseif {[info procs ::vroom::import_row_$buf(rowtype)] != ""} {
				::vroom::import_row_$buf(rowtype) [array get buf]
			} else {
				puts $line
				logmsg "I don't know how to import a $buf(rowtype) row"
			}
		} elseif {$line != ""} {
			puts "> $line"
		}
	}

	if {[array exists ::expected_count]} {
		foreach e [array names ::expected_count] {
			if {![info exists ::count($e)]} {
				set ::count($e) 0
			}
			logmsg "[format "%20s" $e] expected [format "%4d" $::count($e)] saw [format "%4d" $::expected_count($e)]"
		}
	}

}

if !$tcl_interactive main
