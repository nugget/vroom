## VROOM - Road Trip backup file toolkit

This is Tcl and PostgreSQL code I use to process backup files from the Road
Trip iPhone app by Darren Stone.

http://darrensoft.ca/roadtrip/

The application syncs its data to Dropbox, and this code will scrape the
Dropbox-stored data files and sync them with a PostgreSQL database.
Includes Tcl packages for manipulating and processing the data, which 
I use on my website to publish car statistics.

http://macnugget.org/cars/

This stuff was written just to scratch my own itch, but if you're willing
to embrace Tcl and PostgreSQL it should be fairly reusable for other purposes.
