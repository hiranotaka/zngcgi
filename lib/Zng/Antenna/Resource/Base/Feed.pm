package Zng::Antenna::Resource::Base::Feed;

use strict;
use utf8;

sub smartphone_link ( $ ) {
    my $self = shift;
    return $self->link;
}

1;
