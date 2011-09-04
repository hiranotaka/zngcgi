package Zng::Antenna::Resource::XML::StandaloneThread;

use strict;
use utf8;
use vars qw{@ISA};
use CGI;
use Digest::MD5 qw{md5};
use Zng::Antenna::Resource::Base::Thread;
use Zng::Antenna::Resource::XML::StandaloneFeed;

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
    return $self->feed->id;
}

sub title ( $ ) {
    my $self = shift;
    return $self->{data}->{title};
}

sub link ( $ ) {
    my $self = shift;
    return $self->{data}->{link};
}

sub content ( $ ) {
    my $self = shift;
    my $threads = $self->{data}->{threads};
    @$threads > 0 or return undef;
    my $thread = $threads->[0];
    my $title = $thread->{title};
    my $content = $thread->{content};
    return "$title: $content";
}

sub updated ( $ ) {
    my $self = shift;
    my $threads = $self->{data}->{threads};
    @$threads > 0 or return undef;
    return $threads->[0]->{updated};
}

sub feed ( $ ) {
    my $self = shift;
    return Zng::Antenna::Resource::XML::StandaloneFeed->new($self->{data});
}

1;
