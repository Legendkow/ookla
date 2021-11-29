$total = 0.0;
$count = 0;
while (<STDIN>) {
	if(/^([\d\.]+)/) {
		$total += $1;
		$count ++;
	}
}
printf "average: %.3f\n", $total/$count;
