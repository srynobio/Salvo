#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use Salvo;

my $file = $ARGV[0] or die;

my $test = Salvo->new(
    {
        user         => 'u0413537',
        command_file => $file,
        mode         => 'guest',
        ##mode             => 'dedicated',
        account         => 'owner-guest',
        partition       => 'kingspeak-guest',
        cluster         => 'ash',
        jobs_per_sbatch => '5',
        concurrent      => '1',
        #additional_steps => 'cd ~,lscpu',
        ## figure out how to only exclude on right cluster
        ##exclude_nodes    => 'kp[001-095,168-195,200-227]',
        #exclude_cluster    => 'lonepeak',
        runtime          => '1:00:00',
        nodes_per_sbatch => '1',
        queue_limit      => '10',
        hyperthread      => '1',
    }
);

$test->fire;

