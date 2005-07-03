#!/usr/bin/perl -w

# ******************************************************************************
# CLI Exerciser N' Tester                                                   v6.1
#
# Copyright (c) 2005 Frederic Thomas (fred(at)thomascorner.com)
#
# This file might be distributed under the same terms as the
# Slimserver (www.slimdevices.com)
#
# Description:
# Tests and exercises the CLI
#
# WARNING & Notes
# - This is a test tool. Hence all params are global variables to change
#   before each run if needed. Testing less can be achieved by commenting
#   the appropriate testXXX() call in main below. Each testXXX() is fully
#   independant from the others. Order does not matter.
# 
# - Tests normally restore state (except player playlists). However, the volume
#   and other parms will vary widely on all players, so make sure you do not 
#   have high volume settings on your amps before testing.
#
# - To test security, user & pwd must be defined, but security must not
#   be necessarily enabled. The test program will enable it to test login if
#   needed. Likewise, if security is enabled, it will disable it just long
#   enough to test.
#   If user & pwd is undef, then either the test tool can't connect and all
#   test are skipped, or it can and the connect test simply checks security is
#   disabled.
#
# - 
#
# Plattform tested:
# - MacOS X 10.3.x
#
# Known restrictions:
# - Commands not tested: listen, ir
#
# History:
# 0.1 - Inital version for CLI in SlimServer 5.4.1
# 6.1 - For CLI in SlimServer 6.1
# ******************************************************************************

# ******************************************************************************
# uses
# ******************************************************************************

use strict;
use warnings;
use diagnostics;

#use Getopt::Long;
use IO::Socket;
use IO::Socket qw(:DEFAULT :crlf);
use URI::Escape;
use POSIX qw(ceil);
use utf8;
require Encode;

# ******************************************************************************
# Global variables (Can be changed by user)
# ******************************************************************************

# Debug flags
my $gd_sub = 0; 					# subroutines names
my $gd_tcp = 0; 					# tcp exchanges
my $gd_cli = 0; 					# cli exchanges
my $gd_test = 1;					# print test names & result
my $gd_subtest = 1;                 # print subtest names & result
my $gd_syn = 1;						# print syntax errors

# Connection
my $gserver = "127.0.0.1";          # server ip/name
my $gport = 9090;				    # port
my $guser = 'test';					# user name
my $gpwd = 'test';					# password
my $gterm = $LF;

# Output
binmode STDOUT, ":utf8";			# suitable for UTF-8 able terminals, such
									# as Mac OS X Terminal.app

# ******************************************************************************
# Global variables (DON'T TOUCH)
# ******************************************************************************
# TCP connection stuff
my $gsocket;						# connection socket

# CLI connection stuff
my $gcli;							# 1 if connected

# Test database
my %gtest_db; 						# 0 start, 1 skip, 2 failed, 3 full success, 4 skipped success
my %gtest_dbcomment;				# comment (failure/skipped reason)
my %gsyntaxTests;					# to store syntax errors

# Players
my @gplayers;						# players id, filled by test_canPlayers()

# Song database
my %gDBtitles; 						# TID -> title text
my %gDBartist; 						# TID -> AID
my %gDBalbum; 						# TID -> LID
my %gDBgenre; 						# TID -> GID
my %gDBopt;							# field -> TID with it

# Songinfo fields definitions
my %gsonginfoFields = (
	'id'					=> 'zz',
	'title'					=> 'zz',
	'genre'					=> 'g',
	'genre_id'				=> 'p',
	'artist'				=> 'a',
	'artist_id'				=> 's',
	'composer'				=> 'c',
	'band'					=> 'b',
	'conductor'				=> 'h',
	'album'					=> 'l',
	'album_id'				=> 'e',
	'duration'				=> 'd',
	'disc'					=> 'i',
	'disccount'				=> 'q',
	'tracknum'				=> 't',
	'year'					=> 'y',
	'bpm'					=> 'm',
	'comment'				=> 'k',
	'type'					=> 'o',
	'tagversion'			=> 'v',
	'bitrate'				=> 'r',
	'filesize'				=> 'f',
	'drm'					=> 'z',
	'coverart'				=> 'j',
	'modificationTime'		=> 'n',
	'url'					=> 'u',
);



# ******************************************************************************
# Main program
# ******************************************************************************

print "\nSlimServer CLI Exerciser N' Tester (CLIENT) 6.1\n\n";
			
#testConnectDisconnect();
#testGeneral();
#testPlayersQueries();
#testPlayersSleep();
#testPlayersPower();
#testPlayersMixer();
#testPlayersDisplay();
#testDatabaseRescan();
#testDatabaseGenres();
#testDatabaseAlbums();
#testDatabaseArtists();
#testDatabaseTitles();
testDatabaseSonginfo();

test_PrintReport();

cliDisconnect();
print "Done!\n\n";
exit;

# ******************************************************************************
# Subroutines (tests definitions)
# ******************************************************************************

# ---------------------------------------------
# testConnectDisconnect
# ---------------------------------------------
sub testConnectDisconnect {
	$gd_sub && p_sub("testConnectDisconnect()");

	# define test
	my $tid = test_New("Connect (login) and disconnect (exit)");
	
	# pre-conditions
	test_canConnect($tid);
	# authorize 0.1
	# username ...
	# password
	
	if (test_canRun($tid)) {

		# cliDisconnect assumes "exit" works, try manually...
		cliSendReceive(undef, ['exit']);
		test_SubTest($tid, "disconnected", !defined(cliSendReceive(undef, ['exit'])) );
		# Restore $gcli
		$gcli = undef;			

		# Reconnect
		test_SubTest($tid, "Can reconnect after exit", cliConnect());

		if ($gcli) {
			# we're connected, check if authorize is on
			my $auth = cliQueryFlag(undef, ['pref', 'authorize']);
		
			if ($auth) {
				# OK if a user is defined (that was used to login)
				test_SubTest($tid, "login needed to connect if security is on", defined $guser);
				
				# turn auth off
				cliCommand(undef, ['pref', 'authorize', 0]);
			}
			
			# Disconnect.
			cliDisconnect();
			sleep 1;
			
			# Try again without auth, use force_nologin...
			test_SubTest($tid, "login not needed if security is off", cliConnect(1));
			
			if ($gcli) {
				# if we have a user/pwd, enable security			
				if (defined $guser) {
					cliCommand(undef, ['pref', 'authorize', 1]);
					
					# Disconnect.
					cliDisconnect();
					sleep 0.5;
					
					# Try wrong pwd
					my $savepwd = $gpwd;
					$gpwd = 'trililulalal';
					test_SubTest($tid, "Correct pwd needed if security is on", !cliConnect());
					$gpwd = $savepwd;
					cliDisconnect();
					sleep 0.5;
					
					# Try wrong user
					my $saveuser = $guser;
					$guser = 'trililulalal';
					test_SubTest($tid, "Correct user needed if security is on", !cliConnect());
					cliDisconnect();
					sleep 0.5;
					
					# Try all wrong
					$guser = 'trililulalal';
					$gpwd = 'trililulalal';
					test_SubTest($tid, "Correct user & pwd needed if security is on", !cliConnect());
					cliDisconnect();
					sleep 0.5;
					
					
					$gpwd = $savepwd;
					$guser = $saveuser;
					cliConnect();
				}
				else {
					#$gd_subtest && print("# SKIPPED: security tests (no user/pwd provided)\n");
					test_SubTest($tid, "Security tests", 'skip', "no user/pwd provided");
				}
				# restore auth
				cliCommand(undef, ['pref', 'authorize', $auth]);
			}
		}
	}

	test_Done($tid);
}

# ---------------------------------------------
# testGeneral
# ---------------------------------------------
sub testGeneral {
	$gd_sub && p_sub("testGeneral()");

	#define test
	my $tid = test_New("General commands (debug, version, pref)");
	
	#pre-conditions
	test_canConnect($tid);
	
	if (test_canRun($tid)) {
		# version
		test_SubTest($tid, "version defined", defined(cliQuery(undef, ['version'])));

		# debug
		my $flag = cliQueryFlag(undef, ['debug', 'd_cli']);
		cliCommand(undef, ['debug', 'd_cli', 0]);
		test_SubTest(	$tid, "debug FLAG 0 => debug FLAG ? == 0", 
						cliQueryFlag(undef, ['debug', 'd_cli']) == 0);
		cliCommand(undef, ['debug', 'd_cli', 1]);
		test_SubTest(	$tid, "debug FLAG 1 => debug FLAG ? == 1", 
						cliQueryFlag(undef, ['debug', 'd_cli']) == 1);
		cliCommand(undef, ['debug', 'd_cli']);
		test_SubTest(	$tid, "debug FLAG => debug FLAG ? == 0", 
						cliQueryFlag(undef, ['debug', 'd_cli']) == 0);
		cliCommand(undef, ['debug', 'd_cli', $flag]);
		
		# pref
		$flag = cliQueryFlag(undef, ['pref', 'composerInArtists']);
		cliCommand(undef, ['pref', 'composerInArtists', 0]);
		test_SubTest(	$tid, "pref PREF 0 => pref PREF ? == 0", 
						cliQueryFlag(undef, ['pref', 'composerInArtists']) == 0);
		cliCommand(undef, ['pref', 'composerInArtists', 1]);
		test_SubTest(	$tid, "pref PREF 1 => pref PREF ? == 1", 
						cliQueryFlag(undef, ['pref', 'composerInArtists']) == 1);
		cliCommand(undef, ['pref', 'composerInArtists', $flag]);
		
		# command termination
		my $savedterm = $gterm;
		$gterm = $LF;
		test_SubTest($tid, "Server accepts LF as command termination", defined(cliQuery(undef, ['version'])));
		$gterm = $CR . $LF;
		test_SubTest($tid, "Server accepts CRLF as command termination", defined(cliQuery(undef, ['version'])));
		$gterm = $LF . $CR;
		test_SubTest($tid, "Server accepts LFCR as command termination", defined(cliQuery(undef, ['version'])));
		$gterm = $CR;
		test_SubTest($tid, "Server accepts CR as command termination", defined(cliQuery(undef, ['version'])));
		$gterm = $savedterm;
		
	}

	test_Done($tid);
}

# ---------------------------------------------
# testPlayersSleep
# ---------------------------------------------
sub testPlayersSleep {
	$gd_sub && p_sub("testPlayersSleep()");

	#define test
	my $tid = test_New("Player sleep");
	
	#pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid);
	
	if (test_canRun($tid)) {

		# Part 1: a player set to sleep (a) fades the volume before sleeping
		# and (b) powers off.
		
		my $sleeptime = 30 + randomSmaller(30);
		
		# Set all players to sleep
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power', 1]);
			cliCommand($gplayers[$i], ['sync', '-']);
			cliCommand($gplayers[$i], ['mixer', 'volume', 50]);
			cliCommand($gplayers[$i], ['sleep', $sleeptime]);
		}
		
		# Test they report sleep
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid sleep ? <= <sleeptime>", 
							cliQueryNum($playerid, ['sleep']) <= $sleeptime);
			test_SubTest(	$tid, 
							"$playerid status.will_sleep_in <= <sleeptime>", 
							$cliCall{'will_sleep_in'} <= $sleeptime);
			test_SubTest(	$tid, 
							"$playerid status.sleep == <sleeptime>", 
							$cliCall{'sleep'} == $sleeptime);
		}
		
		# wait till 30 secs before sleep
		$gd_subtest && print("\nWaiting for 30 secs before sleep...\n");
		sleep ($sleeptime - 30);
		
		my %vol;
		
		# Test they still report sleep and note volume
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid sleep ? <= 30", 
							cliQueryNum($playerid, ['sleep']) <= 30);
			test_SubTest(	$tid, 
							"$playerid status.will_sleep_in <= 30", 
							$cliCall{'will_sleep_in'} <= 30);
			test_SubTest(	$tid, 
							"$playerid status.sleep == <sleeptime>", 
							$cliCall{'sleep'} == $sleeptime);
			$vol{$playerid} = cliQueryNum($playerid, ['mixer', 'volume']);
		}
		
		# wait till 5 secs before sleep
		$gd_subtest && print("\nWaiting for 5 secs before sleep...\n");
		sleep 25;

		# Test they still report sleep and check volume
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid sleep ? <= 5", 
							cliQueryNum($playerid, ['sleep']) <= 5);
			test_SubTest(	$tid, 
							"$playerid status.will_sleep_in <= 5", 
							$cliCall{'will_sleep_in'} <= 5);
			test_SubTest(	$tid, 
							"$playerid status.sleep == <sleeptime>", 
							$cliCall{'sleep'} == $sleeptime);
			test_SubTest(	$tid, 
							"volume faded before sleep", 
							$vol{$playerid} > cliQueryNum($playerid, ['mixer', 'volume']));
		}
		
		# wait till 1 secs after sleep
		$gd_subtest && print("\nWaiting for 1 sec after sleep...\n");
		sleep 6;

		# Test they are powered off and no longer sleeping
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid sleep ? == 0", 
							cliQueryNum($playerid, ['sleep']) == 0);
			test_SubTest(	$tid, 
							"$playerid status.will_sleep_in <undefined>", 
							!defined $cliCall{'will_sleep_in'});
			test_SubTest(	$tid, 
							"$playerid status.sleep <undefined>", 
							!defined $cliCall{'sleep'});
			test_SubTest(	$tid, 
							"$playerid power ? == 0", 
							cliQueryFlag($playerid, ['power']) == 0);
		}
		
		
		# Part 2: power cycling a player cancels sleep
		
		# Set all players to sleep
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power', 1]);
			cliCommand($gplayers[$i], ['sleep', $sleeptime]);
		}
		
		# Test they report sleep
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			test_SubTest(	$tid, 
							"$playerid sleep ? <= <sleeptime>", 
							cliQueryNum($playerid, ['sleep']) <= $sleeptime);
		}

		# Turn off players
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power', 0]);
		}
		sleep 1;
		# Turn on players
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power', 1]);
		}

		# Test they are no longer sleeping
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			test_SubTest(	$tid, 
							"$playerid sleep ? == 0", 
							cliQueryNum($playerid, ['sleep']) == 0);
		}		
	}
	test_Done($tid);
}

# ------------------------------------------------------------------------------
# testPlayersPower
# ------------------------------------------------------------------------------
sub testPlayersPower {
	$gd_sub && p_sub("testPlayersPower()");

	#define test
	my $tid = test_New("Player power");
	
	#pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid);
	
	if (test_canRun($tid)) {

		# Test the power commands
		
		# Set all players to off
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['sync', '-']);
			cliCommand($gplayers[$i], ['power', 0]);
		}
		
		# Test they report off
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid power ? == 0", 
							cliQueryFlag($playerid, ['power']) == 0);
			test_SubTest(	$tid, 
							"$playerid status.power == 0", 
							$cliCall{'power'} == 0);
			test_SubTest(	$tid, 
							"$playerid status.mode <undefined>", 
							!defined $cliCall{'mode'});
			test_SubTest(	$tid, 
							"$playerid status.playlist_tracks <undefined>", 
							!defined $cliCall{'playlist_tracks'});							
		}
		
		# wait 1 sec
		sleep 1;
		
		# Set all players to on
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power', 1]);
		}
		
		# Test they report on
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my %cliCall = cliStatus($playerid);
			test_SubTest(	$tid, 
							"$playerid power ? == 1", 
							cliQueryFlag($playerid, ['power']) == 1);
			test_SubTest(	$tid, 
							"$playerid status.power == 1", 
							$cliCall{'power'} == 1);
			test_SubTest(	$tid, 
							"$playerid status.mode <defined>", 
							defined $cliCall{'mode'});
			test_SubTest(	$tid, 
							"$playerid status.playlist_tracks <defined>", 
							defined $cliCall{'playlist_tracks'});							
		}
		
		# Test toggle
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['power']);
		}
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			test_SubTest(	$tid, 
							"$playerid power ? == 0", 
							cliQueryFlag($playerid, ['power']) == 0);
		}			
	}
	test_Done($tid);
}

# ------------------------------------------------------------------------------
# testPlayersDisplay
# ------------------------------------------------------------------------------
sub testPlayersDisplay {
	$gd_sub && p_sub("testPlayersDisplay()");

	#define test
	my $tid = test_New("Player display");
	
	#pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid);
	
	if (test_canRun($tid)) {

		# Test the display commands, including playerpref and button applied to
		# display settings

		# display never returns message, but what WAS on before
		# displaynow returns message, BUT for non graph disp:
		#  - the full display line is returned (20 chars)
		#  - if lineperscreen is 1, we get the graphical chars "garbage" (f.e. "rightvbardoublelinechar)rightv")
		# (doublesize pref for slim)
		# AND for graph disp:
		#  - if the screensaver kicks in, it may not report anything!
		
		my %souvenir;
		
		# Set all players to on
		foreach (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			# on off guarantees no screensaver for graphical screens
			
			cliCommand($playerid, ['power', 0]);
			cliCommand($playerid, ['sync', '-']);
			cliCommand($playerid, ['power', 1]);
			if (	cliQuery(undef, ['player', 'displaytype', $playerid]) =~ 'noritake' 
					&&
					cliQueryNum($playerid, ['linesperscreen']) == 1) {
				$souvenir{$playerid} = $playerid;
				cliCommand($playerid, ['playerpref', 'doublesize', 0]);
			}
		}
		
		sleep 1;

		foreach (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			cliCommand($playerid, [	'display', 
									center('CLIent player display test', 40), 
									center("Player $i $playerid", 40),
									5]);
		}	
		
		# wait a bit before checking
		sleep 1;

		# Check we can read the message
		
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my ($l1, $l2) = cliQueryDual($playerid, ['display']);
			test_SubTest(	$tid, 
							"$playerid display ? ? <> message", 
							$l1 ne center('CLIent player display test', 40)
							&&
							$l2 ne center("Player $i $playerid", 40));
			($l1, $l2) = cliQueryDual($playerid, ['displaynow']);
			test_SubTest(	$tid, 
							"$playerid displaynow ? ? == message", 
							$l1 eq center('CLIent player display test', 40)
							&&
							$l2 eq center("Player $i $playerid", 40));
		}

		# sleep while and check message is gone
		$gd_subtest && print("\nWaiting for 5 secs for message disappearance...\n");
		sleep 5;

		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my ($l1, $l2) = cliQueryDual($playerid, ['display']);
			test_SubTest(	$tid, 
							"$playerid display ? ? <> message", 
							$l1 ne center('CLIent player display test', 40)
							&&
							$l2 ne center("Player $i $playerid", 40));
			($l1, $l2) = cliQueryDual($playerid, ['displaynow']);
			test_SubTest(	$tid, 
							"$playerid displaynow ? ? <> message", 
							$l1 ne center('CLIent player display test', 40)
							&&
							$l2 ne center("Player $i $playerid", 40));
							
			# Restore lineperscreen
			if ($souvenir{$playerid}) {
				cliCommand($playerid, ['playerpref', 'doublesize', 1]);
			}
		}


		# Test playerpref and button using powerOnBrightness and brightness_down...
		$gd_subtest && print("\nTesting playerpref, button and linesperscreen\n");

		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my $bright = cliQueryNum($playerid, ['playerpref', 'powerOnBrightness']);
			cliCommand($playerid, ['playerpref', 'powerOnBrightness', 4]);
			test_SubTest(	$tid, 
							"$playerid playerpref powerOnBrightness 4 =>  $playerid playerpref powerOnBrightness ? == 4", 
							cliQueryNum($playerid, ['playerpref', 'powerOnBrightness']) == 4);
			
			sleep 0.2;
			cliCommand($playerid,  ['button', 'brightness_down']);
			sleep 0.2;
			cliCommand($playerid,  ['button', 'brightness_down']);
			sleep 0.2;
			test_SubTest(	$tid, 
							"$playerid button brightness_down (2x) => $playerid playerpref powerOnBrightness ? == 2", 
							cliQueryNum($playerid, ['playerpref', 'powerOnBrightness']) == 2);

			cliCommand($playerid, ['playerpref', 'powerOnBrightness', $bright]);

			# This has nothing to do with anything and there is not much we can do with it today...		
			my $lines = cliQueryNum($playerid, ['linesperscreen']);
			test_SubTest(	$tid, 
							"$playerid linesperscreen ? == 1 or 2", 
							$lines == 2 || $lines == 1);
			
		}
		
	}
	test_Done($tid);
}


# ------------------------------------------------------------------------------
# testPlayersMixer
# ------------------------------------------------------------------------------
sub testPlayersMixer {
	$gd_sub && p_sub("testPlayersMixer()");

	#define test
	my $tid = test_New("Player mixer");
	
	#pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid);
	
	if (test_canRun($tid)) {

		# Test the mixer commands
		
		# Set all players to on
		for (my $i=0; $i<scalar @gplayers; $i++) {
			cliCommand($gplayers[$i], ['sync', '-']);
			cliCommand($gplayers[$i], ['power', 1]);
		}
		
		# Test mixer
		for (my $i=0; $i<scalar @gplayers; $i++) {
			my $playerid = $gplayers[$i];
			my $model = cliQuery(undef, ['player', 'model', $playerid]);
			
			# volume
			__testPlayersMixer($tid, $playerid, 'volume');
			
			# muting
			my $vol = cliQueryNum($playerid, ['mixer', 'volume']);
			cliCommand($playerid, ['mixer', 'volume', 50]);
			cliCommand($playerid, ['mixer', 'muting']);
			sleep 1; # mutes includes a fade!
			test_SubTest(	$tid, 
							"$playerid mixer muting => negative volume", 
							cliQueryNum($playerid, ['mixer', 'volume']) == -50);
			cliCommand($playerid, ['mixer', 'muting']);
			sleep 1;
			test_SubTest(	$tid, 
							"$playerid mixer muting => restored volume", 
							cliQueryNum($playerid, ['mixer', 'volume']) == 50);
			cliCommand($playerid, ['mixer', 'volume', $vol]);
			
			
			# treble/bass
			if ($model ne 'softsqueeze' && $model ne 'squeezebox2') {
				__testPlayersMixer($tid, $playerid, 'treble');
				__testPlayersMixer($tid, $playerid, 'bass');
			}
			else {
				#$gd_subtest && print("# SKIPPED: $playerid mixer bass/treble: not supported by player model: $model\n");
				test_SubTest($tid, "$playerid mixer bass/treble", 'skip', "not supported by player model: $model");
			}
			
			# pitch
			if ($model ne 'softsqueeze' && $model ne 'squeezebox2' && $model ne 'slimp3') {
				__testPlayersMixer($tid, $playerid, 'pitch');
			}
			else {
				#$gd_subtest && print("# SKIPPED: $playerid mixer pitch: not supported by player model: $model\n");
				test_SubTest($tid, "$playerid mixer pitch", 'skip', "not supported by player model: $model");				
			}
		}
		
	}
	test_Done($tid);
}

sub __testPlayersMixer {
	my $tid = shift;
	my $playerid = shift;
	my $field = shift;
	my $valmax = 100;
	my $valmin = 0;
	
	
	if ($field eq 'pitch') {
		$valmax = 120;
		$valmin = 80;
	}
	
	#remember old value
	my $memo = cliQueryNum($playerid, ['mixer', $field]);
	
	# set abs volume
	my $value = $valmin + randomSmaller($valmax - $valmin - 10);
	cliCommand($playerid, ['mixer', $field, $value]);
	
	# check 
	my %cliCall = cliStatus($playerid);
	test_SubTest(	$tid, 
					"$playerid mixer $field ? == $value", 
					cliQueryNum($playerid, ['mixer', $field]) == $value);
	test_SubTest(	$tid, 
					"$playerid status.mixer $field == $value", 
					$cliCall{"mixer $field"} == $value);

	my $delta = randomSmaller($valmax-$value);
	cliCommand($playerid, ['mixer', $field, '+'.$delta]);
	$value += $delta;
	# check 
	%cliCall = cliStatus($playerid);
	test_SubTest(	$tid, 
					"$playerid mixer $field ? == $value", 
					cliQueryNum($playerid, ['mixer', $field]) == $value);
	test_SubTest(	$tid, 
					"$playerid status.mixer $field == $value", 
					$cliCall{"mixer $field"} == $value);
	
	$delta = randomSmaller($value - $valmin);
	$value -= $delta;
	cliCommand($playerid, ['mixer', $field, '-'.$delta]);
	# check 
	%cliCall = cliStatus($playerid);
	test_SubTest(	$tid, 
					"$playerid mixer $field ? == $value", 
					cliQueryNum($playerid, ['mixer', $field]) == $value);
	test_SubTest(	$tid, 
					"$playerid status.mixer $field == $value", 
					$cliCall{"mixer $field"} == $value);

	#restore
	cliCommand($playerid, ['mixer', $field, $memo]);
}


# ---------------------------------------------
# testPlayersQueries
# ---------------------------------------------
sub testPlayersQueries {
	$gd_sub && p_sub("testPlayersQueries()");

	#define test
	my $tid = test_New("Player queries");
	
	#pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid);
	
	if (test_canRun($tid)) {
		
		my %cliCall = cliPlayers();
		my $numPlayers = $cliCall{'count'};
		
		# players.count == player count ?
		test_SubTest(	$tid, 
						"players.count == player count ?", 
						$numPlayers == cliQueryNum(undef, ['player', 'count']));
		
		# we have no guarantee that index of Players is the same than the index
		# used by individual query commands. Create a map.
		# This assumes player ids are unique, so test that...
		my @playersPlayers;
		my @playersPlayer;
		my %playersMap; # $playersMap{playersPlayers[$i]} == $playerPlayer
		
		my $unique = 1;
		for(my $i = 0; $i < $numPlayers; $i++) {
			%cliCall = cliPlayers($i);
			$playersPlayers[$i] = $cliCall{'playerid'};
			for(my $j=0; $j < $i; $j++)
			{
				$unique = $unique && ($playersPlayers[$j] ne $playersPlayers[$i]);
			}
		}
		test_SubTest($tid, "players.playerid unique", $unique);

		$unique = 1;
		for(my $i = 0; $i < $numPlayers; $i++) {
			$playersPlayer[$i] = cliQuery(undef, ['player', 'id', "$i"]);
			for(my $j=0; $j < $i; $j++)
			{
				$unique = $unique && ($playersPlayer[$j] ne $playersPlayer[$i]);
			}
			#find us in playersPlayers
			for(my $j=0; $j < scalar @playersPlayers; $j++)
			{
				if ($playersPlayers[$j] eq $playersPlayer[$i]) {
					#found
					$playersMap{$playersPlayers[$j]} = $i;		
				}
			}
		}
		test_SubTest($tid, "player id ? unique", $unique);
	
		# now we can compare attributes
		for(my $i=0; $i < scalar @playersPlayers; $i++) {
			
			my $playerid = $playersPlayers[$i];
			my $j = $playersMap{$playerid};
			%cliCall = cliPlayers($i);
			
			# players command vs individual by index
			
			test_SubTest($tid, "players.$i.name == player name $j ?", 
				$cliCall{'name'} 
				eq 
				cliQuery(undef, ['player', 'name', $j]));
			
			test_SubTest($tid, "players.$i.ip == player ip $j ?", 
				$cliCall{'ip'}
				eq 
				cliQuery(undef, ['player', 'ip', $j]));

			test_SubTest($tid, "players.$i.model == player model $j ?", 
				$cliCall{'model'}
				eq 
				cliQuery(undef, ['player', 'model', $j]));

			test_SubTest($tid, "players.$i.displaytype == player displaytype $j ?", 
				$cliCall{'displaytype'}
				eq 
				cliQuery(undef, ['player', 'displaytype', $j]));
			
			# players command vs individual by id

			test_SubTest($tid, "players.$i.name == player name $playerid ?", 
				$cliCall{'name'} 
				eq 
				cliQuery(undef, ['player', 'name', $playerid]));
			
			test_SubTest($tid, "players.$i.ip == player ip $playerid ?", 
				$cliCall{'ip'} 
				eq 
				cliQuery(undef, ['player', 'ip', $playerid]));

			my $model = cliQuery(undef, ['player', 'model', $playerid]);
			test_SubTest(	$tid, 
							"players.$i.model == player model $playerid ?", 
							$cliCall{'model'} eq $model);

			test_SubTest($tid, "players.$i.displaytype == player displaytype $playerid ?", 
				$cliCall{'displaytype'} 
				eq 
				cliQuery(undef, ['player', 'displaytype', $playerid]));

			test_SubTest($tid, "players.$i.playerid == player id $playerid ?", 
				$cliCall{'playerid'} 
				eq 
				cliQuery(undef, ['player', 'id', $playerid]));


			# special tests for connected & status

			test_SubTest($tid, "players.$i.connected == $playerid connected ?", 
				$cliCall{'connected'} 
				eq 
				cliQueryFlag($playerid, ['connected']));

			my %cliCall2 = cliStatus($playerid);
			test_SubTest($tid, 
						"players.$i.connected == $playerid status.player_connected", 
							$cliCall{'connected'} 
							eq 
							$cliCall2 {'player_connected'});

			test_SubTest($tid, "players.$i.name == $playerid status.player_name", 
				$cliCall{'name'} 
				eq 
				$cliCall2{'player_name'});
				
			# signalstrength
			my $sigstr = cliQueryNum($playerid, ['signalstrength']);
			my $sigstr2 = $cliCall2{'signalstrength'};
			if(defined $sigstr2) {
				# player must be a squeeze box or 2
				test_SubTest($tid, 
							"status.signalstrength reported for squeezeboxen",
							$model eq 'squeezebox' || $model eq 'squeezebox2'); 
				# must match $sigstr
				test_SubTest($tid, 
							"$playerid status.signalstrength == $playerid signalstrength ?",
							$sigstr2 == $sigstr); 
			}
			else {
				# player must not be a squeezebox
				test_SubTest($tid, 
							"status.signalstrength not reported for non-squeezeboxen",
							!($model eq 'squeezebox' || $model eq 'squeezebox2')); 				
			}
		}
	}
	test_Done($tid);
}

# ---------------------------------------------
# testDatabaseGenres()
# ---------------------------------------------
sub testDatabaseGenres {
	$gd_sub && p_sub("testDatabaseGenres()");

	# define test
	my $tid = test_New("genres query");
	
	# pre-conditions
	test_canConnect($tid);
	test_canDB($tid);

	
	if (test_canRun($tid)) {
		__testDatabaseGenreAlbumArtist($tid, 'genre');

	}

	test_Done($tid);
}

# ---------------------------------------------
# testDatabaseAlbums()
# ---------------------------------------------
sub testDatabaseAlbums {
	$gd_sub && p_sub("testDatabaseAlbums()");

	# define test
	my $tid = test_New("albums query");
	
	# pre-conditions
	test_canConnect($tid);
	test_canDB($tid);

	
	if (test_canRun($tid)) {
		__testDatabaseGenreAlbumArtist($tid, 'album');
	}

	test_Done($tid);
}

# ---------------------------------------------
# testDatabaseArtists()
# ---------------------------------------------
sub testDatabaseArtists {
	$gd_sub && p_sub("testDatabaseArtists()");

	# define test
	my $tid = test_New("artists query");
	
	# pre-conditions
	test_canConnect($tid);
	test_canDB($tid);

	
	if (test_canRun($tid)) {
		__testDatabaseGenreAlbumArtist($tid, 'artist');
	}

	test_Done($tid);
}

sub __callString {
	my $call = shift;
	my @params = @_;
	my $res = "${call}s";
	
	if (@params) {
		foreach my $p (@params) {
			$res .= " GID" if $p =~ /genre/;
			$res .= " AID" if $p =~ /artist/;
			$res .= " LID" if $p =~ /album/;
			$res .= " SEARCH" if $p =~ /search/;
		}
	}
	return $res;
}

sub __testDatabaseGenreAlbumArtist {
	my $tid = shift;
	my $call = shift;
	my @params = @_;

	$gd_sub && p_sub("__testDatabaseGenreAlbumArtist($tid, $call, @params)");

	$gd_subtest && print("\nTesting \"" . __callString($call, @params) . "\"\n");

	# get the suckers...
	my %DB;
	my %cliCall = cliGenresAlbumsArtists($call, undef, @params);
	my $num = $cliCall{'count'};
	for(my $i = 0; $i < $num; $i++) {
		%cliCall = cliGenresAlbumsArtists($call, $i, @params);
		$DB{$cliCall{$call}} = $cliCall{'id'};
	}
	
	if (!@params) {
		# At the top level, tests it matches simple call
		test_SubTest($tid, 
					__callString($call, @params) . ".count == info total ${call}s ?",
					$num == cliQueryNum(undef, ['info', 'total', "${call}s"])); 				
	}
	else {
		# Test we have more than 0
		test_SubTest($tid, 
					__callString($call, @params) . ".count > 0",
					$num > 0 ); 				
	}
	
	# Test we got them all
	test_SubTest($tid, 
				"Acquired $num (==" . __callString($call, @params) . ".count) ${call}s",
				$num == keys %DB); 				
		
	# Perform search
	my %DBsearch;
	my $searchparam;
	while (!defined $searchparam) {
		for my $key ( keys %DB ) {
			if (randomSmaller(5) == 4 && !($key =~ /\*/)) {
				$searchparam = $key;
				last;
			}
		}
	}
	my @paramsearch = @params;
	if (randomSmaller(2) == 1) {
		unshift @paramsearch, "search:$searchparam";
	}
	else {
		push @paramsearch, "search:$searchparam";
	}
	%cliCall = cliGenresAlbumsArtists($call, undef, @paramsearch);
	my $numsearch = $cliCall{'count'};

	for(my $i = 0; $i < $numsearch; $i++) {
		%cliCall = cliGenresAlbumsArtists($call, $i, @paramsearch);
		$DBsearch{$cliCall{$call}} = $cliCall{'id'};
	}

	# Test results
	# Found less than the whole
	test_SubTest($tid, 
				__callString($call, @paramsearch) . ".count <= " . __callString($call, @params) . ".count",
				$numsearch <= keys %DB); 				
	
	# And found my key
	# Don't want to re-implement here all SlimServer pattern matching!
	my $found = 0;
	for my $key ( keys %DBsearch ) {
		if ($key eq $searchparam) {
			$found = 1;
		}
	}
	test_SubTest($tid, 
				__callString($call, @paramsearch) . " \'$searchparam\' returns \'$searchparam\'",
				$found); 

	# Now test cross-references!
	my $totGenres = 0;
	my $totArtists = 0;
	my $totAlbums = 0;
	my $totSongs = 0;
	
	my $hasGenre = 0;
	my $hasArtist = 0;
	my $hasAlbum = 0;
	
	foreach my $p (@params) {
		$hasGenre = 1 if $p =~ /genre/;
		$hasArtist = 1 if $p =~ /artist/;
		$hasAlbum = 1 if $p =~ /album/;
	}
	
	my @params2;
	while ( my ($key, $value) = each(%DB) ) {

		# Add us to the params...
		@params2 = @params;
		if (randomSmaller(2) == 1) {
			unshift @params2, "${call}_id:$value";
		}
		else {
			push @params2, "${call}_id:$value";
		}

		if ($call ne 'genre' && !$hasGenre) {
			$totGenres += __testDatabaseGenreAlbumArtist($tid, 'genre', @params2);
		}
		if ($call ne 'artist' && !$hasArtist) {
			$totArtists += __testDatabaseGenreAlbumArtist($tid, 'artist', @params2);
		}
		if ($call ne 'album' && !$hasAlbum) {
			$totAlbums += __testDatabaseGenreAlbumArtist($tid, 'album', @params2);
		}
		{
			my %cliCall = cliTitles(undef, @params2);
			my $count = $cliCall{'count'};
			test_SubTest(	$tid, 
							__callString('title', @params2) . ".count > 0",
							$count > 0); 				
			$totSongs += $count;			
		}
		
	}

	# total
	# we can't test for equality because of 2 server preferences:
	# - include Composer/Band/etc in Artists => 1 song may have 2 artists
	# - multi-tag support

	if ($call ne 'artist' && !$hasArtist) {
		my %cliCall = cliGenresAlbumsArtists('artist', undef, @params);
		test_SubTest(	$tid, 
						"SUM " . __callString('artist', @params2) . ".count " .
						"($totArtists) >= " . __callString('artist', @params) .
						".count",
						$totArtists >= $cliCall{'count'}); 				
	}
	if ($call ne 'genre' && !$hasGenre) {
		my %cliCall = cliGenresAlbumsArtists('genre', undef, @params);
		test_SubTest(	$tid, 
						"SUM " . __callString('genre', @params2) . ".count " .
						"($totGenres) >= " . __callString('genre', @params) .
						".count",
						$totGenres >= $cliCall{'count'}); 				
	}
	if ($call ne 'album' && !$hasAlbum) {
		my %cliCall = cliGenresAlbumsArtists('album', undef, @params);
		test_SubTest(	$tid, 
						"SUM " . __callString('album', @params2) . ".count " .
						"($totAlbums) >= " . __callString('album', @params) .
						".count",
						$totAlbums >= $cliCall{'count'}); 				
	}
	{
		my %cliCall = cliTitles(undef, @params);
		test_SubTest(	$tid, 
						"SUM " . __callString('title', @params2) . ".count " .
						"($totSongs) >= " . __callString('title', @params) .
						".count",
						$totSongs >= $cliCall{'count'}); 				
	}

	return $num;
}

# ---------------------------------------------
# testDatabaseTitles()
# ---------------------------------------------
sub testDatabaseTitles {
	$gd_sub && p_sub("testDatabaseTitles()");

	# define test
	my $tid = test_New("titles query");
	
	# pre-conditions
	test_canConnect($tid);
	test_canDB($tid);
	
	if (test_canRun($tid)) {
	
		$gd_subtest && print("\nTesting titles, database dumped, please stand by...\n");

		my $num = __testDatabaseDumpDB($tid);

		# Test it matches simple call
		test_SubTest($tid, "titles.count == info total songs ?",
					 $num == cliQueryNum(undef, ['info', 'total', "songs"])); 				
			
		# Perform 10 searches
		$gd_subtest && print("\nTesting titles SEARCH for 10 random songs...\n");
		my %keys;
		$keys{'count'}=0;
		while ($keys{'count'} < 10) {
			my $searchtitle;
			my $idtitle;
			while (!defined $searchtitle) {
				while ( my ($key, $value) = each(%gDBtitles) ) {
					if (randomSmaller(50) > 48 && !($value =~ /\*/) && !defined($keys{$value})) {
						$searchtitle = $value;
						$idtitle = $key;
						$keys{$value} = 1;
						$keys{'count'}++;
						last;
					}
				}
			}
			my %cliCall = cliTitles(undef, "search:$searchtitle", "tags:pse");
			my $numsearch = $cliCall{'count'};
		
			my $match = 1;
			for(my $i = 0; $i < $numsearch; $i++) {
				%cliCall = cliTitles($i, "search:$searchtitle", "tags:pse");

				if (!defined $cliCall{'artist_id'}) {
					syntaxReport('titles tags:pse', "mandatory field \'artist_id\' is not reported");
				}
				elsif (!defined $cliCall{'genre_id'}) {
					syntaxReport('titles tags:pse', "mandatory field \'genre_id\' is not reported");
				}
				elsif (!defined $cliCall{'album_id'}) {
					syntaxReport('titles tags:pse', "mandatory field \'album_id' is not reported");
				}
				elsif ($cliCall{'id'} eq $idtitle) {
					$match = ($gDBtitles{$cliCall{'id'}} eq $cliCall{'title'}) &&
							 ($gDBartist{$cliCall{'id'}} == $cliCall{'artist_id'}) &&
							 ($gDBgenre{$cliCall{'id'}} == $cliCall{'genre_id'}) &&
							 ($gDBalbum{$cliCall{'id'}} == $cliCall{'album_id'});
					last;
				}
			}
	
			# Test results
			# Found less than the whole
			test_SubTest($tid, "titles SEARCH.count <= titles.count",
						 $num <= keys %gDBtitles); 				
			
			# And found my key
			# Don't want to re-implement here all SlimServer pattern matching!
			test_SubTest($tid, 
						"titles SEARCH \'$searchtitle\' returns \'$searchtitle\'",
						$match); 
		} 


		$gd_subtest && print("\nTesting titles TAGS...\n");
		# Now for each of our field, try to see if tags work
		while ( my ($field, $opt) = each(%gsonginfoFields) ) {
			if ($opt eq 'zz') {
				next;
			}
			if (!defined $gDBopt{$field}) {
				test_SubTest($tid, "titles TAG:" .
									$gsonginfoFields{$field} . 
									"-$field", 'skip', 
									"none found in DB");				
			}
			else {
			
				# can't access titles by track_id. Find out the AID/LID/GID
				# from the TID...
				my $TID = $gDBopt{$field};
				my $LID = $gDBalbum{$TID};
				my $AID = $gDBartist{$TID};
				my $GID = $gDBgenre{$TID};
				
				# can we find it again?
				my %cliCall = cliTitles(undef, 
										"album_id:" . $LID,
										"genre_id:" . $GID, 
										"artist_id:" . $AID, 
										"tags:" . $gsonginfoFields{$field});
				my $num = $cliCall{'count'};
				for(my $i = 0; $i < $num; $i++) {
					%cliCall = cliTitles($i, 
										 "album_id:" . $LID,
										 "genre_id:" . $GID, 
										 "artist_id:" . $AID, 
										 "tags:" . $gsonginfoFields{$field});
					
					if ($cliCall{'id'} eq $TID) {
						test_SubTest($tid, 
							"titles AID:$AID GID:$GID LID:$LID TAG:" .
							$gsonginfoFields{$field} . 
							" returns expected tag \'$field\' (TID:$TID): " . 
							(defined $cliCall{$field}?$cliCall{$field}:"") . ")",
							defined $cliCall{$field});
					}
				}

				# is it not present if we don't request it?
				%cliCall = cliTitles(undef, 
										"album_id:" . $LID,
										"genre_id:" . $GID, 
										"artist_id:" . $AID, 
										"tags:");
				$num = $cliCall{'count'};
				for(my $i = 0; $i < $num; $i++) {
					%cliCall = cliTitles($i, 
										 "album_id:" . $LID,
										 "genre_id:" . $GID, 
										 "artist_id:" . $AID, 
										 "tags:");
					
					if ($cliCall{'id'} eq $TID) {
						test_SubTest($tid, 
							"titles AID:$AID GID:$GID LID:$LID TAG: does not return tag",
							!defined $cliCall{$field});
					}
				}
			}
		}
		
		# Compare full songinfo data with full titles data
		# for random songs.
		# Use URL and TID for songinfo access.	

		$gd_subtest && print("\nTesting titles AID SORT...\n");
		# titles AID SORT
		# select the album we know we have tracks for!
		my $TID = $gDBopt{'tracknum'};
		my $LID = $gDBalbum{$TID};
		my %cliCall = cliTitles(undef, "album_id:$LID", "sort:tracknum");
		$num = $cliCall{'count'};
		my $sorted = 1;
		my $lastTN = 0;
		for(my $i = 0; $i < $num; $i++) {
			%cliCall = cliTitles($i, "album_id:$LID", "sort:tracknum");

			if ($cliCall{'id'} == $TID) {
				# we want a tracknum here
				test_SubTest($tid, 
					"titles LID:$LID SORT:tracknum returns \'tracknum\' field",
					defined $cliCall{'tracknum'}); 
			}
			
			if (defined $cliCall{'tracknum'}){
			
				$sorted &&= ($cliCall{'tracknum'} >= $lastTN);			
				$lastTN = $cliCall{'tracknum'};
#				print($lastTN . "\n");
			}
		}
		test_SubTest($tid, 
			"titles LID:$LID SORT:tracknum returns songs sorted by \'tracknum\' field",
			$sorted); 
	}

	test_Done($tid);
}

# ---------------------------------------------
# testDatabaseSonginfo()
# ---------------------------------------------
sub testDatabaseSonginfo {
	$gd_sub && p_sub("testDatabaseSonginfo()");

	# define test
	my $tid = test_New("songinfo query");
	
	# pre-conditions
	test_canConnect($tid);
	test_canDB($tid);
	
	if (test_canRun($tid)) {

		my $num = __testDatabaseDumpDB($tid);



		$gd_subtest && print("\nTesting songinfo data matches title data...\n");
		# For each of our field, try to see if tags work AND if 
		# we get the same data from songinfo than from title
		while ( my ($field, $opt) = each(%gsonginfoFields) ) {
		
			next if ($opt eq 'zz');
			
			if (defined $gDBopt{$field}) {
			
				# can't access titles by track_id. Find out the AID/LID/GID
				# from the TID...
				my $TID = $gDBopt{$field};
				my $LID = $gDBalbum{$TID};
				my $AID = $gDBartist{$TID};
				my $GID = $gDBgenre{$TID};
				
				# find the title data
				my %cliCall = cliTitles(undef, 
										"album_id:" . $LID,
										"genre_id:" . $GID, 
										"artist_id:" . $AID, 
										"tags:abcdefghijklmnopqrstuvwxyz");
				my $num = $cliCall{'count'};
				for(my $i = 0; $i < $num; $i++) {
					%cliCall = cliTitles($i, 
										 "album_id:" . $LID,
										 "genre_id:" . $GID, 
										 "artist_id:" . $AID, 
										 "tags:abcdefghijklmnopqrstuvwxyz");
					
					if ($cliCall{'id'} eq $TID) {
					
						# for this TID, test songinfo...
						
						my $same = 1;
						
						# save %cliCall...
						my %titleData = %cliCall;
					
						%cliCall = cliSonginfo("track_id:" . $TID, "tags:abcdefghijklmnopqrstuvwxyz");
						
						for my $eachfield (keys %cliCall) {
							next if ($eachfield eq 'count');
							$same &&= ($cliCall{$eachfield} eq $titleData{$eachfield});
						}
						for my $eachfield (keys %titleData) {
							next if ($eachfield eq 'count');
							$same &&= ($cliCall{$eachfield} eq $titleData{$eachfield});
						}

						test_SubTest($tid, 
							"songinfo TID == title for TID:$TID",
							$same); 
							
						#test with URL
						$same = 1;
						%cliCall = cliSonginfo("url:" . $titleData{'url'}, "tags:abcdefghijklmnopqrstuvwxyz");
						
						for my $eachfield (keys %cliCall) {
							next if ($eachfield eq 'count');
							$same &&= ($cliCall{$eachfield} eq $titleData{$eachfield});
						}
						for my $eachfield (keys %titleData) {
							next if ($eachfield eq 'count');
							$same &&= ($cliCall{$eachfield} eq $titleData{$eachfield});
						}

						test_SubTest($tid, 
							"songinfo URL == title for TID:$TID",
							$same); 

					}
				}
			}
		}
		
		$gd_subtest && print("\nTesting songinfo TAGS...\n");
		# For each of our field, try to see if tags work AND if 
		# we get the same data from songinfo than from title
		while ( my ($field, $opt) = each(%gsonginfoFields) ) {
			if ($opt eq 'zz') {
				next;
			}
			if (!defined $gDBopt{$field}) {
				test_SubTest($tid, "songinfo TAG:" .
									$gsonginfoFields{$field} . 
									"-$field", 'skip', 
									"none found in DB");				
			}
			else {
				my %cliCall = cliSonginfo("track_id:" . $gDBopt{$field}, "tags:" . $gsonginfoFields{$field});
				test_SubTest($tid, 
							"songinfo TID TAG:" . $gsonginfoFields{$field} .
							" returns expected tag \'$field\' (TID:" . $gDBopt{$field} . "): " . 
							(defined $cliCall{$field}?$cliCall{$field}:"") . ")",
							defined $cliCall{$field});

				%cliCall = cliSonginfo("track_id:" . $gDBopt{$field}, "tags:");
				if ($field eq 'url') {
					test_SubTest($tid, 
								"songinfo TID TAG:" .
								" returns tag anyway (url is default)",
								defined $cliCall{$field});
					%cliCall = cliSonginfo("url:" . $cliCall{$field}, "tags:");
					test_SubTest($tid, 
								"songinfo URL TAG: does not return URL",
								!defined $cliCall{$field});
					
					
				}
				else {
					test_SubTest($tid, 
								"songinfo TID TAG: does not return tag",
								!defined $cliCall{$field});
				}						
			}
		}		
	}
	test_Done($tid);
}


sub __testDatabaseDumpDB {
	my $tid = shift;

	$gd_sub && p_sub("__testDatabaseDumpDB()");

	
	if (!keys %gDBtitles) {
	
		$gd_subtest && print("\nDumping database... this is very long, hang on...\n");
		
		# get the suckers. Ask for everything and remember which tracks have
		# which features...
		my %cliCall = cliTitles();
		my $num = $cliCall{'count'};
		for(my $i = 0; $i < $num; $i++) {
			$gd_subtest && ($i % 10 == 0) && print("Dumping database... $i of $num\n");
			%cliCall = cliTitles($i, "tags:abcdefghijklmnopqrstuvwxyz");
			# implicit check "title" and "id" are defined...
			$gDBtitles{$cliCall{'id'}} = $cliCall{'title'};
			$gDBartist{$cliCall{'id'}} = $cliCall{'artist_id'};
			$gDBalbum{$cliCall{'id'}} = $cliCall{'album_id'};
			$gDBgenre{$cliCall{'id'}} = $cliCall{'genre_id'};
			while ( my ($field, $opt) = each(%gsonginfoFields) ) {
				if ($opt eq 'zz') {
					if (!defined $cliCall{$field}) {
						syntaxReport('titles', "mandatory field \'$field\' is not reported");
					}
				}
				elsif (defined $cliCall{$field}) {
					# remember tag
					if (!defined $gDBopt{$field} || (randomSmaller(50) > 48)) {
						$gDBopt{$field} = $cliCall{'id'};
					}
				}
			}
		}
	}
	$gd_subtest && print("Dumping database... done\n\n");
	return scalar(keys %gDBtitles);
}
# ---------------------------------------------
# testDatabaseRescan()
# ---------------------------------------------
sub testDatabaseRescan {
	$gd_sub && p_sub("testDatabaseRescan()");

	# define test
	my $tid = test_New("Testing rescan & wipecache");
	
	# pre-conditions
	test_canConnect($tid);
	test_canPlayers($tid, 0);
	
	if (test_canRun($tid)) {
		
		# Do a wipecache first to get stable state
		$gd_subtest && print("\nTesting wipecache, issuing one first to get stable state...\n");
		cliCommand(undef, ['wipecache']);
		
		# Test it is reported
		__testDatabaseRescanNotif($tid, 'wipecache');

		# Wait till done
		__testDatabaseRescanWaitDone('wipecache');
		$gd_subtest && print "wipecache complete\n";

		# Note total of artists/songs/usw
		my $totArtists = cliQueryNum(undef, ['info', 'total', 'artists']);
		my $totAlbums = cliQueryNum(undef, ['info', 'total', 'albums']);
		my $totGenres = cliQueryNum(undef, ['info', 'total', 'genres']);
		my $totSongs = cliQueryNum(undef, ['info', 'total', 'songs']);
		
		# Do a wipecache again and compare totals.
		$gd_subtest && print("\nTesting wipecache, check state is stable...\n");
		
		cliCommand(undef, ['wipecache']);
		__testDatabaseRescanNotif($tid, 'wipecache');
		__testDatabaseRescanWaitDone('wipecache');
		$gd_subtest && print "wipecache complete\n";

		my $newSongs = cliQueryNum(undef, ['info', 'total', 'songs']);
		my $newArtists = cliQueryNum(undef, ['info', 'total', 'artists']);
		my $newAlbums = cliQueryNum(undef, ['info', 'total', 'albums']);
		my $newGenres = cliQueryNum(undef, ['info', 'total', 'genres']);
		
		test_SubTest(	$tid, "wipecache => no change in total songs (before: $totSongs, after: $newSongs)",
						$totSongs == $newSongs);
		test_SubTest(	$tid, "wipecache => no change in total artists (before: $totArtists, after: $newArtists)",
						$totArtists == $newArtists);
		test_SubTest(	$tid, "wipecache => no change in total albums (before: $totAlbums, after: $newAlbums)",
						$totAlbums == $newAlbums);
		test_SubTest(	$tid, "wipecache => no change in total genres (before: $totGenres, after: $newGenres)",
						$totGenres == $newGenres);

		# Same for rescan...
		$gd_subtest && print("\nTesting rescan, check state is stable...\n");
		cliCommand(undef, ['rescan']);
		__testDatabaseRescanNotif($tid, 'rescan');
		__testDatabaseRescanWaitDone('rescan');
		$gd_subtest && print "rescan complete\n";

		$newSongs = cliQueryNum(undef, ['info', 'total', 'songs']);
		$newArtists = cliQueryNum(undef, ['info', 'total', 'artists']);
		$newAlbums = cliQueryNum(undef, ['info', 'total', 'albums']);
		$newGenres = cliQueryNum(undef, ['info', 'total', 'genres']);
		
		test_SubTest(	$tid, "wipecache => no change in total songs (before: $totSongs, after: $newSongs)",
						$totSongs == $newSongs);
		test_SubTest(	$tid, "wipecache => no change in total artists (before: $totArtists, after: $newArtists)",
						$totArtists == $newArtists);
		test_SubTest(	$tid, "wipecache => no change in total albums (before: $totAlbums, after: $newAlbums)",
						$totAlbums == $newAlbums);
		test_SubTest(	$tid, "wipecache => no change in total genres (before: $totGenres, after: $newGenres)",
						$totGenres == $newGenres);
		
		
		# Test issuing wipecache while it is in progress..
		$gd_subtest && print("\nTesting wipecache, issuing one while in progress...\n");
		cliCommand(undef, ['wipecache']);
		__testDatabaseRescanNotif($tid, 'wipecache');
		cliCommand(undef, ['wipecache']);
		__testDatabaseRescanNotif($tid, 'wipecache');
		__testDatabaseRescanWaitDone('wipecache');
		$gd_subtest && print "wipecache complete\n";
	}

	test_Done($tid);
}

sub __testDatabaseRescanNotif {
	my $tid = shift;
	my $call = shift;
	my %cliCall;
	%cliCall = cliGenresAlbumsArtists('artist');
	test_SubTest(	$tid, 
					"$call => artists.rescan defined",
					defined $cliCall{'rescan'});
	%cliCall = cliGenresAlbumsArtists('album');
	test_SubTest(	$tid, 
					"$call => albums.rescan defined",
					defined $cliCall{'rescan'});
	%cliCall = cliGenresAlbumsArtists('genre');
	test_SubTest(	$tid, 
					"$call => genres.rescan defined",
					defined $cliCall{'rescan'});
	%cliCall = cliTitles();
	test_SubTest(	$tid, 
					"$call => titles.rescan defined",
					defined $cliCall{'rescan'});
	%cliCall = cliPlaylists();
	test_SubTest(	$tid, 
					"$call => playlists.rescan defined",
					defined $cliCall{'rescan'});
	%cliCall = cliSonginfo();
	test_SubTest(	$tid, 
					"$call => songinfo.rescan defined",
					defined $cliCall{'rescan'});
	test_SubTest(	$tid, 
					"$call => rescan ? == 1",
					cliQueryFlag(undef, ['rescan']));
	foreach my $playerid (@gplayers) {
		%cliCall = cliStatus($playerid);
		test_SubTest(	$tid, 
						"$call => $playerid status.rescan defined",
						defined $cliCall{'rescan'});
		%cliCall = cliPlaylistcontrol($playerid);
		test_SubTest(	$tid, 
						"$call => $playerid playlistcontrol.rescan defined",
						defined $cliCall{'rescan'});
	}
}

sub __testDatabaseRescanWaitDone {
	my $call = shift;	

	until (!cliQueryFlag(undef, ['rescan'])) {
		$gd_subtest && print "Waiting for $call to complete...\n";
		sleep 5;
	}
}



# ******************************************************************************
# Subroutines (utility functions)
# ******************************************************************************

# ---------------------------------------------
# test_New
# ---------------------------------------------
sub test_New {
	my $name = shift;

	$gd_sub && p_sub("test_New($name)");
	
	#add test to db as starting
	$gtest_db{$name} = 0;
	
	#print test name if desired
	$gd_test && test_Print($name);
	
	#done, name is the test ID
	return $name;
}

# ---------------------------------------------
# test_Done
# ---------------------------------------------
sub test_Done {
	my $tid = shift;
	
	$gd_sub && p_sub("test_Done($tid)");

	# the test must be defined
	if (defined $gtest_db{$tid}) {	
		$gd_test && test_PrintResult($tid);
	}
	else {
		# something is wrong...
		p_err("test_Done called on undefined test $tid");
	}		
}

# ---------------------------------------------
# test_Print
# ---------------------------------------------
sub test_Print {
	my $tid = shift;
	
	$gd_sub && p_sub("test_Print($tid)");

	print("\n*****\n* $tid\n*****\n");
}

# ---------------------------------------------
# test_PrintResult
# ---------------------------------------------
sub test_PrintResult {
	my $tid = shift;
	
	$gd_sub && p_sub("test_PrintResult($tid)");

	if ($gtest_db{$tid} == 3) {
		print("\n* $tid: SUCCESS\n");
	}
	elsif ($gtest_db{$tid} == 4) {
		print("\n* $tid: PARTIAL SUCCESS, " . $gtest_dbcomment{$tid} . "\n");		
	}
	elsif ($gtest_db{$tid} == 2) {
		print("\n* $tid: FAILED, " . $gtest_dbcomment{$tid} . "\n");		
	}
	elsif ($gtest_db{$tid} == 1) {
		print("\n* $tid: SKIPPED, " . $gtest_dbcomment{$tid} . "\n");		
	}	
	else {
		p_err("testPrintResult called on undefined/starting test $tid");
	}
}

# ---------------------------------------------
# test_canRun
# ---------------------------------------------
sub test_canRun {
	my $tid = shift;
	
	$gd_sub && p_sub("test_canRun($tid)");

	# the test must be defined
	if (defined $gtest_db{$tid}) {
		if ($gtest_db{$tid} == 0) {
			return 1;
		}
	}
	else {
		# something is wrong...
		p_err("test_canRun called on undefined test $tid");
	}		
}

# ---------------------------------------------
# test_canConnect
# ---------------------------------------------
sub test_canConnect {
	my $tid = shift;

	$gd_sub && p_sub("test_canConnect($tid)");
	
	# the test must be defined
	if (defined $gtest_db{$tid}) {
		if ($gtest_db{$tid} == 0) {
		
			# we must connect or be connected
			if (!cliConnect()) {
		
				# cannot connect..., skip test
				$gtest_db{$tid} = 1;
				$gtest_dbcomment{$tid} = "cannot connect";
			}
		}
		else {
			# something's wrong if different from 1, i.e. skipped
			if ($gtest_db{$tid} != 1) {
				p_err("Precondition error for test: $tid, db state:" . $gtest_db{$tid});
			}
		}
	}
	else {
		# something is wrong...
		p_err("Precondition error for test: $tid, db state undefined");
	}
}

# ---------------------------------------------
# test_canPlayers
# ---------------------------------------------
sub test_canPlayers {
	my $tid = shift;
	my $needed = shift;
	
	$needed = 1 unless defined $needed;

	$gd_sub && p_sub("test_canPlayers($tid)");
	
	# the test must be defined
	if (defined $gtest_db{$tid}) {
		if ($gtest_db{$tid} == 0) {
		
			# we must have players
			if (! scalar @gplayers) {
				my %cliCall = cliPlayers();
				my $num = $cliCall{'count'};
				for(my $i = 0; $i < $num; $i++) {
					%cliCall = cliPlayers($i);
					$gplayers[$i] = $cliCall{'playerid'};
				}
			}
			if (scalar @gplayers < $needed) {
		
				# no players..., skip test
				$gtest_db{$tid} = 1;
				$gtest_dbcomment{$tid} = "not enough players found, needed $needed";
			}
		}
		else {
			# something's wrong if different from 1, i.e. skipped
			if ($gtest_db{$tid} != 1) {
				p_err("Precondition error for test: $tid, db state:" . $gtest_db{$tid});
			}
		}
	}
	else {
		# something is wrong...
		p_err("Precondition error for test: $tid, db state undefined");
	}
}

# ---------------------------------------------
# test_canDB
# ---------------------------------------------
sub test_canDB {
	my $tid = shift;
	my $needed = shift;
	
	$needed = 1 unless defined $needed;

	$gd_sub && p_sub("test_canDB($tid)");
	
	# the test must be defined
	if (defined $gtest_db{$tid}) {
		if ($gtest_db{$tid} == 0) {
			
			# if we're scanning, wait till it's done...
			__testDatabaseRescanWaitDone('rescan');
		
			# we must have songs
			my $songs = cliQueryNum(undef, ['info', 'total', 'songs']);
			if ($songs < $needed) {
		
				# no songs..., skip test
				$gtest_db{$tid} = 1;
				$gtest_dbcomment{$tid} = "not enough songs found, needed $needed";
			}
		}
		else {
			# something's wrong if different from 1, i.e. skipped
			if ($gtest_db{$tid} != 1) {
				p_err("Precondition error for test: $tid, db state:" . $gtest_db{$tid});
			}
		}
	}
	else {
		# something is wrong...
		p_err("Precondition error for test: $tid, db state undefined");
	}
}

# ---------------------------------------------
# test_PrintReport
# ---------------------------------------------
sub test_PrintReport {
	print "\n";
	
	my $first = 0;
	for my $sid (keys %gsyntaxTests) {
		if ($first == 0) {
			print("SYNTAX ERRORS:\n");
			$first = 1;
		}
		print("-- $sid: " . $gsyntaxTests{$sid} . "\n");
	}
	
	$first = 0;
	for my $tid (keys %gtest_db) {
		if ($first == 0) {
			print("\nTEST RESULTS:\n");
			$first = 1;
		}
		if ($gtest_db{$tid} == 0) {
			#strange...
			print("--ERROR: $tid: should not be still starting here!\n");
		}
		elsif ($gtest_db{$tid} == 1) {
			print("--SKIPPED: $tid: " . $gtest_dbcomment{$tid} . "\n");
		}
		elsif ($gtest_db{$tid} == 2) {
			print("--FAILED: $tid: " . $gtest_dbcomment{$tid} . "\n");
		}
		elsif ($gtest_db{$tid} == 3) {
			print("--SUCCESS: $tid\n");
		}
		elsif ($gtest_db{$tid} == 4) {
			print("--PARTIAL SUCCESS: $tid: " . $gtest_dbcomment{$tid} . "\n");
		}
	
	}
}

# ---------------------------------------------
# test_SubTest
# ---------------------------------------------
sub test_SubTest {
	my $tid = shift;
	my $subtest = shift;
	my $result = shift;
	my $reason = shift;

	$gd_sub && p_sub("test_SubTest($tid)");
	
	if (!defined($result) || !$result) {
		$gd_subtest && print("# FAILED: $subtest\n");
	}
	elsif ($result eq 'skip') {
		$gd_subtest && print("# SKIPPED: $subtest - $reason\n");
	}
	else {
		$gd_subtest && print("# SUCCESS: $subtest\n");
	}
	
	# the test must be defined
	if (defined $gtest_db{$tid}) {
		#can be starting or successful
		if ($gtest_db{$tid} == 0 || $gtest_db{$tid} == 3 || $gtest_db{$tid} == 4) {
		
			# if succeeded
			if ($result eq 'skip') {		
				# set to success skip
				$gtest_db{$tid} = 4;
				if ($gtest_dbcomment{$tid}) {
					$gtest_dbcomment{$tid} .= " & skipped: [" . $subtest . ":" . $reason . "]";
				}
				else {
					$gtest_dbcomment{$tid} .= "Skipped: [" . $subtest . ":" . $reason . "]";
				}
			}
			elsif ($result) {		
				# set to success if not to skip
				$gtest_db{$tid} = 3 if !($gtest_db{$tid} == 4);
			}
			else {
				# set to failed
				$gtest_db{$tid} = 2;
				if ($gtest_dbcomment{$tid}) {
					$gtest_dbcomment{$tid} .= " & failed: [" . $subtest ."]";
				}
				else {
					$gtest_dbcomment{$tid} = "Failed: [" . $subtest ."]";
				}
			}
		}
	}
	else {
		# something is wrong...
		p_err("test_SubTest called on undefined test $tid");
	}
}

# ---------------------------------------------
# tcpConnect
# ---------------------------------------------
sub tcpConnect {
	$gd_sub && p_sub("tcpConnect()");
	
	return 1 if defined $gsocket;
	
	$gsocket = IO::Socket::INET->new(PeerAddr => $gserver, 
									PeerPort => $gport, 
									Proto => "tcp", 
									Type => SOCK_STREAM);

	if (defined $gsocket) {
		$gd_tcp && print(":: TCP connected to $gserver:$gport\n");
	}
	else {
		print("!: Cannot TCP connect to $gserver:$gport\n");
	}

	return (defined $gsocket);
}

# ---------------------------------------------
# tcpDisconnect
# ---------------------------------------------
sub tcpDisconnect {
	$gd_sub && p_sub("tcpDisconnect()");
	if(defined $gsocket) {
		close($gsocket);
	}
	$gsocket = undef;
}

# ---------------------------------------------
# tcpSendReceive
# ---------------------------------------------
sub tcpSendReceive
{
	my $string = shift;

	$gd_sub && p_sub("tcpSendReceive()");
	
	return undef if !defined $gsocket;
	
	$gd_tcp && p_tcp($string);
	
	print $gsocket "$string";

	my $answer = <$gsocket>;

	if (defined($answer))
	{
		$gd_tcp && p_tcp($answer);
	}
	else {
		$gd_tcp && p_tcp("<disconnected>");
		tcpDisconnect();
	}
	return $answer;
}


# ---------------------------------------------
# cliConnect
# ---------------------------------------------
sub cliConnect {
	my $force_nologin = shift;
	
	$gd_sub && p_sub("cliConnect()");

	return 1 if $gcli;

	if ($gcli = tcpConnect()) {
		if(defined $guser && !defined $force_nologin) {
			# login required...
			$gcli = cliLogin($guser, $gpwd);
			
			if(!$gcli) {
				print("!: Cannot CLI connect: login error\n");
			}
		}
		my $version = "Unknown";
		if ($gcli) {
			# ask for version, just to check if login is in fact needed!
				$version = cliQuery(undef, ['version']);
		
			if (!defined $version) {
				$gcli = 0;
				print("!: Cannot CLI connect: is security on?\n");
			}
		}

		if ($gcli) {
			$gd_cli && print(":: CLI connected with server version $version\n");
		}
		else {
			tcpDisconnect();
		}
	}
	else {
		print("!: Cannot CLI connect: TCP error\n");	
	}
	
	return $gcli;
}

# ---------------------------------------------
# cliDisconnect
# ---------------------------------------------
sub cliDisconnect {
	$gd_sub && p_sub("cliDisconnect()");
	if($gcli) {
		cliSendReceive(undef, ['exit']);
		tcpDisconnect();
		$gd_cli && print(":: CLI disconnected\n");
	}
	$gcli = undef;
}

# ---------------------------------------------
# cliSendReceive
# ---------------------------------------------
sub cliSendReceive
{
	my $client = shift;
	my $paramsRef = shift;

	my @paramsOutput = @$paramsRef;	
	my $output;
	my $printoutput;

	$gd_sub && p_sub("cliSendReceive()");
	
	return undef if !$gcli;
		
	$printoutput = join("<>", @$paramsRef);
	
	foreach my $param (@paramsOutput) {
		$param = uri_escape($param);
	}

	$output = join(" ", @paramsOutput);

	if(defined($client)) {
		$output = uri_escape($client) . " " . $output;
		$printoutput = $client . "<>" . $printoutput;
	}
	
	$gd_cli && print(">: \"$printoutput\"\n");
	
	$output .= $gterm;
	
	my $answer = tcpSendReceive($output);
	
	if (defined($answer))
	{
		$answer =~ s/$CR?$LF/\n/;
		chomp $answer; 

		my @results = split(" ", $answer);
	
		foreach my $result (@results) {
			$result = Encode::decode_utf8(uri_unescape($result));
		}

		$printoutput = join("<>", @results);
		$gd_cli && print "<: \"$printoutput\"\n";
		return @results;
	}
	else {
		$gd_cli && print ("<: <disconnected>\n");
		return undef;
	}
}

# ---------------------------------------------
# cliCommand
# ---------------------------------------------
sub cliCommand {
	# Handles regular CLI commands (i.e. not extended)
	my $client = shift;
	my $paramsRef = shift;

	$gd_sub && p_sub("cliCommand()");

	my $command = @$paramsRef[0];

	my @results = cliSendReceive($client, $paramsRef);
	
	if (@results && defined $results[0]) {
	
		if(defined($client)) {
			shift(@results);
		}
	
		my $test = (scalar(@results) == scalar(@$paramsRef));
		
		for(my $i = 0; $i < scalar(@results) && $test; $i++)
		{
			$test = $test && (@$paramsRef[$i] eq $results[$i]);
		}
		
		if (!$test) {
			syntaxReport($command, 'syntax error '. join("<>", @$paramsRef) . " -> " . join ("<>", @results));
		}
		
		return $test;
	}
	return 0;
}

# ---------------------------------------------
# cliLogin
# ---------------------------------------------
sub cliLogin {
	# Handles regular CLI commands (i.e. not extended)
	my $user = shift;
	my $pwd = shift;

	$gd_sub && p_sub("cliLogin()");

	my @params;
	
	push @params, "login";
	push @params, $user;
	push @params, $pwd if defined $pwd;

	my @results = cliSendReceive(undef, \@params);
	
	if (@results && defined $results[0]) {
		
		my $test = $results[0] eq $params[0];
		$test = $test && ($results[1] eq $params[1]);
		if (defined $pwd) {
			$test = $test && defined $results[2];
		}
		
		if (!$test) {
			syntaxReport('login', 'syntax error '. join("<>", @params) . " -> " . join ("<>", @results));
		}
		return $test;
	}
	return 0;
}

# ---------------------------------------------
# cliQuery
# ---------------------------------------------
sub cliQuery {
	# Handles regular CLI queries (i.e. not extended)
	my $client = shift;
	my $paramsRef = shift;
	my $result;
	
	$gd_sub && p_sub("cliQuery()");

	push @$paramsRef, '?';

	my @results = cliSendReceive($client, $paramsRef);
	
	if (@results && defined $results[0]) {
	
		if(defined($client)) {
			shift(@results);
		}
	
		my $test = (scalar(@results) == scalar(@$paramsRef));
		
		for(my $i = 0; $i < scalar(@results) && $test; $i++)
		{
			if (@$paramsRef[$i] eq '?') {
				$result = $results[$i];
			}
			else {
				$test = $test && (@$paramsRef[$i] eq $results[$i]);
			}
		}
		
		if (!$test) {
			syntaxReport('Returned data mismatch', join("<>", @$paramsRef) . " -> " . join ("<>", @results));
		}
		
		return $result;
	}
	return undef;
}

# ---------------------------------------------
# cliQueryNum
# ---------------------------------------------
sub cliQueryNum
{
	my $client = shift;
	my $paramsRef = shift;

	$gd_sub && p_sub("cliQueryNum()");
	
	my $num = cliQuery($client, $paramsRef);
	if (!checkType($num, 'num')) {
		syntaxReport('Returned value not a number', join("<>", @$paramsRef) . " -> " . $num);
	}
	return $num;
}

# ---------------------------------------------
# cliQueryFlag
# ---------------------------------------------
sub cliQueryFlag
{
	my $client = shift;
	my $paramsRef = shift;

	$gd_sub && p_sub("cliQueryFlag()");
	
	my $flag = cliQueryNum($client, $paramsRef);
	if (!checkType($flag, 'flag')) {
		syntaxReport('Returned value not a flag', join("<>", @$paramsRef) . " -> " . $flag);
	}
	return $flag;
}

# ---------------------------------------------
# cliQuery
# ---------------------------------------------
sub cliQueryDual
{
	# Handles regular CLI queries (i.e. not extended)
	# Special case for commands taking two ? arguments (display and displaynow)
	my $client = shift;
	my $paramsRef = shift;

	$gd_sub && p_sub("cliQueryDual()");

	push @$paramsRef, '?';
	push @$paramsRef, '?';
	
	my @results = cliSendReceive($client, $paramsRef);

	if (@results && defined $results[0]) {
	
		if(defined($client)) {
			shift(@results);
		}
	
		# For some reason display ? ? returns both lines in the first argument....
		my $test = (scalar(@results) <= scalar(@$paramsRef));
		my @result;
		
		for(my $i = 0; $i < scalar(@results); $i++) {
			if(@$paramsRef[$i] eq '?') {
				push @result, $results[$i];
			}
			else {
				$test = $test && (@$paramsRef[$i] eq $results[$i]);
			}
		}
		
		if(!$test || !@result) {
			syntaxReport('Returned data mismatch', join("<>", @$paramsRef) . " -> " . join ("<>", @results));
		}
		return @result;
	}
	return undef;
}

# ---------------------------------------------
# cliQuerySync
# ---------------------------------------------
sub cliQuerySync
{
	# Handles regular CLI queries (i.e. not extended)
	# Special case sync since the command sync ? does not return anything replacing ?
	# if the player is not synced. Should return -, i.e. what needs to be 
	# sent to unsync...
	my $client = shift;
	my $paramsRef = shift;
	my $result;
	
	push @$paramsRef, '?';
	
	my @results = cliSendReceive($client, $paramsRef);
	
	if (@results && defined $results[0]) {
	
		if(defined($client)) {
			shift(@results);
		}
	
		my $test = 1;
	
		my $numResults = scalar(@results);
	
		for(my $i = 0; $i < $numResults; $i++) {
			if(@$paramsRef[$i] eq '?') {
				$result = $results[$i];
			}
			else {
				$test = $test && (@$paramsRef[$i] eq $results[$i]);
			}
		}
		
		if (!defined($result)) {
			$result = "-";
		}

		if (!$test) {
			syntaxReport('Returned data mismatch', join("<>", @$paramsRef) . " -> " . join ("<>", @results));
		}
		
		return $result;
	}
	return undef;
}


# ---------------------------------------------
# cliExtCommand
# ---------------------------------------------
sub cliExtCommand
{
	# Handles regular extended CLI queries & commands
	my $client = shift;
	my $paramsRef = shift;
	
	$gd_sub && p_sub("cliExtCommand()");

	my @results = cliSendReceive($client, $paramsRef);
	
	if (@results && defined $results[0]) {
	
		if(defined($client)) {
			shift(@results);
		}
	
		my $test = (scalar(@results) >= scalar(@$paramsRef));
		
		for(my $i = 0; $i < scalar(@results) && $test; $i++)
		{
			if ($i < scalar(@$paramsRef)) {
				$test = $test && (@$paramsRef[$i] eq $results[$i]);
				if (!$test) {
					syntaxReport('Returned data mismatch', join("<>", @$paramsRef) . " -> " . join ("<>", @results));
				}
			}
			else {
				$test = $test && ($results[$i] =~ /([^:]+):(.*)/);
				if (!$test) {
					syntaxReport('Can\'t parse:' . $results[$i], " from " . join ("<>", @results));
				}
			}
		}
				
		return @results;
	}
	return undef;
}

# ---------------------------------------------
# cliPlayers
# ---------------------------------------------
sub cliPlayers {
	my $index = shift;

	$gd_sub && p_sub('cliPlayers(' . (defined($index)?", $index)":")"));

	my %cliPlayersFields = (
		'count' 		=> 'num', 
		'playerindex' 	=> 'num', 
		'playerid' 		=> 'string',
		'ip' 			=> 'string', 
		'name'		 	=> 'string', 
		'model'			=> 'string', 
		'displaytype'	=> 'string', 
		'connected'		=> 'flag',
	);

	my $from;
	my $to;
	if (!defined $index) {
		$index = -1;
		$from = 0;
		$to = -1;
	}
	else {
		$from = randomSmaller($index);
		$to = randomBigger($index, 10);
	}
	my $idx = -1;
	my %result;

	my @cliPlayersCache_Results = cliExtCommand(undef, ['players', $from, ($to - $from + 1)]);
	
	for(my $i = 3; $i < scalar(@cliPlayersCache_Results); $i++){	
		if ($cliPlayersCache_Results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliPlayersFields{$curfield}) {
				if ('playerindex' eq $curfield) {
					$idx = $curvalue;
					if ($idx > $index) {
						return %result;
					}
				}
				elsif ($idx == $index) {
					if (checkType($curvalue, $cliPlayersFields{$curfield})) {
						$result{$curfield} = $curvalue;
						#return $curvalue;
					}
					else {
						syntaxReport('Type error for field players.' . $curfield , $curvalue . " is not " . $cliPlayersFields{$curfield});
					}
				}
			}
			else {
				syntaxReport("Unknown field $curfield for players command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $cliPlayersCache_Results[$i], "players command");
		}
	}
	return %result;
}

# ---------------------------------------------
# cliStatus
# ---------------------------------------------
sub cliStatus {
	my $client = shift;
	my $index = shift;
	my @params = @_;
	
	$gd_sub && p_sub('cliStatus(' . $client . (defined($index)?", $index)":")"));

	my %cliStatusFields = (
		'rescan' 				=> 'flag', 
		'player_name'			=> 'string', 
		'player_connected' 		=> 'flag', 
		'power' 				=> 'flag', 
		'signalstrength'		=> 'num', 
		'mode' 					=> 'string', 
		'rate' 					=> 'num',
		'time' 					=> 'num', 
		'duration'		 		=> 'num', 
		'sleep'					=> 'num', 
		'will_sleep_in'			=> 'num', 
		'sync_master'			=> 'id',
		'sync_slaves'			=> 'string',
		'mixer volume'			=> 'num',
		'mixer bass'			=> 'num',
		'mixer treble'			=> 'num',
		'mixer pitch'			=> 'num',
		'playlist repeat'		=> 'num',
		'playlist shuffle'		=> 'num',
		'playlist_cur_index'	=> 'num',
		'playlist_tracks'		=> 'num',
		'playlist index'		=> 'num',
		'id'					=> 'num',
		'title'					=> 'string',
		'genre'					=> 'string',
		'genre_id'				=> 'num',
		'artist'				=> 'string',
		'artist_id'				=> 'num',
		'composer'				=> 'string',
		'band'					=> 'string',
		'conductor'				=> 'string',
		'album'					=> 'string',
		'album_id'				=> 'num',
		'duration'				=> 'num',
		'disc'					=> 'num',
		'disccount'				=> 'num',
		'tracknum'				=> 'num',
		'year'					=> 'num',
		'bpm'					=> 'num',
		'comment'				=> 'string',
		'type'					=> 'string',
		'tagversion'			=> 'string',
		'bitrate'				=> 'string',
		'filesize'				=> 'string',
		'drm'					=> 'string',
		'coverart'				=> 'flag',
		'modificationTime'		=> 'string',
		'url'					=> 'string',
	);

	my $from;
	my $to;
	if (!defined $index) {
		$index = -1;
		$from = 0;
		$to = -1;
	}
	else {
		$from = randomSmaller($index);
		$to = randomBigger($index, 10);
	}
	my $idx = -1;
	my %result;
	my @results = cliExtCommand($client, ["status", $from, ($to - $from + 1), @params]);
	
	for(my $i = 3; $i < scalar(@results); $i++){	
		if ($i < 3+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliStatusFields{$curfield}) {
				if ('playlist index' eq $curfield) {
					$idx = $curvalue;
					if ($idx > $index) {
						return %result;
					}
				}
				elsif ($idx == $index) {
					if (checkType($curvalue, $cliStatusFields{$curfield})) {
						$result{$curfield} = $curvalue;
					}
					else {
						syntaxReport('Type error for field status.' . $curfield , $curvalue . " is not " . $cliStatusFields{$curfield});
					}
				}
			}
			else {
				syntaxReport("Unknown field $curfield for status command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "status command");
		}
	}
	return %result;
}

# ---------------------------------------------
# cliPlaylistcontrol
# ---------------------------------------------
sub cliPlaylistcontrol {
	my $client = shift;
	my @params = @_;
	
	$gd_sub && p_sub('cliPlaylistcontrol(' . $client . ")");

	my %cliStatusFields = (
		'rescan' 				=> 'flag', 
		'count'					=> 'num', 
	);

	my %result;
	my @results = cliExtCommand($client, ["playlistcontrol", @params]);

	for(my $i = 1; $i < scalar(@results); $i++){	
		if ($i < 1+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliStatusFields{$curfield}) {
				if (checkType($curvalue, $cliStatusFields{$curfield})) {
					$result{$curfield} = $curvalue;
				}
				else {
					syntaxReport('Type error for field playlistcontrol.' . $curfield , $curvalue . " is not " . $cliStatusFields{$curfield});
				}
			}
			else {
				syntaxReport("Unknown field $curfield for playlistcontrol command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "playlistcontrol command");
		}
	}
	return %result;
}


# ---------------------------------------------
# cliGenresAlbumsArtists
# ---------------------------------------------
sub cliGenresAlbumsArtists {
	my $call = shift;
	my $index = shift;
	my @params = @_;
	
	if (!defined $call) {
		print "############################# cliGenresAlbumsArtists called without \$call !!!!! \n";
	}

	$gd_sub && p_sub("cliGenresAlbumsArtists($call)");

	my %cliFields = (
		'rescan' 				=> 'flag', 
		'count'					=> 'num', 
		'id' 					=> 'num', 
		$call 					=> 'string',
	);

	my $from;
	my $to;
	if (!defined $index) {
		$index = -1;
		$from = 0;
		$to = -1;
	}
	else {
		$from = randomSmaller($index);
		$to = randomBigger($index, 10);
	}
	my $idx = -1;
	my %result;
	my $first = 1;

	my @results = cliExtCommand(undef, ["${call}s", $from, ($to - $from + 1), @params]);
	
	for(my $i = 3; $i < scalar(@results); $i++){	
		if ($i < 3+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliFields{$curfield}) {
				if ('id' eq $curfield) {
					if ($first) {
						$idx = $from;
						$first = 0;
					}
					else {	
						$idx++;
					}
					if ($idx > $index) {
						return %result;
					}
				}
				if ($idx == $index) {
					if (checkType($curvalue, $cliFields{$curfield})) {
						$result{$curfield} = $curvalue;
					}
					else {
						syntaxReport("Type error for field ${call}s.${curfield}" , "$curvalue is not ${cliFields{$curfield}}");
					}
				}
			}
			else {
				syntaxReport("Unknown field \'$curfield\' for ${call}s command", "value:\'$curvalue\'");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "${call}s command");
		}
	}
	return %result;
}

# ---------------------------------------------
# cliTitles
# ---------------------------------------------
# Cache
my @gcliTitles_cachedParams;
my $gcliTitles_cachedFrom;
my $gcliTitles_cachedTo;
my @gcliTitles_cachedResults;
sub cliTitles {
	my $index = shift;
	my @params = @_;

	$gd_sub && p_sub('cliTitles(' . (defined($index)?"$index)":")"));

	my %cliFields = (
		'count' 				=> 'num', 
		'rescan'				=> 'flag', 
		'id'					=> 'num',
		'title'					=> 'string',
		'genre'					=> 'string',
		'genre_id'				=> 'num',
		'artist'				=> 'string',
		'artist_id'				=> 'num',
		'composer'				=> 'string',
		'band'					=> 'string',
		'conductor'				=> 'string',
		'album'					=> 'string',
		'album_id'				=> 'num',
		'duration'				=> 'num',
		'disc'					=> 'num',
		'disccount'				=> 'num',
		'tracknum'				=> 'num',
		'year'					=> 'num',
		'bpm'					=> 'num',
		'comment'				=> 'string',
		'type'					=> 'string',
		'tagversion'			=> 'string',
		'bitrate'				=> 'string',
		'filesize'				=> 'string',
		'drm'					=> 'string',
		'coverart'				=> 'flag',
		'modificationTime'		=> 'string',
		'url'					=> 'string',
	);

	my $usecache = 0;
	
	# Can we use our cache...
	if (@gcliTitles_cachedResults) {
#		print("gcliTitles_cachedResults defined\n");
		if (@params) {
#			print("params defined\n");
			if (@gcliTitles_cachedParams) {
#				print("gcliTitles_cachedParams defined\n");
				if (scalar @params == scalar @gcliTitles_cachedParams) {
#					print("same num of elements\n");
					my $test = 1;
					for(my $i = 0; $i < @params; $i++) {
						$test = $test && ($params[$i] eq $gcliTitles_cachedParams[$i]);
					}
					if ($test) {
#						print("same elements\n");
						if (defined $index) {
#							print("want: $index\n");
							if (	($gcliTitles_cachedFrom <= $index) 
									&& 
									($index <= $gcliTitles_cachedTo) ) {
#								print("$index between $gcliTitles_cachedFrom and $gcliTitles_cachedTo: OK\n");
								$usecache = 1;
							}
						}
						else {
#							print("header: OK\n");
							$usecache = 1;
							$index = -1;
						}
					}
				}
			}
		}
	}

	my $from;
	my $to;
	if (!$usecache) {
		if (!defined $index) {
			$index = -1;
		}
		$from = randomSmaller($index);
		$to = randomBigger($index, 30);
		$gcliTitles_cachedFrom = $from;
		$gcliTitles_cachedTo = $to;
		
		@gcliTitles_cachedResults = cliExtCommand(undef, ["titles", $from, ($to - $from + 1), @params]);
		@gcliTitles_cachedParams = @params;
	}

	my $idx = -1;
	my %result;
	my $first = 1;
	my @results = @gcliTitles_cachedResults;
	$from = $gcliTitles_cachedFrom;
	$to = $gcliTitles_cachedTo;
	
	for(my $i = 3; $i < scalar(@results); $i++){	
		if ($i < 3+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("titles: Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliFields{$curfield}) {
				if ('id' eq $curfield) {
					if ($first) {
						$idx = $from;
						$first = 0;
					}
					else {	
						$idx++;
					}
					if ($idx > $index) {
						return %result;
					}
				}
				if ($idx == $index) {
					if (checkType($curvalue, $cliFields{$curfield})) {
						$result{$curfield} = $curvalue;
					}
					else {
						syntaxReport('Type error for field titles.' . $curfield , $curvalue . " is not " . $cliFields{$curfield});
					}
				}
			}
			else {
				syntaxReport("Unknown field $curfield for titles command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "titles command");
		}
	}
	return %result;
}

# ---------------------------------------------
# cliPlaylists
# ---------------------------------------------
sub cliPlaylists {
	my $index = shift;
	my @params = @_;

	$gd_sub && p_sub('cliPlaylists(' . (defined($index)?", $index)":")"));

	my %cliFields = (
		'count' 				=> 'num', 
		'rescan'				=> 'flag', 
		'id'					=> 'num',
		'title'					=> 'string',
		'genre'					=> 'string',
		'genre_id'				=> 'num',
		'artist'				=> 'string',
		'artist_id'				=> 'num',
		'composer'				=> 'string',
		'band'					=> 'string',
		'conductor'				=> 'string',
		'album'					=> 'string',
		'album_id'				=> 'num',
		'duration'				=> 'num',
		'disc'					=> 'num',
		'disccount'				=> 'num',
		'tracknum'				=> 'num',
		'year'					=> 'num',
		'bpm'					=> 'num',
		'comment'				=> 'string',
		'type'					=> 'string',
		'tagversion'			=> 'string',
		'bitrate'				=> 'string',
		'filesize'				=> 'string',
		'drm'					=> 'string',
		'coverart'				=> 'flag',
		'modificationTime'		=> 'string',
		'url'					=> 'string',
	);

	my $from;
	my $to;
	if (!defined $index) {
		$index = -1;
		$from = 0;
		$to = -1;
	}
	else {
		$from = randomSmaller($index);
		$to = randomBigger($index, 10);
	}
	my $idx = -1;
	my %result;
	my $first = 1;
	my @results = cliExtCommand(undef, ["playlists", $from, ($to - $from + 1), @params]);
	
	for(my $i = 3; $i < scalar(@results); $i++){	
		if ($i < 3+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliFields{$curfield}) {
				if ('id' eq $curfield) {
					if ($first) {
						$idx = $from;
						$first = 0;
					}
					else {	
						$idx++;
					}
					if ($idx > $index) {
						return %result;
					}
				}
				elsif ($idx == $index) {
					if (checkType($curvalue, $cliFields{$curfield})) {
						$result{$curfield} = $curvalue;
					}
					else {
						syntaxReport('Type error for field playlists.' . $curfield , $curvalue . " is not " . $cliFields{$curfield});
					}
				}
			}
			else {
				syntaxReport("Unknown field $curfield for playlists command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "playlists command");
		}
	}
	return %result;
}


# ---------------------------------------------
# cliSonginfo
# ---------------------------------------------
sub cliSonginfo {
	my @params = @_;

	$gd_sub && p_sub("cliSonginfo()");

	my %cliFields = (
		'count' 				=> 'num', 
		'rescan'				=> 'flag', 
		'id'					=> 'num',
		'title'					=> 'string',
		'genre'					=> 'string',
		'genre_id'				=> 'num',
		'artist'				=> 'string',
		'artist_id'				=> 'num',
		'composer'				=> 'string',
		'band'					=> 'string',
		'conductor'				=> 'string',
		'album'					=> 'string',
		'album_id'				=> 'num',
		'duration'				=> 'num',
		'disc'					=> 'num',
		'disccount'				=> 'num',
		'tracknum'				=> 'num',
		'year'					=> 'num',
		'bpm'					=> 'num',
		'comment'				=> 'string',
		'type'					=> 'string',
		'tagversion'			=> 'string',
		'bitrate'				=> 'string',
		'filesize'				=> 'string',
		'drm'					=> 'string',
		'coverart'				=> 'flag',
		'modificationTime'		=> 'string',
		'url'					=> 'string',
	);

	my %result;
	my @results = cliExtCommand(undef, ["songinfo", 0, 100, @params]);
	
	for(my $i = 3; $i < scalar(@results); $i++){	
		if ($i < 3+scalar @params) {
			# find the param at $params[$i-3
			# al 0 2 p0 r0
			# 0  1 2 3  4
			if ($results[$i] ne $params[$i - 3]) {
				syntaxReport("Non matching param \'${params[$i -3]}\'" , "not found");
			}
		}
		elsif ($results[$i] =~ /([^:]+):(.*)/) {
			my $curfield = $1;
			my $curvalue = $2;
			if (defined $cliFields{$curfield}) {
				if (checkType($curvalue, $cliFields{$curfield})) {
					$result{$curfield} = $curvalue;
				}
				else {
					syntaxReport('Type error for field songinfo.' . $curfield , $curvalue . " is not " . $cliFields{$curfield});
				}
			}
			else {
				syntaxReport("Unknown field $curfield for songinfo command", "value:$curvalue");
			}
		}
		else {
			syntaxReport('Can\'t parse:' . $results[$i], "songinfo command");
		}
	}
	return %result;
}



# ---------------------------------------------
# checkType
# ---------------------------------------------
sub checkType {
	my $value = shift;
	my $type = shift;
	
	$gd_sub && p_sub("checkType($value, $type)");

	if (!defined $type) {
		return 0;
	}
	elsif ($type eq 'num') {
		return (($value + 0) eq $value);
	}
	elsif ($type eq 'flag') {
		return ( (($value + 0) eq $value) && ($value eq '0' || $value eq '1') );
	}
#	elsif ($type eq 'string' || $type eq 'string*') {
#		return defined $value;
#	}
	elsif ($type eq 'string') {
		return defined $value && length($value);
	}
	else {
		print "############################# Unkown type \'$type\' in checkType() !!!!! \n";
	}
	return $value;
}

# ---------------------------------------------
# randomSmaller
# ---------------------------------------------
sub randomSmaller {
	my $limit = shift;
	
	if($limit <= 0) {
		return 0;
	}
	
	return ceil(rand($limit));
}

# ---------------------------------------------
# randomBigger
# ---------------------------------------------
sub randomBigger {
	my $limit = shift;
	my $max = shift;
	
	$max = 20 unless defined $max;
	
	return $limit + 1 + ceil(rand($max));
}

# ---------------------------------------------
# syntaxReport
# ---------------------------------------------
sub syntaxReport {
	my $text = shift;
	my $problem = shift;
	
	if (defined $gsyntaxTests{"$text"}) {
		$gsyntaxTests{"$text"} .= "//" . $problem;
	}
	else {
		$gsyntaxTests{"$text"} = $problem;
	}
	$gd_syn && print "## SYNTAX: $text - $problem\n";
}



# ---------------------------------------------
# Utility functions
# ---------------------------------------------
sub p_sub {
	my $msg = shift;
	
	print("sub: " . $msg . "\n");
}

sub p_tcp {
	my $msg = shift;
	
	print("tcp: " . $msg . "\n");
}

sub p_ok {
	my $msg = shift;
	
	print("OK: " . $msg . "\n");
}

sub p_failure {
	my $msg = shift;
	
	print("FAILURE: " . $msg . "\n");
}

sub p_err {
	my $msg = shift;
	
	print("ERROR: " . $msg . "\n");
}

sub center {
    my ($text, $width) = @_;
    my $len = length $text;
    $width ||= 0;

    if ($len < $width) {
		my $lpad = int(($width - $len) / 2);
		my $rpad = $width - $len - $lpad;
		$text = (' ' x $lpad) . $text . (' ' x $rpad);
    }

    return $text;
}
