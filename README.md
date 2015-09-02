# Salvo - Slurm command and job launcher
![alt text](https://github.com/srynobio/Salvo/blob/master/img/salvo3.jpg)

```
Synopsis:

    Salvo - Slurm command and job launcher

    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING>
    ./Salvo -command_file <FILE> -account <STRING> -partition <STRING> -UID <STRING> -just_batch

Description:

    Designed to aid launching of jobs on CHPC cluster from a command list file.
    View github page <https://github.com/srynobio/Salvo> for more detailed description.

Required options:

    -command_file, -cf      :   File containing list of commands to run. <FILE>
    -account, -a            :   CHPC account name. e.g. yandell-em. <STRING>
    -partition, -p          :   CHPC partition to run jobs on. e.g. ember-freecycle <STRING>
    -UID                    :   Your University or employee id. <STRING>

Additional options:

    -time, -t               :   Time to allow each job to run on node <STRING> (default 1:00:00).
    -node, -n               :   Number of nodes to run across per sbatch job submitted. <INT> default 1).
    -available_nodes, -an   :   Number of jobs to launch and run at any one time. <INT> (default 1).
    -clean_up, -cu          :   Option will remove launch.index, *sbatch and *out jobs.
    -jobs_per_sbatch, -jps  :   Number of jobs to add to each sbatch script. <INT> (default 1);
    -just_sbatch            :   This option will create all sbatch jobs die, but not submit them (default FALSE).
    -chdir                  :   This option will tell each sbatch job to cd into this directory before running command. <STRING> (default current).
    -help                   :   Prints this battleworn help message.
```

## Detailed description
Often it gets tedious creating sbatch scripts every time you want to launch n number of jobs on a cluster.  Salvo is designed to give you a couple of options when launching jobs in a slurm based environment:

1.	Creation of sbatch scripts, for user submission.
2.	Creation of sbatch scripts, and submission of sbatch jobs in a controlled manner.
 





 





 


