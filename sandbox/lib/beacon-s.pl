#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use IO::Socket::INET;

# flush after every write
$| = 1;

my $socket = IO::Socket::INET->new(
    LocalHost => '10.242.128.49',
    LocalPort => '45652',
    Proto     => 'tcp',
    Type      => SOCK_STREAM,
    Listen    => SOMAXCONN,
    Reuse     => 1
) or die "Could not create socket: $!\n";

say "SERVER Waiting for client connections.";
do { 
    my $client = $socket->accept;

    # get information about a newly connected client
    my $client_address = $client->peerhost();
    my $client_port    = $client->peerport();
    print "connection from $client_address:$client_port\n";

    # Get data on who client is.
    my $node = "";
    $client->recv( $node, 1024 );
    say "Received beacon from node: $node";

    ## send cmds via json message.
    my $work = shift @file_repo;
    say "sending file $work to $node.";
    $client->send($work);

} while (@file_repo);

$socket->close;


