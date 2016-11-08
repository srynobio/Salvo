#!/usr/bin/env perl
# beacon.pl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;
use IPC::Cmd 'run';
use Sys::Hostname;
use Parallel::ForkManager;
use Cwd 'abs_path';
use File::Copy;

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

    open( my $FH,  '<',  $abs_file );

    say "------ Node info -------";
    say "JOBID: $ENV{SLURM_JOBID}";
    say "Node list: $ENV{SLURM_JOB_NODELIST}";
    say "------------------------";

    my $error_count;
    my $file_count;
    foreach my $cmd (<$FH>) {
        chomp $cmd;
        $file_count++;

        $pm->start and next;

        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
          run( command => $cmd, verbose => 0 );

        if ($success) {
            say "cmd completed: $cmd";
            map { say "Buffer: $_" } @$full_buf;
        }
        else {
            say "error results: $error_message";
            map { say "Error Buffer: $_" } @$full_buf;
            need_rerun($cmd, $file_count);
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
    my ( $cmd, $file_count ) = @_;
    open( my $FH, '>', "rerun.work.$node.$file_count.cmds" );
    say $FH $cmd;
    close $FH;
}

## ---------------------------------------- ##

