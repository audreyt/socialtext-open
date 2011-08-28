# @COPYRIGHT@
package Socialtext::Search::ContentTypes;

use strict;
use warnings;

use base qw( Socialtext::Base );
use Readonly;

Readonly our $PAGE_TYPE       => 'p_a_g_e';
Readonly our $ATTACHMENT_TYPE => 'a_t_t_a_c_h_m_e_n_t';

Readonly our @ALL_TYPES => ( $PAGE_TYPE, $ATTACHMENT_TYPE );

Readonly our %TYPES_BY_CLASSREF => (
    'Socialtext::Page'       => $PAGE_TYPE,
    'Socialtext::Attachment' => $ATTACHMENT_TYPE
);

Readonly our %TYPES_BY_NAME => (
    'page'       => $PAGE_TYPE,
    'attachment' => $ATTACHMENT_TYPE
);


sub lookup {
    my $class = shift;
    my $key = shift;

    return $TYPES_BY_CLASSREF{$key} || $TYPES_BY_NAME{$key} || undef;
}

sub get_types {
    return @ALL_TYPES;
}

__END__

=head1 NAME

Socialtext::Search::ContentTypes - Lookup class for different searchable
content types.

=head1 SYNOPSIS

my $type = Socialtext::Search::ContentTypes->lookup( ref $page );
$type = Socialtext::Search::ContentTypes->lookup( "page" );

my @types = Socialtext::Search::ContentTypes->get_types();

=head1 DESCRIPTION

Provides a single class method for looking up content types by various
known attributes.

This should make it easy to use consistent content type information in
indexing and querying.

=head1 TODO

Add appropriate lookup keys for users and tags when we enable searches for 
them.

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


1;
