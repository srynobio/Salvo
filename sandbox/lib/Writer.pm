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
    my ( $self, $stack, $jobid ) = @_;

    my $jobname   = 'salvo-' . $jobid;
    my $slurm_out = $jobname . '.out';
    my $outfile   = $jobname . '.sbatch';

    my $cmds = join( "\n", @{$stack} );

    my $extra_steps = '';
    if ( $self->additional_steps ) {
        $extra_steps = join( "\n", @{ $self->additional_steps } );
    }

    # add the exclude option
    my $exclude = '';
    if ( $self->exclude_nodes ) {
        my $nodes = $self->exclude_nodes;
        $exclude = "#SBATCH -x $nodes";
    }

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $self->runtime
#SBATCH -N $self->nodes_per_sbatch
#SBATCH -A $self->account
#SBATCH -p $self->partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out
$exclude

# Working directory
cd $self->work_dir

$extra_steps

$cmds

wait

EOM

    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;

    close $OUT;
}

## ----------------------------------------------------- ##

sub guest_writer {
    my ( $self, $node_hash, $stack, $info_hash, $jobid ) = @_;

    my $jobname   = 'salvo-' . $jobid;
    my $slurm_out = $jobname . '.out';
    my $outfile   = $jobname . '.sbatch';

    my $cmds = join( "\n", @{$stack} ) if $stack;

    my $extra_steps = '';
    if ( $self->additional_steps ) {
        $extra_steps = join( "\n", @{ $self->additional_steps } );
    }

    # add the exclude option
    my $exclude = '';
    if ( $self->exclude_nodes ) {
        my $nodes = $self->exclude_nodes;
        $exclude = "#SBATCH -x $nodes";
    }

    # collect from info hash & object
    my $account   = $info_hash->{account_info}->{ACCOUNT};
    my $partition = $info_hash->{account_info}->{PARTITION};
    $account   =~ s/_/-/g;
    $partition =~ s/_/-/g;
    my $work_dir  = $self->work_dir;
    my $runtime   = $self->runtime;
    my $nodes_per = $self->nodes_per_sbatch;
    my $node_id   = $node_hash->{NODE};

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $runtime
#SBATCH -N $nodes_per
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out
#SBATCH -w $node_id
$exclude

# Working directory
cd $work_dir

$extra_steps

$cmds

wait

EOM
    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;
    close $OUT;
}

## ----------------------------------------------------- ##

1;
