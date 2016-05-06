package Salvo;
use strict;
use warnings;
use feature 'say';
use Moo;
use Cwd;

with qw {
  Reporter
  Writer
  Processer
};

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

has user => (
    is      => 'rw',
    default => sub {
        my $self = shift;
        return $self->{user};
    },
);

has command_file => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{command_file};
    },
);

has jobs_per_sbatch => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{jobs_per_sbatch} || 1;
    },
);

has mode => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{mode};
    },
);

has account => (
    is => 'rw',
    default => sub {
        my $self = shift;
        return $self->{account};
    },
);

has partition => (
    is => 'rw',
    default => sub {
        my $self = shift;
        return $self->{partition};
    },
);

has concurrent => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{concurrent} || undef;
    },
);

has exclude_nodes  => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{exclude_nodes};
    },
);

has exclude_cluster  => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{exclude_cluster} || 'NULL';
    },
);

has work_dir => (
    is => 'ro',
    default => sub {
        my $self = shift;
        return $self->{work_dir} || getcwd;
    },
);

has runtime => (
    is      => 'ro',
    default => sub {
        my $self = shift;
        return $self->{runtime} || '3:00:00';
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
        return $self->{queue_limit} || 1;
    },
);

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


## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub BUILD {
    my ( $self, $args ) = @_;

    $self->{SBATCH} = {
        lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sbatch',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sbatch',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sbatch',
    };

    $self->{SQUEUE} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/squeue',
        lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/squeue',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/squeue',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/squeue',
    };

    $self->{SINFO} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/sinfo',
        lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/sinfo',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/sinfo',
    };

    $self->{SCANCEL} = {
        ash       => '/uufs/ash.peaks/sys/pkg/slurm/std/bin/scancel',
        lonepeak  => '/uufs/lonepeak.peaks/sys/pkg/slurm/std/bin/scancel',
        kingspeak => '/uufs/kingspeak.peaks/sys/pkg/slurm/std/bin/scancel',
        ember     => '/uufs/ember.arches/sys/pkg/slurm/std/bin/scancel',
    };

    unless ( $args->{user} && $args->{command_file} && $args->{mode} ) {
        say "[WARN] required options not given,";
        exit(1);
    }

    ## populate the object.
    foreach my $options (keys %{$args}) {
        $self->{$options} = $args->{$options};
    }
}

## ----------------------------------------------------- ##

sub additional_steps {
    my $self = shift;

    return undef if ( !$self->{additional_steps} );

    my @steps;
    if ( $self->{additional_steps} ) {
        if ( $self->{additional_steps} =~ /\,/ ) {
            @steps = split /\,/, $self->{additional_steps};
        }
        else {
            push @steps, $self->{additional_steps};
        }
    }
    return \@steps;
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
        ## remove node from list with no access.
        if ( !$aval{$found} ) {
            delete $useable_nodes->{$found};
            next;
        }
        ## add number of nodes as [-2] and
        ## account info as [-1]
        push @{ $useable_nodes->{$found} },
          scalar @{ $useable_nodes->{$found} };

        push @{ $useable_nodes->{$found} },
          { account_info => $aval{$found}->[0] };
    }
    return $useable_nodes;
}

## ----------------------------------------------------- ##

sub cmds {
    my $self = shift;

    my $file = $self->command_file;
    open( my $IN, '<', $file );

    my @cmd_stack;
    foreach my $cmd (<$IN>) {
        chomp $cmd;

        if ( $self->jobs_per_sbatch > 1 and $self->concurrent ) {
            push @cmd_stack, "$cmd &";
        }
        else {
            push @cmd_stack, $cmd;
        }
    }
    close $IN;
    return \@cmd_stack;
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

#####            next if ( $node_details[-1] =~ /ucgd/ );

            ## remove hyphen
            $node_details[-1] =~ s/\-/_/g;

            ## make node master table.
            ## change memory into GB.
            push @{ $found_nodes{ $node_details[-1] } },
              {
                NODE   => $node_details[0],
                CPUS   => $node_details[1],
                MEMORY => int( $node_details[2] / 1000 ),
              };
        }
    }
    return \%found_nodes;
}

## ----------------------------------------------------- ##

1;
