package Zng::Antenna::Resource::BBS2ch::Thread;

use strict;
use vars qw{@ISA};
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::BBS2ch::Feed;
use Zng::Antenna::Resource::Base::Thread;

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
    my $feed_data = $data->{feed};
    my $server = $feed_data->{server};
    my $directory = $feed_data->{directory};
    my $created = $data->{created};
    return "$server/test/read.cgi/$directory/$created/l20";
}

sub mobile_link ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $feed_data = $data->{feed};
    my $server = $feed_data->{server};
    my $directory = $feed_data->{directory};
    my $created = $data->{created};
    if ($server =~ m{^http://[^/]+\.2ch\.net(?:/|$)}) {
	return "http://c.2ch.net/test/-/$directory/$created/n";
    } else {
	return "$server/test/cell.cgi?/$directory/$created/l5n";
    }
}

sub base_uri ( $ ) {
    my $self = shift;
    my $feed_data = $self->{data}->{feed};
    my $server = $feed_data->{server};
    my $directory = $feed_data->{directory};
    return "$server/$directory/";
}

sub text_content ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $author = $data->{author};
    my $email = $data->{email};
    my $content = $data->{text_content};
    if ($email eq '') {
	return "$author: $content";
    } else {
	return "$author <$email>: $content";
    }
}

sub html_content ( $ ) {
    my $self = shift;
    my $data = $self->{data};
    my $author = $data->{author};
    my $email = $data->{email};
    my $content = $data->{html_content};
    if ($email eq '') {
	return "<dl><dt>$author</dt><dd>$content</dd>";
    } else {
	return "<dl><dt>$author &lt;$email&gt;</dt><dd>$content</dd>";
    }
}

sub updated ( $ ) {
    my $self = shift;
    return $self->{data}->{updated};
}

sub feed ( $ ) {
    my $self = shift;
    my $feed_data = $self->{data}->{feed};
    my $feed = Zng::Antenna::Resource::BBS2ch::Feed->new($feed_data);
    return $feed;
}

1;
