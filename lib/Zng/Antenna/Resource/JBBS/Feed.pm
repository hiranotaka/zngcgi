package Zng::Antenna::Resource::JBBS::Feed;

use strict;
use utf8;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Feed;
use Zng::Antenna::Resource::JBBS::Thread;

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

    my $id = "\x5b\xfc\xb9\xc4\x72\xde\x3a\x8f\xc7\x75\xc4\x59\x0d\xab\x4c\x88";
    $id = md5($id . $data->{directory});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $directory = $data->{directory};
    return "http://jbbs.shitaraba.net/$directory/";
}

sub smartphone_link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $directory = $data->{directory};
    return "http://jbbs.livedoor.jp/bbs/lite/subject.cgi/$directory/";
}

sub threads ( $ ) {
    my $self = shift;
    my $threads_data = $self->{data}->{threads};
    my $threads = [];
    for my $thread_data (@$threads_data) {
	my $thread = Zng::Antenna::Resource::JBBS::Thread->new($thread_data);
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

    require Zng::Antenna::Resource::JBBS::Updater;
    Zng::Antenna::Resource::JBBS::Updater::update($self->{data}, $net);
}

1;
