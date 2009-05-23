package Zng::Net::Stream;
use strict;
use vars qw{@ISA};
use Net::HTTP::NB;

@ISA = qw{Net::HTTP};

my $PACKAGE = __PACKAGE__;

sub connect {
    my $self = shift;

    $self->blocking(0);
    unless ($self->SUPER::connect(@_) || $!{EINPROGRESS}) {
	return undef;
    }
    return $self;
}

sub sysread {
    my $self = shift;
    my $count = $self->SUPER::sysread(@_);

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
