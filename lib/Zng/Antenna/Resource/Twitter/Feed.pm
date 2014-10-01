package Zng::Antenna::Resource::Twitter::Feed;

use strict;
use utf8;
use vars qw{@ISA};
use Encode;
use Digest::MD5 qw{md5};
use URI::Escape;
use Zng::Antenna::Resource::Base::Feed;
use Zng::Antenna::Resource::Twitter::Thread;

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

    my $id = "\xc6\x6a\x45\x6d\x2f\x66\xc2\x5c\xda\x5f\xe1\xd2\x97\xf8\x1b\x61";
    $id = md5($id . $data->{owner_screen_name});
    $id = md5($id . encode_utf8 $data->{slug});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    my $list_id = $self->{data}->{slug};
    return 'Twitter';
}

sub link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $owner_screen_name = $data->{owner_screen_name};
    my $escaped_slug = uri_escape_utf8 $data->{slug};
    return "http://twitter.com/$owner_screen_name/lists/$escaped_slug";
}

sub threads ( $ ) {
    my $self = shift;
    my $threads_data = $self->{data}->{threads};
    my $threads = [];
    for my $thread_data (@$threads_data) {
	my $thread = Zng::Antenna::Resource::Twitter::Thread->new($thread_data);
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

    require Zng::Antenna::Resource::Twitter::Updater;
    Zng::Antenna::Resource::Twitter::Updater::update($self->{data}, $net);
}

1;
