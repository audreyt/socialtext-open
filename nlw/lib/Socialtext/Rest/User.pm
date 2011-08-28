package Socialtext::Rest::User;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::Rest::Entity';
use Socialtext::Functional 'hgrep';
use Socialtext::User;
use Socialtext::HTTP ':codes';
use Socialtext::SQL 'sql_txn';
use Socialtext::JSON qw/decode_json/;

our $k;

# We punt to the permission handling stuff below.
sub permission { +{ GET => undef, PUT => undef } }
sub entity_name { "User " . $_[0]->username }
sub accounts { undef };

sub attribute_table_row {
    my ($self, $name, $value) = @_;
    return '' if $name eq 'accounts';
    return '' if $name eq 'groups';
    return $self->SUPER::attribute_table_row($name, $value);
}

sub get_resource {
    my ( $self, $rest ) = @_;

    my $query = $rest->query;
    my $acting_user = $rest->user;
    my $user = Socialtext::User->new( username => $self->username );

    # REVIEW: A permissions issue at this stage will result in a 404
    # which might not be the desired result. In a way it's kind of good,
    # in an information hiding sort of way, but....
    return undef unless $user;

    my $all = $query->param('all');
    my $badmin = $acting_user->is_business_admin;
    return undef if $all and !$badmin;

    my $show_pvt = $query->param('want_private_fields') && $badmin ? 1 : 0;
    my $repr = {};
    if ($all) {
        return +{
            ( hgrep { $k ne 'password' }
                %{ $user->to_hash(want_private_fields => $show_pvt) } ),
            accounts => [
                map { $_->hash_representation(user_count=>1) }
                $user->accounts
            ],
            groups => [
                map { $_->to_hash(plugins=>1, show_account_ids=>1,
                                  show_admins => 1)
                    } $user->groups->all
            ],
        };
    }
    elsif (my @shared_accts = $user->shared_accounts($acting_user)) {
        my $minimal  = $query->param('minimal');
        my $user_hash;
        if ($minimal) {
            $user_hash = $user->to_hash(minimal => 1);
            $user_hash->{primary_account_id} = $user->primary_account_id;
            $user_hash->{is_business_admin} = $user->is_business_admin;
        }
        else {
            $user_hash = {
                ( hgrep { $k ne 'password' }
                %{ $user->to_hash(want_private_fields => $show_pvt) } ),
            };
        }
        return +{
            %$user_hash,
            accounts => [
                map { $_->hash_representation(
                        user_count=>1,
                        minimal => $minimal,
                    ) }
                @shared_accts
            ],
            groups => [
                map { $_->to_hash(
                        $minimal 
                            ? ( minimal => 1 )
                            : ( plugins => 1,
                                show_account_ids => 1,
                                show_admins => 1,
                            )
                        )
                    } $user->shared_groups($acting_user, 1, 'ignore badmin')
            ],
        };
    }

    return undef;
}

sub PUT_json {
    my $self = shift;
    my $rest = shift;
    my $username = $self->username;
    return $self->not_authorized unless $rest->user->is_business_admin;

    my $user = eval { Socialtext::User->Resolve($username) };
    unless ($user) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'No such user';
    }

    my $content = $rest->getContent();
    my $object = eval { decode_json( $content ) };
    if (!$object or ref($object) ne 'HASH') {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'Content should be a JSON hash.';
    }

    my @todo; # figure out what to do, we'll do it in a txn below.
    if ($object->{private_external_id}) {
        return $self->not_authorized unless $rest->user->is_business_admin;
        my $external_id = $object->{private_external_id};
        push @todo, sub {
            $user->update_store(private_external_id => $external_id) };
    }

    if ($object->{primary_account_id}) {
        my $new_acct_id = $object->{primary_account_id};
        my $acct = Socialtext::Account->new(account_id => $new_acct_id);
        unless ($acct) {
            $rest->header( -status => HTTP_400_Bad_Request );
            return 'Invalid account ID';
        }

        push @todo, sub { $user->primary_account($acct) };
    }

    if (!@todo) {
        $rest->header(-status => HTTP_400_Bad_Request);
        return "Nothing to Update";
    }


    eval {
        sql_txn { $_->() for @todo; };
    };
    if (my $e = $@) {
        $rest->header( -status => HTTP_400_Bad_Request );
        return $e;
    }

    $rest->header(
        -status => HTTP_204_No_Content,
        -Location => "/data/users/" . $user->user_id,
    );
    return '';
}


1;
