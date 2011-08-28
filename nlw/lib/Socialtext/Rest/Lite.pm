package Socialtext::Rest::Lite;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest';

use Socialtext::Lite;
use Socialtext::Challenger;
use Socialtext::HTTP ':codes';
use Socialtext::HTTP::Cookie;
use Socialtext::Events;

# basically just a dispatcher to NLW::Lite
# need some deduping

sub if_plugin_authorized {
    my ($self, $plugin, $method, $perl_method) = @_;
    if ((uc($method) eq 'GET') && Socialtext::HTTP::Cookie->NeedsRenewal) {
        return $self->renew_authentication();
    }
    return $self->SUPER::if_plugin_authorized($plugin, $method, $perl_method);
}

sub if_authorized {
    my ($self, $method, $perl_method, @args) = @_;
    if ((uc($method) eq 'GET') && Socialtext::HTTP::Cookie->NeedsRenewal) {
        return $self->renew_authentication();
    }
    return $self->SUPER::if_authorized($method, $perl_method, @args);
}

sub not_authorized {
    my $self = shift;
    eval {
        Socialtext::Challenger->Challenge(
            hub      => $self->hub,
            redirect => $self->rest->query->url(
                -absolute => 1, -path => 1, -query => 1
            ),
        );
    };
    if ( my $e = $@ ) {
        if ( Exception::Class->caught('Socialtext::WebApp::Exception::Redirect') )
        {
            my $location = $e->message;
            $self->rest->header(
                -status   => HTTP_302_Found,
                -Location => $location,
            );
            return '';
        }
    }
    $self->rest->header(
        -status => HTTP_500_Internal_Server_Error,
    );
    return 'Challenger Did not Redirect';
}

sub homepage {
    my $self = shift;
    return $self->not_authorized unless $self->rest->user->is_authenticated;

    my $loc = $self->hub->pluggable->hook('nlw.lite_homepage')
       || '/m/workspace_list';
    $self->rest->header(
        -status   => HTTP_302_Found,
        -Location => $loc,
    );
    return '';
}

sub changes {
    my ( $self, $rest ) = @_;

    $self->if_authorized(
        'GET',
        sub {
            my $tag = $self->_tag_from_uri();
            my $content = Socialtext::Lite->new( hub => $self->hub )
                ->recent_changes($tag);

            $rest->header(
                -status => HTTP_200_OK,
                -type   => 'text/html' . '; charset=UTF-8'
            );
            return $content;
        }
    );
}

sub login {
    my ($self, $rest) = @_;

    # force a "ws" parameter, even if its empty; otherwise our base class
    # chokes when it tries to access the "ws" param in order to try to create
    # a workspace for us to work with.
    #
    # we don't necessarily have a workspace in use, so its ok for this to be
    # 'undef'.
    $self->params->{ws} ||= undef;

    # doesn't matter if the user is authorized or not; this page *has* a
    # visible display either way.
    my $redirect_to = $rest->query->param('redirect_to');
    my $content = Socialtext::Lite->new( hub => $self->hub )
            ->login($redirect_to);
    $rest->header(
        -status => HTTP_200_OK,
        -type   => 'text/html' . '; charset=UTF-8'
    );
    return $content;
}

sub nologin {
    my ($self, $rest) = @_;

    my $content = Socialtext::Lite->new(hub => $self->hub)->nologin();
    $rest->header(
        -status => HTTP_200_OK,
        -type   => 'text/html' . '; charset=UTF-8'
    );
    return $content;
}

sub forgot_password {
    my ($self, $rest) = @_;

    $self->params->{ws} ||= undef;

    my $content = Socialtext::Lite->new( hub => $self->hub )->forgot_password();
    $rest->header(
        -status => HTTP_200_OK,
        -type   => 'text/html' . '; charset=UTF-8'
    );
    return $content;
}


sub workspace_list {
    my ($self, $rest) = @_;

    # force a "ws" parameter, even if its empty; otherwise our base class
    # chokes when it tries to access the "ws" param in order to try to create
    # a workspace for us to work with.
    #
    # we don't necessarily have a workspace in use, so its ok for this to be
    # 'undef'.
    $self->params->{ws} ||= undef;

    # doesn't matter if the user is authorized or not; this page *has* a
    # visible display either way.
    my $content = Socialtext::Lite->new( hub => $self->hub )
            ->workspace_list();
    $rest->header(
        -status => HTTP_200_OK,
        -type   => 'text/html' . '; charset=UTF-8'
    );
    return $content;
}

sub tag {
    my ( $self, $rest ) = @_;

    $self->if_authorized(
        'GET',
        sub {
            my $content = Socialtext::Lite->new( hub => $self->hub )
                ->tag( tag => $self->_tag_from_uri, pagenum => scalar $rest->query->param('page') );
            $rest->header(
                -status => HTTP_200_OK,
                -type   => 'text/html' . '; charset=UTF-8'
            );
            return $content;
        }
    );
}

sub search {
    my ( $self, $rest ) = @_;

    $self->if_authorized(
        'GET',
        sub {
            my $search_term = $rest->query->param('search_term');
            my $pagenum = $rest->query->param('page');
            my $content = Socialtext::Lite->new( hub => $self->hub )->search(
                search_term => $search_term,
                pagenum => $pagenum,
            );
            $rest->header(
                -status => HTTP_200_OK,
                -type   => 'text/html' . '; charset=UTF-8'
            );
            return $content;
        }
    );
}

sub get_page {
    my ( $self, $rest ) = @_;

    $self->if_authorized(
        'GET',
        sub {

            my $action = $rest->query->param('action');

            my $page = $self->_get_page();
            my $content;

            if ( $action && $action eq 'edit' ) {
                unless ( $self->user_can('edit') ) {
                    $rest->header(
                        -Location => $self->full_url,
                        -status  => HTTP_302_Found,
                    );
                    return '';
                }

                $content
                    = Socialtext::Lite->new( hub => $self->hub )->edit_action($page);
                $rest->header(
                    -status => HTTP_200_OK,
                    -type   => 'text/html' . '; charset=UTF-8'
                );
            }
            elsif ( $action && $action eq 'join_to_edit' ) {
                if ( Socialtext::Lite->new( hub => $self->hub )->user_can_join_to_edit_page($page) ) {
                    require Socialtext::Handler::Authen;
                    bless({} => 'Socialtext::Handler::Authen')->_add_user_to_workspace(
                        $self->rest->user,
                        $self->workspace->name,
                    );
                }

                $rest->header(
                    -Location => $self->full_url,
                    -status  => HTTP_302_Found,
                );
                return '';
            }
            else {
                $content = Socialtext::Lite->new( hub => $self->hub )->display($page);
                $rest->header(
                    -status        => HTTP_200_OK,
                    -type   => 'text/html' . '; charset=UTF-8',
                    -Last_Modified => $self->make_http_date(
                        $page->modified_time()
                    ),
                );

                if ($page->exists) {
                    Socialtext::Events->Record({
                        event_class => 'page',
                        action => 'view',
                        page => $page,
                    });
                }
            }
            return $content;
        }
    );
}

sub edit_page {
    my ( $self, $rest ) = @_;


    unless ( $self->user_can('edit') ) {
        $rest->header(
            -Location => $self->full_url,
            -status   => HTTP_302_Found,
        );
        return '';
    }
    my $page = $self->_get_page();
    my $content = Socialtext::Lite->new( hub => $self->hub )->edit_save(
        page        => $page,
        action      => $rest->query->param('action') || 'edit_save',
        content     => $rest->query->param('page_body') || '',
        comment     => $rest->query->param('comment_body') || '',
        revision_id => $rest->query->param('revision_id') || '',
        revision    => $rest->query->param('revision') || '',
        subject     => $rest->query->param('subject') || '',
    );

    # $html contains contention info
    if ( length($content) ) {
        $rest->header(
            -status => HTTP_200_OK,
            -type   => 'text/html' . '; charset=UTF-8',
        );
        return $content;
    }
    else {
        $rest->header(
            -Location => $self->full_url,
            -status   => HTTP_302_Found,
        );
        return '';
    }
}

sub _get_page {
    my $self = shift;

    my $page;
    # XXX should be able to use $self->pname or $self->page here
    # but had some issues. come back later
    if ( $self->params->{pname} ) {
        $page = $self->hub->pages->new_from_uri( $self->params->{pname} );
    }
    else {
        $page = $self->hub->pages->new_from_uri( $self->workspace->title );
    }

    return $page;
}

sub _tag_from_uri {
    my $self = shift;

    # XXX why can't i get tag from self->tag?
    return $self->params->{tag};
}

1;

1;
