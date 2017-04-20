# Salvo - SLURM command and job launcher

![alt text](https://github.com/srynobio/Salvo/blob/master/img/salvo.jpg)

## Synopsis:

    Salvo - SLURM command and job launcher v 1.3.4

## Description:

    Designed to aid launching of SLURM jobs from a command list file.
    View github page <https://github.com/srynobio/Salvo> for more detailed description.

    Version 1.3.4 now allows CHPC users to submit jobs to:
        kingspeak-guest
        ash-guest
        ember-guest
        lonepeak-guest : (lonepeak does not have access to UCGD lustre space).

	Salvo can be launched in two distinct modes: dedicated & idle.  
	Options and differences are given below.


### Dedicated:

Dedicated launch mode allows you to specify that you want to launch SLURM jobs to a specific account on the cluster.  Salvo will attempt to relaunch preempted jobs, however timed out jobs are not relaunched.

Dedicated required options:

    -command_file, -cf  :   File containing list of commands to run. <FILE>
    -account, -a        :   CHPC account name. e.g. owner-guest. <STRING>
    -partition, -p      :   CHPC partition to run jobs on. e.g. ember-guest <STRING>
    -cluster, -c        :   Cluster to launch to. e.g. ash <STRING>
    -mode, -m           :   Launch mode. e.g.  dedicated


Additional options:

    -user,u                 :	Will add a user to run as. <STRING> (default $ENV{USER})
    -runtime, -r            :   Time to allow each job to run on node. <STRING> (default 5:00:00)
    -nodes_per_sbatch, -nps :   Number of nodes to run per sbatch launch <INT> (default 1)
    -jobs_per_sbatch, -jps  :   Number of jobs to run per sbatch launch. <INT> (default 1)
    -queue_limit, -ql       :   Number of jobs queue/run per cluster at one time. <INT> (default 50)
    -additional_steps, -as  :   Additional step to add to each sbatch job <STRING> (comma separated)
    -work_dir, -wd          :   This option will add the directory to work out of to each sbatch job. <STRING> (default current)
    -exclude_nodes, -en     :   Will exclude submission to selected nodes <STRING> e.g. kp[001-095,168-195,200-227]
    -jobname, -j            :   Jobnames to give to a current launch. <STRING> (default salvo)
    -concurrent             :	Will add "&" to the end of each command allowing concurrent runs.


### Idle:

Idle launch mode allows users to utilize all idle nodes across all available clusters.  It executes this by creating smaller subsets of the original command file and passes them to each node as they become accessible.  For each cluster environment you have access to, individual beacons are deployed via sbatch, then beacons request work via a TCP socket once the node becomes available.  Command file names are modified as they process (\*cmds->\*processing->\*complete).  Preempted jobs are renamed (\*cmds) and relaunched.  Using idle mode allows users to saturate the CHPC environment and quickly process work.  Setting the jps option in different ways allows for greater distribution of command jobs (see infomation section below).

Idle required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -mode, -m               :   Launch mode. e.g. idle


Additional options:

	-user, -u 				:	Will add the user to run as. <STRING> (default $ENV{USER})
    -runtime, -r            :   Time to allow each job to run on node. <STRING> (default 5:00:00)
    -nodes_per_sbatch, -nps :   Number of nodes to run per sbatch launch <INT> (default 1)
    -jobs_per_sbatch, -jps  :   Number of jobs to run per sbatch launch. <INT> (default 1)
    -additional_steps, -as  :   Additional step to add to each sbatch job <STRING> (comma separated)
    -work_dir, -wd          :   This option will add the directory to work out of to each sbatch job. <STRING> (default current)
    -exclude_cluster, -ec   :	Will exclude submission to select cluster. <STRING> e.g. lonepeak
    -exclude_nodes, -en     :   Will exclude submission to selected nodes <STRING> e.g. kp[001-095,168-195,200-227]
    -jobname, -j            :   Jobname to give to current launch. <STRING> (default salvo)
    -min_mem_required, -mm  :   Minimum memory required per node (in Gigs).
    -min_cpu_required, -mc  :   Minimum cpu per node <INT>
    -hyperthread            :   Will read the number of avaliable cpus and double value (will only work on known hyperthreaded machines).


### Additional help options:
        
    -help                   :   Prints this battleworn help message.
    -clean                  :   Will remove processing, launched, out, complete, cmds files created by Salvo.


### Node information options:

    -squeue_me, -sm			: Will output all current runing jobs across all clusters.
    -sinfo_idle, -si		: Will output all currently idle nodes across all clusters.
    -node_info, ni			: Will give a greater detailed output of all idle nodes across all clusters.



## Description of the options:

### Required options:

#### -command_file
```
 -command_file, -cf :   File containing list of commands to run. <FILE>
```
* A text file containing each of the commands to run.

```
Example:
sambamba merge -t 40 /path/to/my/merged1.bam /path/to/my/file1.bam /path/to/my/file2.bam 
sambamba merge -t 40 /path/to/my/merged2.bam /path/to/my/file3.bam /path/to/my/file4.bam
sambamba merge -t 40 /path/to/my/merged3.bam /path/to/my/file5.bam /path/to/my/file6.bam
sambamba merge -t 40 /path/to/my/merged4.bam /path/to/my/file7.bam /path/to/my/file8.bam
...
```

#### -account
```
 -account, -a : Cluster account name. e.g. owner-guest <STRING>
```
* The account to submit the sbatch job to (not used in idle mode).

```
Examples:
-a owner-guest
-a smithp-guest
```

#### -partition
```
-partition, -p : A partition to run jobs on. e.g. kingspeak-guest <STRING>
```
* The specific partition to submit the sbatch job to (not used in idle mode).

```
Examples:
-p kingspeak-guest
-p ash-guest
```

#### -mode
```
-mode, -m : The mode used to run Salvo. <STRING>
```
* One of two distinct mode used to run Salvo.

```
Examples:
-m idle
-m dedicated
```

#### -cluster
```
-cluster, -m : The cluster you would like to launch dedicated jobs to.
```
```
Examples:
-cluster kingspeak
-cluster ash
```

### Additional options:

#### -user
```
-user, -u : Your user id. <STRING> (default $ENV{USER}).
```

#### -runtime
```
-runtime, -r : Time to allow each job to run on node <STRING> (default 5:00:00).
```

#### -jobs\_per_sbatch
```
-jobs_per_sbatch, -jps : Number of jobs to run per sbatch launch. <INT> 
```
* When using `-m idle` mode and excluding `-jps` Salvo will self-discover cpus values and transmit an equal number of commands to the given node. For example if you have 20 idle nodes with 24 cpus, and 20 with 64, Salvo would send 24 commands to the first 20 and 64 commands to the last.  
* If the `-hyperthread` option is used Salvo will double the number of commands sent; if the machine is discovered to be hyperthreaded. 
* Please keep in mind that adjustment to number of commands are not modified based on a given nodes memory available, this requires pre-planing, and use of the `-jps` option.

```
Examples:
$./Salvo -cf my.cmd.txt -m idle -jps 10
This would send commands 10 at a time to each node.

$./Salvo -cf my.cmd.txt -m idle 
This would send commands based on each nodes available cpus.

$./Salvo -cf my.cmd.txt -m idle -hyperthread
This would double the commands to each node if discovered to be hyperthreaded.
```

#### -node\_per_sbatch
```
-node_per_sbatch, -nps : Number of nodes to group per sbatch job submitted. <INT> default 1).
```
* The number of nodes to include per each node job.
* Useful for running MPI based jobs.

```
Example:
$./Salvo -cf my.mpi.job.txt -m idle -nps 6
```

#### -queue_limit
```
-queue_limit, -ql : Number of jobs to launch and run in the queue (per cluster) at one time. <INT> (default 50)
```

If you have a large number of commands to submit simultaneously, this option will allow you to control how many are launched at any given time.  This will help stop queue system overload when commands are in the thousands.

* Only used for `-m dedicated` mode, `-m idle` is based on idle availability.

#### -added_steps
```
-added_steps, -as : Additional step to add to each sbatch job <STRING> (comma separated)
```
* Will allow inclusion of additional steps needed to run or set your environment.

```
Example:
$ ./Salvo -as "source ~/.bashrc, module load samtools"
```

#### -work_dir
```
-work_dir, -wd : This option will tell each sbatch job to `cd` into a given directory before running commands. <STRING> (default current).
```

#### -exclude_nodes
```
-exclude_nodes, -en : Will exclude submission to selected nodes <STRING>
```

```
Example:
-en  kingspeak:kp[001-095,168-195,200-227]
```

#### -exclude_cluster
```
--exclude_cluster, -ec	: Will exclude a given cluster from launch list.
```

```
Example:
$./Salvo -cf my.mpi.job.txt -m idle -nps 6 -ec ember
```

#### -jobname
```
--jobname, -j	: Jobnames to give to a current launch. <STRING> (default Salvo)
```
* All Salvo generated file will be prefixed with this name.

#### -concurrent
```
--concurrent : Will add "&" to the end of each command allowing concurrent runs.
```
* Will append all jobs per sbatch script to include \"&\" to the end of each command.
* This option is only used in dedicated mode.

#### -hyperthread
```    
-hyperthread : Will read the number of available cpus and double value (should only be used on known hyperthreaded machines).
```

### Additional help options:

#### -clean
```
-clean : Will remove processing, launched, out, complete, cmds files created by Salvo.
```
* Will clean up intermediate files generated by Salvo.


### Node information options:

#### -squeue_me
```
-squeue_me, -sm : Will output all current running jobs across all clusters.
```

#### -sinfo_idle
```
-sinfo_idle, -si : Will output all currently idle nodes across all clusters.
```

#### -node_info
```
-node_info, -ni : Will give a greater detailed output of all idle nodes across all clusters.
```
* Offers a more detailed description of nodes available, total cpus, total nodes.


### BUGS AND LIMITATIONS

Please report any bugs or feature requests to the [issue tracker](https://github.com/srynobio/Salvo/issues)

AUTHOR Shawn Rynearson <shawn.rynearson@gmail.com>

LICENCE AND COPYRIGHT Copyright (c) 2017, Shawn Rynearson <shawn.rynearson@gmail.com> All rights reserved.

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

DISCLAIMER OF WARRANTY BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.)))
