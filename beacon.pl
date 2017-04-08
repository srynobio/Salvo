#!/usr/bin/env perl
# beacon.pl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;
use IPC::Open3;
use Sys::Hostname;
use Parallel::ForkManager;
use Cwd 'abs_path';
use File::Copy;
use Fcntl qw(:flock SEEK_END);

# flush after every write
$| = 1;

## get commandline host and port info.
my $localhost = $ARGV[0];
my $localport = $ARGV[1];

my $socket = new IO::Socket::INET(
    PeerHost => $localhost,
    PeerPort => $localport,
    Proto    => 'tcp',
    Type     => SOCK_STREAM,
) or die "ERROR in Socket Creation : $!\n";
say "beacon ready for work.";

## collect node data.
my $node = hostname;
$socket->send( $node, 1024 );

## get sent command file.
my $message;
$socket->recv( $message, 1024 );
my ( $cmd_file, $cpu ) = split /:/, $message;

if ( !$cmd_file ) {
    say "Error receiving command file! Got: $message";
    $socket->close;
    exit(1);
}

## kill unneeded clients
if ( $cmd_file eq 'die' ) {
    say "...No work left, shutting down this beacon.";
    $socket->close;
    exit(0);
}

say "Processing file:$cmd_file";
process_cmds( $cmd_file, $cpu );
$socket->close;

## ---------------------------------------- ##

sub process_cmds {
    my ( $command_file, $cpu ) = @_;
    $command_file =~ s/$/.processing/;
    my $abs_file = abs_path($command_file);

    my $pm = Parallel::ForkManager->new($cpu);

    open( my $FH, '<', $abs_file );

    say "------ Node info -------";
    say "JOBID: $ENV{SLURM_JOBID}";
    say "Node list: $ENV{SLURM_JOB_NODELIST}";
    say "------------------------";

    my $error_count;
    my $cmd_count;
    foreach my $cmd (<$FH>) {
        chomp $cmd;
        $cmd_count++;

        $pm->start and next;
        say "[COMMAND]:$cmd";

        local ( *IN, *OUT, *ERROR );
        my $pid = open3( \*IN, \*OUT, \*ERROR, $cmd );

        ## collect out and error.
        my @error = <ERROR>;
        my @out   = <OUT>;

        if (@error) {
            say "[INFO] Error running command: $cmd";
            map { "ERROR MSG: $_" } @error;
            need_rerun($cmd);
            $error_count++;
        }
        $pm->finish($cmd);
    }
    $pm->wait_all_children;

    if ( !$error_count ) {
        my $new_file = "$abs_file.complete";
        if ( !-d $new_file ) {
            rename $abs_file, $new_file;
        }
    }
}

## ---------------------------------------- ##

sub need_rerun {
    my $cmd = shift;
    open( my $FH, '>>', 'salvo.command.tmp' );
    flock( $FH, 2 );
    chomp $cmd;
    say $FH $cmd;
    close $FH;
}

## ---------------------------------------- ##

