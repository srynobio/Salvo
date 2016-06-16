#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;
use Sys::Hostname;
use IPC::Cmd qw[can_run run run_forked];
use Cwd 'abs_path';
use File::Copy;

# flush after every write
$| = 1;

my $socket = new IO::Socket::INET(
    PeerHost => '10.242.128.49',
    PeerPort => '45652',
    Proto    => 'tcp',
    Type     => SOCK_STREAM,
) or die "ERROR in Socket Creation : $!\n";
say "Client TCP Connection Success.";

## collect node data.
my $node = hostname;
$socket->send( $node, 1024 );

## get sent command file.
my $cmd_file;
$socket->recv( $cmd_file, 1024 );

if ( !$cmd_file ) {
    say "Error collecting command file!";
    $socket->close;
}

process_cmds($cmd_file);
$socket->close;

## ---------------------------------------- ##

sub process_cmds {
    my $command_file = shift;
    my $abs_file     = abs_path($command_file);

    open( my $FH, '<', $abs_file );

    my $error_count;
    foreach my $cmd (<$FH>) {
        chomp $cmd;
        say "running cmd: $cmd";

        my $result = run_forked($cmd);

        if ( $result->{exit_code} eq 255 ) {
            $error_count++;
        }
    }

    if ( !$error_count ) {
        my $new_file = "$abs_file.complete";
        move( $abs_file, $new_file );
    }
}

## ---------------------------------------- ##

