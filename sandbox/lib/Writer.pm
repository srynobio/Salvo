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
    my ( $self, $stack ) = @_;

    my $jobname   = 'salvo-' . $self->random_id;
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

    ## write out object
    my $runtime   = $self->runtime;
    my $nps       = $self->nodes_per_sbatch;
    my $account   = $self->account;
    my $partition = $self->partition;
    my $work_dir  = $self->work_dir;

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $runtime
#SBATCH -N $nps
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out
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

#sub idle_writer {
#    my ( $self, $node_hash, $stack, $info_hash ) = @_;
#
#    my $jobname   = 'salvo-' . $self->random_id;
#    my $slurm_out = $jobname . '.out';
#    my $outfile   = $jobname . '.sbatch';
#
#    my $cmds = join( "\n", @{$stack} ) if $stack;
#
#    my $extra_steps = '';
#    if ( $self->additional_steps ) {
#        $extra_steps = join( "\n", @{ $self->additional_steps } );
#    }
#
#    # add the exclude option
#    my $exclude = '';
#    if ( $self->exclude_nodes ) {
#        my $nodes = $self->exclude_nodes;
#        $exclude = "#SBATCH -x $nodes";
#    }
#
#    # collect from info hash & object
#    my $account   = $info_hash->{account_info}->{ACCOUNT};
#    my $partition = $info_hash->{account_info}->{PARTITION};
#    $account   =~ s/_/-/g;
#    $partition =~ s/_/-/g;
#    my $work_dir = $self->work_dir;
#    my $runtime  = $self->runtime;
#    my $node_id  = $node_hash->{NODE};
#    my $nps       = $self->nodes_per_sbatch;
#
#    my $sbatch = <<"EOM";
##!/bin/bash
##SBATCH -t $runtime
##SBATCH -N $nps
##SBATCH -A $account
##SBATCH -p $partition
##SBATCH -J $jobname
##SBATCH -o $slurm_out
##SBATCH -w $node_id
#$exclude
#
## Working directory
#cd $work_dir
#
#$extra_steps
#
#$cmds
#
#wait
#
#EOM
#    open( my $OUT, '>', $outfile );
#    say $OUT $sbatch;
#    close $OUT;
#}

## ----------------------------------------------------- ##

#sub multi_node_idle_writer {
#    my ( $self, $stack, $info_hash ) = @_;
#
#    my $jobname   = 'salvo-' . $self->random_id;
#    my $slurm_out = $jobname . '.out';
#    my $outfile   = $jobname . '.sbatch';
#
#    my $cmds = join( "\n", @{$stack} ) if $stack;
#
#    my $extra_steps = '';
#    if ( $self->additional_steps ) {
#        $extra_steps = join( "\n", @{ $self->additional_steps } );
#    }
#
#    # add the exclude option
#    my $exclude = '';
#    if ( $self->exclude_nodes ) {
#        my $nodes = $self->exclude_nodes;
#        $exclude = "#SBATCH -x $nodes";
#    }
#
#    # collect from info hash & object
#    my $account   = $info_hash->{account_info}->{ACCOUNT};
#    my $partition = $info_hash->{account_info}->{PARTITION};
#    $account   =~ s/_/-/g;
#    $partition =~ s/_/-/g;
#    my $work_dir  = $self->work_dir;
#    my $runtime   = $self->runtime;
#    my $nodes_per = $self->nodes_per_sbatch;
#
#    my $sbatch = <<"EOM";
##!/bin/bash
##SBATCH -t $runtime
##SBATCH -N $nodes_per
##SBATCH -A $account
##SBATCH -p $partition
##SBATCH -J $jobname
##SBATCH -o $slurm_out
#$exclude
#
## Working directory
#cd $work_dir
#
#$extra_steps
#
#$cmds
#
#wait
#
#EOM
#    open( my $OUT, '>', $outfile );
#    say $OUT $sbatch;
#    close $OUT;
#}

## ----------------------------------------------------- ##

sub beacon_writer {
    my ( $self, $node, $node_detail ) = @_;

    my $jobname   = 'salvo-' . $self->random_id;
    my $slurm_out = $jobname . '.out';
    my $outfile   = $jobname . '.sbatch';

    my $extra_steps = '';
    if ( $self->additional_steps ) {
        $extra_steps = join( "\n", @{ $self->additional_steps } );
    }

    # collect from info hash & object
    my $account   = $node_detail->{account_info}->{ACCOUNT};
    my $partition = $node_detail->{account_info}->{PARTITION};
    $account   =~ s/_/-/g;
    $partition =~ s/_/-/g;
    my $work_dir = $self->work_dir;
    my $runtime  = $self->runtime;
    ##my $node_id  = $node->{NODE};
###SBATCH -w $node_id

    my $sbatch = <<"EOM";
#!/bin/bash
#SBATCH -t $runtime
#SBATCH -N 1
#SBATCH -A $account
#SBATCH -p $partition
#SBATCH -J $jobname
#SBATCH -o $slurm_out

# Working directory
cd $work_dir

$extra_steps

./beacon-c.pl

wait

EOM
    open( my $OUT, '>', $outfile );
    say $OUT $sbatch;
    close $OUT;
}

## ----------------------------------------------------- ##

sub random_id {
    my $self = shift;

    my $id = int( rand(10000) );
    if ( -e "salvo-$id.sbatch" ) {
        $id = $self->random_id;
    }
    return $id;
}

## ----------------------------------------------------- ##

1;
