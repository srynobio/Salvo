#!/usr/bin/env perl
# Salvo
use strict;
use warnings qw(io);
use feature 'say';
use autodie;
use Getopt::Long;
use IO::Dir;
use File::Find;
use Cwd;

use Data::Dumper;

INIT {
    ## environmental variables to work with.
    $ENV{SBATCH} = {
        loanpeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sbatch',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sbatch',
    };

    $ENV{SQUEUE} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/squeue',
        loanpeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/squeue',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/squeue',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/squeue',
    };

    $ENV{SINFO} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sinfo',
        loanpeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sinfo',
    };
}

my $usage = <<"EOU";

Synopsis:

    Salvo - Slurm command and job launcher v 0.1.1

    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING>
    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING> -just_batch

Description:

    Designed to aid launching of jobs on Slurm cluster from a command list file.
    View github page <https://github.com/srynobio/Salvo> for more detailed description.

Required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -which_partition, -wp   :   Which partition to submit job to. ( ucgd-kp, or guest ).
                                guest will search all available partitions you have access to.
    -uid                    :   Your University or employee id. <STRING>


    -mode, -m               :   ????? mpi or single_jobs ?????


Options without full requirements:
    
    -sinfo_idle, -si        :   Prints to STDOUT all idle nodes in all cluster environments.
    -squeue_me, -sm         :   Prints to STDOUT squeue information in all cluster environments under your uid number. (uid required)

    -report_node_info, -ni  :   Will report user specific guest node information. (uid required).

Additional options:
    
    -time, -t               :   Time to allow each job to run on node <STRING> (default 1:00:00).
    -node, -n               :   Number of nodes to run per sbatch job submitted. <INT> (default 1).
    -queue_limit, -ql       :   Number of jobs to launch and run in the total CHPC queue at one time. <INT> (default 1).
    -jobs_per_sbatch, -jps  :   Number of jobs to add to each sbatch script. <INT> (default 1).
                                This will be reset to available CPUs per node in guest mode, unless -halt_reset used.
    -halt_reset, -hr        :   Will stop CPU per node reset. <BOOL> (default false).
    -added_steps, -as       :   Additional step[s] or commands to add to each sbatch job <STRING> (comma separated).
    -concurrent, -cnt       :   Will run jobs concurrently if desired by adding \"&\" to the end of each command. <BOOL> (default false).
    -just_sbatch            :   This option will create all sbatch jobs die, but not submit them (default FALSE).
    -chdir                  :   This option will tell each sbatch job to cd into this directory before running command. <STRING> (default current).
    -clean                  :   Option will remove launch.index, *sbatch and *out jobs.
    -help                   :   Prints this battleworn help message.

EOU

my %salvo_opts;
GetOptions(
    \%salvo_opts,            "command_file|cf=s",
    "jobs_per_sbatch|jps=i", "time|t=s",
    "nodes|n=i",             "queue_limit|ql=i",
    "clean",                 "just_sbatch",
    "added_steps|as=s",      "chdir=s",
    "uid=s",                 "which_partition|wp=s",
    "sinfo_idle|si",         "squeue_me|sm",
    "report_node_info|ni",   "mode|m=s",
    "concurrent|cnt",        "halt_reset|hr",
    "help|h",
);

## Options without full requirements:
if ( $salvo_opts{sinfo_idle} ) {
    sinfo_idle();
    exit(0);
}

if ( $salvo_opts{squeue_me} ) {
    if ( !$salvo_opts{uid} ) {
        die $usage, "-uid required!";
    }
    squeue_me();
    exit(0);
}

if ( $salvo_opts{report_node_info} ) {
    if ( !$salvo_opts{uid} ) {
        die $usage, "-uid required!";
    }
    report_node_info();
    exit(0);
}

# Just run clean up.
if ( $salvo_opts{clean} ) {
    system("rm *mark *out *sbatch launch.index");
    say "Cleaned up!";
    exit(0);
}

## Require check
unless ($salvo_opts{command_file}
    and $salvo_opts{which_partition}
    and $salvo_opts{uid} 
    and $salvo_opts{mode} )
{
    die "$usage\n[ERROR] - Required options: command_file, uid, which_partition and mode";
}

## clean up old sbatch scripts.
say "Looking for and removing any prior sbatch scripts";
my @found_sbatch = `find . -user $salvo_opts{uid} -name \"*sbatch\"`;
chomp @found_sbatch;
if (@found_sbatch) {
    say "removing found sbatch scripts";
    map { `rm $_` } @found_sbatch;
}

## set up some defaults.
$salvo_opts{jobs_per_sbatch} //= 1;
$salvo_opts{time}            //= '1:00:00';
$salvo_opts{nodes}           //= 1;
$salvo_opts{queue_limit}     //= 1;
$salvo_opts{which_partition} //= 'ucgd-kp';

## if steps were added get them ready.
my @steps;
if ( $salvo_opts{added_steps} ) {
    if ( $salvo_opts{added_steps} =~ /\,/ ) {
        @steps = split /\,/, $salvo_opts{added_steps};
    }
    else {
        push @steps, $salvo_opts{added_steps};
    }
}

## Get the supplied dir or the current working.
my $dir = ( ( $salvo_opts{chdir} ) ? $salvo_opts{chdir} : getcwd );

# open command file
my $CMDS = IO::File->new( $salvo_opts{command_file} );

## set up commands
my @cmds;
foreach my $cmd (<$CMDS>) {
    chomp $cmd;
    if ( $salvo_opts{concurrent} ) {
        $cmd =~ s/$/ &/;
        push @cmds, $cmd;
    }
    else {
        push @cmds, $cmd;
    }
}
$CMDS->close;

## which nodes to use.
if ( $salvo_opts{which_partition} eq 'ucgd-kp' ) {
    launch_ucgd();
    exit(1);
}

elsif ( $salvo_opts{which_partition} eq 'guest' ) {
    launch_guest();
    exit(1);
}
else {
    die "[ERROR] partition $salvo_opts{which_partition} not an option\n";
}

## -------------------------------------------------------------------- ##

sub monitor_jobs {}



## -------------------------------------------------------------------- ##

sub report_node_info {

    say "Partition\tAvailableNodes\tTotalCPUs\tNodeList";
    say "---------\t--------------\t---------\t--------";

    my $accs_nodes = ican_access();
    if ( ! keys %{$accs_nodes} ) {
        say "[WARN] No available nodes to review.";
        exit(0);
    }

    my $total_node;
    my $total_cpus;
    foreach my $partn ( keys %{$accs_nodes} ) {

        my ( @ids, $cpus );
        foreach my $node ( @{ $accs_nodes->{$partn} } ) {
            if ( ref $node eq 'HASH' and $node->{NODE} ) {
                push @ids, $node->{NODE};
            }
            if ( ref $node eq 'HASH' and $node->{CPUS} ) {
                $cpus += $node->{CPUS};
            }
        }
        my $node_number = $accs_nodes->{$partn}->[-2];
        $total_node += $node_number;
        $total_cpus += $cpus;

        my $format = sprintf( "%-20s\t%s\t%s\t%s",
            $partn, $node_number, $cpus, join( ',', @ids ) );
        say $format;
    }
    say "[Total AvailableNodes: $total_node]";
    say "[Total AvailableCPUs: $total_cpus]";
}

## -------------------------------------------------------------------- ##

sub launch_guest {
    my $jobid = 1;

    RECHECK:

    ## checking for nodes or pausing and retrying until found.
    say "[WARN] Checking for available nodes...";
    my $accs_nodes = ican_access();
    while ( ! keys %{$accs_nodes} ) {
        sleep(60);
        $accs_nodes = ican_access();
    }

    foreach my $partn ( keys %{$accs_nodes} ) {
        ## collect the account info.
        my $acct_hash = $accs_nodes->{$partn}->[-1];

        ## each node from the partition.
        foreach my $ind_node ( @{ $accs_nodes->{$partn} } ) {
            last if ( !@cmds );

            ## only work with node data.
            next if ( ref $ind_node ne 'HASH' );
            next if ( !$ind_node->{NODE} );

            ## set the jpn number.
            my $subsect;
            if ( $salvo_opts{halt_reset} ) {
                $subsect = $salvo_opts{jobs_per_sbatch};
            }
            else {

                if (    $salvo_opts{jobs_per_sbatch}
                    and $salvo_opts{jobs_per_sbatch} > $ind_node->{CPUS} )
                {
                    say "[WARN] jobs_per_sbatch value is greater then "
                        . "available CPUs on $ind_node->{NODE}, resetting to $ind_node->{CPUS}.";
                    $subsect = $ind_node->{CPUS};
                }
                elsif ( $salvo_opts{jobs_per_sbatch}
                    and $salvo_opts{jobs_per_sbatch} < $ind_node->{CPUS} )
                {
                    $subsect = $salvo_opts{jobs_per_sbatch};
                }
                else { $subsect = $ind_node->{CPUS}; }
            }

            ## get command chunck and write sbatch script.
            my @node_work = splice( @cmds, 0, $subsect );
            guest_writer( $ind_node, \@node_work, $jobid, $acct_hash );
            $jobid++;
        }

        ## launch!
        sbatch_submitter( $acct_hash->{account_info}->{CLUSTER} );
    }

    ## continue looking for free nodes
    ## until all commands are done.
    if (@cmds) {
        say "[WARN] Number of commands left: ", scalar @cmds;
        say "[WARN] Waiting for more free guest nodes.";
        sleep(5);
        #########sleep(60);
        goto RECHECK;
    }
    
    # give sbatch system time to work
    sleep(10);

    # check the status of current sbatch jobs
    # before moving on.
    _wait_all_jobs();
    _error_check();
    unlink('launch.index');
}

## -------------------------------------------------------------------- ##

sub launch_ucgd {

    # split base on jps, then create sbatch scripts.
    my @var;
    push @var, [ splice @cmds, 0, $salvo_opts{jobs_per_sbatch} ] while @cmds;

    my $jobid = 1;
    foreach my $group (@var) {
        chomp $group;
        $jobid++;
        ucgd_writer( $group, $jobid );
    }

    ## launch!
    sbatch_submitter('kingspeak');

    # give sbatch system time to work
    sleep(10);

    # check the status of current sbatch jobs
    # before moving on.
    _wait_all_jobs();
    _error_check();
    unlink('launch.index');
}

## -------------------------------------------------------------------- ##

sub sbatch_submitter {
    my $cluster = shift;

    my $DIR     = IO::Dir->new(".");
    my $running = 0;
    foreach my $launch ( $DIR->read ) {
        chomp $launch;
        next unless ( $launch =~ /sbatch$/ );

        STATUS:
        if ( $running >= $salvo_opts{queue_limit} ) {
            my $status = _jobs_status($cluster);
            if ( $status eq 'add' ) {
                $running--;
                redo;
            }
            elsif ( $status eq 'wait' ) {
                sleep(10);
                goto STATUS;
            }
        }
        else {



            ######## some kind of dup going on???
            system "$ENV{SBATCH}->{$cluster} $launch >> launch.index";
            system "cat $launch >> launch.index";
            $running++;
            next;
        }
    }
    #############
    my $ppppp;
}

## -------------------------------------------------------------------- ##

sub _wait_all_jobs {

    if ( $salvo_opts{which_partition} eq 'ucgd-kp' ) {

      LINE:
        ## get launch.index info
        open( my $LAUNCH, '<', 'launch.index' )
          or die "Can't find launch.index";
        my %indexs;
        foreach my $line (<$LAUNCH>) {
            chomp $line;
            my @info = split /\s+/, $line;
            $indexs{ $info[-1] }++;
        }
        close $LAUNCH;

        ## get currently running process info
        my @processing = `squeue -A ucgd-kp -u $salvo_opts{uid} -h --format=\"%A\"`;
        chomp @processing;

        ## return if no jobs are processing.
        return if ( !@processing );

        my $running = 0;
        foreach my $run (@processing) {
            chomp $run;
            if ( $indexs{$run} ) {
                $running++;
            }
        }

        ## if jobs are running sleep and recheck
        if ( $running >= 1 ) {
            sleep(60);
            goto LINE;
        }
        else { return }
    }

    if ( $salvo_opts{which_partition} eq 'guest' ) {

        my $process;
        do {
            sleep(60);
            _relaunch();
            sleep(60);
            $process = _process_check();
        } while ($process);
    }
}

## -------------------------------------------------------------------- ##

sub _error_check {
    my @error = `grep error *.out`;
    chomp @error;
    if ( !@error ) { return }

    say "[WARN] lines containing error text were discovered.";
    map { say "[WARN] $_" } @error;
}

## -------------------------------------------------------------------- ##

sub _process_check {

    my @processing = `squeue -A $salvo_opts{account} -u u0413537 -h --format=%A`;
    chomp @processing;
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


## -------------------------------------------------------------------- ##

sub _jobs_status {
    my $cluster = shift;

    if ( $salvo_opts{which_partition} eq 'ucgd-kp' ) {
        my $state = `$ENV{SQUEUE}->{$cluster} -A ucgd-kp -u $salvo_opts{uid} -h |wc -l`;

        if ( $state >= $salvo_opts{queue_limit} ) {
            return 'wait';
        }
        else { return 'add' }
    }
    if ( $salvo_opts{which_partition} eq 'guest' ) {

        my $state;
        foreach my $cluster ( keys %{ $ENV{SINFO} } ) {
            my $total =
              `$ENV{SQUEUE}->{$cluster} -u $salvo_opts{uid} -h |wc -l`;
            $state += $total;
        }

        if ( $state >= $salvo_opts{queue_limit} ) {
            return 'wait';
        }
        else { return 'add' }
    }
}

## -------------------------------------------------------------------- ##

sub squeue_me {
    foreach my $cluster ( keys %{ $ENV{SQUEUE} } ) {
        system("$ENV{SQUEUE}->{$cluster} -u $salvo_opts{uid} -h ");
    }
}

## -------------------------------------------------------------------- ##

sub sinfo_idle {
    foreach my $cluster ( keys %{ $ENV{SINFO} } ) {
        system("$ENV{SINFO}->{$cluster} | grep idle");
    }
}

## -------------------------------------------------------------------- ##

sub guest_writer {
    my ( $node_info, $cmds, $jobid, $acct_hash ) = @_;

    my $MEM = $node_info->{MEMORY};

    my $jobname   = 'salvo-' . $jobid;
    my $slurm_out = $jobname . '.out';
    my $outfile   = $jobname . '.sbatch';

    my $cmds = join( "\n", @{$cmds} );
    my $extra_steps = join( "\n", @steps ) if @steps;

    ## reset hyphen
    ( my $account   = $acct_hash->{account_info}->{ACCOUNT} )   =~ s/_/-/g;
    ( my $partition = $acct_hash->{account_info}->{PARTITION} ) =~ s/_/-/g;

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $salvo_opts{time}
#SBATCH -N $salvo_opts{nodes}
#SBATCH -w $node_info->{NODE}
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out

cd $dir

$extra_steps

$cmds

wait

EOM

    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;

    close $OUT;
}

## -------------------------------------------------------------------- ##

sub ucgd_writer {
    my ( $stack, $jobid ) = @_;

    my $jobname   = 'salvo-' . $jobid;
    my $slurm_out = $jobname . '.out';
    my $outfile   = $jobname . '.sbatch';

    my $cmds = join( "\n", @{$stack} );
    my $extra_steps = join( "\n", @steps ) if @steps;

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $salvo_opts{time}
#SBATCH -N $salvo_opts{nodes}
#SBATCH -A ucgd-kp
#SBATCH -p ucgd-kp
#SBATCH -J $jobname
#SBATCH -o $slurm_out

cd $dir

$extra_steps

$cmds

wait

EOM

    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;

    close $OUT;
}

## -------------------------------------------------------------------- ##

sub ican_find {

    my %guest_nodes;
    foreach my $node ( keys %{ $ENV{SBATCH} } ) {
        chomp $node;

        my $cmd =
          "$ENV{SINFO}->{$node} --format=\"%n %c %m %t %P\" | grep idle";
        my @s_info = `$cmd`;
        chomp @s_info;
        next if ( !@s_info );

        foreach my $line (@s_info) {
            chomp $line;
            my @node_details = split /\s+/, $line;

            next if ( $node_details[-1] =~ /ucgd/ );

            ## remove hyphen
            $node_details[-1] =~ s/\-/_/g;

            ## make node master table.
            push @{ $guest_nodes{ $node_details[-1] } },
              {
                NODE   => $node_details[0],
                CPUS   => $node_details[1],
                MEMORY => int( $node_details[2] / 1000 ),
              };
        }
    }
    return \%guest_nodes;
}

## -------------------------------------------------------------------- ##

sub ican_access {

    my $guest_nodes = ican_find();

    my $access = `sacctmgr list assoc format=account%30,cluster%30,qos%30 user=$salvo_opts{uid}`;
    my @node_access = split /\n/, $access;
    my @node_data = splice( @node_access, 2, $#node_access );

    my %aval;
    foreach my $id (@node_data) {
        chomp $id;

        my ( undef, $account, $cluster, $partition ) = split /\s+/, $id;

        ## remove hyphens
        $account   =~ s/\-/_/g;
        $partition =~ s/\-/_/g;

        my @partition_cache;
        if ( $partition =~ /\,/ ) {
            my @each_parti = split /\,/, $partition;

            foreach my $qos (@each_parti) {

                push @{ $aval{$qos} },
                  {
                    CLUSTER   => $cluster,
                    ACCOUNT   => $account,
                    PARTITION => $qos,
                  };
            }
        }
        else {
            push @{ $aval{$partition} },
              {
                CLUSTER   => $cluster,
                ACCOUNT   => $account,
                PARTITION => $partition,
              };
        }
    }

    foreach my $found ( keys %{$guest_nodes} ) {
        chomp $found;
        ## remove node from list with no access.
        if ( !$aval{$found} ) {
            delete $guest_nodes->{$found};
            next;
        }
        ## add number of nodes as [-2] and 
        ## account info as [-1]
        push @{ $guest_nodes->{$found} },
          scalar @{ $guest_nodes->{$found}};

        push @{ $guest_nodes->{$found} },
          { account_info => $aval{$found}->[0] };
    }
    return $guest_nodes;
}

## -------------------------------------------------------------------- ##

