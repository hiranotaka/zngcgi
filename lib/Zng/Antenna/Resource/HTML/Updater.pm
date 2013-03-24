package Zng::Antenna::Resource::HTML::Updater;

use strict;
use utf8;
use HTTP::Request;
use HTTP::Status;

sub __handle_response ( $$ ) {
    my $feed = shift;
    my $response = shift;

    $feed->{temporary_error} = undef;

    unless ($response) {
	$feed->{temporary_error} = $@;
	return;
    }

    my $code = $response->code;
    if ($code == RC_OK) {
	$feed->{updated} = $response->last_modified;
    } else {
	$feed->{temporary_error} = "unexpected HTTP status $code";
	return;
    }
}

sub update ( $$ ) {
    my $feed = shift;
    my $net = shift;

    my $url = $feed->{url};
    my $request = HTTP::Request->new(HEAD => $url);

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response;
    };
    $net->add_request($request, $handler);
}

1;
