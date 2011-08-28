package Socialtext::WikiText::Emitter::Messages::Text;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Socialtext::WikiText::Emitter::Messages::Solr';
use Readonly;

Readonly my %markup => (
    asis => [ '', '' ],
    b    => [ '',  '' ],
    i    => [ '',  '' ],
    del  => [ '',  '' ],
    hyperlink => [ '"',  '"' ],
    hashmark  => ['#',''],
    video     => [ '',  '' ],
);

sub msg_markup_table { return \%markup }

sub msg_format_link {
    my $self = shift;
    my $ast  = shift;
    my $text = $ast->{text} || $ast->{wafl_string};
    return qq{"$text"};
}

1;

=head1 NAME

Socialtext::WikiText::Emitter::Messages::Text - Emit text

=head1 SYNOPSIS

  use Socialtext::WikiText::Parser::Messages;
  use Socialtext::WikiText::Emitter::Messages::Text;

  my $parser = Socialtext::WikiText::Parser::Messages->new(
      receiver => Socialtext::WikiText::Emitter::Messages::Text->new(
          callbacks => {
              viewer => $signal->recipient,
          },
      )
  );
  my $plain_text = $parser->parse($signal->body);

=head1 DESCRIPTION

Emit plain text messages, suitable for rendering Signals to a speakable form.

=cut
