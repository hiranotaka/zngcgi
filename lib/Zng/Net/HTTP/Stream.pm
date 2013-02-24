package Zng::Net::HTTP::Stream;
use strict;
use vars qw{@ISA};
use Net::HTTP::Methods;

@ISA = qw{Net::HTTP::Methods};

my $PACKAGE = __PACKAGE__;

sub http_connect {
    my $self = shift;

    my $handle = IO::Socket::INET->new;
    unless ($handle->configure(@_) || $!{EINPROGRESS}) {
	return undef;
    }
    ${*$self}{handle} = $handle;
    return $self;
}

sub sysread {
    my $self = shift;
    my $count = ${*$self}{handle}->sysread(@_);

    unless (defined $count) {
	if ($!{EAGAIN}) {
	    $self->_rbuf(${*$self}{'save'});
	    die "$PACKAGE: resource temporarily unavailable\n";
	}
	return undef;
    }
    ${*$self}{'save'} .= substr($_[0], $_[2]);
    return $count;
}

sub read_response_headers {
    my $self = shift;

    ${*$self}{'save'} = $self->_rbuf;
    $self->SUPER::read_response_headers(@_);
}

sub read_entity_body {
    my $self = shift;

    ${*$self}{'save'} = $self->_rbuf;
    $self->SUPER::read_entity_body(@_);
}

sub handle {
    my $self = shift;

    return ${*$self}{handle};
}
