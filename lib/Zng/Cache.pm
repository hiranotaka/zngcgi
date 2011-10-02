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

    my $file = $options{file};
    bless {
	updater => $options{updater},
	file => $file,
	part_file => "$file.part",
	lock_file => "$file.lock",
	content => undef,
	last_modified => undef,
	ttl => $options{ttl},
    }, $class;
}

sub content ( $ ) {
    my $self = shift;
    return $self->{content};
}

sub last_modified ( $ ) {
    my $self = shift;
    return $self->{last_modified};
}

sub __expired ( $$ )  {
    my $self = shift;
    my $ttl = shift;

    my $last_modified = $self->{last_modified};
    defined $last_modified or return 1;

    my $ttl = $self->{ttl};
    defined $ttl or return 1;

    return $last_modified + $ttl < time;
}

sub __lock ( $ ) {
    my $self = shift;

    my $lock_file = $self->{lock_file};
    open my $lock_handle, '>>', $lock_file or
	die "Couldn't open $lock_file: $!";
    flock $lock_handle, LOCK_EX or die "Couldn't lock a file: $!";
    return $lock_handle;
}

sub __stat ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my $stat = stat $handle or die "Couldn't stat a file: $!";
    $self->{last_modified} = $stat->mtime;
}

sub __open_to_read ( $ ) {
    my $self = shift;

    my $file = $self->{file};
    my $handle;
    unless (open $handle, '<', $file) {
	$!{ENOENT} or die "Couldn't open $file: $!";
	return undef;
    }
    return $handle;
}

sub __read ( $$ ) {
    my $self = shift;
    my $handle = shift;

    $handle or return;
    my $content = retrieve_fd $handle or
	die "Couldn't retrieve content from a file: $!";
    $self->{content} = $content;
}

sub __open_to_write ( $ ) {
    my $self = shift;

    my $part_file = $self->{part_file};
    open my $handle, '>', $part_file or die "Couldn't open $part_file: $!";
    return $handle;
}

sub __write ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my $content = $self->{content};
    store_fd $content, $handle or die "Couldn't store content to a file: $!";
    $handle->flush or die "Couldn't flush a file: $!";

    my $part_file = $self->{part_file};
    my $file = $self->{file};
    rename $part_file, $file or die "Couldn't rename $file to $part_file: $!";
}

sub __update ( $ ) {
    my $self = shift;

    my $updater = $self->{updater};
    $self->{content} = &$updater($self->{content});
}

sub fetch ( $ ) {
    my $self = shift;

    # Try to read cache without lock
    my $handle = $self->__open_to_read;
    if ($handle) {
	$self->__stat($handle);
	unless ($self->__expired) {
	    $self->__read($handle);
	    return;
	}
	undef $handle;
    }

    # Force to read cache with lock
    my $lock_handle = $self->__lock;
    my $handle = $self->__open_to_read;
    if ($handle) {
	$self->__stat($handle);
	unless ($self->__expired) {
	    undef $lock_handle;
	    $self->__read($handle);
	    return;
	}
	undef $handle;
	$self->__read($handle);
    }

    # Update
    $self->__update;

    # Write cache
    my $handle = $self->__open_to_write;
    $self->__write($handle);
    undef $lock_handle;
    $self->__stat($handle);

    return;
}

sub update ( $ ) {
    my $self = shift;

    my $lock_handle = $self->__lock;
    my $handle = $self->__open_to_read;
    if ($handle) {
	$self->__read($handle);
	undef $handle;
    }
    $self->__update;
    $self->__write($self->__open_to_write);
}

1;
