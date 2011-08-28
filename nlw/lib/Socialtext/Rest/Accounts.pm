package Socialtext::Rest::Accounts;
# @COPYRIGHT@
use Moose;
use Class::Field qw( const field );
use Socialtext::JSON;
use Socialtext::HTTP ':codes';
use Socialtext::Account;
use Socialtext::Exceptions;
use Socialtext::l10n;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Collection';

sub allowed_methods {'GET, POST'}

field errors        => [];

sub permission { +{ GET => undef } }

sub collection_name {
    'Accounts';
}

after '_initialize' => sub {
    my $self = shift;
    $self->{FilterParameters}{filter} = 'account_name';
};

# We provide our own get_resources, so we can do filtering in the database
around 'get_resource' => sub {
    my $orig = shift;
    my $self = shift;
    my $rest = shift;
    my $user = $rest->user();

    # If we're filtering, get that from the DB directly
    my $filter = $self->rest->query->param('filter');
    my $all    = $rest->query->param('all');

    if ($user->is_business_admin and $filter and $all) {
        my $offset = $self->rest->query->param('offset') || 0;
        my $limit = $self->rest->query->param('count') ||
                    $self->rest->query->param('limit') || 100;
        return [ 
            map { $_->hash_representation }
                Socialtext::Account->All(
                    name => $filter,
                    case_insensitive => 1,
                    offset => $offset,
                    limit => $limit,
                )->all()
        ];
    }

    # Not filtering, so use the regular stack.
    return $orig->($self, $rest);
};

sub _entities_for_query {
    my $self   = shift;
    my $rest   = $self->rest();
    my $user   = $rest->user();
    my $query  = $rest->query->param('q') || '';

    # $query eq 'all' is preserved for backwards compatibility.
    my $all = $rest->query->param('all') || $query eq 'all';

    if ($user->is_business_admin and $all) {
        return Socialtext::Account->All->all;
    }
    return $user->accounts;
}

sub _entity_hash {
    my $self    = shift;
    my $account = shift;

    return $account->hash_representation;
}

sub element_list_item {
    my $self = shift;
    my $hash = shift;

    return "<li>$hash->{account_name}</li>";
}

sub POST {
    my $self = shift;
    my $rest = shift;
    
    my $account_request_hash = decode_json( $rest->getContent() );
    my $new_account_name = $account_request_hash->{name};
    my $new_account_type = $account_request_hash->{type};

    unless ($self->user_can('is_business_admin')) {
        $rest->header(
                      -status => HTTP_401_Unauthorized,
                     );
        return '';
    }

    my $account = $self->_create_account($new_account_name, $new_account_type);
    if( $account ) {
        $rest->header(
                      -status => HTTP_201_Created,
                      -type   => 'application/json',
                      -Location => $self->full_url('/', $account->account_id),
                     );
        my $account_info_hash =
          {
           account_id => $account->account_id,
           name => $account->name,
          };
            
                                 
        return encode_json( $account_info_hash );
    } else {
        # hrmm, what to do here for errors, I'm going with FORBIDDEN for now
        $rest->header(
                      -status => HTTP_403_Forbidden,
                      -type   => 'text/plain',
                     );
        return join( "\n", @{$self->errors} );
    }
}

sub _create_account {
    my $self = shift;
    my $new_account_name = shift;
    my $new_account_type = shift;
    my $new_account;

    eval {
        $new_account = $self->hub->account_factory->create(
            name => $new_account_name,
            ($new_account_type ? (account_type => $new_account_type) : ()),
        );
    };

    if ( my $e
         = Exception::Class->caught('Socialtext::Exception::DataValidation') )
    {
        $self->add_error($_) for $e->messages;
        return;
    }
    return $new_account;
}

sub add_error {
    my $self = shift;
    my $error_message = shift;
    $error_message =~ s/</&lt;/g;
    push @{ $self->errors }, $error_message;
    return 0;
}

sub SORTS {
    return +{
        alpha => sub {
            lcmp($Socialtext::Rest::Collection::a->{account_name},
                 $Socialtext::Rest::Collection::b->{account_name});
        },
        newest => sub {
            $Socialtext::Rest::Collection::b->{modified_time} <=>
                $Socialtext::Rest::Collection::a->{modified_time};
        },
    };
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
