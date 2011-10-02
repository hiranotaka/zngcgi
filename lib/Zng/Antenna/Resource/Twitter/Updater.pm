package Zng::Antenna::Resource::Twitter::Updater;

use strict;
use utf8;
use HTTP::Date qw{str2time};
use HTTP::Request;
use HTTP::Status;
use JSON;
use URI::Escape;

sub __parse_user ( $$ ) {
    my $thread = shift;
    my $user = shift;

    if (ref $user ne 'HASH') {
	$thread->{permanent_error} = __PACKAGE__ . ": user must be a hash.";
	return 0;
    }

    $thread->{id} = $user->{id};
    $thread->{screen_name} = $user->{screen_name};
    $thread->{name} = $user->{name};
    return 1;
}

sub __parse_status ( $$ ) {
    my $thread = shift;
    my $status = shift;

    if (ref $status ne 'HASH') {
	$thread->{permanent_error} = __PACKAGE__ . ": status must be a hash.";
	return 0;
    }

    my $created_at = $status->{created_at};
    $created_at =~ s/\+0000/GMT/;
    $thread->{updated} = str2time $created_at;
    $thread->{status_id} = int $status->{id};

    my $content = $status->{text};
    $thread->{content} = Zng::Antenna::Updater::html_to_text $content;

    __parse_user $thread, $status->{user};
    return 1;
}

sub __parse_statuses ( $$ ) {
    my $feed = shift;
    my $statuses = shift;

    if (ref $statuses ne 'ARRAY') {
	$feed->{permanent_error} = __PACKAGE__ . ": statuses must be an array.";
	return 0;
    }

    my $threads = $feed->{threads} || [];
    my $thread_map = {};
    for my $thread (@$threads) {
	my $id = $thread->{id};
	$thread_map->{$id} = $thread;
    }

    for my $status (@$statuses) {
	my $new_thread = { feed => $feed };
	__parse_status $new_thread, $status or return 0;

	my $id = $new_thread->{id};
	my $old_thread = $thread_map->{$id};
	!$old_thread ||
	    $old_thread->{status_id} < $new_thread->{status_id} or next;
	$thread_map->{$id} = $new_thread;
    }

    $feed->{threads} = [ values %$thread_map ];
    return 1;
}

sub __parse_content ( $$ ) {
    my $feed = shift;
    my $content = shift;

    my $statuses;
    eval {
	$statuses = decode_json $content;
    };
    if ($@ ne '') {
	$feed->{permanent_error} = __PACKAGE__ . ": cannot parse JSON: $@";
	return;
    }

    __parse_statuses $feed, $statuses or return;

    $feed->{permanent_error} = undef;
}

sub __handle_response ( $$ ) {
    my $feed = shift;
    my $response = shift;

    unless ($response) {
	$feed->{temporary_error} = $@;
	return;
    }

    my $code = $response->code;
    if ($code == RC_OK) {
	__parse_content $feed, $response->content;
    } else {
	$feed->{temporary_error} = "unexpected HTTP status $code";
	return;
    }

    $feed->{temporary_error} = undef;
}

sub update ( $$ ) {
    my $feed = shift;
    my $net = shift;

    my $owner_screen_name = $feed->{owner_screen_name};
    my $escaped_slug = uri_escape_utf8 $feed->{slug};
    my $threads = $feed->{threads} || [];
    my $max_status_id = 1;
    for my $thread (@$threads) {
	$thread->{status_id} > $max_status_id or next;
	$max_status_id = $thread->{status_id};
    }

    my $url = "http://api.twitter.com/1/$owner_screen_name/lists/" .
	"$escaped_slug/statuses.json?since_id=$max_status_id&per_page=200";
    my $request = HTTP::Request->new(GET => $url);

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response;
    };
    $net->add_request($request, $handler);
}

1;
