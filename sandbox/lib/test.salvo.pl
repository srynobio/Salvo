#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use autodie;
use Salvo;

my $file = $ARGV[0] or die;

my $test = Salvo->new(
    {
        user             => 'u0413537',
        command_file     => $file,
        mode             => 'idle',
        account          => 'smithp-guest',
        partition        => 'ash-guest',
        cluster          => 'ash',
        jobs_per_sbatch  => '3',
        additional_steps => 'module load samtools',
        exclude_nodes    => 'kingspeak:kp[001-095,168-195,200-227]',
        exclude_cluster  => 'lonepeak',
        runtime          => '5:00:00',
        nodes_per_sbatch => '1',
        queue_limit      => '1000',
        hyperthread      => '1',
    }
);

my @need_to_clean = glob q("*sbatch salvo.work*.cmds");
if (@need_to_clean) {
    say "[WARN] Removing old salvo files";
    unlink @need_to_clean;
}
$test->fire;
