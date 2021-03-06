#!/usr/bin/perl
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System (“NMIS”).
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
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use CGI qw(:standard *table *Tr *td *form *Select *div);

use NMIS;
use func;
use Auth;

my $q = new CGI; # This processes all parameters passed via GET and POST
my $Q = $q->Vars; # values in hash

my $C = loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug});
die "failed to load configuration!\n" if (!$C or ref($C) ne "HASH" or !keys %$C);

#======================================================================

# nodeconf should not refresh, ever.
$Q->{refresh} = undef;

my $widget = getbool($Q->{widget},"invert") ? 'false' : 'true';
$Q->{expand} = "true" if ($widget eq "true");

### unless told otherwise, and this is not JQuery call, widget is false!
if ( not defined $Q->{widget} and not defined $ENV{HTTP_X_REQUESTED_WITH} ) {
	$widget = "false";
}

if ( not defined $ENV{HTTP_X_REQUESTED_WITH} ) {
	$widget = "false";
}

my $wantwidget = ($widget eq "true");

my $formid = 'nodeconf';

# Before going any further, check to see if we must handle
# an authentication login or logout request
# if arguments present, then called from command line
if ( @ARGV ) { $C->{auth_require} = 0; } # bypass auth

# variables used for the security mods
my $headeropts = {type => 'text/html', expires => 'now'};
my $AU = Auth->new(conf => $C);  # Auth::new will reap init values from NMIS::config

if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}

# $AU->CheckAccess, will send header and display message denying access if fails.
$AU->CheckAccess("table_nodeconf_view","header");

# check for remote request
if ($Q->{server} ne "") { exit if requestServer(headeropts=>$headeropts); }

#======================================================================

# select function
if ($Q->{act} eq 'config_nodeconf_view') {
	displayNodemenu();
}
elsif ($Q->{act} eq 'config_nodeconf_update') {
	if (updateNodeConf()){ displayNodemenu(); }
}
else {
	displayNodemenu();
	#notfound();
}

sub notfound {
	print header(-status=>400, %$headeropts);
	print "nodeConf: ERROR, act=$Q->{act}, node=$Q->{node}, intf=$Q->{intf}\n";
	print "Request not found\n";
}

exit;

#==================================================================
#
# display
#
sub displayNodemenu
{
	my $NT = loadLocalNodeTable();

	print header($headeropts);
	if (!$wantwidget)
	{
			pageStart(title => $Q->{node}." Node Configuration");
	}
	my $menuformid = "${formid}_menu";

	print start_table,start_Tr,start_td;

	# start of form
	my $thisurl = url(-absolute => 1)."?";
  # the get() code doesn't work without a query param, nor does it work with all params present
	# conversely the non-widget mode needs post inputs as query params are ignored
	print start_form(-id => $menuformid, -href => $thisurl);
	print hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => "config_nodeconf_view")
			. hidden(-override => 1, -name => "widget", -value => $widget);

	print start_table() ; # first table level

	# row with Node selection
	my @nodes = ("",grep { $AU->InGroup($NT->{$_}{group})
														 and getbool($NT->{$_}{active}) } sort keys %{$NT});
	print start_Tr;
	print td({class=>"header"}, a({class=>"wht", href=>$C->{'nmis'}."?conf=".$Q->{conf}}, "NMIS $NMIS::VERSION"))
			if (!getbool($Q->{widget}));

	print td({class=>"header",width=>'25%'},
			"Select node<br>".
				popup_menu(-name=>"node", -override=>'1',
					-values=>\@nodes,
					-default=>"$Q->{node}",
					-title=>"node to modify",
					-onChange=> ($wantwidget? "get('$menuformid');" : "submit()" )));

	print td({class=>"header",align=>'center'},'Optional Node and Interface Configuration');
	print end_Tr;
	print end_table();

	print end_form;

	# background values

	displayNodeConf(node=>$Q->{node}) if $Q->{node} ne "";

	print end_td,end_Tr,end_table;

	pageEnd if (!$wantwidget);

}


# show the config form for a single given node
sub displayNodeConf
{
	my %args = @_;
	my $node = $args{node};


	my $thisurl = url(-absolute => 1)."?";
	print start_form(-id => $formid, -href => $thisurl);
	print hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => "config_nodeconf_update")
			. hidden(-override => 1, -name => "node", -value => $node)
			. hidden(-override => 1, -name => "widget", -value => $widget)
			. hidden(-id => "doupdate", -override => 1, -name => "update", -value => '');

	print start_table({width=>'100%'}) ; # first table level

	my $S = Sys::->new;

	if (!($S->init(name=>$node,snmp=>'false'))) {
		print Tr,td({class=>'error',colspan=>'3'},"Error on getting info of node $node");
		return;
	}
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	# get any existing nodeconf overrides for this node
	my $nodename = $NI->{system}->{name};
	my ($errmsg, $override) = get_nodeconf(node => $nodename)
			if (has_nodeconf(node => $nodename));
	logMsg("ERROR $errmsg") if $errmsg;
	$override ||= {};

	print Tr(td({class=>"header",width=>'20%'}),td({class=>"header",width=>'20%'}),
			td({class=>"header",width=>'20%'},'<b>Original value</b>'),
			eval {
				if ($AU->CheckAccess("Table_nodeConf_rw","check")) {
					return td({class=>"header"},'<b>Replaced by</b><br>(active after update of node)') ;
				} else {
					return td({class=>"header"},'<b>Replaced by') ;
				}
			});

	print Tr(td({class=>'header'},'<b>Node</b>'),td({class=>'header'},"&nbsp;"),
			td({class=>'header'},"&nbsp;"),td({-align=>'center'},
				eval {
					if ($AU->CheckAccess("Table_nodeConf_rw","check"))
					{
							# in case of store config non-widgetted we only need to
							# submit the form
							# (and ensure the doupdate hidden field is off, if we're
							# coming back to this page!)
							return button(-name=>'submitbutton',
														onclick => ($wantwidget? "get('$formid');"
																				: '$("#doupdate").val(""); submit()'),
														-value=>'Store'),

							# but to emulate the update=true get() call, we need to set
							# the appropriate hidden field before submitting and convince
							# get not to mess with the url, or we'll have duplicate but
							# different update fields...
							button(-name=>'updatebutton',
										 onclick => '$("#doupdate").val("true"); '
										 .($wantwidget? "get('$formid');" : 'submit();'),
										 -value=>'Store and Update Node');
					} else { return ""; }
				}));

	my $NCT_sysContact = $NI->{nodeconf}{sysContact} || $NI->{system}{sysContact};
	print Tr,td({class=>"header"}),td({class=>"header"},"Contact"),
			td({class=>'header3'}, $NCT_sysContact),
	td({class=>"Plain"},textfield(-name=>"contact",-override=>1,
																-style => 'width: 95%',
																-value => $override->{sysContact}||''));

	my $NCT_sysLocation = $NI->{nodeconf}{sysLocation} || $NI->{system}{sysLocation};
	print Tr,td({class=>"header"}),td({class=>"header"},"Location"),
			td({class=>'header3'}, $NCT_sysLocation),
	td({class=>"Plain"},textfield(-name=>"location",-override=>1,
																-style => 'width: 95%',
																-value => $override->{sysLocation}||''));

	if ( !getbool($NI->{system}{collect}) ) {
		print Tr(td({class=>"header"}),td({class=>"header"},"Collect"),
				td({class=>'header'},'disabled'));
	}

	my $NCT_nodetype = $NI->{nodeconf}->{nodeType} || $NI->{system}->{nodeType};
	print Tr,td({class=>"header"}),td({class=>"header"},"Node Type"),
	td({class=>'header3'}, $NCT_nodetype),
	td({class=>"Plain"},
		 popup_menu(-name=>"nodetype", -override=>'1',
								-values=>["", split(/\s*,\s*/, $C->{nodetype_list})],
								-labels => { "" => "<from model>", map { $_ => $_ } (split(/\s*,\s*/, $C->{nodetype_list})) },
								-default=> "",
								-style => 'width: 95%',
								-title=>"new Node Type" ));

	# label for the 'desired state' column
	my %rglabels = ('unchanged' => 'unchanged', 'false' => 'false', 'true' => 'true');

	if ( getbool($NI->{system}{collect}) )
	{
		print Tr,td({class=>'header'},'<b>Interfaces</b>');
		foreach my $intf (sorthash( $IF, ['ifDescr'], 'fwd'))
		{
			next if (ref($IF->{$intf}) ne "HASH"
							 or !defined($IF->{$intf}->{ifDescr})
							 or $IF->{$intf}->{ifDescr} eq ''); # exists but empty text should no longer happen

			my $intfstatus = $IF->{$intf};
			my ($description, $displayname, $speed, $speedIn, $speedOut,
					$collect, $event, $threshold,$size, $setlimits);

			my $ifDescr = $intfstatus->{ifDescr};
			my $thisintfover = ref($override->{$ifDescr}) eq "HASH"? $override->{$ifDescr} : {};

			# check if interfaces are changed - fixme what does that mean?
			if ($thisintfover->{ifDescr}
					and $ifDescr ne $thisintfover->{ifDescr})
			{
				# fixme undef better?
				$collect = $event = $threshold = $description = $displayname = $speed = undef;
			}
			else
			{
				if ( !$thisintfover->{ifSpeedIn} and $thisintfover->{ifSpeed} )
				{
					$thisintfover->{ifSpeedIn} = $thisintfover->{ifSpeed};
				}
				if (!$thisintfover->{ifSpeedOut} and $thisintfover->{ifSpeed})
				{
					$thisintfover->{ifSpeedOut} = $thisintfover->{ifSpeed};
				}

				$description = $thisintfover->{Description};
				$displayname = $thisintfover->{display_name};
				$speed = $thisintfover->{ifSpeed};
				$speedIn = $thisintfover->{ifSpeedIn};
				$speedOut = $thisintfover->{ifSpeedOut};
				$collect = $thisintfover->{collect};
				$event = $thisintfover->{event};
				$threshold = $thisintfover->{threshold};
				$setlimits = $thisintfover->{setlimits};
			}
			$setlimits = "normal" if (!$setlimits or $setlimits !~ /^(normal|strict|off)$/);

			my $NCT_Description = exists $intfstatus->{nc_Description} ?
					$intfstatus->{nc_Description} : $intfstatus->{Description};

			print Tr,
			td({class=>'header'}, $intfstatus->{ifDescr}),
			td({class=>'header'},"Description"),td({class=>'header3'},$NCT_Description),
			td({class=>"Plain"},textfield(-name=>"descr_${intf}",
																		-style => 'width: 95%',
																		-override=>1,
																		-value=>$description));

			print Tr, td({class=>'header'}),
			td({class=>'header'},"Display Name"),td({class=>'header3'}, $displayname),
			td({class=>"Plain"},textfield(-name=>"displayname_${intf}",
																		-style => 'width: 95%',
																		-override=>1,
																		-value => $displayname));

			my $NCT_ifSpeed = $intfstatus->{nc_ifSpeed} || $intfstatus->{ifSpeed};
			#print Tr,td({class=>'header'}),
			#	td({class=>'header'},"Speed"),td({class=>'header3'},$NCT_ifSpeed),
			#	td({class=>"Plain"},textfield(-name=>"speed_${intf}",-override=>1,-value=>$speed));

			my $NCT_ifSpeedIn = $intfstatus->{nc_ifSpeedIn} || $intfstatus->{ifSpeedIn};
			$NCT_ifSpeedIn = $NCT_ifSpeed if not $NCT_ifSpeedIn;
			print Tr,td({class=>'header'}),
			td({class=>'header'},"Speed In"),td({class=>'header3'},$NCT_ifSpeedIn),
			td({class=>"Plain"},textfield(-name=>"speedIn_${intf}",-override=>1,-value=>$speedIn));

			my $NCT_ifSpeedOut = $intfstatus->{nc_ifSpeedOut} || $intfstatus->{ifSpeedOut};
			$NCT_ifSpeedOut = $NCT_ifSpeed if not $NCT_ifSpeedOut;
			print Tr,td({class=>'header'}),
			td({class=>'header'},"Speed Out"),td({class=>'header3'},$NCT_ifSpeedOut),
			td({class=>"Plain"},textfield(-name=>"speedOut_${intf}",-override=>1,-value=>$speedOut));


			print Tr,td({class=>'header'}),
			td({class=>'header'},"Speed Limit"), td({class=>'header3'}, $setlimits),
			td({class=>"Plain"}, radio_group(-name=>"setlimits_${intf}",
																			 -values=>['normal',
																								 'strict',
																								 'off'],
																			 -default=>$setlimits, ));

			my $NCT_collect = $intfstatus->{nc_collect} || $intfstatus->{collect};
			print Tr,td({class=>'header'}),
			td({class=>'header'},"Collect"),td({class=>'header3'},$NCT_collect),
			td({class=>"Plain"},radio_group(-name=>"collect_${intf}",
																			-values=>['unchanged',
																								'true',
																								'false'],
																			-default=>$collect,-labels=>\%rglabels));



			if ( getbool($collect) or (!getbool($collect,"invert")
																 and getbool($NCT_collect)) )
			{
				my $NCT_event = $intfstatus->{nc_event} || $intfstatus->{event};
				print Tr,td({class=>'header'}),
				td({class=>'header'},"Events"),td({class=>'header3'},$NCT_event),
				td({class=>"Plain"},radio_group(-name=>"event_${intf}",
																				-values=>['unchanged',
																									'true',
																									'false'],
																				-default=>$event,-labels=>\%rglabels));
			} else {
				print hidden(-name=>"event_${intf}", -default=>'unchanged',-override=>'1');
			}

			if (getbool($NI->{system}{threshold})
					and (getbool($collect) or (!getbool($collect,"invert")
																		 and getbool($NCT_collect)) )) {
				my $NCT_threshold = $intfstatus->{nc_threshold} || $intfstatus->{threshold};
				print Tr,td({class=>'header'}),
				td({class=>'header'},"Thresholds"),td({class=>'header3'},$NCT_threshold),
				td({class=>"Plain"},
					 radio_group(-name=>"threshold_${intf}",
											 -values=>['unchanged',
																 'true',
																 'false'],
											 -default=>$threshold,-labels=>\%rglabels));
			} else {
				print hidden(-name=>"threshold_${intf}", -default=>'unchanged',-override=>'1');
			}


		}
	}
	else
	{
		print Tr(td({class=>'info',colspan=>'4'},"No collection of Interfaces"));
	}
	print end_table();
	print end_form;
}

# combine the form data submitted by the user with the current nodeconf (if any)
# and save the result.
sub updateNodeConf {
	my %args = @_;

	my $node = $Q->{node};

	my $S = Sys::->new;

	if (!($S->init(name=>$node,snmp=>'false'))) {
		##		print Tr,td({class=>'error',colspan=>'4'},"Error on getting info of node $node");
		return;
	}
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	# get the current nodeconf overrides
	my $nodename = $NI->{system}->{name};
	my ($errmsg, $override) = get_nodeconf(node => $nodename)
			if (has_nodeconf(node => $nodename));
	logMsg("ERROR $errmsg") if $errmsg;
	$override ||= {};

	if  ($Q->{contact} eq "") {
		delete $override->{sysContact};
	} else {
		$override->{sysContact} = $Q->{contact};
	}
	if  ($Q->{location} eq "") {
		delete $override->{sysLocation};
	} else {
		$override->{sysLocation} = $Q->{location};
	}
	if ($Q->{nodetype} eq "") {
		delete $override->{nodeType};
	} else {
		$override->{nodeType} = $Q->{nodetype};
	}

	# $intf is the ifIndex
	foreach my $intf (keys %{$IF})
	{
		my $ifDescr = $IF->{$intf}{ifDescr};

		my $thisintfover = $override->{$ifDescr} ||= {};

		$thisintfover->{ifDescr} = $IF->{$intf}{ifDescr}; # for linking the if state to the nodeconf

		my %tranferrables = ("descr_$intf" => "Description",
												 "displayname_$intf" => "display_name",
												 "speed_$intf" => "ifSpeed",
												 "speedIn_$intf" => "ifSpeedIn",
												 "speedOut_$intf" => "ifSpeedOut",
												 "collect_$intf" => "collect",
												 "event_$intf" => "event",
												 "threshold_$intf" => "threshold",
												 "setlimits_$intf" => "setlimits",
				);

		while (my ($source, $target) = each %tranferrables)
		{
			# event, collect and threshold are special:
			# value "unchanged" means remove the override
			if (($source =~ /^(collect|event|threshold)_/ and $Q->{$source} eq "unchanged")
					# others: no value given means remove
					or !defined($Q->{$source})
					or $Q->{$source} eq "")
			{
				delete $thisintfover->{$target};
			}
			else
			{
				# speed in and out are a bit more equal than others, too:
				# if present they must be positive integers
				if ($source =~ /^speed(In|Out)?_/)
				{
					my $theval = $Q->{$source};

					if (int($theval) ne $theval or $theval <= 0)
					{
						print header(-status => 400, %$headeropts),
						"Validation error for $source: '$theval' is not a positive integer!";
						return undef;
					}
				}
				$thisintfover->{$target} = $Q->{$source};
			}
		}

		# don't keep this override if there are no entries except the automatic 'ifDescr'
		delete $override->{$ifDescr} if (scalar keys %{$thisintfover} == 1);
	}

  # this makes the resulting subsequent node menu into a blank one,
	# longterm fixme: instead this should report an 'update done' and show the same node again
	delete $Q->{node};

	# right; anything left to save?
	# if not, tell update_nodeconf to delete the node's data (data arg undef)
	undef $override if (!keys %$override);
	$errmsg = update_nodeconf(node => $node, data => $override);
	logMsg("ERROR $errmsg") if ($errmsg);

	# signal from button
	if ( getbool($Q->{update}) ) {
		doNodeUpdate(node=>$node);
		return 0;
	}
	return 1;
}

sub doNodeUpdate {
	my %args = @_;
	my $node = $args{node};

	# note that this will force nmis.pl to skip the pingtest as we are a non-root user !!
	# for now - just pipe the output of a debug run, so the user can see what is going on !

	# now run the update and display
	print header($headeropts);

	if (!$wantwidget)
	{
			pageStart(title => "$node update");
	}

	my $thisurl = url(-absolute => 1)."?";
	print start_form(-id=>$formid, -href => $thisurl);
	print hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => "config_nodeconf_view")
			. hidden(-override => 1, -name => "widget", -value => $widget);

	print table(Tr(td({class=>'header'},"Completed web user initiated update of $node"),
				td(button(-name=>'button',
									-onclick => ($wantwidget? "javascript:get('$formid');" : "submit()"),
									-value=>'Ok'))));

	print "<pre>\n";
	print escapeHTML("Running update on node $node - Please wait...\n\n\n");

	my $pid = open(PIPE, "-|");
	if (!defined $pid)
	{
		print "Error: cannot fork: $!\n";
	}
	elsif (!$pid)
	{
		# child
		open(STDERR, ">&STDOUT"); # stderr to go to stdout, too.
		exec("$C->{'<nmis_bin>'}/nmis.pl","type=update", "node=$node", "info=true", "force=true");
		die "Failed to exec: $!\n";
	}
	select((select(PIPE), $| = 1)[0]);			# unbuffer pipe
	select((select(STDOUT), $| = 1)[0]);		# unbuffer stdout

	while ( <PIPE> ) {
		print escapeHTML($_);
	}
	close(PIPE);
	print "\n</pre><pre>\n";
	print escapeHTML("Running collect on node $node - Please wait.....\n\n\n");

	$pid = open(PIPE, "-|");
	if (!defined $pid)
	{
		print "Error: cannot fork: $!\n";
	}
	elsif (!$pid)
	{
		# child
		open(STDERR, ">&STDOUT"); # stderr to go to stdout, too.
		exec("$C->{'<nmis_bin>'}/nmis.pl","type=collect", "node=$node", "info=true");
		die "Failed to exec: $!\n";
	}
	select((select(PIPE), $| = 1)[0]);			# unbuffer pipe

	while ( <PIPE> ) {
		print escapeHTML($_);
	}
	close(PIPE);
	print "\n</pre>\n";

	print table(Tr(td({class=>'header'},"Completed web user initiated update of $node"),
				td(button(-name=>'button',
									-onclick => ($wantwidget? "get('$formid');" : "submit()"),
									-value=>'Ok'))));
	print end_form;
}
