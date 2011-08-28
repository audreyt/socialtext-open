package Socialtext::Rest::Users;
# @COPYRIGHT@
use Moose;
use Socialtext::JSON;
use Socialtext::HTTP ':codes';
use Socialtext::User;
use Socialtext::Exceptions;
use Socialtext::User::Find;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';
with 'Socialtext::Rest::Pageable';

sub allowed_methods {'GET, POST'}

sub if_authorized {
    my $self = shift;
    my $method = shift;
    my $call = shift;

    if ($method eq 'POST') {
        return $self->not_authorized
            unless ($self->user_can('is_business_admin'));
    }
    elsif ($method eq 'GET') {
        return $self->not_authorized
            if ($self->rest->user->is_guest);
    }
    else {
        return $self->bad_method;
    }

    return $self->$call(@_);
}

sub POST_json {
    my $self = shift;
    return $self->if_authorized('POST', '_POST_json', @_);
}

sub _POST_json {
    my $self = shift;
    my $rest = shift;

    my $create_request_hash = decode_json($rest->getContent());

    unless ($create_request_hash->{username} and
            $create_request_hash->{email_address}) 
    {
        Socialtext::Exception->throw(
            error => "username, email_address required",
            http_status => HTTP_400_Bad_Request,
        );
    }
    
    my ($new_user) = eval {
        Socialtext::User->create(
            %{$create_request_hash},
            creator => $self->rest->user()
        );
    };

    if (my $e = Exception::Class->caught('Socialtext::Exception::DataValidation')) {
        $rest->header(
            -status => HTTP_400_Bad_Request,
            -type   => 'text/plain'
        );
        return join("\n", $e->messages);
    }
    elsif ($@) {
        Socialtext::Exception->throw(
            error => "Unable to create user: $@",
            http_status => HTTP_400_Bad_Request,
        );
    }

    $rest->header(
        -status   => HTTP_201_Created,
        -type     => 'application/json',
        -Location => $self->full_url('/', $new_user->username()),
    );
    return '';
}

has 'user_find' => (
    is => 'ro', isa => 'Socialtext::User::Find',
    lazy_build => 1,
);

sub _build_user_find {
    my $self = shift;
    my $filter = $self->rest->query->param('filter');
    my $query = $self->rest->query;

    my $show_pvt = $query->param('want_private_fields')
        && $self->rest->user->is_business_admin;
       
    # Instantiate the User Finder
    my $user_find;
    eval {
        $user_find = Socialtext::User::Find->new(
            viewer => $self->rest->user,
            limit  => $self->items_per_page,
            offset => $self->start_index,
            filter => $filter,
            order  => $query->param('order') || '',
            all    => $query->param('all') || 0,
            show_pvt => $show_pvt,
        );
    };
    if ($@) {
        warn $@;
        Socialtext::Exception->throw(
            error => "Bad request or illegal filter options",
            http_status => HTTP_400_Bad_Request,
        );
    }
    return $user_find;
}

sub _get_total_results {
    my $self = shift;

    my $count = eval { $self->user_find->get_count() };
    if ($@) {
        warn $@;
        Socialtext::Exception->throw(
            error => "Query error",
            http_status => HTTP_400_Bad_Request,
        );
    }
    return $count;
}

sub _get_entities {
    my $self = shift;
    my $rest = shift;

    my $results = eval { $self->user_find->typeahead_find };
    if ($@) {
        warn $@;
        Socialtext::Exception->throw(
            error => "Illegal filter or query error",
            http_status => HTTP_400_Bad_Request,
        );
    }

    return $results || [];
}

sub _entity_hash { return $_[1] }

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
