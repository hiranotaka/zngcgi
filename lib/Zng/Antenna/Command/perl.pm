package Zng::Antenna::Command::perl;

use strict;
use Data::Dumper;
use HTTP::Date qw{time2isoz};
use Zng::Antenna;

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    $q->charset('utf-8');

    if ($q->param('secret') ne $config->{secret}) {
	$fh->print($q->header(-status => '403 Forbidden'));
	return;
    }

    my $cache = Zng::Antenna::fetch $config;

    my $expires = $cache->last_modified + $config->{ttl};
    $fh->print($q->header(-type => 'text/plain', -charset => 'utf-8',
			  -expires => $expires),
	       Dumper $cache->content->{feeds});
}

1;
