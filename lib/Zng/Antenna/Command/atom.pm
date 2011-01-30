package Zng::Antenna::Command::atom;

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
    my $escaped_author = $q->escapeHTML($config->{author});
    my $escaped_self_url = $q->escapeHTML($q->self_url);
    my $escaped_url = $q->escapeHTML($q->url);

    my $formatted_updated = join 'T', split / /, time2isoz $last_modified;
    $fh->print($q->header(-type => 'application/atom+xml',
			  -charset => 'utf-8',
			  -expires => $last_modified + $config->{expires}),
	       qq{<?xml version="1.0" encoding="utf-8"?>},
	       qq{<feed xmlns="http://www.w3.org/2005/Atom"},
	       qq{ xml:lang="$escaped_lang">},
	       qq{<id>$escaped_id</id>},
	       qq{<title>$escaped_title</title>},
	       qq{<author><name>$escaped_author</name></author>},
	       qq{<link href="$escaped_self_url" rel="self" />},
	       qq{<link href="$escaped_url" rel="alternate" },
	       qq{type="text/html" />},
	       qq{<updated>$formatted_updated</updated>});

    for my $i (0..49) {
	my $thread = $threads->[$i] or last;

	my $escaped_id = $q->escapeHTML(Zng::Antenna::tag_uri $thread->id);
	my $escaped_title = $q->escapeHTML($thread->title);
	my $escaped_link = $q->escapeHTML($thread->link);
	my $formatted_updated =
	    join 'T', split / /, time2isoz $thread->updated;
	my $escaped_base_uri = $q->escapeHTML($thread->base_uri);
	my $content = $thread->html_content;
	unless (defined $content) {
	    $content = $q->escapeHTML($thread->text_content);
	}
	$fh->print(q{<entry>},
		   qq{<id>$escaped_id</id>},
		   qq{<title>$escaped_title</title>},
		   qq{<link href="$escaped_link" rel="alternate" />},
		   qq{<updated>$formatted_updated</updated>});

	if (defined $content) {
	    my $escaped_content = $q->escapeHTML($content);
	    $fh->print(qq{<content type="html" xml:base="$escaped_base_uri">},
		       $escaped_content,
		       q{</content>});
	}

	my $feed = $thread->feed;
	unless ($feed->standalone) {
	    my $escaped_id = $q->escapeHTML(Zng::Antenna::tag_uri $feed->id);
	    my $escaped_title = $q->escapeHTML($feed->title);
	    my $escaped_link = $q->escapeHTML($feed->link);

	    $fh->print(q{<source>},
		       qq{<id>$escaped_id</id>},
		       qq{<title>$escaped_title</title>},
		       qq{<link href="$escaped_link" rel="alternate" />},
		       q{</source>});
	}
	$fh->print(q{</entry>});
    }
    $fh->print q{</feed>};
}

1;
