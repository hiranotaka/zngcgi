package Zng::Antenna::Resource::Hatena::Feed;

use strict;
use utf8;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Feed;
use Zng::Antenna::Resource::Hatena::Thread;

@ISA = qw{Zng::Antenna::Resource::Base::Feed};

sub new ( $$ ) {
    my $class = shift;
    my $data = shift;

    my $user_id = $data->{user_id};
    $data->{url} = "http://d.hatena.ne.jp/$user_id/rss";

    my $self = bless {
	data => $data,
    }, $class;
    return $self;
}

sub id ( $ ) {
    my $self = shift;
    my $data = $self->{data};

    my $id = "\x8e\xd8\xe8\xc1\x01\x76\x08\x90\xf8\xcf\x7e\x2d\x74\x28\xc6\x69";
    $id = md5($id . $data->{user_id});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    my $user_id = $self->{data}->{user_id};
    return "http://d.hatena.ne.jp/$user_id/";
}

sub mobile_link ( $ ) {
    my $self = shift;
    my $user_id = $self->{data}->{user_id};
    return "http://d.hatena.ne.jp/$user_id/archivemobile";
}

sub threads ( $ ) {
    my $self = shift;
    my $threads_data = $self->{data}->{threads};
    my $threads = [];
    for my $thread_data (@$threads_data) {
	my $thread = Zng::Antenna::Resource::Hatena::Thread->new($thread_data);
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
