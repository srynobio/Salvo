package Reporter;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use Fcntl qw(:flock SEEK_END);

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub report_node_info {
    my $self = shift;

    say "Partition\tAvailableNodes\tTotalCPUs\tNodeList";
    say "---------\t--------------\t---------\t--------";

    my $access = $self->ican_find;
    if ( !keys %{$access} ) {
        $self->ERROR("No idle node available to review.");
    }

    my %reporter;
    while ( my ( $node, $info ) = each %{$access} ) {
        next if ( !$info->{CLUSTER} );
        push @{ $reporter{ $info->{CLUSTER} } },
          {
            CPU => $info->{CPU},
            ID  => $info->{NODE}
          };
    }

    my $total_node;
    my $total_cpus;
    foreach my $env ( keys %reporter ) {

        my $cpus = 0;
        my ( @ids, $node_count );
        foreach my $i ( @{ $reporter{$env} } ) {
            $node_count++;
            push @ids, $i->{ID};
            $cpus += $i->{CPU};
        }

        my $format = sprintf( "%-20s\t%s\t%s\t%s",
            $env, $node_count, $cpus, join( ',', @ids ) );
        say $format;
        $total_node += $node_count;
        $total_cpus += $cpus;

    }
    say "[Total AvailableNodes: $total_node]";
    say "[Total AvailableCPUs: $total_cpus]";
    say "";

    $self->reserve_info;
}

## ----------------------------------------------------- ##

sub reserve_info {
    my $self = shift;

    foreach my $cluster ( keys %{ $self->{SINFO} } ) {
        my $resv = `$self->{SINFO}->{$cluster} -T`;
        say "----------------------------------";
        say "- Node reserve info for $cluster -";
        say "----------------------------------";
        say $resv;
    }
}

## ----------------------------------------------------- ##

sub squeue_me {
    my $self = shift;
    my $user = $self->user;

    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
        system("$self->{SQUEUE}->{$cluster} -u $user -h ");
    }
}

## -------------------------------------------------------------------- ##

sub sinfo_idle {
    my $self = shift;

    foreach my $cluster ( keys %{ $self->{SINFO} } ) {
        system("$self->{SINFO}->{$cluster} | grep idle");
    }
}

## -------------------------------------------------------------------- ##

sub INFO {
    my ( $self, $message ) = @_;
    my $time = $self->timestamp;
    say STDOUT "[INFO] [$time] $message";
    return;
}

## -------------------------------------------------------------------- ##

sub WARN {
    my ( $self, $message ) = @_;
    my $time = $self->timestamp;
    say STDOUT "[WARN] [$time] $message";
    return;
}

## -------------------------------------------------------------------- ##

sub ERROR {
    my ( $self, $message ) = @_;
    my $time = $self->timestamp;
    say STDERR "[ERROR] [$time] $message";
    exit(1);
}

## -------------------------------------------------------------------- ##

sub timestamp {
    my $self = shift;
    my $time = localtime;
    return $time;
}

## -------------------------------------------------------------------- ##

1;

