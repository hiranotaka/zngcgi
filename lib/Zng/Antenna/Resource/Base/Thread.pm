package Zng::Antenna::Resource::Base::Thread;

use strict;
use utf8;

sub mobile_link ( $ ) {
    my $self = shift;
    return $self->link;
}

sub smartphone_link ( $ ) {
    my $self = shift;
    return $self->link;
}

1;
