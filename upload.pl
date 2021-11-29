#!/usr/bin/perl
use Time::HiRes qw( usleep ualarm gettimeofday);
use IO::Socket::INET;
use IO::Select;
# auto-flush on socket
$| = 1;

# create a connecting socket
my @socks = ();
my $sock2id = {};
my $sel = IO::Select->new;
my $CONCURRENCY = 20;
if ($ARGV[1] ne "") {
	$CONCURRENCY = $ARGV[1];
	print "concurrency is $CONCURRENCY\n";
}
my $remains = $CONCURRENCY;
my @sizes = ();
my $maxChunks = 240 * 16;
for (my $i=0; $i < $CONCURRENCY; $i++) {
	$socks[$i] = new IO::Socket::INET (
		PeerHost => $ARGV[0],
		PeerPort => 8080,
		Proto => 'tcp',
	);
	die "cannot connect to the server $!n" unless $socks[$i];
	$sel->add($socks[$i]);
	$sizes[$i] = 0;
	$sock2id->{$socks[$i]} = $i;
}
print "connected to the server\n";
for (my $i=0; $i < $CONCURRENCY; $i++) {
	$socks[$i]->send("UPLOAD 250000000\n$bytes\n");
}
$bytes = "a" x 0x10000;
my $start = getTS();
my @ready;
my $start2 = getTS();
my $tmp;
my $delta;
my $tmpTotal = 0;
my $allTotal = 0;
while (1) {
	@ready = $sel->can_write(0.001);
	for my $sock (@ready) {
		my $i = $sock2id->{$sock};
		$sock->send($bytes);
		$sizes[$i] ++;
		if ($sizes[$i] >= $maxChunks) {
			prin($sock);
		}
		$tmpTotal += 0x10000;
		$allTotal += 0x10000;
	}
	$tmp = getTS();
	$delta = $tmp - $start2;
	if ($delta >= 1.0) {
		$start2 = $tmp;
		printf "%.3f\n", $tmpTotal/$delta/0x8000000;
		$tmpTotal = 0;
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

=skip
my $total = "";
for (my $i=0; $i < 4; $i++) {
	$buff = "";
	$socks[$i]->recv($buff, 1000);
	$total .= "$i\n$buff";
}
printf "took %f secs\n", getTS() - $start;
print $total;
=cut
sub getTS() {
	my ($seconds, $microseconds) = gettimeofday;
	return $seconds + $microseconds/1000000;
}
