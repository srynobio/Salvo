#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use Salvo;
use Getopt::Long;

my $usage = 'TODO';

my %salvo_opts;
GetOptions(
    \%salvo_opts,             "command_file|cf=s",
    "account|a=s",            "partition|p=s",
    "cluster|c=s",            "mode|m=s",
    "user|u=s",               "jobs_per_sbatch|jps=i",
    "concurrent",             "hyperthread",
    "exclude_cluster|ec=s",   "runtime|r=s",
    "nodes_per_sbatch|nps=i", "queue_limit|ql=i",
    "additional_steps|as=s",  "exclude_nodes|en=s",
    "help|h",
);

if ( $salvo_opts{help} ) {
    say $usage;
    exit(0);
}

## Check required.
unless ( $salvo_opts{user} and $salvo_opts{mode} and $salvo_opts{command_file} ) {
    say $usage;
    say "Required options not met.";
    exit(1);
}

my $salvo = Salvo->new( \%salvo_opts );
$salvo->fire;

