package Zng::Antenna::Resource::JBBS::Thread;

use strict;
use utf8;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Thread;
use Zng::Antenna::Resource::JBBS::Feed;

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
    $id = md5($id . $self->{data}->{created});
    return $id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $directory = $data->{feed}->{directory};
    my $created = $data->{created};
    return "http://jbbs.shitaraba.net/bbs/read.cgi/$directory/$created/l20";
}

sub mobile_link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $directory = $data->{feed}->{directory};
    my $created = $data->{created};
    return "http://jbbs.shitaraba.net/bbs/i.cgi/$directory/$created/n";
}

sub content ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $author = $data->{author};
    my $email = $data->{email};
    my $content = $data->{content};
    if ($email eq '') {
	return "$author: $content";
    } else {
	return "$author <$email>: $content";
    }
}

sub updated ( $ ) {
    my $self = shift;
    return $self->{data}->{updated};
}

sub feed ( $ ) {
    my $self = shift;
    my $feed_data = $self->{data}->{feed};
    my $feed = Zng::Antenna::Resource::JBBS::Feed->new($feed_data);
    return $feed;
}

1;
