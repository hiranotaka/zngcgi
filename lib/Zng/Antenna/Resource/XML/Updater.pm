package Zng::Antenna::Resource::XML::Updater;

use strict;
use utf8;
use HTTP::Date qw{str2time};
use HTTP::Request;
use HTTP::Status;
use URI;
use XML::LibXML;

sub XML_NS { 'http://www.w3.org/XML/1998/namespace' }
sub RDF_NS { 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' }
sub RSS_NS { 'http://purl.org/rss/1.0/' }
sub DC_NS { 'http://purl.org/dc/elements/1.1/' }
sub CONTENT_NS {"http://purl.org/rss/1.0/modules/content/" }

sub __parse_rss_title ( $$ ) {
    my $thread = shift;
    my $element = shift;

    $thread->{title} = $element->textContent;
}

sub __parse_rss_description ( $$ ) {
    my $thread = shift;
    my $element = shift;

    $thread->{content} = $element->textContent;
}

sub __parse_rss_link ( $$ ) {
    my $thread = shift;
    my $element = shift;

    my $content = $element->textContent;

    my $uri = URI->new_abs($content, $element->baseURI);
    if ($uri->scheme ne 'http') {
	$thread->{link} = undef;
	return;
    }

    $thread->{link} = $uri->as_string;
}

sub __parse_dc_date ( $$ ) {
    my $thread = shift;
    my $element = shift;

    my $content = $element->textContent;
    $thread->{updated} = str2time $content;
}

sub __parse_content_encoded ( $$ ) {
    my $thread = shift;
    my $element = shift;

    my $content = $element->textContent;
    $thread->{content} = Zng::Antenna::Updater::html_to_text $content;
}

sub __parse_rdf_about ( $$ ) {
    my $thread = shift;
    my $element = shift;

    $thread->{id} = $element->getAttributeNS(RDF_NS, 'about');
}

sub __parse_rss_channel ( $$ ) {
    my $feed = shift;
    my $element = shift;

    __parse_rdf_about $feed, $element;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'title' && $namespaceURI eq RSS_NS) {
	    __parse_rss_title $feed, $node;
	} elsif ($localname eq 'link' && $namespaceURI eq RSS_NS) {
	    __parse_rss_link $feed, $node;
	}
    }
}

sub __parse_rss_item ( $$ ) {
    my $thread = shift;
    my $element = shift;

    __parse_rdf_about($thread, $element);

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'title' && $namespaceURI eq RSS_NS) {
	    __parse_rss_title $thread, $node;
	} elsif ($localname eq 'description' && $namespaceURI eq RSS_NS) {
	    __parse_rss_description $thread, $node;
	} elsif ($localname eq 'link' && $namespaceURI eq RSS_NS) {
	    __parse_rss_link $thread, $node;
	} elsif ($localname eq 'date' && $namespaceURI eq DC_NS) {
	    __parse_dc_date $thread, $node;
	} elsif ($localname eq 'encoded' && $namespaceURI eq CONTENT_NS) {
	    __parse_content_encoded $thread, $node;
	}
    }
}

sub __parse_rdf ( $$ ) {
    my $feed = shift;
    my $element = shift;

    my $threads = [];
    $feed->{threads} = $threads;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'channel' && $namespaceURI eq RSS_NS) {
	    __parse_rss_item $feed, $node;
	} elsif ($localname eq 'item' && $namespaceURI eq RSS_NS) {
	    my $thread = { feed => $feed };
	    push @$threads, $thread;
	    __parse_rss_item $thread, $node;
	}
    }
}

sub __parse_rss2_guid ( $$ ) {
    my $thread = shift;
    my $element = shift;

    my $id = $element->textContent;
    $thread->{id} = $id;
}

sub __parse_rss2_item ( $$ ) {
    my $thread = shift;
    my $element = shift;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'guid' && $namespaceURI eq '') {
	    __parse_rss2_guid $thread, $node;
	} elsif ($localname eq 'title' && $namespaceURI eq '') {
	    __parse_rss_title $thread, $node;
	} elsif ($localname eq 'link' && $namespaceURI eq '') {
	    __parse_rss_link $thread, $node;
	} elsif ($localname eq 'pubDate' && $namespaceURI eq '') {
	    __parse_dc_date $thread, $node;
	} elsif ($localname eq 'description' && $namespaceURI eq '') {
	    __parse_content_encoded $thread, $node;
	}
    }
}

sub __parse_rss2_channel ( $$ ) {
    my $feed = shift;
    my $element = shift;

    my $threads = [];
    $feed->{threads} = $threads;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'title' && $namespaceURI eq '') {
	    __parse_rss_title $feed, $node;
	} elsif ($localname eq 'link' && $namespaceURI eq '') {
	    __parse_rss_link $feed, $node;
	} elsif ($localname eq 'item' && $namespaceURI eq '') {
	    my $thread = { feed => $feed };
	    push @$threads, $thread;
	    __parse_rss2_item $thread, $node;
	}
    }
}

sub __parse_rss2 ( $$ ) {
    my $feed = shift;
    my $element = shift;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'channel' && $namespaceURI eq '') {
	    __parse_rss2_channel($feed, $node);
	}
    }
}

sub __parse_content ( $$ ) {
    my $feed = shift;
    my $content = shift;

    $feed->{permanent_error} = undef;

    my $parser = XML::LibXML->new;
    my $document;
    eval {
	$document = $parser->parse_string($content, $feed->{url})
    };
    if ("$@" ne '') {
	$feed->{permanent_error} = __PACKAGE__ . ": cannot parse XML: $@";
	return;
    }

    my $element = $document->documentElement;
    my $localname = $element->localname;
    my $namespaceURI = $element->namespaceURI;
    if ($localname eq 'RDF' && $namespaceURI eq RDF_NS) {
	__parse_rdf $feed, $element;
    } elsif ($localname eq 'rss' && $namespaceURI eq '') {
	__parse_rss2 $feed, $element;
    } else {
	$feed->{permanent_error} =
	    __PACKAGE__ . ": unsupported XML type $localname\n";
	return;
    }
}

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
	$feed->{http_last_modified} = $response->last_modified;
	__parse_content $feed, $response->content;
    } elsif ($code == RC_NOT_MODIFIED) {
    } else {
	$feed->{temporary_error} = "unexpected HTTP status $code";
	return;
    }
}

sub update ( $$ ) {
    my $feed = shift;
    my $net = shift;

    my $url = $feed->{url};
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{http_last_modified});

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response;
    };
    $net->add_request($request, $handler);
}

1;
