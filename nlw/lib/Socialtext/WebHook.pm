# @COPYRIGHT@
package Socialtext::WebHook;
use Moose;
use Socialtext::Workspace;
use Socialtext::SQL qw/sql_execute sql_singlevalue/;
use Socialtext::SQL::Builder qw/sql_nextval/;
use Carp qw/croak/;
use Socialtext::Workspace;
use Socialtext::Account;
use Socialtext::Group;
use Socialtext::User;
use Socialtext::Page;
use Socialtext::JSON qw/decode_json encode_json/;
use Socialtext::Log qw/st_log/;
use Socialtext::Timer qw/time_scope/;
use List::MoreUtils qw/any/;
use namespace::clean -except => 'meta';

has 'id'           => (is => 'ro', isa => 'Int', required => 1);
has 'creator_id'   => (is => 'ro', isa => 'Int', required => 1);
has 'class'        => (is => 'ro', isa => 'Str', required => 1);
has 'account_id'   => (is => 'ro', isa => 'Int');
has 'group_id'     => (is => 'ro', isa => 'Int');
has 'workspace_id' => (is => 'ro', isa => 'Int');
has 'details_blob' => (is => 'ro', isa => 'Str', default => '{}');
has 'url'          => (is => 'ro', isa => 'Str', required => 1);
has 'workspace' => (is => 'ro', isa => 'Maybe[Object]',  lazy_build => 1);
has 'account'   => (is => 'ro', isa => 'Maybe[Object]',  lazy_build => 1);
has 'group'     => (is => 'ro', isa => 'Maybe[Object]',  lazy_build => 1);
has 'creator'   => (is => 'ro', isa => 'Maybe[Object]',  lazy_build => 1);
has 'details'   => (is => 'ro', isa => 'HashRef', lazy_build => 1);

my %valid_classes = map { $_ => 1 } (
    (map { "page.$_" } qw/create delete update tag watch unwatch */),
    qw/signal.create/,
);

sub _build_workspace {
    my $self = shift;
    return undef unless $self->workspace_id;
    return Socialtext::Workspace->new(workspace_id => $self->workspace_id);
}

sub _build_account {
    my $self = shift;
    return undef unless $self->account_id;
    return Socialtext::Account->new(account_id => $self->account_id);
}

sub _build_group {
    my $self = shift;
    return undef unless $self->group_id;
    return Socialtext::Group->GetGroup(group_id => $self->group_id);
}

sub _build_creator   {
    my $self = shift;
    return Socialtext::User->new(user_id => $self->creator_id);
}

sub _build_details {
    my $self = shift;
    return decode_json( $self->details_blob );
}

sub to_hash {
    my $self = shift;
    return {
        map { $_ => $self->$_ }
          qw/id creator_id account_id group_id workspace_id class details url/
    };
}

sub delete {
    my $self = shift;
    st_log->info("DELETE,WEBHOOK,id:" . $self->id . ",class:" . $self->class);
    sql_execute(q{DELETE FROM webhook WHERE id = ?}, $self->id);
}

# Class Methods

sub ById {
    my $class = shift;
    my $id = shift or die "id is mandatory";

    my $sth = sql_execute(q{SELECT * FROM webhook WHERE id = ?}, $id);
    die "No webhook found with id '$id'" unless $sth->rows;

    my $rows = $sth->fetchall_arrayref({});
    return $class->_new_from_db($rows->[0]);
}

sub Find {
    my $class = shift;
    my %args  = @_;

    my (@bind, @where);
    for my $field (qw/class creator_id account_id workspace_id group_id/) {
        if (my $val = $args{$field}) {
            my $op = $val =~ m/%/ ? 'like' : '=';
            push @where, "$field $op ?";
            push @bind, $val;

            if ($field eq 'class' and $args{wildcard}) {
                $where[-1] = "($where[-1] OR class = ?)";
                push @bind, $args{wildcard};
            }
        }
    }

    my $where = join ' AND ', @where;
    die "Your Find was too loose." unless $where;
    my $sth = sql_execute( "SELECT * FROM webhook WHERE $where", @bind );
    return $class->_rows_from_db($sth);
}

sub Clear {
    sql_execute(q{DELETE FROM webhook});
}

sub All {
    my $class = shift;

    my $sth = sql_execute(q{SELECT * FROM webhook ORDER BY id});
    return $class->_rows_from_db($sth);
}

sub _rows_from_db {
    my $class = shift;
    my $sth   = shift;

    my $results = $sth->fetchall_arrayref({});
    return [ map { $class->_new_from_db($_) } @$results ];
}

sub _new_from_db {
    my $class = shift;
    my $hashref = shift;

    
    for (qw/account_id workspace_id group_id/) {
        delete $hashref->{$_} unless defined $hashref->{$_};
    }
    return $class->new($hashref);
}

sub ValidateWebHookClass {
    my $pkg_class = shift;
    my $class = shift;

    die "'$class' is not a valid webhook class.\n"
        unless $valid_classes{$class};
}

sub Create {
    my $class = shift;
    my %args  = @_;

    $class->ValidateWebHookClass($args{class});

    my $h = $class->new(
        %args,
        id => sql_nextval('webhook___webhook_id'),
    );
    sql_execute('INSERT INTO webhook VALUES (?,?,?,?,?,?,?,?)',
        $h->id,
        $h->creator_id,
        $h->class,
        ($h->account_id   ? $h->account_id   : undef ),
        ($h->workspace_id ? $h->workspace_id : undef ),
        $h->details_blob,
        $h->url,
        ($h->group_id     ? $h->group_id     : undef ),
    );

    st_log->info("CREATE,WEBHOOK,id:" . $h->id . ",class:" . $h->class);
    return $h;
}

sub Add_webhooks {
    my $class = shift;
    my %p = @_;
    $p{account_ids} ||= [];

    my $payload;
    eval {
        my $hooks = $class->Find( class => $p{class}, wildcard => $p{wildcard} );
        HOOK: for my $h (@$hooks) {
            my $hcreator = $h->creator;
            for my $container (qw/account group/) {
                if (my $h_cont_id = $h->{"${container}_id"}) {
                    my $hook_matches = 0;
                    for my $s_id (@{ $p{"${container}_ids"} }) {
                        next unless $s_id == $h_cont_id;
                        $hook_matches++;
                        last;
                    }
                    next HOOK unless $hook_matches;
                }
            }

            # Filter by workspace
            if (my $h_ws_id = $h->{workspace_id}) {
                next HOOK unless $p{workspace_id} == $h_ws_id;
            }

            # Filter by tag
            if (my $htag = $h->details->{tag}) {
                next HOOK unless any {
                    lc(ref($_) ? $_->tag : $_) eq lc($htag)
                } @{$p{tags}};
            }

            # Page specific filters
            if ($p{class} =~ m/^page\./) {
                if (!$hcreator->is_business_admin) {
                    # Run-time check that the user can still see this workspace
                    my $ws = Socialtext::Workspace->new(
                        workspace_id => $p{workspace_id});
                    next HOOK unless $ws->has_user($hcreator);
                }

                # Filter by page_id
                if (my $page_id = $h->details->{page_id}) {
                    next HOOK unless $page_id eq $p{page_id};
                }
            }

            # Signal specific filters
            if ($p{class} =~ m/^signal\./) {
                next HOOK unless $hcreator->is_business_admin
                              or $p{signal}->is_visible_to($hcreator);

                if (my $hanno = $h->details->{annotation}) {
                    next HOOK unless ref($hanno) eq 'ARRAY';
                    my $annos = $p{signal}->annotations;
                    next HOOK unless @$annos;
                    my $matches = 0;
                    my ($type, $field, $value) = @$hanno;
                    ANNO: for my $anno (@$annos) {
                        # Check the type matches
                        next ANNO unless $anno->{$hanno->[0]};

                        if (@$hanno == 1) {
                            # only check the type
                            $matches++;
                            last ANNO;
                        }
                        else {
                            my $attrs = $anno->{$type};
                            next ANNO unless exists $attrs->{$field};
                            if (@$hanno == 2) {
                                $matches++;
                                last ANNO;
                            }
                            else {
                                next ANNO unless $attrs->{$field} eq $value;
                                $matches++;
                                last ANNO;
                            }
                        }
                    }
                    next HOOK unless $matches;
                }

                # Filter by to_user
                if (my $huser_id = $h->details->{to_user}) {
                    my $uts = [
                        grep    {defined}
                            map { $_->user_id } $p{signal}->user_topics
                    ];
                    next HOOK
                        unless $p{signal}->recipient_id == $huser_id
                        or any { $_ == $huser_id } @$uts;
                }

                # Filter by sender_id
                if (my $user_id = $h->details->{sender_id}) {
                    next HOOK unless $p{signal}->user->user_id == $user_id;
                }
            }

            # Should only need to calculate the payload once
            unless ($payload) {
                time_scope 'webhook_payload';
                $payload = $p{payload_thunk}->(%p);
            }

            Socialtext::JobCreator->insert(
                'Socialtext::Job::WebHook' => {
                    hook => {
                        id => $h->id,
                        url => $h->url,
                    },
                    payload => $payload,
                },
            );
        }
    };
    if ($@) {
        warn $@;
        st_log->info("Error firing webhooks: '$@' " . ref($@));
    }
}

__PACKAGE__->meta->make_immutable;
1;
