package Idle;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Socket::INET;
use Parallel::ForkManager;
use File::Copy;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

has socket => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        my $host_id = `ifconfig eth0 | grep 'inet addr' | cut -d':' -f2 | awk '{print \$1}'`;
        chomp $host_id;
        my $socket = IO::Socket::INET->new(
            LocalHost => $host_id,
            LocalPort => 45652,
            Proto     => 'tcp',
            Type      => SOCK_STREAM,
            Listen    => SOMAXCONN,
            Reuse     => 1
        );
        $self->{socket} = $socket;
        $self->localhost($host_id);
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

has active => ( is => 'rw', );

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub idle {
    my $self = shift;
    $self->create_cmd_files;

    ## this begins beacon.s as child.
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

    ## nodes are collect and beacon.c is launched to.
  MORENODES:
    my $access = $self->ican_access;
    while ( my ( $node_name, $node_data ) = each %{$access} ) {
        next if ( $self->qlimit_check($node_data) );

        foreach my $detail ( keys %{$node_data} ) {
            next if ( $detail eq 'account_info' );
            next if ( $detail eq 'nodes_count' );
            $self->beacon_writer( $node_data->{$detail}, $node_data );
        }
        $self->_idle_launcher($node_data);
    }

    ## let some processing happen.
    $self->INFO("Processing...");
    sleep 300;

  CHECKPROCESS:
    $self->INFO("Checking for unprocessed cmd files.");
    if ( $self->get_cmd_files ) {
        goto MORENODES;
    }

    $self->INFO("Checking state of processing jobs.");
    if ( $self->get_processing_files ) {
        $self->check_preemption;
        sleep 300;
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

sub check_preemption {
    my $self = shift;

    my @out_files = glob "salvo*out";

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
                next if ( !$reprocess );
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
            move( $new_file, $file );
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
        $self->ERROR("Can not start server beacon");
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
        say "Received beacon from node: $node";

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
    if ( $self->hyperthread ) {
        $cpu = $cpu * 2;
    }
    return $cpu;
}

## ----------------------------------------------------- ##

sub get_cmd_files {
    my $self = shift;

    my @cmd_files = glob "salvo.work.*.cmds";
    (@cmd_files) ? ( return @cmd_files ) : ( return undef );
}

## ----------------------------------------------------- ##

sub get_processing_files {
    my $self = shift;

    my @process_files = glob "salvo.work.*.cmds.processing";
    (@process_files) ? ( return 1 ) : ( return undef );
}

## ----------------------------------------------------- ##

sub qlimit_check {
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

        my $batch = sprintf( "%s %s >> launch.index",
            $self->{SBATCH}->{ $node_data->{account_info}->{CLUSTER} },
            $launch );
        system $batch;

        ## rename so not double launched.
        rename $launch, "$launch.launched";
    }
}

## ----------------------------------------------------- ##

1;
