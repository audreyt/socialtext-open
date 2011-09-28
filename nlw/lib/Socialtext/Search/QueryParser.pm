package Socialtext::Search::QueryParser;
# @COPYRIGHT@
use Moose;
use Socialtext::People::Fields;
use namespace::clean -except => 'meta';
use Socialtext::String qw(title_to_id);

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

sub _build_annotation {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    my $namespace = 'socialtext';
    if ($key =~ /(.+(?<!\\)):(.+)/) {
        $namespace = $1;
        $key = $2;
    }
    $key = title_to_id($key);
    $namespace = title_to_id($namespace);
    $value =~ s/\]/\\]/g;
    return qq!annotation:["$namespace","$key","$value"]!;
}

# Raw text manipulations like this are not 100% safe to do, but should be okay
# considering their esoteric nature (i.e. dealing w/ fields).
sub munge_raw_query_string {
    my ( $self, $query, $account_ids, %opts) = @_;

    # Establish some field synonyms.
    $query =~ s/(?:\s+|^)=(\S+)/ title:$1/g;        # Old style title search
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

    my @parts = split(/(?<!\\)"/, $query);

    my $h = 0;
    while ($h < scalar(@parts)) {
        if ($h % 2 == 1) {
            $parts[$h] =~ s/=/\\=/g;
        }
        $h++;
    }
    
    my $i = 0;
    my $nq = '';
    while ($i < scalar(@parts)) {
        if ($i % 2 == 1) {
            ++$i;
            next;
        }

        if ($parts[$i] eq '') {
            $nq = '"' . $parts[1] . '"'
                if ($i==0 and (2 == scalar(@parts) or $parts[2] !~ /^=/));
            $i++;
            next;
        }

        my $had_equal = 0;
        while ($parts[$i] =~ /(?<!\\)=/) {
            $had_equal = 1;
            if ($parts[$i] =~ /(\S+)=\s+/) {
                my ($start, $end) = ($-[0], $+[0]);
                substr($parts[$i],$start, $end-$start, $1 . ' ');
            }
            elsif ($parts[$i] =~ /\s+=\s+/) {
                my ($start, $end) = ($-[0], $+[0]);
                substr($parts[$i], $start, $end-$start, ' ');
            }
            elsif ($parts[$i] =~ /(\S+)=(\S+)/) {
                my ($start, $end) = ($-[0], $+[0]);
                my $key = $1;
                my $value = $2;
                my $annotation = $self->_build_annotation($key, $value);
                substr($parts[$i], $start, $end-$start, $annotation);
            }
            elsif ($parts[$i] =~ /(\S+)=$/) {
                my ($start, $end) = ($-[0], $+[0]);
                my $key = $1;
                my $value = $parts[$i+1];
                my $annotation = $self->_build_annotation($key, $value);
                substr($parts[$i], $start, $end-$start, $annotation);
            }
            elsif ($parts[$i] =~ /^=(\S+)/) {
                my ($start, $end) = ($-[0], $+[0]);
                my $key = $parts[$i-1];
                my $value = $1;
                my $annotation = $self->_build_annotation($key, $value);
                substr($parts[$i], $start, $end-$start, $annotation);
            }
            elsif ($parts[$i] eq '=') {
                my $key = $parts[$i-1];
                my $value = $parts[$i+1];
                my $annotation = $self->_build_annotation($key, $value);
                $parts[$i] = $annotation;
            }
        }
        if ($parts[$i] =~ / title:$/
            or (!$had_equal and $i + 1 < scalar(@parts))) {
            if ($i + 2 < scalar(@parts)) {
                $parts[$i] .= '"' . $parts[ $i + 1 ] . '"'
                    if ($parts[ $i + 2 ] !~ /^=/);
            }
            else {
                $parts[$i] .= '"' . $parts[ $i + 1 ] . '"';
            }
        }
        $nq .= $parts[$i];
        ++$i;
    }
    $nq =~ s/\\=/=/g;
    $query = $nq;

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
