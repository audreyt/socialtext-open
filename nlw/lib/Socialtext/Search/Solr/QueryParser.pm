# @COPYRIGHT@
package Socialtext::Search::Solr::QueryParser;
use Moose;

=head1 NAME

Socialtext::Search::Solr::QueryParser

=head1 SYNOPSIS

  my $qp = Socialtext::Search::QueryParser->new;
  my $query = $qp->parse($query_string);

=head1 DESCRIPTION

Pre-parse Solr specific query options.

=cut

extends 'Socialtext::Search::QueryParser';

sub _build_field_map {
    my $self = shift;
    return {
        name           => 'name_pf_t',
        first_name     => 'first_name_pf_s',
        given_name     => 'first_name_pf_s',
        middle_name    => 'middle_name_pf_s',
        last_name      => 'last_name_pf_s',
        family_name    => 'last_name_pf_s',
        preferred_name => 'preferred_name_pf_t',
        email          => 'email_address_pf_s',
        email_address  => 'email_address_pf_s',
        url            => 'personal_url_pf_h',
        facebook       => 'facebook_url_pf_h',
        linkedin       => 'linkedin_url_pf_h',
        (
            map { $_ => $_ . "_sn_pf_s" }
                qw/aol yahoo gtalk skype twitter sametime/
        ),
        manager       => 'supervisor_pf_rt',
        manager_id    => 'supervisor_pf_i',
        supervisor_id => 'supervisor_pf_i',
        assistant_id  => 'assistant_pf_i',
        anno          => 'annotation',
    };
}

sub _build_searchable_fields {
    my $self = shift;
    [
        # General fields - multi-type
        qw/tag body w doctype id creator creator_name tag date created filename filename_ext/,
        # Page / attachment fields:
        qw/title editor pagetype/,
        # Signal fields:
        qw/pvt dm_recip a g reply_to mention
           link_page_key link_w link is_question
           annotation/,
        # People fields: (keys AND values)
        %{ $self->field_map },
        qw/phone tag_exact tag_count sounds_like/,
        # Group fields
        qw/name description desc/,
    ]
}

around 'parse' => sub {
    my $orig = shift;

    my $query = $orig->(@_);
    if ($query =~ m/annotation:\[([^\]]+)\]/) {
        my ($start, $end) = ($-[0], $+[0]);
        my @args = map { s/^"(.+)"$/$1/; $_ } split ',', $1;
        my $new_query = "annotation:" . lc join('|', @args);
        $new_query .= "|*" if @args < 3;
        substr($query, $start, $end) = $new_query;
    }

    return $query;
};

1;
