package Zng::Antenna::Command::rdf;

use strict;
use HTTP::Date qw{time2isoz};
use Zng::Antenna;

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    my $cache = Zng::Antenna::fetch $config;

    $q->charset('utf-8');

    my $last_modified = $cache->last_modified;
    my $threads = $cache->content->{threads};

    my $escaped_lang = $q->escapeHTML($config->{lang});
    my $escaped_id = $q->escapeHTML($config->{id});
    my $escaped_title = $q->escapeHTML($config->{title});
    my $escaped_url = $q->escapeHTML($q->url);
    my $formatted_updated = join 'T', split / /, time2isoz $last_modified;
    $fh->print($q->header(-type => 'application/rdf+xml',
			  -charset => 'utf-8',
			  -expires => $last_modified + $config->{expires}),
	       q{<?xml version="1.0" encoding="utf-8"?>},
	       q{<rdf:RDF xmlns="http://purl.org/rss/1.0/"},
	       q{ xmlns:dc="http://purl.org/dc/elements/1.1/"},
	       q{ xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"},
	       qq{ xml:lang="$escaped_lang">},
	       qq{<channel rdf:about="$escaped_id">},
	       qq{<title>$escaped_title</title>},
	       qq{<link>$escaped_url</link>},
	       qq{<dc:date>$formatted_updated</dc:date>},
	       q{<description></description>},
	       q{<items>},
	       q{<rdf:Seq>});

    for my $i (0..49) {
	my $thread = $threads->[$i] or last;
	my $escaped_id = $q->escapeHTML(Zng::Antenna::tag_uri $thread->id);
	$fh->print(qq{<rdf:li rdf:resource="$escaped_id" />});
    }

    $fh->print(q{</rdf:Seq>},
	       q{</items>},
	       q{</channel>});

    for my $i (0..49) {
	my $thread = $threads->[$i] or last;
	my $escaped_id = $q->escapeHTML(Zng::Antenna::tag_uri $thread->id);
	my $title = $thread->title;
	my $feed = $thread->feed;
	$title .= ' @ ' . $feed->title unless $feed->standalone;
	my $escaped_title = $q->escapeHTML($title);
	my $escaped_link = $q->escapeHTML($thread->link);
	my $updated = $thread->updated;
	my $formatted_updated =  join 'T', split / /, time2isoz $updated;
	my $content = $q->escapeHTML($thread->content);
	$fh->print(qq{<item rdf:about="$escaped_id">},
		   qq{<title>$escaped_title</title>},
		   qq{<link>$escaped_link</link>},
		   qq{<dc:date>$formatted_updated</dc:date>});

	if (defined $content) {
	    my $escaped_content = $q->escapeHTML($content);
	    $fh->print(qq{<description>$escaped_content</description>});
	}

	$fh->print(q{</item>});
    }
    $fh->print(q{</rdf:RDF>});
}

1;
