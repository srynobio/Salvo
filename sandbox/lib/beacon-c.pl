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
say "Client TCP Connection Success.";

## collect node data.
my $node = hostname;
$socket->send( $node, 1024 );

## get sent command file.
my $inbox;
$socket->recv( $inbox, 1024 );

say "file!! $inbox";


my ($cmd_file, $cpu) = split /:/, $inbox;

if ( !$cmd_file ) {
    say "Error collecting command file!";
    $socket->close;
}
say "$node: Processing file $cmd_file";
process_cmds($cmd_file, $cpu);

$socket->close;

## ---------------------------------------- ##

sub process_cmds {
    my ( $command_file, $cpu ) = @_;
    $command_file =~ s/$/.processing/;
    my $abs_file = abs_path($command_file);

    my $pm = Parallel::ForkManager->new($cpu);

    open( my $FH, '<', $abs_file );

    my $error_count;
    foreach my $cmd (<$FH>) {
        chomp $cmd;

        $pm->start and next;

        my ( $write, $read, $err );
        my $pid = open3( $write, $read, $err, $cmd );


    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;

    print Dumper $pid, $write, $read, $err, $cmd, $child_exit_status;

        $error_count++ if $err;
        $pm->finish;
    }
    $pm->wait_all_children;

    if ( !$error_count ) {
        my $new_file = "$abs_file.complete";
        if ( !-d $new_file ) {
            move( $abs_file, $new_file );
        }
    }
}

## ---------------------------------------- ##

