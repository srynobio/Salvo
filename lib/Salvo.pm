package Salvo;
use strict;
use warnings;
use feature 'say';
use Moo;
use File::Copy;
use IPC::Cmd qw[can_run run run_forked];

with qw {
  Reporter
  Writer
  Idle
  Dedicated
};

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

has user => (
    is      => 'rw',
    default => sub {
        my $self = shift;
        return $self->{user} || $ENV{USER};
    },
);

has command_file => (
    is      => 'rw',
    default => sub {
        my $self = shift;
        return $self->{command_file};
    },
);

has jobs_per_sbatch => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{jobs_per_sbatch} || 1;
    },
);

has mode => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{mode};
    },
);

has account => (
    is      => 'rw',
    default => sub {
        my $self = shift;
        return $self->{account};
    },
);

has partition => (
    is      => 'rw',
    default => sub {
        my $self = shift;
        return $self->{partition};
    },
);

has exclude_nodes => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{exclude_nodes};
    },
);

has exclude_cluster => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{exclude_cluster} || 'NULL';
    },
);

has work_dir => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{work_dir} || $ENV{PWD};
    },
);

has runtime => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{runtime} || '5:00:00';
    },
);

has nodes_per_sbatch => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{nodes_per_sbatch} || 1;
    },
);

has queue_limit => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{queue_limit} || 50;
    },
);

has min_mem_required => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{min_mem_required} || undef;
    },
);

has localhost => ( is => 'rw' );
has localport => ( is => 'rw' );

has hyperthread => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        if ( $self->{hyperthread} ) {
            return 1;
        }
        else {
            return undef;
        }
    },
);

has jobname => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{jobname} || 'Salvo';
    },
);

has concurrent => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        if ( $self->{concurrent} ) {
            return 1;
        }
        else {
            return undef;
        }
    },
);

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub BUILD {
    my ( $self, $args ) = @_;

    $self->{SBATCH} = {
        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sbatch',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sbatch',
    };

    $self->{SQUEUE} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/squeue',
        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/squeue',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/squeue',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/squeue',
    };

    $self->{SINFO} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sinfo',
        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sinfo',
    };

    $self->{SCANCEL} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/scancel',
        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/scancel',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/scancel',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/scancel',
    };
    $self->{UUFSCELL} = {
        ash       => 'ash.peaks',
        #lonepeak  => 'lonepeak.peaks',
        kingspeak => 'kingspeak.peaks',
        ember     => 'ember.arches',
    };

    ## populate the object.
    foreach my $options ( keys %{$args} ) {
        $self->{$options} = $args->{$options};
    }

    ## Return if asking for reporting info.
    if (   $args->{sinfo_idle}
        or $args->{squeue_me}
        or $args->{node_info}
        or $args->{reserve_info}
        or $args->{job_flush} )
    {
        return;
    }

    ## check requirements
    unless ( $args->{command_file} && $args->{mode} ) {
        say "[ERROR] required options not given,";
        exit(1);
    }

    ## check that command file exists.
    if ( !-e $args->{command_file} ) {
        $self->ERROR("Command file given could not be found.");
    }
}

## ----------------------------------------------------- ##

sub fire {
    my $self = shift;
    my $mode = $self->mode;

    if ( $mode eq 'dedicated' ) {
        $self->dedicated;
    }
    elsif ( $mode eq 'idle' ) {
        $self->idle;
    }
    else {
        $self->ERROR("Misfire!! $mode not an mode option.");
    }
    unlink 'launch.index' if -e 'launch.index';
    say "Salvo Done!";
    exit(0);
}

## ----------------------------------------------------- ##

sub get_cmds {
    my $self = shift;

    my $cf = $self->command_file;
    open( my $IN, '<', $cf );

    my @cmd_stack;
    foreach my $cmd (<$IN>) {
        chomp $cmd;
        if ( $self->concurrent ) {
            $cmd = "$cmd &";
        }
        push @cmd_stack, $cmd;
    }
    close $IN;

    return \@cmd_stack;
}

## ----------------------------------------------------- ##

sub create_cmd_files {
    my $self = shift;

    my $cf = $self->command_file;
    open( my $IN, '<', $cf );

    my @cmd_stack;
    foreach my $cmd (<$IN>) {
        chomp $cmd;
        push @cmd_stack, $cmd;
    }
    close $IN;

    my @commands;
    push @commands, [ splice @cmd_stack, 0, $self->jobs_per_sbatch ]
      while @cmd_stack;

    my $id;
    foreach my $stack (@commands) {
        $id++;
        my $file = $self->jobname . ".work.$id.cmds";
        open( my $FH, '>', $file );
        map { say $FH $_ } @{$stack};
        close $FH;
    }
}

## ----------------------------------------------------- ##

sub additional_steps {
    my $self = shift;

    return undef if ( !$self->{additional_steps} );
    $self->INFO("Additional steps found adding to sbatch scripts.");

    my @steps;
    if ( $self->{additional_steps} ) {
        if ( $self->{additional_steps} =~ /\,/ ) {
            @steps = split /\,/, $self->{additional_steps};
            map { $_ =~ s/^\s+//g } @steps;
        }
        else {
            push @steps, $self->{additional_steps};
        }
    }
    return \@steps;
}

## ----------------------------------------------------- ##

sub node_flush {
    my $self = shift;

    open( my $INDX, '<', 'launch.index' )
      or $self->WARN("Could not open launch.index file for clean up.");

    my @ids;
    foreach my $launch (<$INDX>) {
        chomp $launch;
        my @info = split /\s+/, $launch;
        push @ids, $info[-1];
    }

    foreach my $node ( keys %{ $self->{SCANCEL} } ) {
        foreach my $job (@ids) {
            my $cancel = sprintf( "%s %s", $self->{SCANCEL}->{$node}, $job );
            system $cancel;
        }
    }
}

## ----------------------------------------------------- ##

sub ican_access {
    my $self = shift;

    my $useable_nodes = $self->_ican_find;
    my $user          = $self->user;

    my $access =
      `sacctmgr list assoc format=account%30,cluster%30,qos%30 user=$user`;
    my @node_access = split /\n/, $access;
    my @node_data = splice( @node_access, 2, $#node_access );

    my %aval;
    foreach my $id (@node_data) {
        chomp $id;

        my ( undef, $account, $cluster, $partition ) = split /\s+/, $id;
        next if ( $cluster eq $self->exclude_cluster );

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

    foreach my $found ( keys %{$useable_nodes} ) {
        chomp $found;
        ## remove node from list with no user access.
        if ( !$aval{$found} ) {
            delete $useable_nodes->{$found};
            next;
        }

        ## add number of nodes and account info
        my $number_of_nodes = scalar keys %{ $useable_nodes->{$found} };
        $useable_nodes->{$found}{nodes_count}  = $number_of_nodes;
        $useable_nodes->{$found}{account_info} = $aval{$found}->[0];
    }
    return $useable_nodes;
}

## ----------------------------------------------------- ##

sub _ican_find {
    my $self = shift;

    my %found_nodes;
    foreach my $node ( keys %{ $self->{SBATCH} } ) {
        chomp $node;

        my $cmd =
          "$self->{SINFO}->{$node} --format=\"%n %c %m %t %P\" | grep idle";
        my @s_info = `$cmd`;
        chomp @s_info;
        next if ( !@s_info );

        foreach my $line (@s_info) {
            chomp $line;
            my @node_details = split /\s+/, $line;

            ## remove hyphen
            $node_details[-1] =~ s/\-/_/g;

            ## make node master table.
            ## change memory into GB.
            $found_nodes{ $node_details[-1] }{ $node_details[0] } = {
                NODE   => $node_details[0],
                CPUS   => $node_details[1],
                MEMORY => int( $node_details[2] / 1000 ),
            };
        }
    }

    ## remove node that dont meet memory requirements if set.
    my $removed = 0;
    my $mim_memory = $self->min_mem_required;
    if ($mim_memory) {
        foreach my $cluster ( keys %found_nodes ) {
            foreach my $node ( keys %{ $found_nodes{$cluster} } ) {
                my $memory = $found_nodes{$cluster}->{$node}->{MEMORY};
                if ( $memory < $mim_memory ) {
                    $removed++;
                    delete $found_nodes{$cluster}->{$node};
                }
            }
        }
    }
    $self->INFO("$removed nodes were removed for not meeting memory requirements.");
    return \%found_nodes;
}

## ----------------------------------------------------- ##

1;
