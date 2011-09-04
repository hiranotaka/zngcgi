package Zng::Antenna::Resource::HTML::Feed;

use strict;
use utf8;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Feed;
use Zng::Antenna::Resource::HTML::Thread;

sub new ( $ ) {
    my $class = shift;
    my $data = shift;

    my $self = bless {
	data => $data,
    }, $class;
    return $self;
}

sub id ( $ ) {
    my $self = shift;
    my $data = $self->{data};

    my $id = "\xa9\x89\x18\x5c\x9d\x14\x98\xa3\x7a\xf9\x0d\x4c\xb2\x0f\x98\x12";
    $id = md5($id . $data->{url});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    return $self->{data}->{url};
}

sub threads ( $ ) {
    my $self = shift;
    return Zng::Antenna::Resource::HTML::Thread->new($self->{data});
}

sub standalone ( $ ) {
    my $self = shift;
    return 1;
}

sub update ( $$ ) {
    my $self = shift;
    my $net = shift;

    require Zng::Antenna::Resource::HTML::Updater;
    Zng::Antenna::Resource::HTML::Updater::update($self->{data}, $net);
}

1;
