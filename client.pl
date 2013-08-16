#!/usr/bin/env perl
BEGIN { $^W = 0; }

use IO::Socket;
use POSIX;
use IO::Select;


unless (@ARGV[0] || isdigit(@ARGV[0])){inputError();}

#connection information
my $connection = {
	PeerHost => '127.0.0.1',
	PeerPort => '7070',
	Proto => 'tcp',
	Blocking => 0 
};
# connection "pool" array
my @connPool;



my $sel = new IO::Select(); 

for(my $i = 0;$i <= @ARGV[0] ; $i++){

	my $remote = new IO::Socket::INET->new( 	
		%$connection
	) or die "Could not open socket";
	sleep 2;

	syswrite($remote, $i. "\n");
	print "sent " . $i . "\n";
	$sel->add($remote);

	push @connPool, $remote;


}

while (1){
	my @fha = $sel->can_read(0.1);
	foreach my $fh (@fha) {
			my $answer = <$fh>;
			my @splitanswer = split /;/, $answer;
			print "sent a @splitanswer[0]! and got the answer: " . @splitanswer[1] . "\n";
			syswrite($fh, "quit\n");
			$sel->remove($fh);

	}
	last if $sel->count() == 0;

}



foreach my $conn (@connPool){close $conn;}



sub inputError{

print STDERR "No or incorrect Number Supplied \n"; exit 1;

}