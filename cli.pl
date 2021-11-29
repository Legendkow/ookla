#!/usr/bin/perl
use Time::HiRes qw( usleep ualarm gettimeofday);
use IO::Socket::INET;

# auto-flush on socket
$| = 1;

# create a connecting socket
my $sock = new IO::Socket::INET (
    PeerHost => $ARGV[0],
    PeerPort => 8080,
    Proto => 'tcp',
);
die "cannot connect to the server $!n" unless $sock;
print "connected to the server\n";

$bytes = "a" x 25000000;
my $start = getTS();
$sock->send("UPLOAD 25000000\n$bytes\n");
$buff = "";
$sock->recv($buff, 1000);
printf "took %f secs\n", getTS() - $start;
print $buff;
print "one more time\n";
$start = getTS();
$sock->send("UPLOAD 25000000\n$bytes\n");
$buff = "";
$sock->recv($buff, 1000);
printf "took %f secs\n", getTS() - $start;
print $buff;
sub getTS() {
	my ($seconds, $microseconds) = gettimeofday;
	return $seconds + $microseconds/1000000;
}
