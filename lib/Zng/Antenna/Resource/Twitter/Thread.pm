package Zng::Antenna::Resource::Twitter::Thread;

use strict;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Thread;
use Zng::Antenna::Resource::Twitter::Feed;

@ISA = qw{Zng::Antenna::Resource::Base::Thread};

sub new ( $$ ) {
    my $class = shift;
    my $data = shift;

    my $self = bless {
	data => $data,
    }, $class;

    return $self;
}

sub id ( $ ) {
    my $self = shift;
    my $id = $self->feed->id;
    $id = md5($id . $self->{data}->{id});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{name};
}

sub link ( $ ) {
    my $self = shift;
    my $screen_name = $self->{data}->{screen_name};
    return "http://twitter.com/$screen_name";
}

sub mobile_link ( $ ) {
    my $self = shift;
    my $screen_name = $self->{data}->{screen_name};
    return "http://mobile.twitter.com/$screen_name";
}

sub smartphone_link ( $ ) {
    my $self = shift;
    return $self->mobile_link;
}

sub content ( $ ) {
    my $self = shift;
    return $self->{data}->{content};
}

sub updated ( $ ) {
    my $self = shift;
    return $self->{data}->{updated};
}

sub feed ( $ ) {
    my $self = shift;
    my $feed_data = $self->{data}->{feed};
    my $feed = Zng::Antenna::Resource::Twitter::Feed->new($feed_data);
    return $feed;
}

1;
