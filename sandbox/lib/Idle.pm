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

has child => (
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

    my $subprocess = 0;
    my $pm         = $self->child;
    while ( $subprocess < 1 ) {
        $subprocess++;
        $pm->start and next;
        $self->start_beacon;
        $pm->finish;

        my $child = $pm->running_procs;
        kill 'KILL', $child;
    }

  MORENODES:
    my $access = $self->ican_access;
    while ( my ( $node_name, $node_data ) = each %{$access} ) {
        ## check if excluded
        next if ( $node_name eq $self->exclude_cluster );

        foreach my $detail ( keys %{$node_data} ) {
            next if ( $detail eq 'account_info' );
            next if ( $detail eq 'nodes_count' );
            $self->beacon_writer( $node_data->{$detail}, $node_data );
        }
        $self->_idle_launcher($node_data);
    }

    if ( $self->get_cmd_files ) {
        $self->INFO("Looking for more nodes.");
        sleep 600;
        goto MORENODES;
    }
    
    ## wait for processing file before clean up.
    while ( $self->get_processing_files ) {
        $self->INFO("Waiting for processing jobs.");
        sleep 300;
        redo;
    }
    $pm->wait_all_children;
    $self->node_clean_up;
}

## ----------------------------------------------------- ##

sub create_cmd_files {
    my $self = shift;
    my $cmds = $self->get_cmds;

    # split base on jps, then create sbatch scripts.
    my @cmdstack;
    push @cmdstack, [ splice @{$cmds}, 0, $self->jobs_per_sbatch ]
      while @{$cmds};

    my $cmds_count = 0;
    foreach my $stack (@cmdstack) {
        $cmds_count++;
        my $w_file = "salvo.work.$cmds_count.cmds";

        open( my $FH, '>', $w_file );
        map { say $FH $_ } @{$stack};
        close $FH;
    }
}

## ----------------------------------------------------- ##

sub start_beacon {
    my ( $self, $count ) = @_;

    # flush after every write
    $| = 1;

    my $socket = $self->socket;
    $self->INFO("Server beacon launching.");

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
        my $sinfo_cmd = sprintf(
            "%s -N -l -h --node %s",
            $self->{SINFO}->{$clst}, $node
        );
        my @n_data = `$sinfo_cmd`; 
        next if (! @n_data);

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
    (@cmd_files) ? ( return @cmd_files ) : (return 0);
}

## ----------------------------------------------------- ##

sub get_processing_files {
    my $self = shift;

    my @process_files = glob "salvo.work.*.processs.processing";
    (@process_files) ? ( return @process_files ) : (return 0);
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

sub _idle_wait_all_jobs {
    my $self = shift;

    my $process;
    do {
        sleep(60);
        $self->INFO("Checking if jobs need to be relaunched.");
        $self->_idle_hanging_check;
        $self->_idle_relaunch;
        sleep(60);
        $self->INFO("Checking current processing.");
        $process = $self->_idle_process_check();
    } while ($process);
}

## ----------------------------------------------------- ##

sub _idle_relaunch {
    my $self = shift;

    my @error = `grep error *out`;
    chomp @error;
    if ( !@error ) { return }

    my %relaunch;
    my @error_files;
    foreach my $cxl (@error) {
        chomp $cxl;

        my @ids = split /\s/, $cxl;
        my ( $error_file, undef ) = split /:/, $ids[0];

        ## add to error array before changes
        push @error_files, $error_file;

        ## rename as sbatch script
        ( my $sbatch = $error_file ) =~ s/out/sbatch/;

        if ( $cxl =~ /TIME LIMIT/ ) {
            say "[WARN] $sbatch was cancelled due to time limit";
            next;
        }

        ## record launch id with sbatch script
        next unless ( $cxl =~ /PREEMPTION|CANCELLED/ );
        $relaunch{ $ids[4] } = $sbatch;
    }

    ## get launched then remove.
    my @indexs = `cat launch.index`;

    my $relaunch = 0;
    foreach my $line (@indexs) {
        chomp $line;
        my @parts = split /\s/, $line;

        ## find in lookup and dont re-relaunch.
        if ( $relaunch{ $parts[-1] } ) {
            my $file = $parts[0] . '.launched';

            my @dropped_cmds =
              `sed -n '/^## Commands/,/^## End of Commands/p' $file`;

            my @cleaned_dropped;
            foreach my $cmd (@dropped_cmds) {
                chomp $cmd;
                next if ( $cmd =~ /^##/ );
                $cmd =~ s/&$//;
                push @cleaned_dropped, $cmd;
            }

            open( my $CF, '>>', $self->command_file ) 
                or $self->ERROR("Could not open $self->command_file.");

            map { say $CF $_ } @cleaned_dropped;
            $relaunch++;
        }
    }

    ## remove error files.
    unlink @error_files;
    $self->idle if $relaunch;
}

## ----------------------------------------------------- ##

sub _idle_process_check {
    my $self = shift;

    my @processing;
    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {

        my $squeue_command = sprintf(
            "%s -u %s -h --format %s",
            $self->{SQUEUE}->{$cluster},
            $self->user, "\"%A\""
        );
        next if ( !$squeue_command );
        my @usage = `$squeue_command`;
        map { push @processing, $_ } @usage;
    }
    if ( !@processing ) { return 0 }

    ## check run specific processing.
    ## make lookup of what is running.
    my %running;
    foreach my $active (@processing) {
        chomp $active;
        $active =~ s/\s+//g;
        $running{$active}++;
    }

    my @launched = `cat launch.index`;
    chomp @launched;
    if (! @launched) {
        $self->ERROR("Can't find needed launch.index file.");
    }

    my $current = 0;
    foreach my $launch (@launched) {
        chomp $launch;
        my @result = split /\s+/, $launch;

        if ( $running{ $result[-1] } ) {
            $current++;
        }
    }
    ($current) ? ( return 1 ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub _idle_hanging_check {
    my $self = shift;

    my @launched = `cat launch.index`;
    $self->ERROR("launch.index file not found.") if ( !@launched );

    ## make lookup.
    my %launch_index;
    foreach my $current (@launched) {
        chomp $current;
        my @launch_info = split /\s+/, $current;
        $launch_index{ $launch_info[-1] }++;
    }

    my %relaunch;
    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
        chomp $cluster;

        my $reason = sprintf(
            "%s -u %s -h --format %s",
            $self->{SQUEUE}->{$cluster},
            $self->user, "\"%A %r\""
        );
        my @result = `$reason`;
        next if ( !@result );

        foreach my $responce (@result) {
            chomp $responce;
            my ( $id, $reason ) = split /\s+/, $responce;

            ## keep current and focused.
            next unless ( $launch_index{$id} );
            next unless ( $reason =~ /(ReqNodeNotAvail|Resources|Priority)/ );

            $self->{hang_count}{$id} += 1;
            if ( $self->{hang_count}{$id} > 10 ) {
                $self->WARN("Job being killed and relaunched due to hangtime.");
                my $cxl = sprintf( "%s %s", $self->{SCANCEL}->{$cluster}, $id );
                system($cxl);
            }
        }
    }
}

## ----------------------------------------------------- ##

sub _idle_error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    ## if errors still found, keep trying to relaunch
    $self->WARN("Canceled jobs found, relaunching them...");
    $self->_wait_all_jobs();
}

## ----------------------------------------------------- ##

1;
