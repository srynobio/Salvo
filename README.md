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

```
 -command_file, -cf      :   File containing list of commands to run. <FILE>
```
* A text file containg each of the commands to run.

```
Example:
sambamba merge -t 40 /path/to/my/merged1.bam /path/to/my/file1.bam /path/to/my/file2.bam 
sambamba merge -t 40 /path/to/my/merged2.bam /path/to/my/file3.bam /path/to/my/file4.bam
sambamba merge -t 40 /path/to/my/merged3.bam /path/to/my/file5.bam /path/to/my/file6.bam
sambamba merge -t 40 /path/to/my/merged4.bam /path/to/my/file7.bam /path/to/my/file8.bam
...
```
----

```
 -account, -a            :   Cluster account name. e.g. our-nodes. <STRING>
```
* The account to submit the sbatch job to.
```
Example:
#SBATCH -A our-nodes
```
----

```
-partition, -p          :   A partition to run jobs on. e.g. our-partition <STRING>
```
* The specific parition to submit the sbatch job to.
```
Example:
#SBATCH -p our-partition
```
----

```
-UID                    :   Your University or employee id. <STRING>
```
* Your identification known to the system.

### Additional options:

```
  -time, -t               :   Time to allow each job to run on node <STRING> (default 1:00:00).
```
* Allowed submission run time.
----

```
  -node, -n               :   Number of nodes to run per sbatch job submitted. <INT> default 1).
```
* The number of nodes to include per each node job.

```
Example:
#SBATCH -n 10
```
----

```
  -queue_limit, -ql       :   Number of jobs to launch and run in the queue at one time. <INT> (default 1)
```
* The number of job to submit at one time.

If you have a large number of commands to submitting simultaneously, this option will allow you to control how many are launched at any given time.   This will stop queue system overload and monopolizing resources; especially if job are expected to run longer then ~1 hour.

```
Example:
$ wc commandlist.txt
$ 400
$ ./Salvo -ql 20
Jobs launched in batches of 20.
```
----

```
 -jobs_per_sbatch, -jps  :   Number of jobs to run concurrently, & added to each command. <INT> (default 1);
```
* Number of job to include to each sbatch script.

```
Example:
$ ./Salvo -jps 10
Each sbatch script generated will have 10 job included, prefixed by the "&" and ending with "wait" bash command.
```
----

```
  -added_steps, -as :   Additional step to add to each sbatch job <STRING> (comma separated).
```
* Will allow inclusion of additional steps need to run or set your environment.

```
Example:
$ ./Salvo -as "source .bashrc, module load samtools"
```
----

```
  -just_sbatch :   This option will create all sbatch jobs die, but not submit them (default FALSE).
```
* As apposed to allowing Salvo to run and manage your jobs, this option will print all the sbatch scripts to your current directory.
----

```
  -chdir :   This option will tell each sbatch job to cd into this directory before running command. <STRING> (default current).
```
* Will include in your sbatch the directory to change to before execution
----

```
  -clean_up, -c :   Option will remove launch.index, *sbatch and *out jobs
```
* Will clean up intermediate files post completion.


 


