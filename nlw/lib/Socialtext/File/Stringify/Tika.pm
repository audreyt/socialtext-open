package Socialtext::File::Stringify::Tika;
# @COPYRIGHT@
use Moose;
use Socialtext::System;
use Socialtext::File::Stringify::Default;
use Socialtext::Log qw/st_log/;
use namespace::clean -except => 'meta';

sub to_string {
    my ( $class, $buf_ref, $file, $mime ) = @_;
    Socialtext::System::backtick('st-tika',
        { stdin => $file, stdout => $buf_ref });
    if (my $e = $@) {
        st_log->error(qq{st-tika failed on "$file": $e});
        Socialtext::File::Stringify::Default->to_string($buf_ref, $file, $mime);
    }
    elsif ($$buf_ref =~ /^\s*$/) {
        st_log->warning(qq{No text found in file "$file"\n});
        $$buf_ref = '';
    }
    else {
        # We know Tika outputs UTF-8 so it's safe to just turn the flag on.
        # Avoids a copy during utf8_decode() higher-up the stringifier stack.
        Encode::_utf8_on($$buf_ref);
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Socialtext::File::Stringify::Tika - Tika stringification engine

=head1 SYNOPSIS

  use Socialtext::File::Stringify;
  ...
  $text = Socialtext::File::Stringify->to_string($filename);

=head1 DESCRIPTION

Stringification engine for MS Office documents, using "Tika".  Compatible with
Office 2007.

=cut
