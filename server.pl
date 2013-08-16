#!/usr/bin/env perl
BEGIN { $^W = 1; }

use IO::Select;
use IO::Socket;
use POSIX;
use strict;
use Storable qw(dclone);
use Data::Dumper;

$Data::Dumper::Useqq = 1;  

my $routing = { ''              => \&testmsg,
                'fibo'          => \&fiboFunc,
                'data'          => \&browser,
                'get'           => \&getFile,
              };


my $response = { 'headers'       => {'content-type' => 'text/html'},
                 'httpStatus'    => undef,
                 'content'       => undef,
                 'socket'        => undef,
                 'fh'            => undef,
                 'method'        => undef,
                 'mime-type'     => undef
              };

my $mimetypes = {
                    'jpg' =>  'image/jpeg',
                    'png' =>  'image/png',
                    'gif' =>  'image/gif',
                    'pdf' =>  'application/pdf',
                    'css' =>  'text/css'
                };



my $sock = new IO::Socket::INET (
                               LocalHost => '0.0.0.0',
                               LocalPort => '7070',
                               Proto => 'tcp',
                               Listen => 16,
                               ReuseAddr  => 1,
                               Blocking => 0

                               );
die "Could not create socket: $!\n" unless $sock;
$sock->autoflush(1);
my $sel = new IO::Select(); # create handle set for reading
$sel->add($sock);      # add the main socket to the set

while(1){
    my @fha = $sel->can_read(1);
    foreach my $fh (@fha) {
        if($fh == $sock) {
            # Create a new socket
            my $new = $fh->accept;
            $sel->add($new);
            }

        else {

            my $buf = <$fh>;
            if($buf)
            {
                if ($buf =~ m|^quit|i){ 
              $sel->remove($fh);
            }
            else
            {

                my %request = determineReq($fh, $buf); 

                print "STARTING HERE   " .Dumper(%request) . "ENDING HERE"; 
                if ($request{"METHOD"} eq "GET"){ 
                    my @path = split( /\//, $request{OBJECT});
                    
                    my $method = $path[1];
                    shift @path;

                    unless (exists $routing->{$method} ) { 

                        $response->{'headers'} = {'content-type' => 'text/html; charset=UTF-8'};
                        $response->{'content'} = template("404 " . @path .  "\n"); 
                        $response->{'httpStatus'} = "404 Requested Site not found";

                    }
                    else {

                        $response->{'headers'} = {'content-type' => 'text/html; charset=UTF-8'};
                        $response->{'httpStatus'} = "200 OK";
                        my $res = $routing->{$method}->($response, @path);
                        $response->{'content'} = template($res);
     
                    }

                    sendResp($fh, $response)
                };

                if ($request{"METHOD"} eq "POST" and $request{OBJECT} ne "/"){ 
                    my @path = split /\//, $request{OBJECT};
                    print $fh template("Hello " . $path[1] . ". I wish you a nice weekend!\n"); 
                };


                $sel->remove($fh);
            }

            }
            else
            {
            $sel->remove($fh);
            }

        }
    }

}
close($sock);


sub sendResp {

    my $fh            = shift;
    my $response      = shift;

    #build and send headers
    print $fh  "HTTP/1.0 " . ($response->{'httpStatus'} or "500 Error") . "\r\n";

    my $headers = $response->{'headers'};
    foreach my $key (keys %$headers) {
        print $fh $key . ": " . $headers->{$key} ."\r\n";
    }
    print $fh "\r\n";

    # Process Body
    # binary?
    if ($response->{'fh'}){

        sendBinary($response->{'fh'}, $fh);
        
        close $response->{'fh'};
        $response->{'fh'} = undef;
    }

    # regular html
    else{

        print $fh $response->{'content'};
    }

}


sub determineReq {

    my $fh           = shift;
    my $request_line = shift;
    my %req;
    my $first_line;

    $req{HEADER} = {};

    while ($request_line ne "\r\n") {
        unless ($request_line) {
            close $fh; 
        }

        chomp $request_line;

        unless ($first_line) {
            $first_line = $request_line;

            my @parts = split(" ", $first_line);
            if (@parts != 3) {
             close $fh;
            }

            $req{METHOD} = $parts[0];
            $req{OBJECT} = $parts[1];
         }

        else {
            my ($name, $value) = split(": ", $request_line);
            $name       = lc $name;
            $req{HEADER}{$name} = $value;
         }

         $request_line = <$fh>;

    }
    return %req;

}





###################
#
#  C A L L E D    M E T H O D S
#
######################


sub fiboFunc {
  my $response = shift;
  #check parameters
  my $input = $_[1];
  $input =~ m/^0|([1-9][0-9]*)/;
  my $n = $1;

  return "<br> Please supply a valid number (1-n). $input is not one" unless $n;

  my $res = fibo($n);
  return "<br> the fibo-result for $n is <b>" . $res . "</b><br>"; 

}

sub fibo {
    my $n = shift;

    if ($n == 0) {return 0;}
    if ($n == 1) {return 1;}

    return fibo($n-1) + fibo($n-2);

}


sub browser {
    my $response = shift;
    my $subPath = $_[1];

    my $dir;
    if ($subPath) {$dir =  'data/' . $subPath; }
    else          {$dir =  'data';}
        print $dir . "\n";
    my @return;

    opendir(DIR, $dir) or return "No such dir";

    while (my $file = readdir(DIR)) {

        # Use a regular expression to ignore files beginning with a period
        next if ($file =~ m/^\./);

        if (-d $dir."/".$file) { push @return, "<a href='/$dir/$file'>"  .$file . "</a>";}
        if (-f $dir."/".$file and exists $mimetypes->{getSuffix($file)}) { push @return, "<a href='/get/$dir/$file'>"  .$file . "</a>"; } # only display supported mime-types

    }

    closedir(DIR);

    return join "<br>", @return;
}


sub getFile{
    my $response = shift;
    my @path = @_;
    shift @path; # remove function call /function/
    my $suffix = getSuffix($path[-1]);
    if (exists $mimetypes->{$suffix}){ $response->{'headers'}->{'content-type'} = $mimetypes->{$suffix}; }

    my $filepath = join "/", @path;
    print $filepath ."\n";
    $filepath =~ s/%20/ /g;
    unless (-f $filepath){ return "this is no file!"}
    open my $fh, '<', $filepath or print "error opening $filepath: $!";

    $response->{"fh"} = $fh; 
    return $fh;
}


sub getSuffix { 
    my $filepath = shift;
    my @suffix = split /\./, $filepath;
    return $suffix[-1];

}

sub sendBinary { 
    my $fh     = shift;
    my $socket = shift;
    my $data;

    while (read($fh, $data, 1024)){
        send($socket, $data, 1024);
    }

 }


sub testmsg{ return "I received a /";}

sub template {
 my $text = shift;
 return "<doctype><html>
 <head>
 <link href='//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.2/css/bootstrap-combined.min.css' rel='stylesheet'>
 <title>Ales Title</title>
 </head>
 <body>
 <h1>Howdy</h1>
 <p>$text</p>
 </body></html>"

}
