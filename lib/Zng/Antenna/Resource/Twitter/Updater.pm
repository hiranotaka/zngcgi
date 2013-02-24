package Zng::Antenna::Resource::Twitter::Updater;

use strict;
use utf8;
use HTTP::Date qw{str2time};
use HTTP::Request;
use HTTP::Status;
use JSON;
use URI::Escape;
use Digest::SHA;
use MIME::Base64;
use Fcntl;

sub gen_random_key {
    my $length = shift || 10;
    sysopen my $fh, '/dev/random', O_RDONLY | O_NONBLOCK or die;
    my $buf;
    $fh->sysread($buf, 10);
    return unpack("H*", $buf);
}

sub encode_param {
    my $param = shift;
    URI::Escape::uri_escape_utf8($param, '^\w.~-');
}

sub create_signature_base_string {
    my ($method, $url, $params) = @_;
    $method = uc $method;
    $params = {%$params};
    delete $params->{oauth_signature};
    delete $params->{realm};
    my $normalized_request_url = normalize_request_url($url);
    my $normalized_params = normalize_params($params);
    my $signature_base_string = join('&', map(encode_param($_),
        $method, $normalized_request_url, $normalized_params));
    $signature_base_string;
}

sub normalize_request_url {
    my $uri = shift;
    $uri = URI->new($uri) unless (ref $uri && ref $uri eq 'URI');
    unless (lc $uri->scheme eq 'http' || lc $uri->scheme eq 'https') {
        Carp::croak qq/Invalid request url, "$uri"/;
    }
    my $port = $uri->port;
    my $request_url = ($port && ($port == 80 || $port == 443))
        ? sprintf(q{%s://%s%s}, lc($uri->scheme), lc($uri->host), $uri->path)
        : sprintf(q{%s://%s:%d%s}, lc($uri->scheme), lc($uri->host), $port, $uri->path);
    $request_url;
}

sub build_auth_header {
    my ($realm, $params) = @_;
    my $head = sprintf q{OAuth realm="%s"}, $realm || '';
    my $authorization_header = join(', ', $head,
        sort { $a cmp $b } map(sprintf(q{%s="%s"}, encode_param($_), encode_param($params->{$_})),
            grep { /^x?oauth_/ } keys %$params));
    $authorization_header;
}

sub normalize_params {
    my $params = shift;
    my @pairs = ();
    for my $k (sort keys %$params) {
        if (!ref $params->{$k}) {
            push @pairs, 
                sprintf(q{%s=%s}, encode_param($k), encode_param($params->{$k}));
        }
        elsif (ref $params->{$k} eq 'ARRAY') {
            for my $v (sort @{ $params->{$k} }) {
                push @pairs, 
                    sprintf(q{%s=%s}, encode_param($k), encode_param($v));
            }
        }
    }
    return join('&', @pairs);
}

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

    my $threads = $feed->{threads} || [];
    my $max_status_id = 1;
    for my $thread (@$threads) {
	$thread->{status_id} > $max_status_id or next;
	$max_status_id = $thread->{status_id};
    }

    my $method = 'GET';
    my $url_base = "http://api.twitter.com/1.1/lists/statuses.json";

    my $url_params = {
	slug => $feed->{slug},
	owner_screen_name => $feed->{owner_screen_name},
    };

    my $oauth_params = {
	oauth_consumer_key => $feed->{consumer_key},
	oauth_timestamp => time,
	oauth_nonce => gen_random_key,
	oauth_version => '1.0',
	oauth_token => $feed->{auth_token},
	oauth_signature_method => 'HMAC-SHA1',
    };

    my $signature_base_params = {%$oauth_params, %$url_params};
    my $signature_base =
	create_signature_base_string($method, $url_base,
				     $signature_base_params);

    my $key = join('&', $feed->{consumer_secret}, $feed->{auth_token_secret});
    $oauth_params->{oauth_signature} =
	encode_base64(Digest::SHA::hmac_sha1($signature_base, $key));

    my $url = $url_base . '?' . normalize_params($url_params);
    my $header = [
	'Authorization' => build_auth_header('', $oauth_params),
    ];
    my $request = HTTP::Request->new($method, $url, $header);

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response;
    };
    $net->add_request($request, $handler);
}

1;
