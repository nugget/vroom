#!/usr/local/bin/tclsh8.5

package require http
package require vroom
package require tls

proc main {} {
	global vroomdb
	::vroom::init

	::http::register https 443 ::tls::socket

	set url [lindex $::argv 0]

	unset -nocomplain urllist
	if {[regexp {^http} $url]} {
		lappend urllist $url
	} else {
		pg_select $vroomdb "SELECT dropbox_url FROM vehicles WHERE dropbox_url IS NOT NULL" buf {
			lappend urllist $buf(dropbox_url)
		}
	}

	if {[info exists urllist]} {
		foreach u $urllist {
			if {[regexp {([^/]+$)} $u _ fn]} {
				set fn [file join $::env(TMP) [::vroom::urldecode $fn]]

				if {[file exists $fn]} {
					set size [file size $fn]
				} else {
					set size 0
				}

				set rh [::http::geturl $u -validate 1]
				upvar #0 $rh state

				if {[info exists state(totalsize)]} {
					set dbsize $state(totalsize)
				} else {
					set dbsize 0
				}
				::http::cleanup $rh

				if {$size != $dbsize} {
					puts "$u updated ($size != $dbsize)"
					set fh [open $fn "w"]
					puts "Downloading to $fn on channel $fh"
					set rh [::http::geturl $u -channel $fh]
					close $fh
					::http::cleanup $rh

					set fh [open "|[file join [file dirname [info script]] import_backup.tcl] \"$fn\"" "r"]
					while {1} {
						set line [gets $fh]
						puts $line
						if {[eof $fh]} {
							close $fh
							break
						}
					}
				}
			}
		}
	}
}

if !$tcl_interactive main
