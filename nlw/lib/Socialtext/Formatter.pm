# @COPYRIGHT@
package Socialtext::Formatter;
use strict;
use warnings;

our $VERSION = '0.9';

use Class::Field qw'field const';
use Socialtext::Base;
@Socialtext::Formatter::ISA = ('Socialtext::Base');

use Socialtext::AppConfig;
use Socialtext::Statistics 'stat_call';
use Socialtext::l10n '__';

const class_id => 'formatter';
const class_title  => __('class.formatter');
const class_prefix => 'Socialtext::Formatter::';

const all_phrases => [
    qw(wafl_phrase asis wiki hyper im b_hyper mail
        b_mail file tt strong em del)
];
const all_blocks =>
    [qw(wafl_block hr hx wafl_p ul ol indent table p empty_p else)];

field page_id         => '';
field url_prefix      => '';

sub formatter_classes {
    qw(
        WaflBlock WaflPhrase
        Line Heading Paragraph EmptyParagraph WaflParagraph
        Table TableRow TableCell Ulist Olist Item Indent
        Teletype Strong Emphasize Underline Delete
        HyperLink IMLink BracketHyperLink MailLink BracketMailLink
        FileLink FreeLink Asis
    );
}

sub wafl_classes {
    my $self = shift;
    qw(
        Preformatted Html Selenium PageInclusion
    ),
    $self->hub->current_workspace->enable_spreadsheet
      ? (qw(SpreadsheetInclusion)) : (),
    qw(
        Image Video File HtmlPage CSS InterWikiLink TradeMark
        WeblogLink BlogLink CategoryLink TagLink TeleType Toc
        Awesome
    );
}

sub table {
    my $self = shift;
    $self->{table} ||= $self->create_table;
}

sub wafl_table {
    my $self = shift;
    $self->{wafl_table} ||= $self->create_wafl_table;
}

sub create_table {
    my $self = shift;
    my @formatter_classes = @_;
    @formatter_classes = $self->formatter_classes unless @_;

    my $class_prefix = $self->class_prefix;

    my %table = map {
        my $class = /::/ ? $_ : "$class_prefix$_";
        $class->can('formatter_id') ? ( $class->formatter_id, $class ) : ();
    } @formatter_classes;

    \%table;
}

sub create_wafl_table {
    my $self = shift;
    my @wafl_classes = @_;
    @wafl_classes = $self->wafl_classes unless @_;

    my $class_prefix = $self->class_prefix;

    my %table;

    foreach my $class (@wafl_classes) {
        my $wafl_class = $class =~ /::/
            ? $class
            : "$class_prefix$class";
        next unless $wafl_class->can('wafl_id');
        $table{$wafl_class->wafl_id} = $wafl_class;
    }

    $self->_add_external_wafl( \%table );

    \%table;
}

# XXX better on Unit?
# http://www.w3.org/TR/html401/types.html#type-name
#  ID and NAME tokens must begin with a letter ([A-Za-z]) and may be followed
#  by any number of letters, digits ([0-9]), hyphens ("-"), underscores ("_"),
#  colons (":"), and periods (".").
sub legalize_sgml_id {
    my $id = shift;

    $id =~ s/[^\w:.-]+/_/g;
    $id =~ s/^_*//;

    return $id;
}

sub _add_external_wafl {
    my $self = shift;
    return unless $self->hub->registry_loaded;
    my $table = shift;
    my $map   = $self->hub->registry->lookup->wafl;

    for my $wafl_id ( keys %$map ) {
        $table->{$wafl_id} = $map->{$wafl_id}->[1];
    }
}

1;

__END__

=head1 NAME

Socialtext::Formatter - The NLW Formatter 

=head1 SYNOPSIS

    # parse some text and turn it into html
    my $parser = Socialtext::Formatter::Parser->new(
        table = $hub->formatter->table,
        wafl_table = $hub->formatter->wafl_table,
    );
    my $units = $parser->text_to_parsed('Some text to parse');
    my $html = $units->to_html

    # let the viewer handle everything
    my $other_html = $hub->viewer->text_to_html('Some text to parse');

=head1 DESCRIPTION

The NLW Formatter contains information about what L<Socialtext::Formatter::Unit>
classes are to be used to parse and format some text.

=head1 METHODS

=over 4

=item table

Returns a reference to a hash representing the default collection of
Unit classes that can be used to parse a string. The key is the formatter
id, the value is the class name of the Unit that parses that formatter id.

=item wafl_table

Returns a reference to a hash representing the current collection of Wafl
Blocks and Phrases that can be parsed in the same structure as table.

=item create_table(@classes)

Given a list of Unit subclasses, create a hash in the same form as table,
suitable for constructing an L<Socialtext::Formatter::Parser>.

=item create_wafl_table(@classes)

Given a list of Wafl subclasses, create a hash in the same form as wafl_table,
suitable for constructing an L<Socialtext::Formatter::Parser>.

=item legalize_sgml_id

Utility class method that turns a string into a valid SGML identifier.
This is useful for creating attributes in html.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
