#!/usr/bin/perl
#
#  Copyright 1999-2015 Opmantek Limited (www.opmantek.com)
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
#
# this helper upgrades table files where safe to do so
our $VERSION="8.6.3G";

use strict;
use Digest::MD5;								# good enough
use JSON::XS;
use Getopt::Std;
use File::Basename;
use File::Copy;

my $me = basename($0);
my $usage = "$me version $VERSION\n\nUsage: $me [-u] [-o|-p] [-n regex] <install dir> <config dir>
-u: do perform the upgrade instead of just reporting table file states
-o: report only upgradeable files
-p: report only problematic files
-n: NEVER upgrade the matching files

exit code: 0 or 255 (with -u)
without -u: 0 if no upgradables and no problem files were found,
2 upgradables and no problems,
1 no upgradables but problems,
3 both upgradables and problems.
\n\n";

my %opts;
die $usage if (!getopts("uopn:",\%opts)
							 or ($opts{p} && $opts{o})); # o and p are mutually exclusive
my ($newdir, $livedir) = @ARGV;
die $usage if (!-d $newdir or !-d $livedir or $livedir eq $newdir);

print "$me version $VERSION\n\n";

# load the embedded known signatures for the last few releases
my (%knownsigs, %newsig, $exitcode);
for (<DATA>)
{
	my ($file,@sigs) = split(/\s+/);
	$knownsigs{$file} = \@sigs;
	
	# complain if a known install file is missing completely - not terminal in general
	warn "warning: $newdir/$file is missing!\n" if (!-f "$newdir/$file");
	
	# and bail out if the purportedly known good new file doesn't match any of the known signatures
	$newsig{$file} = compute_signature("$newdir/$file");
	die "error: signature state ($newsig{$file}) for $newdir/$file not part of a known release!\n"
			if (!grep($_ eq $newsig{$file}, @sigs) and 
					(!$opts{n} or $file !~ qr{$opts{n}}));
}

# compute current signatures of the live stuff
my (%cursigs, @cando);
opendir(D, $livedir) or die "cannot open directory $livedir: $!\n";
for my $relfn (readdir(D))
{
	next if ($relfn !~ /^Table.+\.nmis$/);
	$cursigs{$relfn} = compute_signature("$livedir/$relfn");
}
closedir(D);

my $seecandidates = $opts{o};
my $wanttrouble = $opts{p};

# compare current files against known sigs; if known we can upgrade safely
for my $fn (sort keys %cursigs)
{
	my $sig = $cursigs{$fn};
	if ($opts{n} && $fn =~ qr{$opts{n}})
	{
		print "$fn is ignored because of option -n.\n";
	}
	elsif ($newsig{$fn} eq $sig)
	{
		print "$fn is uptodate.\n" if (!$seecandidates && !$wanttrouble);
	}
	elsif (!$knownsigs{$fn})
	{
		print "$fn is NOT UPGRADEABLE: locally created custom file.\n"
				if ($wanttrouble or !$seecandidates);
		$exitcode |= 1;
	}
	elsif (grep($_ eq $sig, @{$knownsigs{$fn}}))
	{
		print "$fn is upgradeable: not modified since installation.\n"
				if ($seecandidates or !$wanttrouble);
		push @cando, $fn;
		$exitcode |= 2;
	}
	else
	{
		print "$fn is NOT UPGRADEABLE: has been modified since installation.\n"
				if ($wanttrouble or !$seecandidates);
		$exitcode |= 1;
	}
}
# and handle totally new files
for my $newfn (sort keys %knownsigs)
{
	next if ($cursigs{$newfn});
	print "$newfn is upgradeable: new file.\n"
			if ($seecandidates or !$wanttrouble);
	push @cando, $newfn;
	$exitcode |= 2;
}

# perform the actual overwriting if desired
if ($opts{u} && @cando)
{
	print "Upgrading all upgradeable table files...\n";
	for my $todo (@cando)
	{
		my $res = File::Copy::cp("$newdir/$todo", "$livedir/$todo");
		die "copying of $todo to $livedir failed: $!\n" if (!$res);
	}
	print "Completed.\n";
}

exit ($opts{u}? 0 : $exitcode);


# computes a short signature for a Table-blah.nmis file,
# args: filename/path, optional sauce
# returns: signature or undef + warns on error
sub compute_signature
{
	my ($fn, $sauce) = @_;

	open(F, $fn) or die "cannot open file $fn: $!\n";
	my @lines = <F>;
	close F;

	my @filedata;
	for my $line (@lines)
	{
		next if ($line =~ /^\s*#/);						# comment lines
		$line =~ s/^\s*//; $line =~ s/\s*$//; # leading and trailing ws
		$line =~ s/\s+/ /g;					# collapse whitespace++ into single space
		$line =~ s/;\s*#.*$/;/;			# inline comments IFF at the end of a real statement
		next if ($line =~ /^\s*$/);

		push @filedata, $line;
	}
	$sauce ||= '';

	my $fullsig = Digest::MD5::md5_hex($sauce.join(" ",@filedata));
	return substr($fullsig,0,16);
}


# table file signatures for the last few releases are stored here
__DATA__
Table-Access.nmis 40fa00017376ca51
Table-BusinessServices.nmis 539adae4fed03ff2
Table-CircuitGroups.nmis 9e00f871315bd959 545ea59abb4473ad
Table-Config.nmis 2649df66dd11a020 3d825194acdc9597
Table-Contacts.nmis 50894801c64f3628 3039d313daf0209d
Table-Customers.nmis 6503aea40218241e
Table-Enterprise.nmis b954e3ca75233bce
Table-Escalations.nmis 9bcb104964b85dce c27dd6dff9035745 4e543898d2899c17 a5acd2e61e3c18c3
Table-Events.nmis 7826f94d352fecf8
Table-Links.nmis 485da1859e3cc036 3f6a43471d7e4cfe
Table-Locations.nmis 2d63c7fa7954e92a bd24e107f8158818 2e2e263c0c08d268
Table-Logs.nmis e70cc904a9d923e5
Table-Nodes.nmis 6cf38465b6dec232 32815befe46ad8e6 c536bfe56a073e41 703420fa55f06eb6 5b144d5f598eb815 013e95cef5802716 80d4c960b5570f70 a8c9b78dd1ad3910 ef34b637d02ba140 948b836801802bf9 7f1a618619af76f7
Table-Polling-Policy.nmis 7abb03f496c1943f
Table-Portal.nmis f092a05f0f7a2bbb
Table-PrivMap.nmis dccc46beb3506fa8
Table-ServiceStatus.nmis be3cd0dfc5c22efa
Table-Services.nmis d22d855ca6728a15 938d42a272b9053d fa25c56e2c3c4bcd 83c345f04466ba63
Table-Tables.nmis 92c2e1ee40856b53
Table-Toolset.nmis c3551c5e8117e00d
Table-Users.nmis e2d4055294ae58e2
Table-cmdbModels.nmis ea9eceefcf31c9ed
Table-ifTypes.nmis aed6f62c2aa89d8a
Tables.nmis fcd319f68f81fee2 91d30cf4bfaf25aa 33c5300087f34abb 07f47ede46bd4779 8d44d78f24b62c7c
