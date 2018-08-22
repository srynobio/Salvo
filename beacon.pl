#!/usr/bin/env perl
# beacon.pl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;
use IPC::Cmd qw[run];
############use IPC::Open3;
use Sys::Hostname;
use Parallel::ForkManager;
###use Cwd 'abs_path';
###use File::Copy;
###use Fcntl qw(:flock SEEK_END);

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

## collect node info.
my $nodeInfo = `sinfo -h -n $ENV{SLURMD_NODENAME} -o "%c:%m:%n"`;
chomp $nodeInfo;
$socket->send( $nodeInfo, 1024 );

## get sent command file.
my $message;
$socket->recv( $message, 9000 );
my @cmds = split/::/, $message;

## kill unneeded clients
if ( length $message == 0 or $message eq 'die' ) {
    say "No commands for node: $node. Releasing node.";
    $socket->close;
    exit(0);
}

## run the set[s] of command and return to updated db.
my $cmdStatus = commandRunner(\@cmds);
$socket->send($cmdStatus, 1024);
$socket->close;

## ---------------------------------------- ##

sub commandRunner {
    my $cmds = shift;

    my $returnMessage;
    foreach my $run (@$cmds) {

        my $pm = Parallel::ForkManager->new($cpu);
        $pm->start and next;

        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
          run( command => $run, verbose => 0 );

        if ($success) {
            $returnMessage = "success";
            return "success";
        }
        if ($error_message) {
            say "@$stderr_buf";
            $returnMessage = "error";
        }
        $pm->finish;
    }
    $pm->wait_all_children;
    return $returnMessage;
}

## ---------------------------------------- ##

=cut
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

        my $fails = 0;
        if (@error) {
            say "[INFO] Checking error messages";
            foreach my $fail (@error) {
                if ( $fail =~ /error/i ) {
                    say "[INFO] following error message found: $fail";
                    $fails++;
                    $error_count++;
                }
            }
        }
        need_rerun($cmd) if ( $fails > 0 );
        waitpid( $pid, 0 );
        if ($?) {
            say "[INFO] cmd $cmd exited with a status of $?.";
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

=cut
## ---------------------------------------- ##

