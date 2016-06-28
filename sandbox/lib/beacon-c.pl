#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;
use Sys::Hostname;
##use IPC::Cmd 'run_forked';
use IPC::Open3;
use Parallel::ForkManager;
use Cwd 'abs_path';
use File::Copy;

use Data::Dumper;


# flush after every write
$| = 1;

my $socket = new IO::Socket::INET(
    PeerHost => '10.242.128.49',
    PeerPort => '45652',
    Proto    => 'tcp',
    Type     => SOCK_STREAM,
) or die "ERROR in Socket Creation : $!\n";

say "beacon.c ready for work.";

## collect node data.
my $node = hostname;
$socket->send( $node, 1024 );

## get sent command file.
my $message;
$socket->recv( $message, 1024 );
my ($cmd_file, $cpu) = split /:/, $message;

if ( !$cmd_file ) {
    say "Error receiving command file!";
    $socket->close;
}

## kill unneeded clients
if ( $cmd_file eq 'die') {
    $socket->close;
}

say "Processing file:$cmd_file";
process_cmds($cmd_file, $cpu);
$socket->close;

## ---------------------------------------- ##

sub process_cmds {
    my ( $command_file, $cpu ) = @_;
    $command_file =~ s/$/.processing/;
    my $abs_file = abs_path($command_file);

    my $pm = Parallel::ForkManager->new($cpu);

    open( my $FH, '<', $abs_file );
    open( my $ERR, '>>', 'failed.cmds.file');

    my $error_count;
    foreach my $cmd (<$FH>) {
        chomp $cmd;

        $pm->start and next;

        my ( $write, $read, $err );
        my $pid = open3( $write, $read, $err, $cmd );
        waitpid( $pid, 0 );

        if ($err) {
            $error_count++;
            say "beacon.c error: $err";
            say $ERR $cmd;
        }
        $pm->finish;
    }
    $pm->wait_all_children;

    if ( !$error_count ) {
        my $new_file = "$abs_file.complete";
        if ( ! -d $new_file ) {
            move( $abs_file, $new_file );
        }
    }
    else {
        say "Failed run: $command_file";
        my $orig_file = $command_file;
        $orig_file =~ s/.processing//;
        if ( !-d $orig_file ) {
            move( $command_file, $orig_file );
        }
    }
}

## ---------------------------------------- ##

