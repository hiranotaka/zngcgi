package Zng::Antenna::Resource::XML::Feed;

use strict;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Feed;
use Zng::Antenna::Resource::XML::Thread;

@ISA = qw{Zng::Antenna::Resource::Base::Feed};

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
    my $data = $self->{data};

    my $id = "\x3c\xcd\xbf\xc0\xed\x0f\x01\xe3\xc0\x5f\x66\x04\xc4\x67\x1d\xa2";
    $id = md5($id . $data->{url});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    return $self->{data}->{link};
}

sub threads ( $ ) {
    my $self = shift;
    my $threads_data = $self->{data}->{threads};
    my $threads = [];
    for my $thread_data (@$threads_data) {
	my $thread = Zng::Antenna::Resource::XML::Thread->new($thread_data);
	push @$threads, $thread;
    }
    return @$threads;
}

sub standalone ( $ ) {
    my $self = shift;
    return 0;
}

sub update ( $$ ) {
    my $self = shift;
    my $net = shift;

    require Zng::Antenna::Resource::XML::Updater;
    Zng::Antenna::Resource::XML::Updater::update($self->{data}, $net);
}

1;
