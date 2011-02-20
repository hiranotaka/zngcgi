package Zng::Antenna::Resource::Hatena::Thread;

use strict;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Thread;
use Zng::Antenna::Resource::Hatena::Feed;

@ISA = qw{Zng::Antenna::Resource::Base::Thread};

sub new ( $$ ) {
    my $class = shift;
    my $data = shift;

    my $id = $data->{id};
    my $user_id_re = quotemeta $data->{feed}->{user_id};
    if ($id =~ /http:\/\/d.hatena.ne.jp\/$user_id_re\/([^#\/]+)(?:#|\/)(.*)/) {
	$data->{date} = int $1;
	$data->{section} = int $2;
    }

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
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $user_id = $data->{feed}->{user_id};
    my $date = $data->{date};
    my $section = $data->{section};
    return "http://d.hatena.ne.jp/$user_id/$date/$section";
}

sub mobile_link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $user_id = $data->{feed}->{user_id};
    my $date = $data->{date};
    my $section = $data->{section};
    return "http://d.hatena.ne.jp/$user_id/mobile?date=$date;section=$section";
}

sub base_uri ( $ ) {
    my $self = shift;
    return $self->{data}->{base_uri};
}

sub text_content ( $ ) {
    my $self = shift;
    return $self->{data}->{text_content};
}

sub html_content ( $ ) {
    my $self = shift;
    return $self->{data}->{html_content};
}

sub updated ( $ ) {
    my $self = shift;
    return $self->{data}->{updated};
}

sub feed ( $ ) {
    my $self = shift;
    my $feed_data = $self->{data}->{feed};
    my $feed = Zng::Antenna::Resource::Hatena::Feed->new($feed_data);
    return $feed;
}

1;
