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
our $VERSION="8.6.0a";

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

	# native/non-encoding for json is ok for input to md5
	my $fullsig = Digest::MD5::md5_hex($sauce.JSON::XS->new->canonical(1)->pretty(0)->encode(\%structure));
	return substr($fullsig,0,16);
}

# model file, signatures for the last few releases are stored here
__DATA__
Common-Cisco-asset.nmis 675e126af3677a52
Common-Cisco-cbqos.nmis e270054af44bc308
Common-Cisco-cpu.nmis d0570e92ed3e4985
Common-Cisco-macTable.nmis e503d0cbd7220f8f
Common-Cisco-memory.nmis f9af857a75788ae4
Common-Cisco-neighbor.nmis 680e05322f63c24f
Common-Cisco-netflow.nmis 33ad2b9786e1e4f4
Common-Cisco-rtt.nmis 7cd3a757c422f5bd
Common-Cisco-status.nmis 5075457bccea2102 c08e756f6ccd2fa8
Common-Cisco-vlan.nmis 2e41983677ada8b7
Common-Huawei-cbqos.nmis 58b9266692e45cae
Common-Juniper-jnxOperations.nmis 265a1c2ef344630f
Common-Windows-alerts.nmis 56028b9a1767f70a 49d9dd2900082d39
Common-Windows-interface.nmis 8c29f6ab41dcb2ff
Common-Windows-system.nmis 57809a9258f320a4 aded8512fdc1a137
Common-Windows-wmi.nmis eae47688035b325d
Common-asset.nmis f6c2fe2777c14437
Common-calls.nmis 77ca79216fd1aefa
Common-cbqos-in.nmis 68c58453714e91dc a0bbc467ffd18646 6c8df3ec0d0c0858
Common-cbqos-out.nmis ab31ff8eee5db591 48665448110af552 1210e379c4b6a92d
Common-database.nmis 2227e7b78b5547b4 b3d083221e94f22c 8b309566ec783d52 6514b77ecc0dd2c8 5bacf781a1495ba5 a934b015029bbe63 a41276db67e9be61 92a7f5ebc9af25aa 5f1f1a8792f0498d b70fbcbf9e210596 1b1d1620e6b66683 5dbac9d4f0590b2c e56cad8dc7066418 4bd336af049d4135
Common-entityMib.nmis 23129c70d072e098
Common-event.nmis 3c17ac2753efd729
Common-heading.nmis 1c1c2e7cf3a0606c dc1e5ee59839f42a 6b6ffeeb92a8996f fc120bc0906f3b70 7e458f0172e120ea 0f6d824494640deb 8e453ea283e3fd7a c1c8d886c4c7f7f1 4be5135841352538 a2c592a8fe826493 f652ed992cf8d4a2 087587a01227a79e 5c37adf22c7f4ab4 c2bd5a05f75efac3
Common-lldp.nmis e2d224fefdae20fb
Common-macTable.nmis 361d95305604254f
Common-mpls.nmis c05bc0c2b2f47123
Common-routing.nmis bef2fb4c73d5fec9 329d8897cefd7011
Common-software.nmis b8a70318d469754b
Common-stats.nmis 2f7157c230386ee2 efbcfd8340518376 14dd2080e99197df 051ad0c9af4e10ba 67a57e6c34135bc1 6094dfc29937dd19 17ac95f3a6a726cb
Common-summary.nmis 10d878a1904ebb31
Common-threshold.nmis c787902cfc0496e9 2085498abd902193 5f00df141ba53a85 709aa976ce2acd85 42a0e451c9206d1a 306e9d25639e3af6 43500a40644ea0e6
Graph-APCBattTemp.nmis 236bfec034b1269c de5f3206f3eeae68
Graph-APCCapacity.nmis 67294b482fbb1e1f a243dadb1d7875dd
Graph-APCCurrent.nmis 0c04f8bd2eaaeccd 907121ea0bcf9be0
Graph-APCLoad.nmis eaa2669b984cbd15 8ae6b39af42b084d
Graph-APCPDULoad.nmis 9c5586d71aa9a2d6 7ae674e5beb34faa
Graph-APCPDUTemperature.nmis 0798893b748d3e4b c1c240c62c320dff
Graph-APCPDUVoltage.nmis e2c5887c394785fb 4f04f408fea55915
Graph-APCVoltage.nmis aa3e31c404dfdb5e a910505de5e1886a
Graph-AirFiberCapacity.nmis 304475760e3e0d1a
Graph-AirFiberPower.nmis 5bcce88991287dad
Graph-AirMax.nmis 60454785faab6c31 eef33964f2779a9d
Graph-Capacity.nmis 9a947314cea924ab
Graph-DualChannelPower.nmis 0cc470d62d5d654a 5bcd1fb1891d69d4
Graph-EltekACVoltage.nmis 37ef3620ea0c98bd
Graph-EltekBattTemp.nmis a9e9e00d9056d75f
Graph-EltekBreakerAlarms.nmis 732541e9e27f8a7e
Graph-EltekCapacity.nmis bda74df9965cd800
Graph-EltekCurrents.nmis cbca36c54e293781
Graph-EltekRectifierState.nmis 49384cd2ca2bf907
Graph-EltekTempAlarms.nmis 3aebc4fa0e6abe2d
Graph-EltekVoltageAlarms.nmis e9e61c6ec0eb5f5a
Graph-GPSSats.nmis 833fc39873ef07b0 7c1500a755e89524
Graph-LinkRateAp.nmis de25b80252ba37fd
Graph-LinkRateStat.nmis de25b80252ba37fd
Graph-NovelSatDataRate.nmis f53ae50af4da8bb1
Graph-NovelSatNetStatus.nmis 1a9f24f5c6100364
Graph-NovelSatNetTraffic.nmis 15f848fe9447cbd9
Graph-NovelSatSignal.nmis 2e244fb4f8f373c4
Graph-QualityOfServiceStat.nmis b85190ddf5fb729f
Graph-Radio.nmis f811cc0170d2971b
Graph-RadwinChain.nmis 22cafa61d665f77a
Graph-RadwinErrors.nmis b940e3c970d6d19b
Graph-RadwinHSU.nmis 914b158c6618be35
Graph-RadwinMill.nmis 7d7d9a959a900e4c
Graph-RadwinRSSI.nmis ce2c123ba06b359c
Graph-RadwinSignalStrength.nmis f8d7449cfd99d178
Graph-RadwinUtil.nmis aef8a45a1775b06e
Graph-RadwinUtil2.nmis a1a1ff30b5fc5fe0
Graph-RadwinUtilRate.nmis 953bd7cffc760947
Graph-Radwintemp.nmis 47c0daef34262a6d
Graph-SONETErrors.nmis ee76114fdc1dd1ed 06273622fb3105aa
Graph-SignalErrors.nmis ffb4ac5b8675593b
Graph-SignalLevel.nmis f15bb029f41b27bd e4bbd7ae3e3583b7
Graph-StaCount.nmis df2615651499560b 58458a65087eb68e
Graph-StaSignal.nmis cd19f3e92fd699f0
Graph-Strength.nmis f7587b064b15c343
Graph-StrengthStat.nmis f7587b064b15c343
Graph-WindowsDisk.nmis d791a8ff89eaa5a6
Graph-WindowsDiskBytes.nmis 33c3f54e959ff659
Graph-WindowsPaging.nmis 3d130595c242337d 0b9c9c11539c87a4
Graph-WindowsProcessor.nmis e02c9d782c50ad67 141c2d3776687cf0
Graph-Wlan.nmis 819d1964dd843173 9320d53730365392
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
Graph-cpu-huawei.nmis 5220481d664b804c
Graph-cpu.nmis 1fa5ee0d2b6908ba c039ae94ec692c0d
Graph-cpuUtil.nmis 2d5466478641d021
Graph-csscontent.nmis c925be8d6b20f493
Graph-cssgroup.nmis 01f18cb0dc2a5a37
Graph-degree.nmis a6edd263f6c825a4
Graph-diskio-rw.nmis 843ad186a028b563
Graph-diskio-rwbytes.nmis 3e7e6d6df40e5627
Graph-ds3Errors.nmis 52d536766a509518 08d99a03e4cbf54e
Graph-ees.nmis 6828ec38b6a0efca
Graph-env-temp.nmis e03c1594aa719a6b d681f0aa53e1b06c 9f318ebfcc66ef2f 52fb1470af0fbbba ea1de9ff2c868202
Graph-errpkts.nmis 85f62f6272c16295
Graph-errpkts_hc.nmis 5fe561e36c8d121d
Graph-fan-status.nmis 6326f9ff079f3f32 e7848a690e015311
Graph-fkGponOnuStatus.nmis 67782665ea319caf
Graph-fortinet-cpu.nmis d03e3298996c3d90
Graph-fortinet-disk.nmis 2d06828578f5a627
Graph-fortinet-mem.nmis 71ea63d4c9001b31
Graph-fortinet-sessions.nmis 7160c03af6ff25d4
Graph-fortinet-vd-cpu.nmis 7937fbab9d4ec0a1
Graph-fortinet-vd-mem.nmis fc6012eb82adff01
Graph-fortinet-vd-sessions.nmis 01b7dd31a10a1a0f
Graph-frag.nmis 2bfbcd8cb8e4ed34
Graph-gsm_status_2g.nmis 8b0fef6603cf7b49
Graph-gsm_status_3g.nmis 33b988d5abbe6988
Graph-health-ping.nmis 01dcf864dbb5093a f9cec5794bb6a4da 6b96feaf72a8ab85
Graph-health.nmis 2d7292e8ec0c4f33 732400abda37f46d
Graph-hrbufmem.nmis 18ecbd05ab9219ee
Graph-hrcachemem.nmis 849c721e0976297f
Graph-hrcpu.nmis d133563fac3acb74
Graph-hrdisk.nmis 2b724d234a97ef89
Graph-hrmem.nmis f822616bbe06d224 4961460c6573a93d
Graph-hrproc.nmis 75091d4d54fff399 b1884cd477fe50e7
Graph-hrprocload.nmis 64f282788a3a5223
Graph-hrsmpcpu.nmis c9eac2d103505434 46474bf6303958b7
Graph-hrswapmem.nmis 8a00f4dc855edfa2
Graph-hrsystem.nmis b7224fe39a15aa46
Graph-hrusers.nmis 72c134af89e79f2a
Graph-hrvmem.nmis fc4ee146987e466d 12f351d0771b331c
Graph-hrwincpu.nmis 3c4f3a6953a606d8
Graph-hrwincpuint.nmis aaf5cec916a94425
Graph-hrwinmem.nmis 35718efb287ccda3
Graph-hrwinpps.nmis 98b8088c81121f3c
Graph-hrwinproc.nmis a0f9f1a7a31fd7e9 94d60449adf196ba
Graph-hrwinusers.nmis eec91f5029f1b1ed cd91c3cb9ca3be5f
Graph-huawei-cbqos-pkts.nmis b10b2deee5d3b820
Graph-huawei-cbqos.nmis ca77b69c602c0ff5
Graph-humsensor.nmis dc17b1f2c0d1a707
Graph-hwCpuMem.nmis 114c85b170d9e3d4
Graph-hwGponStats.nmis c188832421748505
Graph-hwTempPwr.nmis 851b7a0c4a7ee435
Graph-inDropPackets.nmis 6bdd095534e04e38
Graph-ip.nmis c6baba48b23bda7f 74a54c12bbb5bac0 89b1939ad69db272
Graph-jnxCPU.nmis ff556b1c9129bbb4
Graph-jnxMem.nmis ab1a213c7c3e95bc
Graph-jnxTemp.nmis 9a63dfa867000f76
Graph-kpi.nmis 35a06b89a805d58a
Graph-laload.nmis 497c9f570b333d58 52bd4c924a95ae13
Graph-linkrate.nmis 3e60f7dd8729f625 ea68ab8b7388b2bf
Graph-lockstat.nmis 90b0b76602f5def8 91da9e50c54b4c0b
Graph-maxbits.nmis 3487a645887135af
Graph-mem-cluster.nmis eec46df71e79d7db
Graph-mem-dram.nmis 9a53757525316170
Graph-mem-io.nmis be89eb2045aae54e 08471f91a7d0a104
Graph-mem-mbuf.nmis 1ee5e00821c97fd9
Graph-mem-proc-huawei.nmis a7afb3026057b428
Graph-mem-proc.nmis 4cbcb846d17cd08c 86f67cd24ab3662f
Graph-mem-router.nmis 397cb10e6c3a335e adaff7cb9a7d1fd3
Graph-mem-switch.nmis 7fd234e1af82a94b
Graph-memUsageUtil.nmis 2e078d80af088bd4
Graph-memUtil.nmis 47d14ac67152d49a
Graph-memoryBuffer.nmis ec200e3ebf7b7aec
Graph-memoryPool.nmis b48eea15617c91e0
Graph-metrics.nmis f99bf0c709884dec 2cf6e680cb579dd2
Graph-mimosaChain.nmis c93ba012db73275b
Graph-mimosaStream.nmis 9471ea7235aede9e
Graph-modem.nmis 829adca5c684f5c8
Graph-modemMSE.nmis ce12f1af137f5eb5 679de472624ff35c
Graph-mtxrStrength.nmis 7c6ab05cdd33461e
Graph-netflowstats.nmis 75312b98bdb2503b
Graph-nmis.nmis 265a162114885bd4 ef9b4729e729134e bef081f5d72c9d81
Graph-numintf.nmis 2f32b89532e0bbfe
Graph-optpwr.nmis 506a6c5cd7049e0d
Graph-ospfNbr.nmis 03f8744cff1a9954
Graph-ospfNbrStats.nmis e97e1286431c91c3
Graph-pduOutletStatus.nmis a958e78ad0a038ef
Graph-pix-conn.nmis 69e2d5f144442aef
Graph-pkts.nmis 995d9f9faacafe8a
Graph-pkts_hc.nmis 2a00647cd7307334 fe171185afac8745 1fcbcfbe2981ca70
Graph-polltime.nmis 98d41104f428e4a2
Graph-power.nmis cab4288e81c42750
Graph-ppxAtmCells.nmis c1a05e642f34cbaa
Graph-ppxAtmUtil.nmis 004ba1365bde1cae
Graph-ppxCardCPU.nmis 9a949a954cb16413
Graph-psu-status.nmis 3b76482dee427b7b 646e7efbe6dcb363
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
Graph-signal.nmis 287b293349b11925
Graph-ss-blocks.nmis 9926464ed35882ea 766e74e15169a811 09b3b55b4786dee6
Graph-ss-cpu.nmis e693098a58c1ee77 cf0d4a3bb4029ff7
Graph-ss-intcon.nmis af969781ec118fee
Graph-systemcapacity.nmis 03cd79cfd91decf5
Graph-systemcurrent.nmis 98f0995a7f8f95fb
Graph-systemvoltage.nmis 37fdd119e58e61fe 4fce5690e23421d1
Graph-tcp-conn.nmis c906819feb3ce27a 99adeaafb757f454
Graph-tcp-segs.nmis 492e48c3e1095ff7 b741758b3e4ff71e
Graph-temp-status.nmis 57ab15fa7bbeb2f0 da914d19ad701f4f
Graph-temp.nmis 21683e5985b59193 fe2899e7e5836137
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
Model-ACME-Packet.nmis 1995da55a0ef6d1e c0e170755b7a60e4
Model-AIX.nmis 778c98f5612308f9 dd42ee01eb159fa6 e308c1d1d3579fe4 8ca922e4d2831e81
Model-AKCP-sensor.nmis c7598cb871049d36 3bd748115ad3a368
Model-APC-pdu-ap7900.nmis 05009c11f70f473a
Model-APC-pdu-ap7932.nmis 27cacc3d874a1ef6
Model-APC-pdu.nmis f2c1bdb598e2ff3b
Model-APC-ups.nmis e42db2965c704060 5c935b3a13c2daa6
Model-Accelar.nmis 7c09daabe4cd3f43 8063b383449c4fbd 473e4a629d6e7210
Model-AlcatelASAM.nmis 50c1fdaa738fb401 83e3f4595c6719e6 acda353c60ca0a18 d2d5d9b2142e1989
Model-AlcatelASAMv2.nmis 60bd4fe058528bd8
Model-Alcoma.nmis 363404f6741b1ab6 7716542b9fa6ba59
Model-AristaSwitch.nmis 56a548305c5cc437 d050d520cb81b95c
Model-BayStack.nmis 5b9f81e347a8b5bc 20f3b44e91ca4cdc d555e9a6b526af07
Model-CGESM.nmis 742d7815c7d195c8 c072cde690149c1a
Model-Catalyst4000.nmis 740e972af7c50276 8f91e536545afbb7 01ad784e33149cfd
Model-Catalyst5000.nmis b8ff8fe4eb5eed71 ddff90c669e5db62 4f2332f99910d244
Model-Catalyst5000Sup3.nmis bf91484a883933b3 05fa2dce7b31ceac f34f79aa44d6018f
Model-Catalyst6000.nmis e75673ed0cc5efa5 66c21f3797aeec56 bcb8bf00683e3618
Model-CatalystIOS.nmis 5b8e80284af5b825 58b4ca6c33caad09 c5c9cda6ab2fdc7c f57e45b916ce26a3 f1930865b4ca5157 4557e893e26d5ff2
Model-CatalystIOSXE.nmis 996b59b22db57a9b
Model-Checkpoint.nmis 11ee0fa8b92eb80c 7fc1b9eacdb8db09
Model-Cisco10000.nmis ecddd7f865832a10
Model-Cisco7600.nmis c240d49947ff9116 1a7e513d2fbadbbf 5789061a4af028ef ac742c2cbc7e5459
Model-CiscoAP.nmis e293759250cee0b9 dfa57f28dd05977b
Model-CiscoASA.nmis f6d6a0b5bf847d18 24b86e0caf1d0bcf
Model-CiscoASR.nmis fd8f1582493bab18 2896fd06036c36d5 6120ac508c4a3304 b32c1f0856744a39
Model-CiscoATM.nmis c1761e63506775e5 9a998b778a74bf97
Model-CiscoCSS.nmis 74e45b3e7419f40e 8c3f3db30cd6e486
Model-CiscoDSL.nmis dabf2d96ae489d7f 374f511affd96c83 6ed6606e1f0ab42c 8e0d14738ab68def 1cac042659fc2e2c 1d66ceac998e50e7 58c7487e5aea2bc0 66a52da60962b0d4
Model-CiscoDefault.nmis bceed295301338cf 4bc694b868f257b4
Model-CiscoGeneric.nmis f589324fb67f9793 9f159c3f25a627b9
Model-CiscoIOSXE.nmis e85f66570c90c7fd 72b549bdcc0804e9 0cb858418067430b 11f60115dd4cdfad
Model-CiscoIOSXR.nmis 3fb8ea566f34b6e4 e12b72b784ad1c5f 459049c58d8319dc 1754b6d20d61a74a c1d83637f22d1aea 71c999e29bc3b680 a1affb7cf1ae5495
Model-CiscoNXOS.nmis bc4df1a19cdd8e9b aeac57c06f2a8af6 5688a246aed01961 161ae6c49c6f1b3d a00d69038b17aa39 c80d009aa3d6cf1b 155625644907cfdc d80d5e84a5f55776
Model-CiscoPIX.nmis 475b6fe16f5f55d4 59f330a515797f53
Model-CiscoRouter.nmis f4cb68fb386f54c4 54e66e08f36229d9 83ff33224c7c63c0 1bd439a8e31cb653 0bc12598dda8c8a6 24ca17edafeae0b8 d552abe84ee95e51 06598a8a95e10b4e
Model-CiscoVG.nmis bba37e84817dfed5
Model-Default-HC.nmis a8825ef25dbf4890 7d9ba9976f553b4b fbd901de4a88285a
Model-Default.nmis f74f795c534ea46a 72f68603c0a271fe 4af750909edab9c8
Model-EES.nmis 2f96a9629bc08555 811546e34d172b7c
Model-ESXi.nmis 29e0d149f479f4ac 15d304b1fdb12a21 a63a9f2762236032 42fe42c0ebac16f2 22e357c9c5511597 08bef15329da3766 92e38fd76606be7e
Model-Eltek.nmis d9a12800c54d106a
Model-Ericsson-PPX.nmis cc9951f1266a07e4 a0b961cc776ffe20
Model-ExtremeXOS.nmis 629d9792edb85b26
Model-Fortinet-FG.nmis f00703b88a28683d
Model-FoundrySwitch.nmis ec76524338356ee6 bf168d70d1475fa3 421488c17e87d430 e6cf10185dce40b5
Model-FreeBSD.nmis d4f17f11cd2a5a01 4981e0655e48efe9 3a9abc00d41fbc74
Model-FrogFoot.nmis 9cc289f58f1e3c3e dc6744887fbd2a49 4a6a66d4499724df 9a50575536718dd8 bbe76f043957d1ba
Model-Furukawa-OLT.nmis 7489e8225813e7d9 4536d1b306296d78 261f3f8d53d8fbfc b14044e8a752afcd
Model-FutureSoftware.nmis 92096009cb54d5d0 cc2be4402dd800b9
Model-GE-QS941.nmis 5cab506ad33ae94e 61b3564fc34b7534
Model-Generic.nmis 9f6e87c2dced82ce e2352bb53b48d526 6421c79212254318
Model-Huawei-MA5600.nmis 9e752b89778e1542
Model-Huawei-NetEngine.nmis 34ac1c5aaec02f3e
Model-HuaweiRouter.nmis cbcb03fd241ba9e3
Model-Juniper-ERX.nmis d66d891e14df1c12
Model-JuniperRouter.nmis aaff6a36a2c133d7 95f973a102b99e2d be241f66adf340a6 acc55c2d6bcd8bcc
Model-JuniperSwitch.nmis 681bfbf3d57f235d c5614f8a914c8f5f 6d6aeba8055ea46f e2b6c09997041fc4
Model-LucentStinger.nmis 5dbd8bbf0b64ba76 04ad6e9cf916afe8 a3b1c1c39a15a9a0 cc1b7c35eb9e0a21
Model-MGE-ups.nmis ebaca909788ba8ee 78d62d126c66870a
Model-MW-HP-GbE2c.nmis 50645e1358f2ff62 5e57f9290870e2d8 50c4f4f3d4e2c364
Model-MW-HP.nmis 32b3ed500d4c4a90 819a5ca08a073521 11c677ca4856af85
Model-MW-Intel.nmis 5cafb6dfa62191ce deb74f6313ead88c c52e3076b8ff51dc
Model-MW-Juniper.nmis 0ab8ebdf3e23a6c8 61b9fba4cb792f82 664d25120b038e46
Model-MikroTik.nmis f8d9d7eb0925d15a ff4009ac1488aab1 a353c76c562abc23 763ac63ebdf8f155 f5e69106f5b1cbc5
Model-MikroTikRouter.nmis afa45e050d9e2ad3
Model-Mimosa.nmis 85bbe1cd540bdafd f96793bf3d691117
Model-Netgear-GS108T.nmis caa1f22f37fe1652 a97b7d693220f705 324868d459b73597
Model-Netgear-GS724T.nmis fc8bcdd017f3016a a4a0581c2c07b4bb 1454c0c9656baeb8
Model-Netgear-Manual.nmis e50a79fc13613fa0 5efe06d9638880e3 a2412f592876f41f
Model-NovelSat.nmis 0c9d20c5c4c8345c
Model-ONS15454.nmis 4831558a9668d56b 6546eb655567451f bb7ed270a661625a
Model-OmniSwitch.nmis 95c870d2b7f0c439 858ae29f81cb4357 98c10c891ca47415 45ac9fe2f91bf84e
Model-PaloAltoNetworks.nmis 2b0a5c3709bb9917 b3b7673a119b8680 14d93ccadfd65f0f ef2a3aa4669365c0
Model-PingOnly.nmis 50ef2e6b894887b4
Model-QNAP.nmis f0bfacd519eeaaf9 54ca09a7da6d4d95 3fbd3e2fa514bf1d 19ec408694e5a14b
Model-RadOptimux.nmis 97eb50a719a90945 ac1b50627cf3a86e 6b9949dc6c180ee6 aa0ffde7a6626880
Model-RadwinWireless.nmis 5b7a0e1baa408001 193dbf61b138b6a9
Model-Redback.nmis 223c8e6e1d957dba a3599dc21f7d66f8 e26ec4d97bce7363
Model-Riverbed.nmis d46b9496076aa29e 2ae1a2cff5c6d100 e81f7eb6ae5c79a6 5ab8b17322ce30c4 62fe7d942ac06539
Model-Riverstone.nmis 9db7ab997fbb904c 6fca50ff5ff4d673 a550c38da380129e
Model-SNMPv1.nmis 4db3d8421ae8a658 0eb79190d26c010e 3338f0a5438bf173 c268e318f2ec2dd0
Model-SSII-3Com.nmis 76e2893b5d737bc8 bf19f17592baa368 3d382177424312fa
Model-SciAtl.nmis 541d6b96a30fa040 28df9bfea43081bd
Model-ServersCheck.nmis 8d041035d4a31ff3 2483e5817a5b9189
Model-SunSolaris.nmis 41d3c15e0452b799 6f6df4401bb2c2cf 7d9f7259b89baaab f57fc30e03387722
Model-Trango.nmis 6a64f79ce2e84472 693579019215606f f89d8e7ab685639f
Model-Ubiquiti.nmis c9362b682401e7f9
Model-Windows2000.nmis 57eefa482cc0428c f587ee08be43714d 008fd598141b9db8 d76cc6b3694e64ec 137091fec315d4cc e2a598507e943b77
Model-Windows2003.nmis 3f42c421efed5077 a48090e9f95d56ab a9c8c6d00b50e39d 38ee3399177897b0 655cde0646c8fa9a fd6cb7524b7e1313 86e17d027c1f419e
Model-Windows2008-wmi.nmis e4141731668b6f89 6ea61c9717c467c9
Model-Windows2008.nmis f67ca6859cf50312 19c6d7c29651edd0 8539686ff342df9f 2d25f7ec52d9fefd e8b3c48b420816f0 fd48d9d46ee0c0a9 9b8d5f0e921ff75a f4b15aa1cb629bd5
Model-Windows2008R2.nmis e319c992858b7773
Model-Windows2012.nmis bbf007ce847a32ae a800a44f0982e13f e7faddc8d0a6bf0a fd2be8102188edd3 8b9fa59350b6257b e3515295559253a6
Model-ZyXEL-GS.nmis 72f30722cd3e6665 b7eeb6155653a42b 8666c252de0c306b 15e94a542a7fa785
Model-ZyXEL-IES.nmis 7b098aa3c8afa7de 593c69cbe0391cf3 0da840e65c219e00 3ab9322fece09797 4e5954eff8347757
Model-ZyXEL-MGS.nmis c3ea5aec5b903e8e bff9ef1e5d0a70d8 94ca1a1be8a5eeee 701cf09b9a9dae1e
Model-net-snmp.nmis b6518274fab46b78 a78ed1067f7f14ab e321e3f8a79b25c0 13f1d8c3e10ebebc 997fc7bd3be516be 70491c897fe8d828 e106c9b396e76944 d24bab000b0a6fbe b4d10d3789afa1a6 5d97f9cf73a61919 aa24077be26e5897
Model.nmis 3c7c7f1471f80e2c bece80b7b44d959b 34592112596682e2 a6443ed36ccd2120 c91082df42a88c17 fc6e00d8485d47c7 85b6e9852b359133 0b8ce0fbc6085bea fc31c4ba46c1f4be b8427208bee2fc4d 11d418a22fc2adfb efb216ab07a50fd0 d0c4c790f815e46a
