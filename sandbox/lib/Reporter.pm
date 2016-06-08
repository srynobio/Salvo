package Reporter;
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

sub report_node_info {
    my $self = shift;

    say "Partition\tAvailableNodes\tTotalCPUs\tNodeList";
    say "---------\t--------------\t---------\t--------";

    my $accs_nodes = $self->ican_access;
    if ( !keys %{$accs_nodes} ) {
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

## ----------------------------------------------------- ##

sub squeue_me {
    my $self = shift;
    my $user = $self->user;

    foreach my $cluster ( keys %{ $self->{SQUEUE} } ) {
        system("$self->{SQUEUE}->{$cluster} -u $user -h ");
    }
}

## -------------------------------------------------------------------- ##

sub timestamp {
    my $self = shift;
    my $time = localtime;
    return $time;
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

1;

