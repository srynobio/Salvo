# Salvo - Slurm command and job launcher
![alt text](https://github.com/srynobio/Salvo/blob/master/img/salvo3.jpg)

```
Synopsis:

    Salvo - Slurm command and job launcher

    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING>
    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING> -just_batch

Description:

    Designed to aid launching of jobs on Slurm cluster from a command list file.
    View github page <https://github.com/srynobio/Salvo> for more detailed description.

Required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -account, -a            :   CHPC account name. e.g. yandell-em. <STRING>
    -partition, -p          :   CHPC partition to run jobs on. e.g. ember-freecycle <STRING>
    -UID                    :   Your University or employee id. <STRING>

Additional options:

    -time, -t               :   Time to allow each job to run on node <STRING> (default 1:00:00).
    -node, -n               :   Number of nodes to run per sbatch job submitted. <INT> default 1).
    -queue_limit, -ql       :   Number of jobs to launch and run in the queue at one time. <INT> (default 1).
    -jobs_per_sbatch, -jps  :   Number of jobs to run concurrently, & added to each command. <INT> (default 1);
    -added_steps, -as       :   Additional step to add to each sbatch job <STRING> (comma separated).
    -just_sbatch            :   This option will create all sbatch jobs die, but not submit them (default FALSE).
    -chdir                  :   This option will tell each sbatch job to cd into this directory before running command. <STRING> (default current).
    -clean_up, -c           :   Option will remove launch.index, *sbatch and *out jobs.
    -help                   :   Prints this battleworn help message.

```

# Overview:
Often it gets tedious creating sbatch scripts every time you want to launch n number of jobs on a cluster.  Salvo is designed to give you a couple of options when launching jobs in a [slurm](http://slurm.schedmd.com/) based environment:

1.	Creation of sbatch scripts, for user submission.
2.	Creation of sbatch scripts, and submission of sbatch jobs in a controlled manner.

Differences between these step given below.

# Description of the options:

### Required options:

* A text file containg each of the commands to run.
```
 -command_file, -cf      :   File containing list of commands to run. <FILE>
```
```
Example:
sambamba merge -t 40 /path/to/my/merged1.bam /path/to/my/file1.bam /path/to/my/file2.bam 
sambamba merge -t 40 /path/to/my/merged2.bam /path/to/my/file3.bam /path/to/my/file4.bam
sambamba merge -t 40 /path/to/my/merged3.bam /path/to/my/file5.bam /path/to/my/file6.bam
sambamba merge -t 40 /path/to/my/merged4.bam /path/to/my/file7.bam /path/to/my/file8.bam
...
```

* The account to submit the sbatch job to.
```
 -account, -a            :   CHPC account name. e.g. our-nodes. <STRING>
```
```
Example:(result).
#SBATCH -A our-nodes
```

* The specific parition to submit the sbatch job to.
```
-partition, -p          :   CHPC partition to run jobs on. e.g. our-partition <STRING>
```
```
Example:(result).
#SBATCH -p our-partition
```

* Your identification known to the system.
```
-UID                    :   Your University or employee id. <STRING>
```





 





 


