package Zng::Antenna::Resource::BBS2ch::Feed;

use strict;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::BBS2ch::Thread;
use Zng::Antenna::Resource::Base::Feed;

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

    my $id = "\xeb\x56\x66\x7e\xe2\x02\x33\x57\x29\x8d\xd2\xf0\x68\x64\xc7\x9b";
    $id = md5($id . $data->{server});
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
    my $server = $data->{server};
    my $directory = $data->{directory};
    return "$server/$directory/";
}

sub threads ( $ ) {
    my $self = shift;
    my $threads_data = $self->{data}->{threads};
    my $threads = [];
    for my $thread_data (@$threads_data) {
	my $thread = Zng::Antenna::Resource::BBS2ch::Thread->new($thread_data);
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

    require Zng::Antenna::Resource::BBS2ch::Updater;
    Zng::Antenna::Resource::BBS2ch::Updater::update($self->{data}, $net);
}

1;
