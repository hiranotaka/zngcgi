package Zng::Antenna::Resource::Base::Feed;

use strict;

sub smartphone_link ( $ ) {
    my $self = shift;
    return $self->link;
}

1;
