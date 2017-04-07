package Salvo;
use strict;
use warnings;
use feature 'say';
use Moo;
use File::Copy;

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
        return $self->{jobs_per_sbatch} || 0;
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
        return $self->{exclude_cluster} || '';
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

has min_mem_required => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{min_mem_required} || 0;
    },
);

has min_cpu_required => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{min_cpu_required} || 0;
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
        ash => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/squeue',

        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/squeue',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/squeue',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/squeue',
    };

    $self->{SINFO} = {
        ash => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sinfo',

        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sinfo',
    };

    $self->{SCANCEL} = {
        ash => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/scancel',

        #lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/scancel',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/scancel',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/scancel',
    };
    $self->{UUFSCELL} = {
        ash => 'ash.peaks',

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

    ## check for required in dedicated mode.
    if ( $args->{mode} eq 'dedicated' ) {
        unless ( $args->{account} && $args->{partition} && $args->{cluster} ) {
            $self->ERROR(
                "dedicated mode requires account, partition and cluster info.");
        }
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
        $self->get_cmds_from_file;
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

## used in Dedicated mode.

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

sub get_cmds_from_file {
    my $self = shift;

    my $cf = $self->command_file;
    open( my $IN,  '<', $cf );
    open( my $OUT, '>', 'salvo.command.tmp' );

    my @cmd_stack;
    foreach my $cmd (<$IN>) {
        chomp $cmd;
        if ( $self->concurrent ) {
            $cmd = "$cmd &";
        }
        say $OUT $cmd;
    }
    close $IN;
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
      or $self->ERROR("Could not open launch.index file for clean up.");

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

sub ican_find {
    my $self = shift;

    ## get sacctmgr info to get account and partition names.
    my $user = $self->user;
    my $access =
      `sacctmgr list assoc format=account%30,qos%30,cluster%30 user=$user`;
    my @node_access = split /\n/, $access;
    my @node_data = splice( @node_access, 2, $#node_access );

    my %partition_lookup;
    foreach my $info (@node_data) {
        chomp $info;
        my @info_parts = split /\s+/, $info;

        if ( $info_parts[2] =~ /\,/ ) {
            my @multi_qos = split /\,/, $info_parts[2];
            $info_parts[2] = $multi_qos[0];
        }
        $partition_lookup{ $info_parts[2] } = {
            QOS     => $info_parts[1],
            CLUSTER => $info_parts[3],
        };
    }

    my %node_list;
    my %freeNodes;
    foreach my $cluster ( keys %{ $self->{SINFO} } ) {
        my @info = `$self->{SINFO}->{$cluster} -h -s -N -O all`;

        ## make an idle lookup hash.
        my @idle = `$self->{SINFO}->{$cluster} -h -t IDLE -s`;
        foreach my $i (@idle) {
            chomp $i;
            next unless ( $i =~ /(freecycle|guest)/ );
            my @nodelist = split /\s+/, $i;

            next if ( !$nodelist[4] );

            if ( $nodelist[4] =~ /\[/ ) {
                $nodelist[4] =~ /^(.*)\[(.*)\]/;
                my $cluster  = $1;
                my $eachNode = $2;

                my @nodes = split /\,/, $eachNode;

                foreach my $node (@nodes) {
                    if ( $node =~ /-/ ) {
                        my ( $start, $end ) = split /-/, $node;
                        for ( $start .. $end ) {
                            $freeNodes{"$cluster$_"}++;
                        }
                    }
                    else {
                        $freeNodes{"$cluster$node"}++;
                    }
                }
            }
            else {
                $freeNodes{ $nodelist[4] }++;
            }
        }

        ## make hash of all aval nodes.
        foreach my $node (@info) {
            chomp $node;
            my @split_array = split /\|/, $node;

            ## clean up data.
            my @node_array = map {
                $_ =~ s|^\s+||g;
                $_ =~ s|\s+$||g;
                $_;
            } @split_array;

            # skip unless wanted partition type
            next unless ( $node_array[34] =~ /(guest|freecycle)/ );
            next if ( $node_array[34] =~ /gpu/ );
            next unless ( $node_array[34] !~ /owner/ );

            ## set cpu by name;
            my $cpu = $node_array[2];

            ## set memory to gigs.
            my $memory = $node_array[9] / 1000;

            ## flag if hyperthreadable
            my $hyperthread = 0;
            if ( $node_array[40] > 1 && $self->hyperthread ) {
                $cpu         = ( $node_array[2] * 2 );
                $hyperthread = 1;
            }

            ## get hostname info
            my $account;
            my $cluster;
            my $partition;

            if ( $partition_lookup{ $node_array[34] } ) {
                $partition = $node_array[34];
                $account   = $partition_lookup{ $node_array[34] }->{QOS};
                $cluster   = $partition_lookup{ $node_array[34] }->{CLUSTER};
            }

            $node_list{ $node_array[10] } = {
                CPU       => $cpu,
                MEMORY    => $memory,
                NODE      => $node_array[10],
                SOCKETS   => $node_array[38],
                CORES     => $node_array[39],
                THREADS   => $node_array[40],
                ACCOUNT   => $account,
                PARTITION => $node_array[34],
                CLUSTER   => $cluster,
                HYPER     => $hyperthread,
            };
        }
    }

    ## delete non idle nodes.
    foreach my $allNode ( keys %node_list ) {
        if ( !$freeNodes{$allNode} ) {
            delete $node_list{$allNode};
        }
    }

    ## Remove nodes if req are not met.
    my $removed    = 0;
    my $min_memory = $self->min_mem_required;
    my $min_cpu    = $self->min_cpu_required;
    foreach my $element ( keys %node_list ) {
        if ( $node_list{$element}->{MEMORY} < $min_memory ) {
            delete $node_list{$element};
            $removed++;
            next;
        }
        if ( ! $node_list{$element} ) {
            say $self->INFO("node $node_list{$element}->{NODE} does not have cpu info.");
            delete $node_list{$element};
        }
        if ( $node_list{$element}->{CPU} < $min_cpu ) {
            delete $node_list{$element};
            $removed++;
            next;
        }
        if (   $self->exclude_cluster
            && $node_list{$element}->{CLUSTER} eq $self->exclude_cluster )
        {
            delete $node_list{$element};
            $removed++;
            next;
        }
    }
    $self->INFO(
        "$removed nodes removed for exclusion or not meeting memory or cpu requirements."
    );
    return \%node_list;
}

## ----------------------------------------------------- ##

1;

