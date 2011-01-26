package Zng::Antenna::Command::smartphone;

use strict;
use Zng::Antenna::Command::html;

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;
    Zng::Antenna::Command::html::format($config, $q, $fh);
}

1;
