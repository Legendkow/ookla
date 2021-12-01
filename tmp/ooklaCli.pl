#!/usr/bin/perl
use Time::HiRes qw( usleep ualarm gettimeofday);
use IO::Socket::INET;
use IO::Select;

# auto-flush on socket
$| = 1;

# create a connecting socket
my $socks = {};
my $sel;
my $CONCURRENCY = 20;
my $MAXSIZE = 200000000;
my $proxy = "";
my $proxyPort = 8080;
my $serverHost = $ARGV[0]; #it may be a hostname
my $quiet = 0;
my $tasks = "both";
for (my $i = 1; $i <= $#ARGV; $i ++) {
	if ($ARGV[$i] =~ /^\-conc/i) {
		$i ++;
		$CONCURRENCY = int($ARGV[$i]);
		if ($quiet == 0) { print "concurrency is now $CONCURRENCY\n"; }
	} elsif ($ARGV[$i] eq "-proxy") {
		$i ++;
		if ($ARGV[$i] =~ /:/) {
			$proxy = $`;
			$proxyPort = int($');
		} else {
			$proxy = $ARGV[$i];
		}
	} elsif ($ARGV[$i] =~ /^\-q/) {
		$quiet = 1;
	} elsif ($ARGV[$i] =~ /^\-task/) {
		$tasks = lc($ARGV[++$i]);
	} elsif ($ARGV[$i] =~ /^\-max/) {
		$MAXSIZE = 1000000 * int($ARGV[++$i]);
		if ($quiet == 0) { print "maxsize is now $MAXSIZE\n"; }
	}
}
my $remains = $CONCURRENCY;
my $targetIp = ($proxy ne "")? $proxy : $serverHost; 
my $targetPort = ($proxy ne "")? $proxyPort: 8080;


my $start = getTS();
my $tmpTotal = 0;
my $len;
my $start2 = getTS();
my $tmp;
my $delta;
my $ctx;
my $size;
my $offset;
my $buff;
my $averageSum = 0;
my $averageCnt = 0;
my $lostOneConn = 0;
my @ready;
my $sock;
my $mode;

if ($tasks eq "both" || $tasks eq "download") {
	$mode = "download";
	downloadTest();
}
if ($tasks eq "both" || $tasks eq "upload") {
	$mode = "upload";
	uploadTest();
}

sub connect2Server {
	for (my $i=0; $i < $CONCURRENCY; $i++) {
		my $sock = new IO::Socket::INET (
			PeerHost => $targetIp,
			PeerPort => $targetPort,
			Proto => 'tcp',
		);
		die "cannot connect to the server $!n" unless $sock;
		$socks->{$sock} = {sock => $sock, id => $i, size => -1}; #-1 means we haven't got the header yet
		$sel->add($sock);
	}
	if ($quiet == 0) { print "connected to the server\n"; }
}

sub downloadTest {
	$sel = IO::Select->new;
	$remains = $CONCURRENCY;
	if ($quiet == 0) {print "downloading $CONCURRENCY connections\n"; }
	connect2Server(); #will behave slightly differently based on mode
	my $msgToSend = createIntialReq();
	for my $sock (keys %$socks) {
		$socks->{$sock}->{sock}->send($msgToSend);
	}
	while (1) {
		@ready = $sel->can_read(0.001);
		for $sock (@ready) {
			$ctx = $socks->{$sock};
			$buff = "";
			$sock->recv($buff, 0x100000);
			if ($buff eq "") {
				if (freeSock($sock)) {return;}
				next;
			}
			$len = length($buff);
			$tmpTotal += $len;
			$size = $ctx->{size};
			if ($size < 0) {
				#print "$buff\n=====================================\n";
				$offset = index($buff, "\r\n\r\n");
				if ($offset < 0) {
					for my $tmp (keys %$socks) {
						printf "size=%d\n", $socks->{$tmp}->{size};
					}
					print("unexpected http resp, failed to get full header in $buff\n");
					exit(0);
				}
				$len = $len - $offset - 4;
				if (substr($buff, 0, $offset+1) =~ /Content-Length:\s+(\d+)/s) {
					if ($1 != $MAXSIZE) {
						die substr($buff, 0, $offset);
						die "http response ctlen is $1, not equal to $MAXSIZE\n";
					}
				} else {
					die $buff;
					die "failed to get content length header in first buff of $len bytes\n";
				}
				$size = 0;
			}
			$size += $len;
			#printf "recved size $i  %d $sizes[$i]\n", length($buff);
			if ($size >= $MAXSIZE) {
				if (freeSock($sock)) {return;}
			}
			$ctx->{size} = $size;
			if ($tmpTotal > 0x100000) {
				$tmp = getTS();
				$delta = $tmp - $start2;
				if ($delta >= 1.0) {
					$start2 = $tmp;
					if ($quiet == 0) {
						printf "%.3f\n", $tmpTotal/$delta/0x8000000;
					}
					if ($lostOneConn == 0) {
						$averageSum += $tmpTotal/$delta/0x8000000;
						$averageCnt ++;
					}
					$tmpTotal = 0;
				}
			}
		}
	}
}

sub uploadTest {
	$sel = IO::Select->new;
	$remains = $CONCURRENCY;
	if ($quiet == 0) {print "uploading $CONCURRENCY connections\n"; }
	connect2Server(); #will behave slightly differently based on mode
	my $msgToSend = createIntialReq();
	for my $sock (keys %$socks) {
		$socks->{$sock}->{sock}->send($msgToSend);
	}
	my $chunkLen = 50000;
	my $maxChunks = $MAXSIZE/$chunkLen;
	my $bytes = "a" x $chunkLen;
	my $ret = -2;
	my $prevRet = -2;
	my $size = 0;
	$start2 = getTS();
	while (1) {
		@ready = $sel->can_write(0.001);
		for my $sock (@ready) {
			$ctx = $socks->{$sock};
			$ret = $sock->send($bytes);
			if ($ret != $prevRet) {
				#print "ret=$ret\n";
				$prevRet = $ret;
			}
			$size = ++ $ctx->{size};
			if ($size >= $maxChunks) {
				if (freeSock($sock)) { return; }
			}
			$tmpTotal += $chunkLen;
		}
		$tmp = getTS();
		$delta = $tmp - $start2;
		if ($delta >= 1.0) {
			$start2 = $tmp;
			if ($quiet == 0) { printf "%.3f\n", $tmpTotal/$delta/0x8000000;}
			if ($lostOneConn == 0) {
				$averageSum += $tmpTotal/$delta/0x8000000;
				$averageCnt ++;
			}
			$tmpTotal = 0;
		}
	}
}

sub freeSock  {
	my ($sock, $size) = @_;
	$lostOneConn = 1;
	$sel->remove($sock);
	#close($sock);
	$remains --;
	#print "remains=$remains size=$size\n";
	if ($remains == 0) {
		#printf "$sizes[0] $sizes[1] $sizes[2] $sizes[3] %f\n", getTS() - $start;
		if ($averageCnt > 0) {
			printf "$mode: %.3f\n", $averageSum/$averageCnt;
		}
		return 1;
	}
	return 0;
}


sub getTS() {
	my ($seconds, $microseconds) = gettimeofday;
	return $seconds + $microseconds/1000000;
}

sub createIntialReq {
	my $method = ($mode eq "download")? "GET" : "POST";
	my $ctLen = ($mode eq "download")? "": "Content-Length: $MAXSIZE\r\n";
	my $extra = ($proxy ne "")? "http://$serverHost:8080" : "";
	return qq{$method $extra/$mode?size=$MAXSIZE HTTP/1.1\r
User-Agent: Wget/1.20.3 (linux-gnu)\r
Accept: */*\r
Accept-Encoding: identity\r
Host: $serverHost:8080\r
${ctLen}Connection: Keep-Alive\r
Proxy-Connection: Keep-Alive\r
\r
};

}
