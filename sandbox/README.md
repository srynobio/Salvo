# Salvo - Slurm command and job launcher
![alt text](https://github.com/srynobio/Salvo/blob/master/img/salvo.jpg)



##Synopsis:

    Salvo - Slurm command and job launcher v 1.2.1

##Description:

    Designed to aid launching of Slrum jobs from a command list file.
    View github page <https://github.com/srynobio/Salvo> for more detailed description.

    Version 1.2.1 now allows CHPC users to submit jobs to:
        kingspeak-guest
        ash-guest
        ember-guest
        lonepeak-guest : (lonepeak does not have access to UCGD lustre space).

	Salvo can be launched in two distinct modes: dedicated & idle.  
	Options and differences are given below.


###Dedicated:

Dedicated launch mode allows you to specify that you want to launch slurm jobs to a specific CHPC cluster, this is used both for launching to owned nodes or a selected guest cluster.  When using guest resources Salvo will attempt to relaunch preempted jobs, however timed out jobs are not relaunched.

Dedicated required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -account, -a            :   CHPC account name. e.g. yandell-em. <STRING>
    -partition, -p          :   CHPC partition to run jobs on. e.g. ember-freecycle <STRING>
    -cluster, -c            :   Cluster to launch to. e.g. ash <STRING>
    -mode, -m 				:   Launch mode. e.g.  dedicated


Additional options:

	-user, -u 				:	Will add a user to run as. <STRING> (default $ENV{USER})
    -runtime, -r            :   Time to allow each job to run on node. <STRING> (default 5:00:00)
    -nodes_per_sbatch, -nps :   Number of nodes to run per sbatch launch <INT> (default 1)
    -jobs_per_sbatch, -jps  :   Number of jobs to run per sbatch launch. <INT> (default 1)
    -queue_limit, -ql       :   Number of jobs queue/run per cluster at one time. <INT> (default 50)
    -additional_steps, -as  :   Additional step to add to each sbatch job <STRING> (comma separated)
    -work_dir, -wd          :   This option will add the directory to work out of to each sbatch job. <STRING> (default current)
    -exclude_nodes, -en		:   Will exclude submission to selected nodes <STRING> e.g. kp[001-095,168-195,200-227]
    -jobname, -j			:   Jobnames to give to a current launch. <STRING> (default salvo)
    -concurrent			    :	Will add "&" to the end of each command allowing concurrent runs.


###Idle:

Idle launch mode allows users to utilize all idle and free nodes across all available clusters.  It executes this by creating smaller subsets of the original command file and passes them to each node as it becomes accessible.  For each cluster environment you have access to, individual beacons are deployed via sbatch, then beacons request work via a TCP socket once the node becomes available.  Command file names are modified as they process (\*cmds->\*processing->\*complete).  Preempted jobs are renamed (\*cmds) and relaunched.  Using idle mode allows users to saturate the CHPC environment and quickly process work.

Idle required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -mode, -m 				:   Launch mode. e.g. idle


Additional options:

	-user, -u 				:	Will add the user to run as. <STRING> (default $ENV{USER})
    -runtime, -r            :   Time to allow each job to run on node. <STRING> (default 5:00:00)
    -nodes_per_sbatch, -nps :   Number of nodes to run per sbatch launch <INT> (default 1)
    -jobs_per_sbatch, -jps  :   Number of jobs to run per sbatch launch. <INT> (default 1)
    -queue_limit, -ql       :   Number of jobs queue/run per cluster at one time. <INT> (default 1)
    -additional_steps, -as  :   Additional step to add to each sbatch job <STRING> (comma separated)
    -work_dir, -wd          :   This option will add the directory to work out of to each sbatch job. <STRING> (default current)
    -exclude_cluster, -ec   :	Will exclude submission to select cluster. <STRING> e.g. lonepeak
    -exclude_nodes, -en	 	:   Will exclude submission to selected nodes <STRING> e.g. kp[001-095,168-195,200-227]
    -jobname, -j			:   Jobname to give to current launch. <STRING> (default salvo)
    -concurrent			    :	Will add "&" to the end of each command allowing concurrent runs.
    -hyperthread            :   Will read the number of avaliable cpus and double value (should only be used on known hyperthreaded machines).


###Additional help options:
        
    -help                   :   Prints this battleworn help message.
    -clean		            :   Will remove processing, launched, out, complete, cmds files created by Salvo.


###Node information options:

    -squeue_me, -sm			: Will output all current runing jobs across all clusters.
    -sinfo_idle, -si		: Will output all currently idle nodes across all clusters.
    -node_info, ni			: Will give a greater detailed output of all idle nodes across all clusters.



##Description of the options:

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
* The account to submit the sbatch job to (not used for dedicated mode).

```
Example:
-a owner-guest
-a smithp-guest
```

#### -partition
```
-partition, -p : A partition to run jobs on. e.g. kingspeak-guest <STRING>
```
* The specific partition to submit the sbatch job to (not used for dedicated mode).

```
Example:
-p kingspeak-guest
-p ash-guest
```

#### -mode
```
-mode, -m : The mode used to run Salvo. <STRING>
```
* One of two distinct mode used to run Salvo (not used for dedicated mode).

```
Example:
-m idle
-m dedicated
```

#### -cluster
```
-cluster, -m : The cluster you would like to launch dedicated jobs to.
```
```
Example:
-cluster kingspeak
-cluster ash
```

### Additional options:

#### -UID
```
-user, -u : Your University id. <STRING> (default \$ENV{USER}).
```
* Your University of Utah user id.


#### -runtime
```
-runtime, -r : Time to allow each job to run on node <STRING> (default 5:00:00).
```
* Allowed submission run time.

#### -node_per_sbatch
```
-node_per_sbatch, -nps : Number of nodes to run per sbatch job submitted. <INT> default 1).
```
* The number of nodes to include per each node job.
* Useful for running MPI based jobs.

```
Example:
-nps 7
```

#### -queue_limit
```
-queue_limit, -ql : Number of jobs to launch and run in the queue (per cluster) at one time. <INT> (default 50)
```
* The number of job to submit at one time.

If you have a large number of commands to submit simultaneously, this option will allow you to control how many are launched at any given time.  This will help stop queue system overload.


#### -jobs\_per\_sbatch
```
-jobs_per_sbatch, -jps : Number of jobs to run per sbatch launch. <INT> (default 1)
```
* Number of job to include to each sbatch script.

```
Example:
$ ./Salvo -jps 10
Each sbatch script generated will have 10 job included.
```

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
-work_dir, -wd : This option will tell each sbatch job to cd into this directory before running command. <STRING> (default current).
```
* Will include in your sbatch the directory to change to before execution

#### -exclude_nodes
```
-exclude_nodes, -en : Will exclude submission to selected nodes <STRING>
```

```
Example:
-en  kingspeak:kp[001-095,168-195,200-227]
```


#### -jobname
```
--jobname, -j	: Jobnames to give to a current launch. <STRING> (default salvo)
```
* All Salvo generated file will be prefixed with this name.

```
Example:	
-j jointcall
```

#### -concurrent
```
--concurrent : Will add "&" to the end of each command allowing concurrent runs.
```
* Will append all jobs per sbatch script to include \"&\" to the end of each command.

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

LICENCE AND COPYRIGHT Copyright (c) 2016, Shawn Rynearson <shawn.rynearson@gmail.com> All rights reserved.

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

DISCLAIMER OF WARRANTY BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.)))