package Zng::Antenna::Resource::Base::Thread;

use strict;

sub mobile_link ( $ ) {
    my $self = shift;
    return $self->link;
}

sub smartphone_link ( $ ) {
    my $self = shift;
    return $self->link;
}

sub base_uri ( $ ) {
    return undef;
}

sub html_content ( $ ) {
    return undef;
}

1;
