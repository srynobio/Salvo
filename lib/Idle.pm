package Idle;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Socket::INET;
use Parallel::ForkManager;
use File::Copy;

use Data::Dumper;

#our %processing_watch;
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

  MORENODES:
    $access = $self->ican_find;

    ## beacon child launch section.
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

    ## check if node are available and report.
    if ( !keys %{$access} ) {
        $self->WARN("CHPC running at 100%. No Nodes available.");
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
    $self->INFO("Checking for unprocessed cmd files.");
    if (  @{$self->{commands}} ) {
        goto MORENODES;
    }

    $self->INFO("Checking state of processing jobs.");
    $self->INFO("Flushing any unavailable jobs.");
    $self->flush_NotAvail;
    sleep 300;

    $self->INFO("Checking for preempted jobs.");
    $self->check_preemption;
    if ( $self->have_processing_files ) {
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
        my $step = $self->command_writer($cpu);

        ## exit if out of commands
        if ( $step eq 'die' ) {
            $client->send($step);

##### 
            #will now shift commmands correctly need to work on control now.


            ## if everything is done stop running.
            if ( $self->processing_complete ) {
####???                $self->node_flush;
                last;
            }
            next;
        }

        say "sending file $step to $node.";
        my $message = "$step:$cpu";
        rename $step, "$step.processing";
        $client->send($message);
    }
    $socket->close;
}

## ----------------------------------------------------- ##

sub command_writer {
    my ( $self, $cpu ) = @_;
    return 'die' if ( !@{ $self->{commands} } );

    my @commands;
    if ( $self->jobs_per_sbatch ) {
        @commands = @{ $self->{commands} }[ 0 .. $self->jobs_per_sbatch ];
        for ( 1 .. $self->jobs_per_sbatch ) {
            shift @{ $self->{commands} };
        }
    }
    else {
        @commands = @{ $self->{commands} }[ 0 .. $cpu ];
        for ( 1 .. $cpu ) {
            shift @{ $self->{commands} };
        }
    }

    ## second check for commands.
    return 'die' if ( !@commands );

    my $file = $self->random_file_generator;
    open( my $FH, '>', $file );
    map { say $FH $_ } @commands if @commands;
    close $FH;

    return $file;
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
#
#sub check_preemption {
#    my $self = shift;
#
#    my $out_name  = $self->jobname . "*out";
#    my @out_files = glob "$out_name";
#
#    my @reruns;
#    my @outfiles;
#    foreach my $out (@out_files) {
#        chomp $out;
#        open( my $IN, '<', $out );
#
#        my $reprocess;
#        foreach my $line (<$IN>) {
#            chomp $line;
#
#            if ( $line =~ /^Processing/ ) {
#                ( undef, $reprocess ) = split /:/, $line;
#            }
#
#            if ( $line =~ /PREEMPTION/ ) {
#                if ( !$reprocess ) {
#                    $self->watch_processing;
#                    next;
#                }
#                push @reruns,   $reprocess;
#                push @outfiles, $out;
#                undef $reprocess;
#            }
#            if ( $line =~ /TIME/ ) {
#                say "Job $reprocess : $out cancelled due to time limit.";
#            }
#        }
#        close $IN;
#    }
#
#    ## rename back to cmd to be picked up.
#    foreach my $file (@reruns) {
#        next if ( -e "$file.processing.complete" );
#        my $new_file = "$file.processing";
#        if ( !-d $new_file ) {
#            $self->WARN(
#                "Preemption or timed out job: $file found, renaming to launch again."
#            );
#            rename $new_file, $file;
#        }
#    }
#    unlink @outfiles;
#}

## ----------------------------------------------------- ##

sub random_file_generator {
    my $self     = shift;
    my $id       = int( rand(10000) );
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
    (@process_files) ? ( return 1 ) : ( return undef );
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
#
#sub watch_processing {
#    my $self       = shift;
#    my $processing = $self->have_processing_files;
#
#    foreach my $file ( @{$processing} ) {
#        say "test::\@279\t$file";
#        $processing_watch{$file}++;
#    }
#
#    return if ( !keys %processing_watch );
#
#    while ( my ( $file, $count ) = each %processing_watch ) {
#        next unless ( $count >= 50 );
#
#        say "moving file due to process count!!\tcount:$count\tfile:$file";
#        ( my $oldName = $file ) =~ s/\.processing//;
#        rename $file, $oldName;
#        delete $processing_watch{$file};
#    }
#}

## ----------------------------------------------------- ##

sub idle_launcher {
    my ( $self, $node_data ) = @_;


print Dumper 'idle_launch', $node_data, $node_data->{CLUSTER};


    ## create output file
    open( my $OUT, '>>', 'launch.index' );

    my @sbatchs = glob "*sbatch";
    if ( !@sbatchs ) {
        say $self->ERROR("No sbatch scripts found to launch.");
    }

  LINE: foreach my $launch (@sbatchs) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        ## uufscell needed to keep env
        my $cluster  = $node_data->{CLUSTER};
        my $uufscell = $self->{UUFSCELL}->{$cluster};

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

1;
