#!/usr/bin/perl

use strict;
use utf8;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use vars qw{$config};
use CGI;

sub formatter ( $ ) {
    my $type = shift;

    $type =~ /^\w+$/ or return undef;

    my $class = "Zng::Antenna::Command::$type";
    eval "require $class";
    $@ eq '' or return undef;

    my $routine = "${class}::format";
    {
	no strict qw{subs};
	return \&$routine;
    }
}

my $q = CGI->new;
eval {
    require './.antenna5.conf';
    my $type = $q->param('type');
    my $formatter = formatter $type;
    unless (defined $formatter) {
	require Zng::Antenna::Command::html;
	$formatter = \&Zng::Antenna::Command::html::format;
    }
    &$formatter($config, $q, \*STDOUT);
};

if ($@) {
    print($q->header(-type => 'text/plain', -charset => 'utf-8'),
	  "ZngAntenna 5.0\n",
	  "--\n",
	  "A fatal error occurred on answering your query.\n",
	  "Sorry for your inconvenience.\n");

    open my $handle, '>>', 'error.log';
    print $handle scalar localtime, ': ', $@;
}
