package Zng::Antenna::Command::perl;

use strict;
use Data::Dumper;
use HTTP::Date qw{time2isoz};
use Zng::Antenna;

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    my $cache = Zng::Antenna::fetch $config;

    $q->charset('utf-8');

    print($q->header(-type => 'text/plain', -charset => 'utf-8',
		     -expires => $cache->last_modified + $config->{expires}),
	  Dumper $cache->content->{feeds});
}

1;
