package Zng::Cache;

use strict;
use vars qw{$VERSION};
use Fcntl qw{:flock};
use File::stat;
use Storable qw{retrieve_fd store_fd};

$VERSION = '1.00';

sub new ( $% ) {
    my $class = shift;
    my %options = @_;

    bless {
	updater => $options{updater},
	file => $options{file},
	content => undef,
	last_modified => undef,
	ttl => $options{ttl},
    }, $class;
}

sub updater ( $;$ ) {
    my $self = shift;

    my $updater = $self->{updater};
    $self->{updater} = shift if @_;
    return $updater;
}

sub file ( $;$ ) {
    my $self = shift;

    my $file = $self->{file};
    $self->{file} = shift if @_;
    return $file;
}

sub content ( $;$ ) {
    my $self = shift;

    my $content = $self->{content};
    $self->{content} = shift if @_;
    return $content;
}

sub ttl ( $;$ ) {
    my $self = shift;

    my $ttl = $self->{ttl};
    $self->{ttl} = shift if @_;
    return $ttl;
}

sub last_modified ( $;$ ) {
    my $self = shift;

    my $last_modified = $self->{last_modified};
    $self->{last_modified} = shift if @_;
    return $last_modified;
}

sub expired ( $$ )  {
    my $self = shift;
    my $ttl = shift;

    my $last_modified = $self->last_modified;
    defined $last_modified or return 1;

    my $ttl = $self->ttl;
    defined $ttl or return 1;

    return $last_modified + $ttl < time;
}

sub __lock ( $ ) {
    my $self = shift;

    my $file = $self->file;
    open my $lock_handle, '>>', "${file}.lock"
	or die 'cannot open the lock file';

    flock $lock_handle, LOCK_EX
	or die 'cannot get the lock file';
    return $lock_handle;
}

sub __stat ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my $stat = stat $handle
	or die 'cannot stat the cache file';

    my $last_modified = $stat->mtime;
    $self->last_modified($last_modified);
}

sub __read_top ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my $file = $self->file;
    open my $handle, '<', $file or return undef;

    $self->__stat($handle);
    return $handle;
}

sub __read_bottom ( $$ ) {
    my $self = shift;
    my $handle = shift;

    $handle or return;
    my $content = retrieve_fd $handle;
    $self->content($content);
}

sub __write_top ( $ ) {
    my $self = shift;

    my $file = $self->file;
    my $part_file = "${file}.part";
    open my $handle, '>', $part_file
	or die 'cannot open the cache file';

    my $content = $self->content;
    store_fd $content, $handle
	or die 'cannot store to the cache file';

    $handle->flush
	or die 'cannot flush to the cache file';
    rename $part_file, $file
	or die 'cannot commit the cache file';

    return $handle;
}

sub __write_bottom ( $$ ) {
    my $self = shift;
    my $handle = shift;

    $self->__stat($handle);
}

sub __update ( $ ) {
    my $self = shift;

    my $updater = $self->updater;
    my $content = $self->content;
    $content = &$updater($content);
    $self->content($content);
}

sub fetch ( $$$$ ) {
    my $self = shift;

    # Try to read cache without lock
    my $handle = $self->__read_top;
    unless ($self->expired) {
	$self->__read_bottom($handle);
	return;
    }
    undef $handle;

    # Force to read cache with lock
    my $lock_handle = $self->__lock;
    my $handle = $self->__read_top;
    unless ($self->expired) {
	undef $lock_handle;
	$self->__read_bottom($handle);
	return;
    }
    $self->__read_bottom($handle);
    undef $handle;

    # Update
    $self->__update;

    # Write cache
    my $handle = $self->__write_top;
    undef $lock_handle;
    $self->__write_bottom($handle);

    return;
}

1;
