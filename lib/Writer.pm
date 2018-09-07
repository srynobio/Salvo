package Writer;
use strict;
use warnings;
use feature 'say';
use Moo::Role;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub dedicated_writer {
    my ( $self, $cmdStack ) = @_;

    my $jobname   = $self->jobname . '-' . $self->random_id;
    my $slurm_out = $jobname . '.out';
    my $slurm_err = $jobname . '.err';
    my $outfile   = $jobname . '.sbatch';

    my $cmds = join( "\n", @{$cmdStack} );

    my $extra_steps = '';
    if ( $self->additional_steps ) {
        $extra_steps = join( "\n", @{ $self->additional_steps } );
    }

    # add the exclude option
    my $exclude = '';
    if ( $self->exclude_nodes ) {
        my $nodes = $self->exclude_nodes;
        my ( $node, $list ) = split /:/, $nodes;
        $exclude = "#SBATCH -x $list";
    }

    ## write out object
    my $runtime   = $self->runtime;
    my $nps       = $self->nodes_per_sbatch;
    my $account   = $self->account;
    my $partition = $self->partition;
    #######my $qos = $self->qos;

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $runtime
#SBATCH -N $nps
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out
#SBATCH -e $slurm_err
$exclude

source /scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun

module load ucgd_modules
$extra_steps

# clean up before start
/scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun

$cmds

wait

# clean up after finish.
/scratch/ucgd/lustre/ugpuser/shell/slurm_job_postrun

EOM
    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;
    close $OUT;

    return $outfile;
}

## ----------------------------------------------------- ##

sub mpi_writer {
    my ( $self, $node_detail ) = @_;

    my $jobname   = $self->jobname . '-' . $self->random_id;
    my $slurm_out = $jobname . '.out';
    my $slurm_err = $jobname . '.err';
    my $outfile   = $jobname . '.sbatch';
    my $nps       = $self->nodes_per_sbatch;

    # collect from info hash & object
    my $account        = $node_detail->{ACCOUNT};
    my $requested_node = $node_detail->{NODE};
    my $partition      = $node_detail->{PARTITION};
####    my $work_dir = $self->work_dir;
    my $runtime  = $self->runtime;
    my $user     = $self->user;

    my $exclude = '';
    if ( $self->exclude_nodes ) {
        my $nodes = $self->exclude_nodes;
        my ( $node, $list ) = split /:/, $nodes;
        if ( $partition =~ /$node/ ) {
            $exclude = "#SBATCH -x $list";
        }
    }

    my $extra_steps = '';
    if ( $self->additional_steps ) {
        $extra_steps = join( "\n", @{ $self->additional_steps } );
    }

    ## get localhost and localport to pass to beacon
    my $localhost   = $self->localhost;
    my $localport   = $self->localport;
    my $beacon_opts = "$localhost $localport";

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $runtime
#SBATCH -N $nps
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out
#SBATCH -e $slurm_err
$exclude

# Working directory
###cd jjjjwork_dir

source /scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun

module load ucgd_modules
$extra_steps

# clean up before start
/scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun

beacon.pl $beacon_opts

wait

# clean up after finish.
/scratch/ucgd/lustre/ugpuser/shell/slurm_job_postrun

EOM
    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;
    close $OUT;
}

## ----------------------------------------------------- ##





sub standard_writer {
    my $self = shift;

    my $jfkdjfkd;
}

    
# sub standard_writer {
#    my $self = shift;
#    ##########my ( $self, $node_detail ) = @_;
#
#    my $jobname   = $self->jobname . '-' . $self->random_id;
#    my $slurm_out = $jobname . '.out';
#    my $outfile   = $jobname . '.sbatch';
#
#=cut
#    # collect from info hash & object
#    my $account        = $node_detail->{ACCOUNT};
#    my $requested_node = $node_detail->{NODE};
#    my $partition      = $node_detail->{PARTITION};
####    my $work_dir       = $self->work_dir;
#    my $runtime        = $self->runtime;
#    my $user           = $self->user;
#
#    my $exclude = '';
#    if ( $self->exclude_nodes ) {
#        my $nodes = $self->exclude_nodes;
#        my ( $node, $list ) = split /:/, $nodes;
#        if ( $partition =~ /$node/ ) {
#            $exclude = "#SBATCH -x $list";
#        }
#    }
#
#    my $extra_steps = '';
#    if ( $self->additional_steps ) {
#        $extra_steps = join( "\n", @{ $self->additional_steps } );
#    }
#=cut
#
#    ## get localhost and localport to pass to beacon
#    my $localhost   = $self->localhost;
#    my $localport   = $self->localport;
#    my $beacon_opts = "$localhost $localport";
#
#    my $sbatch = <<"EOM";
##!/bin/bash
##SBATCH -t $runtime
##SBATCH -A $account
##SBATCH -p $partition
##SBATCH -J $jobname
##SBATCH -o $slurm_out
##SBATCH -w $requested_node
#$exclude
#
## Working directory
######cd work_dir
#
#source /scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun
#module load ucgd_modules
#$extra_steps
#
## clean up before start
#/scratch/ucgd/lustre/ugpuser/shell/slurm_job_prerun
#
#beacon.pl $beacon_opts
#
#wait
#
## clean up after finish.
#/scratch/ucgd/lustre/ugpuser/shell/slurm_job_postrun
#
#EOM
#    open( my $OUT, '>', $outfile );
#    say $OUT $sbatch;
#    close $OUT;
#}

## ----------------------------------------------------- ##

sub random_id {
    my $self = shift;

    my $id      = int( rand(10000) );
    my $jobname = $self->jobname . "-$id.sbatch";
    say $jobname;
    if ( -e $jobname ) {
        $id = $self->random_id;
    }
    return $id;
}

## ----------------------------------------------------- ##

1;
