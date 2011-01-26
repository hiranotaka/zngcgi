package Zng::Antenna;

use strict;
use Zng::Cache;

sub hex_id ( $ ) {
    my $id = shift;
    return unpack 'H*', $id;
}

sub tag_uri ( $ ) {
    my $id = shift;
    return 'tag:zng.jp,2011:antenna/' . hex_id $id;
}

sub fetch ( $ ) {
    my $config = shift;

    my $updater = sub ( $ ) {
	my $data = shift;
	require Zng::Antenna::Updater;
	return Zng::Antenna::Updater::update($config, $data);
    };
    my $cache = Zng::Cache->new(updater => $updater,
				file => $config->{cache_file},
				expires => $config->{expires});
    $cache->fetch;
    return $cache;
}

1;
