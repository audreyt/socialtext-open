package Socialtext::Page::Legacy;
# @COPYRIGHT@
use 5.12.0;
use warnings;
use Socialtext::Encode;
use base 'Exporter';

our @EXPORT_OK = qw(parse_page_headers read_and_decode_page);
our @EXPORT = @EXPORT_OK;

sub parse_page_headers {
    my $head_ref = ref($_[0]) ? $_[0] : \$_[0];

    my %meta;
    for (split "\n", $$head_ref) {
        next unless /^(\w\S*):\s*(.*)$/;
        my ($attr, $value) = ($1, $2);
        if (defined $meta{$attr}) {
            $meta{$attr} = [$meta{$attr}] unless ref $meta{$attr};
            push @{$meta{$attr}}, $value;
        }
        else {
            $meta{$attr} = $value;
        }
    }

    # Putting whacky whitespace in a page title can kill javascript on the
    # front-end. This fixes {bz: 3475}.
    $meta{Subject} =~ s/\s/ /g if $meta{Subject};

    return \%meta;
}

sub read_and_decode_page {
    my ($filename, $want_content) = @_;

    die "No such file $filename" unless -f $filename;
    die "File path contains '..', which is not allowed."
        if $filename =~ /\.\./;

    # Note: avoid using '<:raw' here, it sucks for performance
    # will Encode byte to char later.
    open(my $fh, '<:mmap', $filename)
        or die "Can't open $filename: $!";

    my $buffer;
    if ($want_content) {
        do { local $/="\n\n"; <$fh> }; # throw away header for speed
        $buffer = do { local $/; <$fh> };
    }
    else {
        $buffer = do { local $/="\n\n"; <$fh> };
    }

    $buffer //= '';
    $buffer = Socialtext::Encode::guess_decode($buffer);
    $buffer =~ s/\015\012/\n/g;
    $buffer =~ s/\015/\n/g;
    return \$buffer;
}

1;

__END__

=head1 NAME

Socialtext::Page::Legacy - Code used for the old filesystem based page store.

=head1 SYNOPSIS

  Try not to use this.

=head1 DESCRIPTION

Old codes only used for importing old filesystem page store.

=cut
