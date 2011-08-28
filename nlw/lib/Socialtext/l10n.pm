package Socialtext::l10n;
# @COPYRIGHT@
use 5.12.0;
use warnings;
use Scalar::Defer qw(defer force);
use base 'Exporter';
use Scalar::Util 'blessed';
use Socialtext::AppConfig;
our @EXPORT = qw(__ loc lcmp lsort lsort_by);
our @EXPORT_OK = qw(loc_lang system_locale best_locale getSortKey);
our %EXPORT_TAGS = (all => [@EXPORT, @EXPORT_OK]);

use Socialtext::l10n::I18N::zz;
use Unicode::Collate ();

=head1 NAME

Socialtext::l10n - Provides localization functions

=head1 SYNOPSIS

    # Exports "__", "loc", "lcmp", "lsort" and "lsort_by"
    use Socialtext::l10n;

    my @foo = lsort("a", "B", "c");
    my @bar = lsort_by( name => ($obj1, $obj2, $obj3));

    # Exports "loc_lang", "system_locale", "best_locale" and "getSortKey" too
    use Socialtext::l10n ':all';

    my $deferred = __('wiki.welcome');   # deferred loc()
    loc_lang('fr');                      # set the locale
    loc_lang();                          # get the current locale
    is loc('wiki.welcome'), 'Bienvenue'; # find localized text
    is $deferred, 'Bienvenue';           # this also works

=head1 Methods

=head2 loc("example.string", $arg)

loc() will lookup the english string to find the localized string.  If
no localized string can be found, the english string will be used.

See Locale::Maketext::Simple for information on string formats.

=head2 __("example.string", $arg)

Creates a I<deferred> string. It's evaluated in the active locale whenever
its value is used.

=head2 loc_lang( [$locale] )

Set the locale.  If C<$locale> is missing, returns the previous value
passed to C<loc_lang>.

=head2 best_locale( [$hub] )

This function tries to find the "best" locale in the current context.  If a
hub is passed in then we try to find the current user's locale in the current
workspace.  We can't find that (or a hub isn't passed in) then we instead
return the system locale.

=head2 system_locale( )

Returns the current system wide locale code.

=head1 Unicode Collation

=head2 lsort(@list)

Sort a list of strings case-insensitively using Unicode collation algorithm,
with proper ordering for accented characters.

=head2 lsort_by($field => @list_of_hashes)

Sort a list of objects or hash references by a specific field, using Unicode collation algorithm.

=head2 lcmp($a, $b)

Like C<$a cmp $b>, except with Unicode collation order.

=head2 getSortKey($string)

Return the collation key for a given string.

=head1 Localization Files

The .po files are kept in F<share/l10n>.

=cut

my $share_dir = Socialtext::AppConfig->new->code_base();
my $l10n_dir = "$share_dir/l10n";
my $collator = Unicode::Collate->new;

sub lsort_by {
    my $field = shift;
    sort { $collator->cmp(
        ((blessed($a) and $a->can($field)) ? $a->$field : $a->{$field}),
        ((blessed($b) and $b->can($field)) ? $b->$field : $b->{$field})
    ) } @_
}

sub lsort {
    $collator->sort(@_);
}

sub lcmp {
    $collator->cmp(@_);
}

sub getSortKey {
    $collator->getSortKey(@_);
}

require Locale::Maketext::Simple;
Locale::Maketext::Simple->import (
    Path => $l10n_dir,
    Decode => 1,
    Export => "_loc",  # We have our own loc()
);


sub Scalar::Defer::Deferred::TO_JSON {
    force $_[0];
}

sub __ {
    my @args = @_;
    defer { loc(@args) };
}

sub loc {
    my $msg = shift;

    # Bracket Notation variables are either _digits or _*.
    my $var_rx = qr/_(?:\d+|\*)/;

    # A whitelist of legal Bracket Notation functions we accept.
    # Locale::Maktext will turn [foo,bar] into $lh->foo("bar"), so technically
    # just about anything is legal.  Rather than try to match all the
    # possibilities we'll just have an opt-in whitelist.  Spaces are not
    # allowed around commas in Bracket Notation.
    my $legal_funcs = "(?:" . join("|", (
        qr/quant,$var_rx,.*?/,
        qr/\*,$var_rx,.*?/,    # alias for quant
        qr/numf,$var_rx/,
        qr/\#,$var_rx/,        # alias for numf
        qr/sprintf,.*?/,
        qr/tense,$var_rx,.*?/,
    )) . ")";

    # A legal bracket, or at least the subset we accept, is either a plain
    # variable or a legal func as defined above.
    my $bracket_rx = qr/~*\[(?:$var_rx|$legal_funcs)\]/;

    # RT 26769: Automagically quote square braces.  We do this by splitting
    # the string on the bracket_rx above, which matches legal loc() variables.
    # The capturing parens in the split include the split-item in the list, so
    # we end up with a list of alternating items like this: non-bracket,
    # bracket, non-bracket, ...  Everything that doesn't match the bracket_rx
    # needs to have its square braces quoted.  Care is taken to not requote
    # already quoted braces.
    my $new_msg = "";
    my @parts = split /($bracket_rx)/, $msg; 
    for my $part (@parts) {
        if ( $part =~ /$bracket_rx/ ) {
            $new_msg .= $part;
        }
        else {
            # Quote square braces, but only if they are already not quoted
            # away.  The complication here w/ the tildes is to make sure we
            # have an odd number of tildes, otherwise we have to add an extra
            # one to ensure we're quoting.
            $part =~ s/(~*)(\[|\])/ 
                my $tildes = $1 || "";
                $tildes .= '~' unless length($tildes) % 2;
                $tildes . $2;
            /xeg;
            $new_msg .= $part;
        }
    }

    my $result = _loc( $new_msg, @_ );
    
    # Un-escape escaped %'s - Locale::Maketext::Simple should be doing this!
    $result =~ s/%%/%/g;
    return $result;
}

# Have to wrap this b/c we renamed the real loc() function to _loc()
sub loc_lang {
    state $current_lang;
    if (@_) {
        $current_lang = shift;
        return _loc_lang($current_lang);
    }
    else {
        return $current_lang || system_locale();
    }
}

sub best_locale {
    my $hub = shift || return system_locale();
    local $@;
    my $loc = eval {
        $hub->pluggable->plugin_object('locales')->get_user_prefs()->{locale};
    };
    warn $@ if $@;
    return $loc || system_locale();
}

sub system_locale {
    return Socialtext::AppConfig->instance->locale();
}

# Override AppConfig's loc(), b/c of a module cross-dependency
{
    no warnings 'redefine';
    *Socialtext::AppConfig::loc = \&loc;
}

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut

1;
