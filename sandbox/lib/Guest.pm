package Guest;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Dir;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub guest {
    my $self   = shift;
    my $cmds   = $self->get_cmds;
    my $access = $self->ican_access;

    while ( my ( $node_name, $node_data ) = each %{$access} ) {
        my $beacon_count = $node_data->{nodes_count};

        for ( my $i = 0 ; $i < $beacon_count ; $i++ ) {
            $self->beacon_writer($node_data);
        }
    }

    my $ooo;
}

## ----------------------------------------------------- ##
#
#sub create_beacon {
#    my ( $self, $node_info ) = @_;
#    my $beacon_count = $node_info->{nodes_count};
#
#    for ( my $i = 0 ; $i < $beacon_count ; $i++ ) {
#        $self->beacon_writer($node_info);
#    }
#}

## ----------------------------------------------------- ##
          
    ##my $jj;
#  RECHECK:
#    my $access = $self->ican_access;
#
#    my %claimed;
#    while ( my ( $node_name, $value ) = each %{$access} ) {
#        last unless ( @{$cmds} );
#
#        my $info_hash       = pop @{$value};
#        my $number_of_nodes = pop @{$value};
#
#        next unless ( $number_of_nodes >= 1 );
#
#        ## check for excluded cluster.
#        if ( $info_hash->{account_info}->{CLUSTER} eq $self->exclude_cluster ) {
#            next;
#        }
#
#        if ( $self->nodes_per_sbatch > 1 ) {
#
#            ## check if there are enough nodes if asked
#            if ( $number_of_nodes < $self->nodes_per_sbatch ) {
#                $self->INFO(
#                    "Cluster $info_hash->{account_info}->{CLUSTER} does not have enough nodes."
#                );
#                next;
#            }
#
#            $self->INFO("multi-node job to $info_hash->{account_info}->{CLUSTER} cluster.");
#            $self->INFO("On $info_hash->{account_info}->{ACCOUNT} account.");
#            $self->INFO("On $info_hash->{account_info}->{PARTITION} partition.");
#            $self->INFO("----------------------------------------------------");
#
#            ## reduce number of nodes aval
#            $number_of_nodes -= $self->nodes_per_sbatch;
#
#            my $jobsper = $self->jobs_per_sbatch;
#            my @stack;
#            for ( 1 .. $jobsper ) {
#                my $single_cmd = shift @{$cmds};
#                push @stack, $single_cmd;
#            }
#            $self->multi_node_guest_writer( \@stack, $info_hash );
#        }
#
#        else {
#            ## step message
#            $self->INFO("Checking $info_hash->{account_info}->{CLUSTER} cluster for nodes.");
#            $self->INFO("----------------------------------------------------");
#
#            foreach my $node ( @{$value} ) {
#                last unless ( @{$cmds} );
#
#                ## check if node already claimed or add to store.
#                next if ( $self->{node_track}{$node->{NODE}} );
#                $self->{node_track}{$node->{NODE}}++;
#
#                ## check for hyperthread option.
#                if ( $self->hyperthread ) {
#                    $node->{CPUS} = ( $node->{CPUS} * 2 );
#                }
#
#                my $jobsper;
#                if ( $self->jobs_per_sbatch > $node->{CPUS} ) {
#                    $jobsper = $node->{CPUS};
#                }
#                else {
#                    $jobsper = $self->jobs_per_sbatch;
#                }
#
#                my @stack;
#                for ( 1 .. $jobsper ) {
#                    my $single_cmd = shift @{$cmds};
#                    push @stack, $single_cmd;
#                }
#                $self->guest_writer( $node, \@stack, $info_hash );
#            }
#        }
#
#        ## launch guest jobs
#        $self->guest_launcher($info_hash);
#    }
#
#    while ( @{$cmds} ) {
#        my $num_of_jobs = scalar @{$cmds};
#        $self->INFO("~~ All available nodes used,  but commands remain. ~~");
#        $self->INFO("~~ Number of commands left: $num_of_jobs. ~~");
#        $self->INFO("~~ Waiting/Checking for more nodes.... ~~");
#        $self->INFO("----------------------------------------------------");
#
#        ## quick check for hanging jobs.
#        sleep(60);
#        $self->INFO("Checking for hanging jobs.");
#        $self->_guest_hanging_check;
#        goto RECHECK;
#    }
#    $self->INFO("Reviewing state of jobs...");
#    $self->INFO("Relaunching if needed...");
#    $self->_guest_wait_all_jobs();

#}

## ----------------------------------------------------- ##

sub guest_launcher {
    my ( $self, $info_hash ) = @_;

    ## create output file
    open( my $OUT, '>>', 'launch.index' );

    my $DIR     = IO::Dir->new(".");
    my $running = 0;
    foreach my $launch ( $DIR->read ) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        print $OUT "$launch\t";
        my $batch = sprintf( "%s %s >> launch.index",
            $self->{SBATCH}->{ $info_hash->{account_info}->{CLUSTER} },
            $launch );
        system $batch;

        ## rename so not double launched.
        rename $launch, "$launch.launched";
    }
}

## ----------------------------------------------------- ##

sub _guest_wait_all_jobs {
    my $self = shift;

    my $process;
    do {
        sleep(60);
        $self->INFO("Checking if jobs need to be relaunched.");
        $self->_guest_hanging_check;
        $self->_guest_relaunch;
        sleep(60);
        $self->INFO("Checking current processing.");
        $process = $self->_guest_process_check();
    } while ($process);
}

## ----------------------------------------------------- ##

sub _guest_relaunch {
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
    $self->guest if $relaunch;
}

## ----------------------------------------------------- ##

sub _guest_process_check {
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

sub _guest_hanging_check {
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

sub _guest_error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    ## if errors still found, keep trying to relaunch
    $self->WARN("Canceled jobs found, relaunching them...");
    $self->_wait_all_jobs();
}

## ----------------------------------------------------- ##

1;
