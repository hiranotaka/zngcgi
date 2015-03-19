package Zng::Antenna::Command::auto;

use strict;
use utf8;

my $MOBILE_USER_AGENT_RE =
    'DoCoMo|KDDI|J-PHONE|Vodafone|SoftBank|DDIPOCKET|WILLCOM';

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    if ($q->user_agent('Mobile Safari')) {
	require Zng::Antenna::Command::smartphone;
	Zng::Antenna::Command::smartphone::format($config, $q, $fh);
    } elsif ($q->user_agent($MOBILE_USER_AGENT_RE)) {
	require Zng::Antenna::Command::mobile;
	Zng::Antenna::Command::mobile::format($config, $q, $fh);
    } else {
	require Zng::Antenna::Command::html;
	Zng::Antenna::Command::html::format($config, $q, $fh);
    }
}

