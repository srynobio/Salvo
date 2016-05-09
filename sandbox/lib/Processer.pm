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

    my $jobid = 1;
    foreach my $cmd (@stack) {
        chomp $cmd;
        $jobid++;
        $self->dedicated_writer( $cmd, $jobid );
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
    my $self  = shift;
    my $cmds  = $self->cmds;
    my $jobid = 1;

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

        ## step message
        $self->WARN("Launching to $info_hash->{account_info}->{CLUSTER} cluster.");
        $self->WARN("Total of $number_of_nodes nodes available.");
        $self->WARN("On $info_hash->{account_info}->{ACCOUNT} account.");
        $self->WARN("On $info_hash->{account_info}->{PARTITION} partition.");
        $self->WARN("----------------------------------------------------");

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

            $self->guest_writer( $node, \@stack, $info_hash, $jobid );
            $jobid++;
        }
        ## launch to node!
        $self->guest_launcher($info_hash);
    }

    while ( @{$cmds} ) {
        $self->WARN("No available nodes, but commands remain.");
        $self->WARN("Waiting for more nodes....");
        $self->WARN("----------------------------------------------------");
        sleep(120);
        goto RECHECK;
    }
    $self->_wait_all_jobs();
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
        system "$self->{SBATCH}->{$info_hash->{account_info}->{CLUSTER}} $launch >> launch.index";

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
            system
              "$self->{SBATCH}->{$self->{cluster}} $launch &>> launch.index";
            $running++;
            next;
        }
    }
}

## ----------------------------------------------------- ##

sub _jobs_status {
    my $self = shift;
    my $state = `$self->{SQUEUE}->{$self->{cluster}} -A $self->{account} -u $self->{user} -h | wc -`;

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

    my @indexs = `cat launch.index`;
    chomp @indexs;

    foreach my $line (@indexs) {
        chomp $line;
        my @parts = split /\s/, $line;

        ## find in lookup and dont re-relaunch.
        if ( $relaunch{ $parts[-1] } ) {
            my $launch_cmd = "$self->{SBATCH}->{$self->{cluster}} $relaunch{$parts[-1]} >> launch.index";
            system $launch_cmd;
            say "[WARN] Relaunching job $relaunch{$parts[-1]}";
        }
    }
    ## remove error files.
    unlink @error_files;
}

## ----------------------------------------------------- ##

sub _process_check {
    my $self = shift;

    my @processing;
    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
        my $squeue_command =
          "$self->{SQUEUE}->{$cluster} -u $self->{user} -h --format=%A";
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

sub _error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    ## if errors still found, keep trying to relaunch
    $self->_wait_all_jobs();
}

## ----------------------------------------------------- ##

1;
