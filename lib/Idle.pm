package Idle;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Socket::INET;
use Parallel::ForkManager;
use File::Copy;
our %processing_watch;

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
    $self->create_cmd_files;

    ## this begins beacon as child.
    my $subprocess = 0;
    my $pm         = $self->subprocess;
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

    ## nodes are collect and beacon.pl is launched.
  MORENODES:
    my $access = $self->ican_access;
    while ( my ( $node_name, $node_data ) = each %{$access} ) {
        next if ( $self->qlimit_limit($node_data) );

        # collect cleared nodes.
        my @cleared_nodes;
        foreach my $detail ( keys %{$node_data} ) {
            next if ( $detail =~ /(account_info|nodes_count)/ );
            push @cleared_nodes, $detail;
        }

        foreach my $detail ( keys %{$node_data} ) {
            next if ( $detail eq 'account_info' );
            next if ( $detail eq 'nodes_count' );

            my $requested_node = shift @cleared_nodes;

            if ( $self->nodes_per_sbatch > 1 ) {
                $self->mpi_writer( $node_data->{$detail}, $node_data );
            }
            else {
                $self->standard_writer( $node_data->{$detail}, $node_data,
                    $requested_node );
            }
        }
        $self->_idle_launcher($node_data);
    }

    ## let some processing happen.
    $self->INFO("Processing...");
    sleep 120;

  CHECKPROCESS:
    $self->INFO("Checking for unprocessed cmd files.");
    if ( $self->get_cmd_files ) {
        goto MORENODES;
    }

    $self->INFO("Checking state of processing jobs.");
    $self->INFO("Flushing any unavailable jobs.");
    sleep 300;
    $self->flush_NotAvail;
    $self->check_preemption;
    if ( $self->get_processing_files ) {
        goto CHECKPROCESS;
    }

    ## Clean up all processes and children.
    $self->INFO("All work processed, shutting down beacon.");
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

sub flush_NotAvail {
    my $self = shift;

    foreach my $node ( keys %{ $self->{SQUEUE} } ) {
        my @cmd =
          `$self->{SQUEUE}->{$node} -h -u $self->user --format=\"%A:%r\"`;
        chomp @cmd;

        my @remove = grep { /(QOSGrpNodeLimit|ReqNodeNotAvail)/ } @cmd;

        foreach my $kill (@remove) {
            my ( $jobid, $reason ) = split /:/, $kill;
            system "$self->{SCANCEL}->{$node} -u $self->user $jobid";
        }
    }
}

## ----------------------------------------------------- ##

sub check_preemption {
    my $self = shift;

    my $out_name  = $self->jobname . "*out";
    my @out_files = glob "$out_name";

    my @reruns;
    my @outfiles;
    foreach my $out (@out_files) {
        chomp $out;
        open( my $IN, '<', $out );

        my $reprocess;
        foreach my $line (<$IN>) {
            chomp $line;

            if ( $line =~ /^Processing/ ) {
                ( undef, $reprocess ) = split /:/, $line;
            }

            if ( $line =~ /PREEMPTION/ ) {
                if ( !$reprocess ) {
                    $self->watch_processing;
                    next;
                }
                push @reruns,   $reprocess;
                push @outfiles, $out;
                undef $reprocess;
            }
            if ( $line =~ /TIME/ ) {
                say "Job $reprocess : $out cancelled due to time limit.";
            }
        }
        close $IN;
    }

    ## rename back to cmd to be picked up.
    foreach my $file (@reruns) {
        next if ( -e "$file.processing.complete" );
        my $new_file = "$file.processing";
        if ( !-d $new_file ) {
            $self->WARN(
                "Preemption or timed out job: $file found, renaming to launch again."
            );
            rename $new_file, $file;
        }
    }
    unlink @outfiles;
}

## ----------------------------------------------------- ##

sub start_beacon {
    my ( $self, $count ) = @_;

    # flush after every write
    $| = 1;

    my $socket = $self->socket;
    if ( !$socket ) {
        $self->ERROR("Can not start server beacon connection error.");
        exit(1);
    }
    $self->INFO("Server beacon launched.");

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

        my $cpu       = $self->node_cpu_details($node);
        my @cmd_files = $self->get_cmd_files;

        my $work = shift @cmd_files;
        ## send cmds to node.
        if ( !$work ) {
            my $die_message = 'die';
            $client->send($die_message);
            next;
        }
        say "sending file $work to $node.";

        my $message = "$work:$cpu";
        rename $work, "$work.processing";
        $client->send($message);
    }
    $socket->close;
}

## ----------------------------------------------------- ##

sub node_cpu_details {
    my ( $self, $node ) = @_;

    my $cpu;
    foreach my $clst ( keys %{ $self->{SINFO} } ) {
        chomp $clst;
        my $sinfo_cmd =
          sprintf( "%s -N -l -h --node %s", $self->{SINFO}->{$clst}, $node );
        my @n_data = `$sinfo_cmd`;
        next if ( !@n_data );

        chomp @n_data;
        my $top_line = $n_data[0];
        my @info = split /\s+/, $top_line;

        $cpu = $info[4];
        last if $cpu;
    }

    ## hyperthread option is used here.
    if ( $self->hyperthread ) {
        $cpu = $cpu * 2;
    }
    return $cpu;
}

## ----------------------------------------------------- ##

sub get_cmd_files {
    my $self = shift;

    my $cmd_name  = "*.cmds";
    my @cmd_files = glob "$cmd_name";
    (@cmd_files) ? ( return @cmd_files ) : ( return undef );
}

## ----------------------------------------------------- ##

sub get_processing_files {
    my $self = shift;

    my $proc_name     = "*.cmds.processing";
    my @process_files = glob "$proc_name";
    (@process_files) ? ( return 1 ) : ( return undef );
}

## ----------------------------------------------------- ##

sub watch_processing {
    my $self       = shift;
    my $processing = $self->get_processing_files;

    foreach my $file ( @{$processing} ) {
        say "test::\@279\t$file";
        $processing_watch{$file}++;
    }

    return if ( !keys %processing_watch );

    while ( my ( $file, $count ) = each %processing_watch ) {
        next unless ( $count >= 50 );

        say "moving file due to process count!!\tcount:$count\tfile:$file";
        ( my $oldName = $file ) =~ s/\.processing//;
        rename $file, $oldName;
        delete $processing_watch{$file};
    }
}

## ----------------------------------------------------- ##

sub qlimit_limit {
    my ( $self, $node_data ) = @_;

    my $squeue = sprintf(
        "%s -u %s -h | wc -l",
        $self->{SQUEUE}->{ $node_data->{account_info}->{CLUSTER} },
        $self->user
    );
    my $number_running = `$squeue`;

    ## If queue_limit is met return true
    ( $number_running >= $self->queue_limit ) ? ( return 1 ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub _idle_launcher {
    my ( $self, $node_data ) = @_;

    ## create output file
    open( my $OUT, '>>', 'launch.index' );

    my @sbatchs = glob "*sbatch";
    if ( !@sbatchs ) {
        say $self->WARN("No sbatch scripts found to launch.");
    }

    foreach my $launch (@sbatchs) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        ## uufscell needed to keep env
        my $cluster  = $node_data->{account_info}->{CLUSTER};
        my $uufscell = $self->{UUFSCELL}->{$cluster};

        my $batch =
          sprintf( "%s --export=UUFSCELL=$uufscell %s >> launch.index",
            $self->{SBATCH}->{ $node_data->{account_info}->{CLUSTER} },
            $launch );
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

1;
