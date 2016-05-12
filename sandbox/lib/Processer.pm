package Processer;
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

sub fire {

    my $self = shift;

    if ( $self->mode eq 'dedicated' ) {
        $self->dedicated;
    }
    elsif ( $self->mode eq 'guest' ) {
        $self->guest;
    }
    else {
        $self->ERROR("Misfire!! $self->mode not an mode option.");
    }

    ## update command file back to original
    my $file   = $self->command_file;
    my $rename = "$file.read-commands";
    rename $rename, $file;

    unlink 'launch.index';
    say "Salvo Done!";
    exit(0);
}

## ----------------------------------------------------- ##

sub dedicated {
    my $self = shift;

    my $cmds = $self->cmds;

    # split base on jps, then create sbatch scripts.
    my @stack;
    push @stack, [ splice @{$cmds}, 0, $self->jobs_per_sbatch ] while @{$cmds};

    foreach my $cmd (@stack) {
        chomp $cmd;
        $self->dedicated_writer( $cmd );
    }

    ## launch sbatch scripts.
    $self->dedicated_launcher;

    # give sbatch system time to work
    sleep(30);

    # check the status of current sbatch jobs
    # before moving on.
    $self->_wait_all_jobs();
    $self->_error_check();
}

## ----------------------------------------------------- ##

sub guest {
    my $self = shift;
    my $cmds = $self->cmds;

  RECHECK:
    my $access = $self->ican_access;

    while ( my ( $node_name, $value ) = each %{$access} ) {
        last unless ( @{$cmds} );

        my $info_hash       = pop @{$value};
        my $number_of_nodes = pop @{$value};

        ## check for excluded cluster.
        if ( $info_hash->{account_info}->{CLUSTER} eq $self->exclude_cluster ) {
            next;
        }

        if ( $self->nodes_per_sbatch > 1 ) {

            ## check if there are enough nodes if asked
            next if ( $number_of_nodes < $self->nodes_per_sbatch );

            $self->INFO("multi-node job to $info_hash->{account_info}->{CLUSTER} cluster.");
            $self->INFO("On $info_hash->{account_info}->{ACCOUNT} account.");
            $self->INFO("On $info_hash->{account_info}->{PARTITION} partition.");
            $self->INFO("----------------------------------------------------");

            ## reduce number of nodes aval
            $number_of_nodes -= $self->nodes_per_sbatch;

            my $jobsper = $self->jobs_per_sbatch;
            my @stack;
            for ( 1 .. $jobsper ) {
                my $single_cmd = shift @{$cmds};
                push @stack, $single_cmd;
            }
            $self->multi_node_guest_writer( \@stack, $info_hash );
        }

        else {

            ## step message
            $self->INFO("Launching to $info_hash->{account_info}->{CLUSTER} cluster.");
            $self->INFO("Total of $number_of_nodes nodes available.");
            $self->INFO("On $info_hash->{account_info}->{ACCOUNT} account.");
            $self->INFO("On $info_hash->{account_info}->{PARTITION} partition.");
            $self->INFO("----------------------------------------------------");

            foreach my $node ( @{$value} ) {
                last unless ( @{$cmds} );

                ## check for hyperthread option.
                if ( $self->hyperthread ) {
                    $node->{CPUS} = ( $node->{CPUS} * 2 );
                }

                my $jobsper;
                if ( $self->jobs_per_sbatch > $node->{CPUS} ) {
                    $jobsper = $node->{CPUS};
                }
                else {
                    $jobsper = $self->jobs_per_sbatch;
                }

                my @stack;
                for ( 1 .. $jobsper ) {
                    my $single_cmd = shift @{$cmds};
                    push @stack, $single_cmd;
                }
                $self->guest_writer( $node, \@stack, $info_hash );
            }
            ## launch to node!
        }

            $self->guest_launcher($info_hash);



        while ( @{$cmds} ) {
            my $num_of_jobs = scalar @{$cmds};
            $self->INFO("~~ No available nodes, but commands remain. ~~");
            $self->INFO("~~ Number of commands left: $num_of_jobs ~~");
            $self->INFO("~~ Waiting for more nodes.... ~~");
            $self->INFO("----------------------------------------------------");
   ##    sleep(30);
            $self->INFO("Checking the state of all jobs.");
            $self->state_check;
            goto RECHECK;
        }
        $self->_wait_all_jobs();
    }
}

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
        my $batch = sprintf(
            "%s %s >> launch.index",
            $self->{SBATCH}->{$info_hash->{account_info}->{CLUSTER}}, $launch 
        );
        system $batch;

        ## rename so not mislaunched.
        rename $launch, "$launch.launched";
    }
}

## ----------------------------------------------------- ##

sub dedicated_launcher {
    my $self = shift;

    my $DIR     = IO::Dir->new(".");
    my $running = 0;
    foreach my $launch ( $DIR->read ) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        if ( $running >= $self->queue_limit ) {
            my $status = $self->_jobs_status();
            if ( $status eq 'add' ) {
                $running--;
                redo;
            }
            elsif ( $status eq 'wait' ) {
                sleep(10);
                redo;
            }
        }
        else {
            my $launch = sprintf(
                "%s %s &>> launch.index",
                $self->{SBATCH}->{$self->{cluster}}, $launch 
            );
            system $launch; 
            $running++;
            next;
        }
    }
}

## ----------------------------------------------------- ##

sub _jobs_status {
    my $self   = shift;

    my $squeue = sprintf(
        "%s -A %s -u %s -h | wc -l",
        $self->{SQUEUE}->{ $self->{cluster} },
        $self->account, $self->user
    );
    my $state = `$squeue`;

    if ( $state >= $self->queue_limit ) {
        return 'wait';
    }
    else {
        return 'add';
    }
}

## ----------------------------------------------------- ##

sub _wait_all_jobs {
    my $self = shift;

    $self->INFO("All jobs launched. Processing.");

    my $process;
    do {
        sleep(60);
        $self->_relaunch();
        sleep(60);
        $process = $self->_process_check();
    } while ($process);
}

## ----------------------------------------------------- ##

sub _relaunch {
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
    chomp @indexs;

    my $relaunch = 0;
    foreach my $line (@indexs) {
        chomp $line;
        my @parts = split /\s/, $line;

        ## find in lookup and dont re-relaunch.
        if ( $relaunch{ $parts[-1] } ) {
            my $orig_file = $parts[0] . '.launched';

            my @dropped_cmds =
              `sed -n '/^## Commands/,/^## End of Commands/p' $orig_file`;

            my @cleaned_dropped;
            foreach my $cmd (@dropped_cmds) {
                chomp $cmd;
                next if ( $cmd =~ /^##/ );
                $cmd =~ s/&$//;
                push @cleaned_dropped, $cmd;
            }

            open( my $CF, '>>', $self->command_file );
            $self->INFO("Writing Preempted commands to relaunch.");
            map { say $CF $_ } @cleaned_dropped;
            $relaunch++;
        }
    }

    ## remove error files.
    unlink @error_files;
    $self->guest if $relaunch;
}

## ----------------------------------------------------- ##

sub _process_check {
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

    ## check what was launched.
    open( my $LAUNCH, '<', 'launch.index' )
      or die "[ERROR] Can't find needed launch.index file.";

    my $current = 0;
    foreach my $launched (<$LAUNCH>) {
        chomp $launched;
        my @result = split /\s+/, $launched;

        if ( $running{ $result[-1] } ) {
            $current++;
        }
    }
    ($current) ? ( return 1 ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub state_check {
    my $self = shift;

    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
        chomp $cluster;

        my $reason = sprintf(
            "%s -u %s -h --format %s",
            $self->{SQUEUE}->{$cluster},
            $self->user, "\"%A %r\""
        );
        my @result = `$reason`;

        next if ( !@result );
        my @notAval = grep { $_ =~ /ReqNodeNotAvail/ } @result;
        next if ( !@notAval );

        foreach my $stopped (@notAval) {
            chomp $stopped;
            my ( $id, $reason ) = split /\s+/, $stopped;

            $self->WARN(
                "Job $id on $cluster being killed and relaunched due to: $reason"
            );
            my $cxl = sprintf( "%s %s", $self->{SCANCEL}->{$cluster}, $id );
            system($cxl);
        }
    }
}

## ----------------------------------------------------- ##

sub _error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    ## if errors still found, keep trying to relaunch
    $self->_wait_all_jobs();
}

## ----------------------------------------------------- ##

1;
