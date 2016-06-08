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
# this helper upgrades model files where safe to do so
#
our $VERSION="8.5.12G";
use strict;
use Digest::MD5;								# good enough
use JSON::XS;
use Getopt::Std;
use File::Basename;
use File::Copy;

my $me = basename($0);
my $usage = "$me version $VERSION\n\nUsage: $me [-u] [-o|-p] [-n regex] <new model dir> <live model dir>
-u: do perform the upgrade instead of just reporting model file states
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
	# complain if a known models-install file is missing completely
	die "error: $newdir/$file is missing!\n" if (!-f "$newdir/$file");
	# also complain if the purportedly known good new file doesn't match any of the known signatures
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
	next if ($relfn !~ /\.nmis$/);
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
	print "Upgrading all upgradeable model files...\n";
	for my $todo (@cando)
	{
		my $res = File::Copy::cp("$newdir/$todo", "$livedir/$todo");
		die "copying of $todo to $livedir failed: $!\n" if (!$res);
	}
	print "Completed.\n";
}

exit ($opts{u}? 0 : $exitcode);


# computes a short signature for a .nmis file (ie. a dumped perl hash)
# args: filename/path, optional sauce
# returns: signature or dies on error
sub compute_signature
{
	my ($fn, $sauce) = @_;

	my %structure = eval { do $fn; };
	die "cannot parse file $fn: $@\n" if ($@ or !keys %structure);
	$sauce ||= '';

	my $fullsig = Digest::MD5::md5_hex($sauce.JSON::XS->new->canonical(1)->pretty(0)->encode(\%structure));
	return substr($fullsig,0,16);
}

# model file, signatures for the last few releases are stored here
__DATA__
Common-Cisco-asset.nmis 675e126af3677a52
Common-Cisco-neighbor.nmis 680e05322f63c24f
Common-Cisco-status.nmis c08e756f6ccd2fa8
Common-Juniper-jnxOperations.nmis 265a1c2ef344630f
Common-calls.nmis 77ca79216fd1aefa
Common-cbqos-in.nmis a0bbc467ffd18646 6c8df3ec0d0c0858
Common-cbqos-out.nmis 48665448110af552 1210e379c4b6a92d
Common-database.nmis a41276db67e9be61 b3d083221e94f22c 8b309566ec783d52 6514b77ecc0dd2c8 5bacf781a1495ba5 a934b015029bbe63 92a7f5ebc9af25aa 5f1f1a8792f0498d b70fbcbf9e210596 1b1d1620e6b66683
Common-event.nmis 3c17ac2753efd729
Common-heading.nmis 8e453ea283e3fd7a dc1e5ee59839f42a 6b6ffeeb92a8996f fc120bc0906f3b70 7e458f0172e120ea 0f6d824494640deb c1c8d886c4c7f7f1 4be5135841352538 a2c592a8fe826493 f652ed992cf8d4a2 087587a01227a79e
Common-routing.nmis 329d8897cefd7011
Common-stats.nmis 051ad0c9af4e10ba efbcfd8340518376 14dd2080e99197df 67a57e6c34135bc1
Common-summary.nmis 10d878a1904ebb31
Common-threshold.nmis 42a0e451c9206d1a 2085498abd902193 5f00df141ba53a85 709aa976ce2acd85
Graph-APCBattTemp.nmis de5f3206f3eeae68
Graph-APCCapacity.nmis a243dadb1d7875dd
Graph-APCCurrent.nmis 907121ea0bcf9be0
Graph-APCLoad.nmis 8ae6b39af42b084d
Graph-APCVoltage.nmis a910505de5e1886a
Graph-EltekACVoltage.nmis 37ef3620ea0c98bd
Graph-EltekBattTemp.nmis a9e9e00d9056d75f
Graph-EltekBreakerAlarms.nmis 732541e9e27f8a7e
Graph-EltekCapacity.nmis bda74df9965cd800
Graph-EltekCurrents.nmis cbca36c54e293781
Graph-EltekRectifierState.nmis 49384cd2ca2bf907
Graph-EltekTempAlarms.nmis 3aebc4fa0e6abe2d
Graph-EltekVoltageAlarms.nmis e9e61c6ec0eb5f5a
Graph-SONETErrors.nmis ee76114fdc1dd1ed 06273622fb3105aa
Graph-SignalErrors.nmis ffb4ac5b8675593b
Graph-SignalLevel.nmis f15bb029f41b27bd
Graph-a3bandwidth.nmis e4fe343b326bd85f
Graph-a3errors.nmis 6ded8760642b828f
Graph-a3traffic.nmis 4cad6c4885476f48
Graph-abits.nmis 34802a5b374e8180 4591e25ddd6dbfe5
Graph-acpu.nmis 38f5bdc3d1da6e4e
Graph-apSession.nmis 8b2d27b2dca64e19
Graph-apSys.nmis 3fbd5fe6f9e06042
Graph-autil.nmis 69d13d7dda76a49f a491f25e6e709123 4eb8325c8c359172
Graph-bgpPeer.nmis 1011685b62b52bcf b9c1298f7adc649a
Graph-bgpPeerStats.nmis c8832752bd860517 a38db8b5ce41f4c4
Graph-bits.nmis 0d948fe34ab19cf8
Graph-buffer.nmis 8a03625101fad4d6 5ab5b989c00298f3
Graph-calls.nmis a9a927145cf81af5
Graph-cbqos-in.nmis f6d6fcef870cfa3a
Graph-cbqos-out.nmis f6d6fcef870cfa3a
Graph-ccpu.nmis 39e48f46acf0f70e
Graph-checkpoint.nmis 25bc6cb18300d4d2
Graph-cps6000Alarm.nmis d9a5b25d5fbd76e3
Graph-cps6000Cct.nmis e2e8d692f38d3704
Graph-cps6000Grp.nmis 3dc5f29ccfed5acf
Graph-cpu-cpm.nmis 25f42d60d8169aed
Graph-cpu.nmis 1fa5ee0d2b6908ba c039ae94ec692c0d
Graph-cpuUtil.nmis 2d5466478641d021
Graph-csscontent.nmis c925be8d6b20f493
Graph-cssgroup.nmis 01f18cb0dc2a5a37
Graph-degree.nmis a6edd263f6c825a4
Graph-diskio-rw.nmis 843ad186a028b563
Graph-diskio-rwbytes.nmis 3e7e6d6df40e5627
Graph-ds3Errors.nmis 52d536766a509518 08d99a03e4cbf54e
Graph-ees.nmis 6828ec38b6a0efca
Graph-env-temp.nmis 52fb1470af0fbbba d681f0aa53e1b06c 9f318ebfcc66ef2f
Graph-errpkts.nmis 85f62f6272c16295
Graph-errpkts_hc.nmis 5fe561e36c8d121d
Graph-fan-status.nmis e7848a690e015311
Graph-fkGponOnuStatus.nmis 67782665ea319caf
Graph-frag.nmis 2bfbcd8cb8e4ed34
Graph-gsm_status_2g.nmis 8b0fef6603cf7b49
Graph-gsm_status_3g.nmis 33b988d5abbe6988
Graph-health-ping.nmis 6b96feaf72a8ab85 f9cec5794bb6a4da
Graph-health.nmis 732400abda37f46d
Graph-hrbufmem.nmis 18ecbd05ab9219ee
Graph-hrcachemem.nmis 849c721e0976297f
Graph-hrcpu.nmis d133563fac3acb74
Graph-hrdisk.nmis 2b724d234a97ef89
Graph-hrmem.nmis f822616bbe06d224 4961460c6573a93d
Graph-hrproc.nmis b1884cd477fe50e7
Graph-hrsmpcpu.nmis c9eac2d103505434 46474bf6303958b7
Graph-hrswapmem.nmis 8a00f4dc855edfa2
Graph-hrsystem.nmis b7224fe39a15aa46
Graph-hrusers.nmis 72c134af89e79f2a
Graph-hrvmem.nmis fc4ee146987e466d 12f351d0771b331c
Graph-hrwincpu.nmis 3c4f3a6953a606d8
Graph-hrwincpuint.nmis aaf5cec916a94425
Graph-hrwinmem.nmis 35718efb287ccda3
Graph-hrwinpps.nmis 98b8088c81121f3c
Graph-hrwinproc.nmis 94d60449adf196ba
Graph-hrwinusers.nmis cd91c3cb9ca3be5f
Graph-humsensor.nmis dc17b1f2c0d1a707
Graph-ip.nmis c6baba48b23bda7f 74a54c12bbb5bac0 89b1939ad69db272
Graph-jnxCPU.nmis ff556b1c9129bbb4
Graph-jnxMem.nmis ab1a213c7c3e95bc
Graph-jnxTemp.nmis 9a63dfa867000f76
Graph-kpi.nmis 35a06b89a805d58a
Graph-laload.nmis 497c9f570b333d58 52bd4c924a95ae13
Graph-maxbits.nmis 3487a645887135af
Graph-mem-cluster.nmis eec46df71e79d7db
Graph-mem-dram.nmis 9a53757525316170
Graph-mem-io.nmis be89eb2045aae54e 08471f91a7d0a104
Graph-mem-mbuf.nmis 1ee5e00821c97fd9
Graph-mem-proc.nmis 4cbcb846d17cd08c 86f67cd24ab3662f
Graph-mem-router.nmis 397cb10e6c3a335e adaff7cb9a7d1fd3
Graph-mem-switch.nmis 7fd234e1af82a94b
Graph-memUsageUtil.nmis 2e078d80af088bd4
Graph-memUtil.nmis 47d14ac67152d49a
Graph-metrics.nmis f99bf0c709884dec 2cf6e680cb579dd2
Graph-modem.nmis 829adca5c684f5c8
Graph-mtxrStrength.nmis 7c6ab05cdd33461e
Graph-nmis.nmis bef081f5d72c9d81 ef9b4729e729134e
Graph-numintf.nmis 2f32b89532e0bbfe
Graph-optpwr.nmis 506a6c5cd7049e0d
Graph-ospfNbr.nmis 03f8744cff1a9954
Graph-ospfNbrStats.nmis e97e1286431c91c3
Graph-pix-conn.nmis 69e2d5f144442aef
Graph-pkts.nmis 995d9f9faacafe8a
Graph-pkts_hc.nmis 2a00647cd7307334 fe171185afac8745 1fcbcfbe2981ca70
Graph-ppxAtmCells.nmis c1a05e642f34cbaa
Graph-ppxAtmUtil.nmis 004ba1365bde1cae
Graph-psu-status.nmis 646e7efbe6dcb363
Graph-pvc.nmis faea714bab5cc7ba
Graph-rbt-mem-proc.nmis 3d69c9ea2fbc7a6f
Graph-rbt_connections.nmis ce72e6e5e4b182e5
Graph-rbt_datastore.nmis beb29653576cab87
Graph-rbt_optimisation.nmis ca61c4e432f4cf6d
Graph-response.nmis 21f085a7823787f0 ea1267d3f5f23e70
Graph-routenumber.nmis e9e4d23bd813f52d
Graph-sensorhum.nmis 0558d8286f67f651
Graph-sensortemp.nmis 620a8f116920bb08
Graph-service-cpu.nmis 18b23d723391bada
Graph-service-cpumem.nmis b0080abcace5bae4 da08e38224c2e28c 0b15890293c976f4
Graph-service-mem.nmis 347dbaa8bf6f73f4
Graph-service-response.nmis b5bc2619fdbc1ba0 98c4b75823873afb
Graph-service.nmis 296451dc3696de74 02fb789c16f22407 cc7e549f29d0f137 2c13273f0e5c3018 d430a3cb10d868a4
Graph-session-util.nmis 8ca64d50b0a2df9f
Graph-sessions.nmis a6ef8dc8dc193426
Graph-ss-blocks.nmis 9926464ed35882ea 766e74e15169a811 09b3b55b4786dee6
Graph-ss-cpu.nmis e693098a58c1ee77 cf0d4a3bb4029ff7
Graph-ss-intcon.nmis af969781ec118fee
Graph-systemcapacity.nmis 03cd79cfd91decf5
Graph-systemcurrent.nmis 98f0995a7f8f95fb
Graph-systemvoltage.nmis 4fce5690e23421d1
Graph-tcp-conn.nmis c906819feb3ce27a 99adeaafb757f454
Graph-tcp-segs.nmis 492e48c3e1095ff7 b741758b3e4ff71e
Graph-temp-status.nmis da914d19ad701f4f
Graph-temp.nmis fe2899e7e5836137
Graph-tempsensor.nmis 10cc63355cae954c
Graph-topo.nmis 99db6fdf220113f1
Graph-traffic.nmis 9ab61eedfe6efa5c
Graph-upsbatlevel.nmis 883ba46f3137fcae
Graph-upsbatremtim.nmis a8672c2632937a61
Graph-upsbattemp.nmis 7822ab385271cef7
Graph-upscurin.nmis 3858f29bd3ef2d61
Graph-upscurout.nmis 890a67458520b8dd
Graph-upsload.nmis 69bca45588949a39
Graph-upsloadperc.nmis 69bca45588949a39
Graph-upspwr.nmis 5c113ffa6fe0aadc
Graph-upsvoltin.nmis be2b92c3349dc9d2
Graph-upsvoltout.nmis 59ba207de936d434
Graph-util.nmis f54dd8075acd46a3
Graph-vmwVmState.nmis c3cd84bddf449c3f
Model-ACME-Packet.nmis c0e170755b7a60e4
Model-AIX.nmis e308c1d1d3579fe4 dd42ee01eb159fa6 8ca922e4d2831e81
Model-AKCP-sensor.nmis c7598cb871049d36 3bd748115ad3a368
Model-APC-ups.nmis 5c935b3a13c2daa6
Model-Accelar.nmis 473e4a629d6e7210 8063b383449c4fbd
Model-AlcatelASAM.nmis d2d5d9b2142e1989 83e3f4595c6719e6 acda353c60ca0a18
Model-BayStack.nmis d555e9a6b526af07 20f3b44e91ca4cdc
Model-CGESM.nmis 742d7815c7d195c8 c072cde690149c1a
Model-Catalyst4000.nmis 01ad784e33149cfd 8f91e536545afbb7
Model-Catalyst5000.nmis 4f2332f99910d244 ddff90c669e5db62
Model-Catalyst5000Sup3.nmis f34f79aa44d6018f 05fa2dce7b31ceac
Model-Catalyst6000.nmis bcb8bf00683e3618 66c21f3797aeec56
Model-CatalystIOS.nmis c5c9cda6ab2fdc7c 58b4ca6c33caad09 f57e45b916ce26a3 f1930865b4ca5157 4557e893e26d5ff2
Model-Checkpoint.nmis 7fc1b9eacdb8db09
Model-Cisco7600.nmis 1a7e513d2fbadbbf 5789061a4af028ef ac742c2cbc7e5459
Model-CiscoAP.nmis e293759250cee0b9 dfa57f28dd05977b
Model-CiscoASA.nmis f6d6a0b5bf847d18 24b86e0caf1d0bcf
Model-CiscoASR.nmis 6120ac508c4a3304 2896fd06036c36d5 b32c1f0856744a39
Model-CiscoATM.nmis c1761e63506775e5 9a998b778a74bf97
Model-CiscoCSS.nmis 74e45b3e7419f40e 8c3f3db30cd6e486
Model-CiscoDSL.nmis 1cac042659fc2e2c 374f511affd96c83 6ed6606e1f0ab42c 8e0d14738ab68def 1d66ceac998e50e7 58c7487e5aea2bc0 66a52da60962b0d4
Model-CiscoDefault.nmis bceed295301338cf 4bc694b868f257b4
Model-CiscoGeneric.nmis f589324fb67f9793 9f159c3f25a627b9
Model-CiscoIOSXE.nmis 0cb858418067430b 72b549bdcc0804e9 11f60115dd4cdfad
Model-CiscoIOSXR.nmis c1d83637f22d1aea e12b72b784ad1c5f 459049c58d8319dc 1754b6d20d61a74a 71c999e29bc3b680 a1affb7cf1ae5495
Model-CiscoNXOS.nmis a00d69038b17aa39 aeac57c06f2a8af6 5688a246aed01961 161ae6c49c6f1b3d c80d009aa3d6cf1b 155625644907cfdc d80d5e84a5f55776
Model-CiscoPIX.nmis 475b6fe16f5f55d4 59f330a515797f53
Model-CiscoRouter.nmis 1bd439a8e31cb653 54e66e08f36229d9 83ff33224c7c63c0 0bc12598dda8c8a6 24ca17edafeae0b8 d552abe84ee95e51 06598a8a95e10b4e
Model-CiscoVG.nmis bba37e84817dfed5
Model-Default-HC.nmis fbd901de4a88285a 7d9ba9976f553b4b
Model-Default.nmis 4af750909edab9c8 72f68603c0a271fe
Model-EES.nmis 2f96a9629bc08555 811546e34d172b7c
Model-ESXi.nmis a63a9f2762236032 15d304b1fdb12a21 42fe42c0ebac16f2 22e357c9c5511597 08bef15329da3766 92e38fd76606be7e
Model-Eltek.nmis d9a12800c54d106a
Model-Ericsson-PPX.nmis a0b961cc776ffe20
Model-FoundrySwitch.nmis 421488c17e87d430 bf168d70d1475fa3
Model-FreeBSD.nmis 3a9abc00d41fbc74 4981e0655e48efe9
Model-FrogFoot.nmis 4a6a66d4499724df dc6744887fbd2a49 9a50575536718dd8
Model-Furukawa-OLT.nmis 4536d1b306296d78 261f3f8d53d8fbfc b14044e8a752afcd
Model-FutureSoftware.nmis cc2be4402dd800b9
Model-GE-QS941.nmis 5cab506ad33ae94e 61b3564fc34b7534
Model-Generic.nmis 6421c79212254318 e2352bb53b48d526
Model-JuniperRouter.nmis 95f973a102b99e2d be241f66adf340a6 acc55c2d6bcd8bcc
Model-JuniperSwitch.nmis c5614f8a914c8f5f 6d6aeba8055ea46f e2b6c09997041fc4
Model-LucentStinger.nmis a3b1c1c39a15a9a0 04ad6e9cf916afe8 cc1b7c35eb9e0a21
Model-MGE-ups.nmis ebaca909788ba8ee 78d62d126c66870a
Model-MW-HP-GbE2c.nmis 50c4f4f3d4e2c364 5e57f9290870e2d8
Model-MW-HP.nmis 11c677ca4856af85 819a5ca08a073521
Model-MW-Intel.nmis c52e3076b8ff51dc deb74f6313ead88c
Model-MW-Juniper.nmis 664d25120b038e46 61b9fba4cb792f82
Model-MikroTik.nmis a353c76c562abc23 ff4009ac1488aab1
Model-Netgear-GS108T.nmis 324868d459b73597 a97b7d693220f705
Model-Netgear-GS724T.nmis 1454c0c9656baeb8 a4a0581c2c07b4bb
Model-Netgear-Manual.nmis e50a79fc13613fa0 5efe06d9638880e3 a2412f592876f41f
Model-ONS15454.nmis bb7ed270a661625a 6546eb655567451f
Model-OmniSwitch.nmis 98c10c891ca47415 858ae29f81cb4357 45ac9fe2f91bf84e
Model-PaloAltoNetworks.nmis ef2a3aa4669365c0 b3b7673a119b8680 14d93ccadfd65f0f
Model-PingOnly.nmis 50ef2e6b894887b4
Model-QNAP.nmis 3fbd3e2fa514bf1d 54ca09a7da6d4d95 19ec408694e5a14b
Model-RadOptimux.nmis aa0ffde7a6626880 ac1b50627cf3a86e 6b9949dc6c180ee6
Model-Redback.nmis e26ec4d97bce7363 a3599dc21f7d66f8
Model-Riverbed.nmis e81f7eb6ae5c79a6 2ae1a2cff5c6d100 5ab8b17322ce30c4 62fe7d942ac06539
Model-Riverstone.nmis a550c38da380129e 6fca50ff5ff4d673
Model-SNMPv1.nmis 3338f0a5438bf173 0eb79190d26c010e c268e318f2ec2dd0
Model-SSII-3Com.nmis 3d382177424312fa bf19f17592baa368
Model-SciAtl.nmis 28df9bfea43081bd
Model-ServersCheck.nmis 8d041035d4a31ff3 2483e5817a5b9189
Model-SunSolaris.nmis 7d9f7259b89baaab 6f6df4401bb2c2cf f57fc30e03387722
Model-Windows2000.nmis d76cc6b3694e64ec f587ee08be43714d 008fd598141b9db8 137091fec315d4cc e2a598507e943b77
Model-Windows2003.nmis 38ee3399177897b0 a48090e9f95d56ab a9c8c6d00b50e39d 655cde0646c8fa9a fd6cb7524b7e1313
Model-Windows2008-ext.nmis de1010549173f402 a05960e07cc294b6
Model-Windows2008.nmis 8539686ff342df9f 19c6d7c29651edd0 2d25f7ec52d9fefd e8b3c48b420816f0 fd48d9d46ee0c0a9 9b8d5f0e921ff75a
Model-Windows2012-ext.nmis 760a3c89c1da93bb 34ddee97cb4de8ab
Model-Windows2012.nmis a800a44f0982e13f e7faddc8d0a6bf0a fd2be8102188edd3 8b9fa59350b6257b
Model-ZyXEL-GS.nmis 8666c252de0c306b b7eeb6155653a42b 15e94a542a7fa785
Model-ZyXEL-IES.nmis 3ab9322fece09797 593c69cbe0391cf3 0da840e65c219e00 4e5954eff8347757
Model-ZyXEL-MGS.nmis 94ca1a1be8a5eeee bff9ef1e5d0a70d8 701cf09b9a9dae1e
Model-net-snmp-ext.nmis b9ab8aa532399f63
Model-net-snmp.nmis 997fc7bd3be516be a78ed1067f7f14ab e321e3f8a79b25c0 13f1d8c3e10ebebc 70491c897fe8d828 e106c9b396e76944 d24bab000b0a6fbe b4d10d3789afa1a6
Model.nmis 85b6e9852b359133 bece80b7b44d959b 34592112596682e2 a6443ed36ccd2120 c91082df42a88c17 fc6e00d8485d47c7 0b8ce0fbc6085bea fc31c4ba46c1f4be b8427208bee2fc4d 11d418a22fc2adfb
