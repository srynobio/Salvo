package Idle;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Socket::INET;
use Parallel::ForkManager;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

has socket => (
    is      => 'ro',
    default => sub {
        my $socket = IO::Socket::INET->new(
            LocalHost => '10.242.128.49',
            LocalPort => '45652',
            Proto     => 'tcp',
            Type      => SOCK_STREAM,
            Listen    => SOMAXCONN,
            Reuse     => 1
        );
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

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub idle {
    my $self = shift;
    $self->create_cmd_files;

    ## this begins beacon.s
    my $subprocess = 0;
    my $pm         = $self->subprocess;
    while ( $subprocess < 1 ) {
        $subprocess++;
        $pm->start and next;
        $self->start_beacon;
        $pm->finish;

        my $child = $pm->running_procs;
        kill 'KILL', $child;
    }

    ## nodes are collect and beacon.c is launched to.
  MORENODES:
    my $access = $self->ican_access;
    while ( my ( $node_name, $node_data ) = each %{$access} ) {

        foreach my $detail ( keys %{$node_data} ) {
            next if ( $detail eq 'account_info' );
            next if ( $detail eq 'nodes_count' );
            $self->beacon_writer( $node_data->{$detail}, $node_data );
        }
        $self->_idle_launcher($node_data);
    }

    ## let some work get done.
    $self->INFO("Processing...");
    sleep 300;

  CHECKPROCESS:
    if ( $self->get_cmd_files ) {
        $self->INFO("Checking for unprocessed cmd files.");
        goto MORENODES;
    }

    if ( $self->get_processing_files ) {
        sleep 300;
        $self->INFO("Checking processing jobs.");
        $self->check_preemption;
        goto CHECKPROCESS;
    }
    $pm->wait_all_children;
    $self->node_flush;
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
            if ( $line =~ /(PREEMPTION|CANCELLED)/ ) {
                next if ( !$reprocess );
                push @reruns,   $reprocess;
                push @outfiles, $out;
                undef $reprocess;
            }
        }
        close $IN;
    }

    ## rename back to cmd to be picked up.
    foreach my $file (@reruns) {
        my $new_file = "$file.processing";
        if ( -d $new_file ) {
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
    $self->INFO("Server beacon launched.");

    do {
        my $client = $socket->accept;

        # get information about a newly connected client
        my $client_address = $client->peerhost();
        my $client_port    = $client->peerport();
        print "connection from $client_address:$client_port\n";

        # Get data on who client is.
        my $node = "";
        $client->recv( $node, 1024 );
        say "Received beacon from node: $node";

        my $cpu = $self->node_cpu_details($node);

        my @cmd_files = $self->get_cmd_files;
        last if ( !@cmd_files );

        ## send cmds to node.
        my $work = shift @cmd_files;
        say "sending file $work to $node.";

        my $message = "$work:$cpu";
        rename $work, "$work.processing";
        $client->send($message);

    } while ( $self->get_cmd_files );

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
    return $cpu;
}

## ----------------------------------------------------- ##

sub get_cmd_files {
    my $self = shift;

    my @cmd_files = glob "salvo.work.*.cmds";
    (@cmd_files) ? ( return @cmd_files ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub get_processing_files {
    my $self = shift;

    my @process_files = glob "salvo.work.*.cmds.processing";
    (@process_files) ? ( return @process_files ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub _idle_launcher {
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
