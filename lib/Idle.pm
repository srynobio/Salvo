package Idle;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Socket::INET;
use Parallel::ForkManager;
use File::Copy;
use Fcntl qw(:flock SEEK_END);

## main node collection hash.
our $access;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

has socket => (
    is      => 'ro',
    default => sub {
        my $self    = shift;
        my $host_id = $self->get_host_id;
        my ( $lower, $upper ) = $self->get_port_range;

        my $socket;
        for ( $lower .. $upper ) {
            $socket = IO::Socket::INET->new(
                LocalHost => $host_id,
                LocalPort => $_,
                Proto     => 'tcp',
                Type      => SOCK_STREAM,
                Listen    => SOMAXCONN,
                Reuse     => 1
            );
            if ($socket) {
                $self->{socket} = $socket;
                $self->localhost($host_id);
                $self->localport($_);
                last;
            }
        }
        return $socket;
    },
);

has subprocess => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        my $pm   = Parallel::ForkManager->new(1);
        return $pm;
    },
);

has active => ( is => 'rw' );

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub idle {
    my $self = shift;

    ## beacon child launch section.
    my $subprocess = 0;
    my $pm         = $self->subprocess;

  MORENODES:
    $self->WARN("Fetching more nodes...");
    $access = $self->ican_find;

    while ( $subprocess < 1 ) {
        $self->active(1);
        $subprocess++;
        $pm->start and next;
        $self->start_beacon;
        $pm->finish;

        my $child = $pm->running_procs;
        kill 'KILL', $child;
        exit(0);
    }

    ## check if node are available and report.
    if ( !keys %{$access} ) {
        $self->INFO("CHPC running at 100%, or no nodes accessible.");
        say "Will check for available nodes in 5 mins...";
        sleep 300;
        goto MORENODES;
    }

    ## create beacon scripts.
    foreach my $avail ( keys %{$access} ) {
        if ( $self->nodes_per_sbatch > 1 ) {
            $self->mpi_writer( $access->{$avail} );
        }
        else {
            $self->standard_writer( $access->{$avail} );
        }
        $self->idle_launcher( $access->{$avail} );
    }

    ## start processing.
    $self->INFO("Processing....");
    sleep 300;
    $self->flush_NotAvail;

  CHECKPROCESS:
    $self->INFO("Checking for unprocessed commands.");
    $self->INFO("Flushing any unavailable jobs.");
    ## check and launch more beacons if work to be done.
    if ( $self->are_cmds_remaining ) {
        $self->flush_NotAvail;
        goto MORENODES;
    }

    $self->INFO("Checking for preempted jobs.");
    if ( $self->are_jobs_preempted ) {
        goto CHECKPROCESS;
    }

    if ( $self->have_processing_files ) {
        sleep 60;
        goto CHECKPROCESS;
    }

    ## Clean up all processes and children.
    $self->INFO("All work processed, shutting down beacons.");
    $self->active(0);
    $self->INFO("Flushing any remaining beacons.");
    $self->node_flush;
    $self->INFO("Shutting down open socket.");
    my $kill_socket = $self->{socket};
    $kill_socket->shutdown(2);
    $kill_socket->close;
    $pm->wait_all_children;
}

## ----------------------------------------------------- ##

sub start_beacon {
    my $self = shift;

    # flush after every write
    $| = 1;

    my $socket = $self->socket;
    if ( !$socket ) {
        $self->ERROR("Can not start receiver beacon, connection error.");
        exit(1);
    }
    $self->INFO("Receiver beacon started.");

    while ( $self->active ) {
        my $client = $socket->accept;

        # get information about a newly connected client
        my $client_address = $client->peerhost();
        my $client_port    = $client->peerport();
        print "connection from $client_address:$client_port\n";

        # Get data on who client is.
        my $node = "";
        $client->recv( $node, 1024 );
        $self->INFO("Received beacon from node: $node");

        ## get cpu info from access hash.
        my $cpu = $access->{$node}->{CPU};

        ## write command file based on request or number of cpus.
        my ($step, $processing_number) = $self->command_writer($cpu);

        ## exit if out of commands
        if ( $step eq 'die' ) {
            $client->send($step);
            next;
        }

        say "sending file $step to $node.";
        my $message = "$step:$processing_number";
        rename $step, "$step.processing";
        $client->send($message);
    }
    $socket->close;
}

## ----------------------------------------------------- ##

sub command_writer {
    my ( $self, $cpu ) = @_;

    my $processing_number;
    ( $self->jobs_per_sbatch )
      ? ( $processing_number = $self->jobs_per_sbatch )
      : ( $processing_number = $cpu );

    open( my $FILE, '<', 'salvo.command.tmp' );
    flock( $FILE, 2 );
    my @command_stack;
    foreach my $cmd (<$FILE>) {
        chomp $cmd;
        push @command_stack, $cmd;
    }
    return 'die' if ( !@command_stack );
    close $FILE;

    ## just get needed number of commands.
    my @to_run;
    my @write;
    my $count = 0;
    foreach my $cmd (@command_stack) {
        chomp $cmd;
        $count++;
        if ( $count <= $processing_number ) {
            push @to_run, $cmd;
        }
        else {
            push @write, $cmd;
        }
    }
    return 'die' if ( !@to_run );

    ## print remaining commands back to file
    open( my $OUT, '>', 'salvo.command.tmp' );
    flock( $OUT, 2 );
    foreach my $remain (@write) {
        say $OUT $remain;
    }
    close $OUT;

    ## write the to_run commands.
    my $file = $self->random_file_generator;
    open( my $FH, '>', $file );
    foreach my $i (@to_run) {
        say $FH $i;
    }
    close $FH;

    return $file, $processing_number;
}

## ----------------------------------------------------- ##

sub are_cmds_remaining {
    my $self = shift;

    open( my $FH, '<', 'salvo.command.tmp' );
    flock( $FH, 2 );

    my $cmd_count = 0;
    foreach my $cmd (<$FH>) {
        chomp $cmd;
        if ( length $cmd > 1 ) {
            $cmd_count++;
        }
    }
    if ( $cmd_count > 1 ) {
        return 1;
    }
    else {
        return 0;
    }
}

## ----------------------------------------------------- ##

sub flush_NotAvail {
    my $self = shift;

    foreach my $node ( keys %{ $self->{SQUEUE} } ) {
        my $user = $self->user;
        my @cmd  = `$self->{SQUEUE}->{$node} -h -u $user --format=\"%A:%r\"`;
        chomp @cmd;

        my @remove = grep { /(QOSGrpNodeLimit|ReqNodeNotAvail)/ } @cmd;

        foreach my $kill (@remove) {
            my ( $jobid, $reason ) = split /:/, $kill;
            system "$self->{SCANCEL}->{$node} -u $user $jobid";
        }
    }
}

## ----------------------------------------------------- ##

sub are_jobs_preempted {
    my $self = shift;

    my $out_name  = $self->jobname . "*out";
    my @out_files = glob "$out_name";

    my @reruns;
    foreach my $out (@out_files) {
        chomp $out;
        open( my $IN, '<', $out );

        my $needs_reprocessing = 0;
        foreach my $line (<$IN>) {
            chomp $line;

            if ( $line =~ /PREEMPTION/ ) {
                $needs_reprocessing++;
                next;
            }
            if ( $needs_reprocessing > 1 ) {
                if ( $line =~ /^[COMMAND]:/ ) {
                    my @command = split /:/, 2;
                    push @reruns, $command[1];
                }
            }
            if ( $line =~ /TIME/ ) {
                say "Job $out cancelled due to time limit.";
            }
        }
        close $IN;
    }

    ## if no reruns found return.
    if ( !@reruns ) {
        return 0;
    }

    ## rename back to cmd to be picked up.
    open( my $FILE, '>>', 'salvo.command.tmp' );
    flock( $FILE, 2 );
    foreach my $cmd (@reruns) {
        $self->WARN("Preemption or timed out cmd: $cmd found, relaunching.");
        say $FILE, $cmd;
    }
    close $FILE;
    return 1;
}

## ----------------------------------------------------- ##

sub random_file_generator {
    my $self     = shift;
    my $id       = int( rand(99000) );
    my $filename = $self->jobname . ".work.$id.cmds";
    if ( -e $filename ) {
        $self->random_file_generator;
    }
    return $filename;
}

## ----------------------------------------------------- ##

sub have_processing_files {
    my $self = shift;

    my $proc_name     = "*.cmds.processing";
    my @process_files = glob "$proc_name";
    chomp @process_files;

    ## no file just leave.
    return undef if ( !@process_files );

    ## get the state
    my $active_state = '';
    if (@process_files) {
        $active_state = $self->_check_processing_activity;
    }

    # collect cmds of issues exist.
    my @cmds;
    if ( $active_state eq 'EMPTY' ) {
        foreach my $files (@process_files) {
            chomp $files;
            open( my $PF, '<', $files );
            foreach my $cmd (<$PF>) {
                push @cmds, $cmd;
            }
            close $PF;
        }
    }

    ## rewrite the command back to tmp.
    if (@cmds) {
        open( my $FH, '>>', 'salvo.command.tmp' );
        flock( $FH, 2 );
        foreach my $cmd (@cmds) {
            say $FH $cmd;
        }
    }

    ## get rid of unneed files.
    unlink @process_files;
    return 1;
}

## ----------------------------------------------------- ##

sub processing_complete {
    my $self = shift;

    my $cmd_files     = "*.cmds.*";
    my @all_cmd_files = glob "$cmd_files";
    chomp @all_cmd_files;

    my $complete     = "*.cmds.processing.complete";
    my @all_complete = glob "$complete";
    chomp @all_complete;

    if ( scalar @all_cmd_files == scalar @all_complete ) {
        return 1;
    }
    return 0;
}

## ----------------------------------------------------- ##

sub idle_launcher {
    my ( $self, $node_data ) = @_;

    ## create output file
    open( my $OUT, '>>', 'launch.index' );

    my @sbatchs = glob "*sbatch";
    if ( !@sbatchs ) {
        say $self->ERROR("No sbatch scripts found to launch.");
    }

    foreach my $launch (@sbatchs) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        ## uufscell needed to keep env
        my $cluster  = $node_data->{CLUSTER};
        my $uufscell = $self->{UUFSCELL}->{$cluster};

        unless ( $cluster && $uufscell ) {
            $self->WARN(
                "No values found for cluster: $cluster and uufscell: $uufscell"
            );
        }

        my $batch =
          sprintf( "%s --export=UUFSCELL=$uufscell %s >> launch.index",
            $self->{SBATCH}->{ $node_data->{CLUSTER} }, $launch );
        system $batch;

        ## rename so not double launched.
        rename $launch, "$launch.launched";
    }
}

## ----------------------------------------------------- ##

sub get_host_id {
    my $self    = shift;
    my $host_id = `hostname -i`;
    chomp $host_id;
    return $host_id;
}

## ----------------------------------------------------- ##

sub get_port_range {
    my $self = shift;

    my @port_ranges = split /\s+/, `sysctl net.ipv4.ip_local_port_range`;
    my $lower       = $port_ranges[2];
    my $upper       = $port_ranges[3];
    return $lower, $upper;
}

## ----------------------------------------------------- ##

sub _check_processing_activity {
    my $self = shift;
    my $user = $self->user;

    $self->INFO("Checking activity of running jobs.");

    open( my $FH, '<', 'launch.index' );

    my $running = 0;
    my $waiting = 0;
    foreach my $launched (<$FH>) {
        my @report = split /\s+/, $launched;
        foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
            my $cmd = printf(
                "%s -u %s -j %s -h -o \"%%t\"",
                $self->{SQUEUE}->{$cluster},
                $user, $report[-1]
            );
            my $result = `$cmd`;
            if ( $result =~ /^R/ ) {
                $running++;
            }
            if ( $result =~ /^PD/ ) {
                $waiting++;
            }
        }
    }

    if ( $running == 0 && $waiting == 0 ) {
        $self->INFO("Process files but no jobs are running or waiting.");
        $self->INFO("Reseting processing jobs.");
        return 'EMPTY';
    }
}

## ----------------------------------------------------- ##

1;
