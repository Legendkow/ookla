#!/usr/bin/perl
use Time::HiRes qw( usleep ualarm gettimeofday);
use IO::Socket::INET;
use IO::Select;

# auto-flush on socket
$| = 1;

# create a connecting socket
my @socks = ();
my $sock2id = {};
my @sizes = ();
my $sel = IO::Select->new;
my $CONCURRENCY = 20;
my $remains = $CONCURRENCY;
my $MAXSIZE = 250000000;

if ($ARGV[1] ne "") {
	$CONCURRENCY = $ARGV[1];
	print "concurrency is $CONCURRENCY\n";
}

for (my $i=0; $i < $CONCURRENCY; $i++) {
	$socks[$i] = new IO::Socket::INET (
		PeerHost => $ARGV[0],
		PeerPort => 8080,
		Proto => 'tcp',
	);
	die "cannot connect to the server $!n" unless $socks[$i];
	$sel->add($socks[$i]);
	$sock2id->{$socks[$i]} = $i;
	$sizes[$i] = 0;
}
print "connected to the server\n";

for (my $i=0; $i < $CONCURRENCY; $i++) {
	$socks[$i]->send("DOWNLOAD $MAXSIZE\n");
}
print "waiting for response\n";
my $start = getTS();
my $tmpTotal = 0;
my $len;
my $start2 = getTS();
my $tmp;
my $delta;
while (1) {
	@ready = $sel->can_read(0.001);
	for my $sock (@ready) {
		my $i = $sock2id->{$sock};
		$buff = "";
		$sock->recv($buff, $MAXSIZE);
		if ($buff eq "") {
			prin($sock);
			next;
		}
		$len = length($buff);
		$tmpTotal += $len;
		$sizes[$i] += $len;
		#printf "recved size $i  %d $sizes[$i]\n", length($buff);
		if ($sizes[$i] >= $MAXSIZE) {
			prin($sock);
		}
		if ($tmpTotal > 0x1000000) {
			$tmp = getTS();
			$delta = $tmp - $start2;
			if ($delta >= 1.0) {
				$start2 = $tmp;
				printf "%.3f\n", $tmpTotal/$delta/0x8000000;
				$tmpTotal = 0;
			}
		}
	}
}
sub prin  {
	my $sock = shift;
	$sel->remove($sock);
	close($sock);
	$remains --;
	if ($remains == 0) {
		printf "$sizes[0] $sizes[1] $sizes[2] $sizes[3] %f\n", getTS() - $start;
		exit;
	}
}


sub getTS() {
	my ($seconds, $microseconds) = gettimeofday;
	return $seconds + $microseconds/1000000;
}
