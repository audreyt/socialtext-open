package Socialtext::Search::QueryParser;
# @COPYRIGHT@
use Moose;
use Socialtext::People::Fields;
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Search::QueryParser

=head1 SYNOPSIS

  my $qp = Socialtext::Search::QueryParser->new;
  my $query = $qp->parse($query_string);

=head1 DESCRIPTION

Base class for parsing search queries.

=cut

has 'searchable_fields' => (is => 'ro', isa => 'ArrayRef[Str]', lazy_build => 1);
has 'field_map' => (is => 'ro', isa => 'HashRef[Str]', lazy_build => 1);

sub parse {
    my $self = shift;
    my $query_string = shift;

    # Fix the raw query string.  Mostly manipulating "field:"-like strings.
    my @tokens = split(/\b((?:category|tag(?:_exact)?):\s*"[^"]+")/i, $query_string);
    $query_string = '';
    for my $token ( @tokens ) {
        # {bz: 4545}: Don't munge within quoted tag/tag_exact field values. 
        if ($token =~ /^(category|tag(?:_exact)?):\s*("[^"]+")$/i) {
            my ($field, $value) = (lc $1, $2);
            $field = 'tag' if $field eq 'category';
            $query_string .= "$field:$value";
            next;
        }
        $query_string .= $self->munge_raw_query_string($token, @_);
    }

    return $query_string;
}

# Raw text manipulations like this are not 100% safe to do, but should be okay
# considering their esoteric nature (i.e. dealing w/ fields).
sub munge_raw_query_string {
    my ( $self, $query, $account_ids, %opts) = @_;

    # Establish some field synonyms.
    $query =~ s/=/title:/g;        # Old style title search
    $query =~ s/category:/tag:/gi; # Old name for tags
    $query =~ s/tag:\s*/tag:/gi;   # fix capitalization and allow an extra space
    $query =~ s/(?:\s|^)#(\p{IsWord}+)/tag:$1/g; # Allow hashtag searches
    $query =~ s!/day!/DAY!;

    my $field_map = $self->field_map;
    if ($opts{doctype} and $opts{doctype} eq 'group') {
        $field_map->{name} = 'title';
        $field_map->{description} = $field_map->{desc} = 'body';
    }

    # Find everything that looks like a field, but is not.  I.e. in "cow:foo"
    # we would find "cow:". 
    my $searchable_fields;
    my @non_fields;
    while ($query =~ /([a-zA-Z_]+):/g ) {
        my ($f_start, $f_length) = ($-[1], $+[1] - $-[1]);
        my $maybe_field = $1;
        $searchable_fields ||= { map { $_ => 1 } @{ $self->searchable_fields } };
        # position -> position_pf_s
        # myers_briggs -> myers_briggs_pf_s

        if ($searchable_fields->{$maybe_field}) {
            if (my $solr_field = $field_map->{$maybe_field}) {
                substr($query, $f_start, $f_length) = $solr_field;
            }
        }
        elsif ($maybe_field =~ m/_pfh?_[a-z]$/) { # e.g. _pf_i _pfh_i
            # Leave it alone, they probably know what they are doing
        }
        else {
            # Last chance, check for profile fields
            if ($account_ids and @$account_ids) {
                my $f = Socialtext::People::Fields->GetField(
                    name => $maybe_field,
                    account_id => $account_ids,
                );
                if ($f) {
                    my $show_it = 1;
                    if ($f->is_hidden) {
                        $show_it = 0 unless $opts{show_hidden};
                    }
                    if ($show_it) {
                        # We found a profile field, so use it's solr name instead
                        substr($query, $f_start, $f_length) = $f->solr_field_name;
                        # Remember this field so we don't subsequently substitute it.
                        $searchable_fields->{$f->solr_field_name} = 1;
                        next;
                    }
                }
            }
            push @non_fields, $maybe_field;
        }
    }

    # If it looks like a field but is not then remove the ":".  This prevents
    # things being treated as fields when they are not fields.
    for my $non_field (@non_fields) {
        $non_field = quotemeta $non_field;
        $query =~ s/(${non_field}):/$1 /g;
    }

    return $query;
}

sub _build_field_map { {} }

__PACKAGE__->meta->make_immutable;
1;
