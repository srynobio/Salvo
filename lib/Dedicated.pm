package Dedicated;
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

sub dedicated {
    my $self = shift;

    my $cmds = $self->get_cmds;

    # split base on jps, then create sbatch scripts.
    my @stack;
    push @stack, [ splice @{$cmds}, 0, $self->jobs_per_sbatch ] while @{$cmds};

    foreach my $cmd (@stack) {
        chomp $cmd;
        $self->dedicated_writer($cmd);
    }

    ## launch sbatch scripts.
    $self->dedicated_launcher;

    # give sbatch system time to work
    sleep(30);

    # check the status of current sbatch jobs
    # before moving on.

    $self->INFO("Jobs launched, monitoring process.");
    $self->_dedicated_wait_all_jobs();
    $self->_dedicated_error_check();
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
            my $launch = sprintf( "%s %s &>> launch.index",
                $self->{SBATCH}->{ $self->{cluster} }, $launch );
            system $launch;
            $running++;
            next;
        }
    }
}

## ----------------------------------------------------- ##

sub _jobs_status {
    my $self = shift;

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

sub _dedicated_wait_all_jobs {
    my $self = shift;

    my $process;
    do {
        sleep(60);
        $self->INFO("Checking processing jobs.");
        $process = $self->_dedicated_process_check();
    } while ($process);
}

## ----------------------------------------------------- ##

sub _dedicated_process_check {
    my $self = shift;

    ## make running lookup.
    my $find = sprintf(
        "%s -u %s -A %s --format=%s -h",
        $self->{SQUEUE}->{ $self->{cluster} },
        $self->user, $self->account, "\"%A\""
    );
    my @running = `$find`;
    return if ( !@running );

    my %processing;
    foreach my $run (@running) {
        chomp $run;
        $processing{$run}++;
    }

    my @indexes = `cat launch.index`;
    chomp @indexes;

    my $current;
    foreach my $launched (@indexes) {
        chomp $launched;

        my @section = split /\s+/, $launched;
        if ( $processing{ $section[-1] } ) {
            $current++;
        }
    }
    ($current) ? ( return 1 ) : ( return 0 );
}

## ----------------------------------------------------- ##

sub _dedicated_error_check {
    my $self = shift;

    my @error = `grep error *.out`;
    if ( !@error ) { return }

    $self->ERROR("*out files were found error messages.");
}

## ----------------------------------------------------- ##

1;

