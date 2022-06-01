#!/usr/bin/perl
#testing tool for SIP2 server/response. Browse the script below and fill in the data required by you.
#   Scalar $request contains text of the SIP2 request

use strict; use warnings;
use IO::Socket::INET;

# flush after every write
$| = 1;

my ($socket,$client_socket);

# creating object interface of IO::Socket::INET modules which internally creates 
# socket, binds and connects to the TCP server running on the specific port.
$socket = new IO::Socket::INET (
	PeerHost => 'aleph.osu.cz',
	PeerPort => '5330',
	Proto => 'tcp',
	) or die "ERROR in Socket Creation : $!\n";

print "TCP Connection Success.\n";
#my $request='98'; #ACS status
#item statys
my $request='1720220214    130727AO|AB3212146132|AC|AY0AZF773';
#my $request='1720220101ZZZZ000101ABT';
#my $request='1720220101ZZZZ000101AB8200001172';
#my $request='1720220101ZZZZ000101AB3212136093';
print "request is $request\n";
$socket->send($request);
print "waiting for response...\n";
my $response;
$socket->recv($response,1024);
print "response is $response\n";
$socket->close();
