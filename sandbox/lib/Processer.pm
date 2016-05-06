package Processer;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use IO::Dir;

use Data::Dumper;

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
        $self->ERROR("Mode: $self->mode not an option.");
    }
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

    ## move to moniter the queue.
    $self->sbatch_launcher;

    # give sbatch system time to work
    sleep(10);

    # check the status of current sbatch jobs
    # before moving on.
    _wait_all_jobs();
    _error_check();
    unlink('launch.index');
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
        $self->guest_launcher($info_hash);
    }

    while ( @{$cmds} ) {
        $self->WARN("No available nodes, but commands remain.");
        $self->WARN("Waiting for more nodes.");
        $self->WARN("----------------------------------------------------");
        sleep(60);
        goto RECHECK;
    }

    ### right here!!!!!!!!!!!!!!!!!!
    my $stopandlook;

}

## ----------------------------------------------------- ##

sub guest_launcher {
    my ( $self, $info_hash ) = @_;

    my $DIR     = IO::Dir->new(".");
    my $running = 0;
    foreach my $launch ( $DIR->read ) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );
        system "$self->{SBATCH}->{$info_hash->{account_info}->{CLUSTER}} $launch &>> launch.index";
    }
}

## ----------------------------------------------------- ##

sub sbatch_launcher {
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
            system "$self->{SBATCH}->{$self->cluster} $launch &>> launch.index";
            $running++;
            next;
        }
    }
}

## ----------------------------------------------------- ##

sub _jobs_status {
    my $self = shift;
    my $state = `$self->{SQUEUE}->{$self->cluster} -A $self->account -u $self->user -h | wc -`;

    if ( $state >= $self->queue_limit ) {
        return 'wait';
    }
    else {
        return 'add';
    }
}

## ----------------------------------------------------- ##

1;
