#!/usr/bin/perl
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System ("NMIS").
#
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).
#  If not, see <http://www.gnu.org/licenses/>
#
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com
#
#  User group details:
#  http://support.opmantek.com/users/
#
# *****************************************************************************

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "/usr/local/rrdtool/lib/perl"; 

# Include for reference
#use lib "/usr/local/nmis8/lib";

# 
use strict;
use Fcntl qw(:DEFAULT :flock);
use func;
use NMIS;
use NMIS::Timing;
use RRDs 1.000.490; # from Tobias

my $t = NMIS::Timing->new();

print $t->elapTime(). " Begin\n";

# Variables for command line munging
my %arg = getArguements(@ARGV);

# Set debugging level.
my $debug = setDebug($arg{debug});
$debug = 1;

# load configuration table
my $C = loadConfTable(conf=>$arg{conf},debug=>$arg{debug});

if ( $ARGV[0] eq "" ) {
	print <<EO_TEXT;
ERROR: $0 will tune RRD database files with required changes.
usage: $0 run=(true|false) change=(true|false)
eg: $0 run=true (will run in test mode)
or: $0 run=true change=true (will run in change mode)

EO_TEXT
	exit 1;
}

if ( $arg{run} ne "true" ) {
	print "$0 you don't want me to run!\n";
	exit 1;
}
if ( $arg{run} eq "true" and $arg{change} ne "true" ) {
	print "$0 running in test mode, no changes will be made!\n";
}

#--data-source-type|-d ds-name:DST

print $t->markTime(). " Loading the Device List\n";
my $LNT = loadLocalNodeTable();
print "  done in ".$t->deltaTime() ."\n";

my $sum = initSummary();

my $qrdst = qr/ds\[(ipForwDatagrams|ipFragCreates|ipFragFails|ipFragOKs|ipInAddrErrors|ipInDelivers|ipInDiscards|ipInHdrErrors|ipInReceives|ipInUnknownProtos|ipOutDiscards|ipOutNoRoutes|ipOutRequests|ipReasmFails|ipReasmOKs|ipReasmReqds)\]\.type/;

# Work through each node looking for interfaces, etc to tune.
foreach my $node (sort keys %{$LNT}) {
	++$sum->{count}{node};
	
	# Is the node active and are we doing stats on it.
	if ( getbool($LNT->{$node}{active}) and getbool($LNT->{$node}{collect}) ) {
		++$sum->{count}{active};
		print $t->markTime(). " Processing $node\n";

		# Initiase the system object and load a node.
		my $S = Sys::->new; # get system object
		$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
		my $NI = $S->ndinfo;
		
		#Are there any interface RRDs?
		print "  ". $t->elapTime(). " Looking for mib2ip databases\n";
		my $rrd = $S->getDBName(graphtype => "mib2ip");
		print "    ". $t->elapTime(). " Found $rrd\n";

		# Get the RRD info on the Interface
		my $hash = RRDs::info($rrd);
		++$sum->{count}->{interface};
					
		# Recurse over the hash to see what you can find.
		foreach my $key (sort keys %$hash){

			# Is this an RRD DS (data source)
			if ( $key =~ /^ds/ ) {
				
#ds[ipForwDatagrams].type = "GAUGE"
#ds[ipFragCreates].type = "GAUGE"
#ds[ipFragFails].type = "GAUGE"
#ds[ipFragOKs].type = "GAUGE"
#ds[ipInAddrErrors].type = "GAUGE"
#ds[ipInDelivers].type = "GAUGE"
#ds[ipInDiscards].type = "GAUGE"
#ds[ipInHdrErrors].type = "GAUGE"
#ds[ipInReceives].type = "GAUGE"
#ds[ipInUnknownProtos].type = "GAUGE"
#ds[ipOutDiscards].type = "GAUGE"
#ds[ipOutNoRoutes].type = "GAUGE"
#ds[ipOutRequests].type = "GAUGE"
#ds[ipReasmFails].type = "GAUGE"
#ds[ipReasmOKs].type = "GAUGE"
#ds[ipReasmReqds].type = "GAUGE"

				# Is this the DS's we are intersted in?
				if ( $key =~ /$qrdst/ ) {
					my $dsname = $1;
					print "      ". $t->elapTime(). " Got $key, dsname=$dsname value = \"$hash->{$key}\"\n";
				
					# Is the value blank (which means in RRD U, unbounded).
					if ( $hash->{$key} eq "" or $hash->{$key} eq "GAUGE") {
						# We need to tune this RRD
						print "      ". $t->elapTime(). " RRD Tune Required for $dsname\n";
													
						# Got everything we need
						#print qq|RRDs::tune($rrd, "--maximum", "$dsname:$maxBytes")\n| if $debug;
						
						# Only make the change if change is set to true
						if ($arg{change} eq "true" ) {
							print "      ". $t->elapTime(). " Tuning RRD, updating data type for $dsname\n";
							#Execute the RRDs::tune API.
							#--data-source-type|-d ds-name:DST
							RRDs::tune($rrd, "--data-source-type", "$dsname:COUNTER");
							
							# Check for errors.
							my $ERROR = RRDs::error;
							if ($ERROR) {
								print STDERR "ERROR RRD Tune for $rrd has an error: $ERROR\n";
							}
							else {
								# All GOOD!
								print "      ". $t->elapTime(). " RRD Tune Successful\n";
								++$sum->{count}{'tune-mib2ip'};
							}
						}
						else {
							print "      ". $t->elapTime(). " RRD Will be Tuned, type change to counter for $dsname\n";
						}
					}
					# MAX is already set to something
					else {
						print "      ". $t->elapTime(). " RRD Tune NOT Required, $key=$hash->{$key}\n";
					}
				}
			}
		}

		print "  done in ".$t->deltaTime() ."\n";		
	}
	else {
		print $t->elapTime(). " Skipping node $node active=$LNT->{$node}{active} and collect=$LNT->{$node}{collect}\n";	
	}
}
	
print qq|
$sum->{count}{node} nodes processed, $sum->{count}{active} nodes active
$sum->{count}{interface}\tinterface RRDs
$sum->{count}{'tune-mib2ip'}\tinterface RRDs tuned
|;


sub initSummary {
	my $sum;

	$sum->{count}{node} = 0;
	$sum->{count}{'tune-mib2ip'} = 0;

	return $sum;
}

