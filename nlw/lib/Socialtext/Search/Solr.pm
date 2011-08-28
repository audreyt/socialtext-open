package Socialtext::Search::Solr;
# @COPYRIGHT@
use Moose;
use WebService::Solr 0.11;
BEGIN {
    if (WebService::Solr->VERSION > 0.12) {
        die << '.';
Sorry, we currently only support WebService::Solr 0.11 or 0.12.

Please downgrade by installing this:

    http://search.cpan.org/CPAN/authors/id/B/BR/BRICAS/WebService-Solr-0.12.tar.gz

Thank you!
.
    }
}
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Search::Solr

=head1 SYNOPSIS

  Do not use directly, this is a base class.

=head1 DESCRIPTION

Base class for other Solr classes.

=cut

has 'ws_name' => (is => 'ro', isa => 'Str');
has 'workspace' => (is => 'ro', isa => 'Object', lazy_build => 1);
has 'hub'       => (is => 'ro', isa => 'Object',           lazy_build => 1);
has 'solr'      => (is => 'ro', isa => 'WebService::Solr', lazy_build => 1);

sub _build_workspace {
    my $self = shift;
    my $ws_name = $self->ws_name;
    my $ws = Socialtext::Workspace->new( name => $ws_name );
    die "Cannot create workspace '$ws_name'" unless defined $ws;
    return $ws;
}

sub _build_hub {
    my $self = shift;
    my $ws_name = $self->ws_name;

    my $hub = Socialtext::Hub->new(
        current_workspace => $self->workspace,
        current_user => Socialtext::User->SystemUser,
    );
    $hub->registry->load;

    return $hub;
}

sub _build_solr {
    my $self = shift;
    my $solr = WebService::Solr->new(
        Socialtext::AppConfig->solr_base,
        { autocommit => 0 },
    );
    $solr->agent->timeout(90);
    return $solr;
}

{
    # Avoids having to copy large bodies as much as possible.  Uses CDATA for
    # the tag content which in the best case means zero regex modification.
    package Socialtext::Search::Solr::BigField;
    use Moose;
    extends 'WebService::Solr::Field';
    has '+value' => ('isa' => 'ScalarRef');
    has '+boost' => ('isa' => 'Undef');
    sub to_xml {
        my $self = shift;
        my $gen = XML::Generator->new(':std', escape => 'always,even-entities');
        return $gen->field( { name => $self->name }, ${$self->value} );
    }
    no Moose;
    __PACKAGE__->meta->make_immutable();
}

__PACKAGE__->meta->make_immutable;
1;
