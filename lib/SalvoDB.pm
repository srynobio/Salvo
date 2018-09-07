package SalvoDB;
use strict;
use warnings;
use feature 'say';
use Moo::Role;
use DBI;


use Data::Dumper;

## ----------------------------------------------------- ##
##                    Attributes                         ##
## ----------------------------------------------------- ##

=cut
has dbConnect => (
    is      => 'rw',
    default => sub {
        my $self   = shift;
        my $jbname = $self->jobname;
        my $dbName = "$jbname.db";
        my $dbh =
          DBI->connect( "dbi:SQLite:dbname=$dbName", "", "",
            { RaiseError => 1 } )
          or die $DBI::errstr;
    }
);
=cut


has dbh => (
    is => 'rw',
    default => sub {
        my $self = shift;
        return $self->{dbh};
    },
);




## ----------------------------------------------------- ##
##                     Methods                           ##
## ----------------------------------------------------- ##

sub connectDB {
    my $self   = shift;
    my $jobname = $self->jobname;
    my $dbName = "$jobname.db";

    my $needBuild = 1;
    if ( -e $dbName ) {
        $self->INFO("Command DB $dbName discovered.");
        $needBuild = 0;
    }

    ## create dbh and add it.
    my $dbh =
      DBI->connect( "dbi:SQLite:dbname=$dbName", "", "", { RaiseError => 1 } )
      or die $DBI::errstr;
    $self->{dbh} = $dbh;

    ## build the data base if not already created.
    $self->buildDB if ($needBuild);
    $self->populateDB if ($needBuild);

    return;
}

## ----------------------------------------------------- ##

sub buildDB {
    my $self = shift;
    my $dbh  = $self->dbh;

    $dbh->do(
        "CREATE TABLE Process(
        	ID INTEGER PRIMARY KEY AUTOINCREMENT,
        	Command varchar(100),
        	Status varchar(10)
        );"
    );
    return;
}

## ----------------------------------------------------- ##

sub populateDB {
    my $self = shift;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare("INSERT INTO Process (Command,Status) VALUES (?,?)");

    my $commandFile = $self->{command_file};
    open(my $CF, '<', $commandFile) or $self->ERROR("Can not open command file: $commandFile");

    foreach my $line (<$CF>) {
        chomp $line;
        if ( $self->concurrent ) {
            $line = "$line &"
        }
        ## Set default for Status column.
        $sth->execute($line,'ready');
    }
}

## ----------------------------------------------------- ##

sub getCmdsDB {
    my $self = shift;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare("SELECT ID, Command FROM Process WHERE Status = 'ready'");
    $sth->execute;

    my @cmds;
    while ( my $fetch = $sth->fetchrow_array ) {
        push @cmds, $fetch;
    }
    return \@cmds;
}

## ----------------------------------------------------- ##

sub numberRunningDB {
    my $self = shift;

    my $dbh = $self->dbh;
    my $sth =
      $dbh->prepare("SELECT COUNT(*) FROM Process WHERE Status = 'running'");
    $sth->execute;

    my $running = $sth->fetchrow;
    return $running;

}

## ----------------------------------------------------- ##

sub updateStatusDB {
    my ( $self, $status, $where, $equals, $outfile) = @_;




    my $dbh = $self->dbh;
    my $sth = $dbh->prepare("UPDATE Process SET Sbatch_File = ? WHERE $where = ?");
    $sth->execute( $status, $equals ) or die "hell!!";

    return;
}

## ----------------------------------------------------- ##









1;

