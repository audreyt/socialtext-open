package Test::Socialtext::Rest;
# @COPYRIGHT@
use strict;
use warnings;

use base 'Socialtext::Rest::Entity';
use Socialtext::AppConfig;
use Socialtext::System qw(backtick);
use Socialtext::File qw(get_contents_utf8 get_contents_binary);

(my $nlw = Socialtext::AppConfig->code_base) =~ s{/[^/]+$}{};
my $files = "$nlw/t/rest_files";

sub GET {
    my $self = shift;
    my $name = $self->name;
    my $file = "$files/$name";

    my $base_type = 'text/plain';
    if (my $new_ct = $self->rest->query->param('force-ct')) {
        warn "forcing content-type to $new_ct";
        $base_type = $new_ct;
    }
    my $charset = 'UTF-8';
    if (my $new_charset = $self->rest->query->param('force-charset')) {
        warn "forcing charset to $new_charset";
        $charset = $new_charset;
    }

    $self->rest->header('-type', "$base_type; charset=$charset");

    die "$name doesn't exist!\n" unless -f $file;
    return backtick($file) if -x $file;
    if ($charset eq 'UTF-8') {
        return get_contents_utf8($file);
    }
    else {
        return get_contents_binary($file);
    }
}

1;

__END__

=head1 NAME

Test::Socialtext::Rest - An extension to the rest API for tests

=head1 SYNOPSIS

    GET /data/test/:file_or_script

=head1 DESCRIPTION

This module provides a method for testing HTTP and HTTPS connections. When
perform a GET on /data/test/filename, the contents of t/rest_files/filename
are returned. However, if file is executable, the data printed to STDOUT is
returned rather than the contents of the file.

If the parameter C<force-charset> is passed in, the response will have that
charset added to the Content-Type header.  The default is UTF-8.  Use "none"
to avoid adding a charset qualifier.

=cut
