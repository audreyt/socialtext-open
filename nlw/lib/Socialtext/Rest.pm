package Socialtext::Rest;
# @COPYRIGHT@

use warnings;
use strict;

# A base class in which to group code common to all 'Socialtext::Rest::*'
# classes.

use Class::Field 'field';
use DateTime;
use DateTime::Format::HTTP;
use Date::Parse qw/str2time/;
use Carp 'croak';
use List::MoreUtils qw/part/;
use Try::Tiny;
use Scalar::Util qw/blessed/;
use URI::Escape qw(uri_escape);
use YAML ();

use Socialtext::Exceptions qw/bad_request/;
use Socialtext::Workspace;
use Socialtext::HTTP ':codes';
use Socialtext::Log 'st_log';
use Socialtext::URI;
use Socialtext::Session;
use Socialtext::JSON qw/decode_json/;
use Socialtext::SQL 'sql_singlevalue';
use Socialtext::l10n qw( system_locale loc loc_lang best_locale );
use Encode ();

our $AUTOLOAD;

field 'hub',   -init => '$self->main->hub';
field 'main',  -init => '$self->_new_main';
field 'page',  -init => '$self->hub->pages->new_from_uri($self->pname)';
field 'authz', -init => '$self->hub ? $self->hub->authz : Socialtext::Authz->new()';
field 'workspace';
field 'params' => {};
field 'rest';
field 'session', -init => 'Socialtext::Session->new()';
field 'impersonator';

sub new {
    my $class = shift;
    my $new_object = bless {}, $class;
    $new_object->_initialize(@_);
    return $new_object;
}

sub error {
    my ( $self, $code, $msg, $body ) = @_;
    $self->rest->header(
        -status => "$code $msg",
        -type   => 'text/plain',
    );
    return $body;
}

sub renew_authentication {
    my $self     = shift;
    my $here     = shift || $self->rest->query->url(-absolute => 1, -path_info => 1, -query => 1);
    my $location = '/challenge?' . uri_escape($here);
    $self->session->add_error(
        loc("error.relogin")
    );
    $self->session->write;
    $self->rest->header(
        -status   => HTTP_302_Found,
        -location => $location,
    );
    return '';
}

sub bad_method {
    my ( $self, $rest ) = @_;
    my $allowed = $self->allowed_methods;
    $rest->header(
        -allow  => $allowed,
        -status => HTTP_405_Method_Not_Allowed,
        -type   => 'text/plain' );
    return HTTP_405_Method_Not_Allowed . "\n\nOnly $allowed are supported.\n";
}

sub if_plugin_authorized {
    my $self = shift;
    my $plugin = shift;
    my $method = shift;
    my $perl_method = shift;

    my $authz = $self->authz;
    my $user  = $self->rest->user;
    return $self->not_authorized
        unless $user
            and $user->is_authenticated
            and $authz->plugin_enabled_for_user(
                user => $user,
                plugin_name => $plugin, 
            );

    return $self->$perl_method(@_);
}

=head2 bad_type

The request sent a content-type that's not useful for the current URI.

=cut
# REVIEW: Ideally this would wire back to the uri_map to tell us
# what types are acceptable.
sub bad_type {
    my ( $self, $rest ) = @_;
    $rest->header(
        -status => HTTP_415_Unsupported_Media_Type,
    );
    return '';
}

sub redirect_workspaces {
    my ( $self, $rest ) = @_;
    $rest->header(
        -status => HTTP_302_Found,
       -Location => $self->rest->query->url(-base => 1) . '/data/workspaces',
    );
    return '';
}

sub _initialize {
    my ( $self, $rest, $params ) = @_;

    $self->rest($rest);
    $self->params($params) if ($params);
    $self->workspace($self->_new_workspace);

    my $user = $self->rest->user;
    if ($user->is_guest) {
        loc_lang(system_locale());
        return;
    }

    my $locale = sql_singlevalue(<<'.', $self->rest->user->user_id);
SELECT value
  FROM user_plugin_pref
 WHERE user_id = ?
   AND plugin = 'locales'
   AND key = 'locale' 
.
    loc_lang( $locale || system_locale() );
}

sub _new_workspace {
    my $self = shift;

    my $workspace;
    if ($self->params->{ws}) {
        $workspace = Socialtext::Workspace->new(name => $self->ws);
    }
    else {
        $workspace = Socialtext::NoWorkspace->new();
    }

    $self->_check_on_behalf_of($workspace);

    return $workspace;
}

sub _check_on_behalf_of {
    my $self      = shift;
    my $workspace = shift;

    # in some cases our rest object is going to be bogus
    # because we are being called internally, or by tests
    return unless $self->rest->can('request');

    my $behalf_header    = $self->rest->request->header_in('X-On-Behalf-Of');
    my $behalf_parameter = $self->rest->query->param('on-behalf-of');
    my $behalf_username = $behalf_parameter || $behalf_header || undef;
    return unless $behalf_username;

    my $current_user = $self->rest->user;

    if ($current_user->is_guest) {
        # {bz: 1665}: Because "guest" is usually due to cred extractor
        # failure, we fail with the same error as not_authorized instead
        # of the terribly misleading "guest may not impersonate".
        $self->rest->header(
            -status => HTTP_401_Unauthorized,
            -WWW_Authenticate => 'Basic realm="Socialtext"',
        );
        Socialtext::Exception::Auth->throw(
            "Cannot impersonate unless authenticated; please check your credentials and/or your appliance's LDAP/SSO configuration"
        );
    }

    my $desired_user;
    try {
        $desired_user = Socialtext::User->new(username => $behalf_username);
        # be careful not to leak a "no such user" error here
        unless ($desired_user and (
                $desired_user->can_be_impersonated_by($current_user) or
                $workspace->impersonation_ok($current_user => $desired_user)))
        {
            Socialtext::Exception::Auth->throw(
                "Cannot impersonate ".$behalf_username." in this context"
            );
        }
    }
    catch {
        my $e = $_;
        st_log->warning("exception while trying to impersonate: $e");
        st_log->warning("... no such user") unless $desired_user;
        if (UNIVERSAL::isa($e,'Socialtext::Exception::Auth')) {
            $self->rest->header(
                -status => HTTP_403_Forbidden,
            );
            $e->rethrow();
        }
        die $e;
    };

    $self->{impersonator} = $self->rest->user;
    $self->rest->{_user} = $desired_user;
    $self->rest->request->connection->user($desired_user->username);

    # clear the paramters in case there is a subrequest
    $self->rest->query->param('on-behalf-of', '');
    $self->rest->request->header_in('X-On-Behalf-Of', '');
    st_log->debug(
        $current_user->username, 'is impersonating',
        $desired_user->username
    );
    return;
}

sub _new_main {
    my $self = shift;
    my $main = Socialtext->new;

    $main->load_hub(
        current_user      => $self->rest->user,
        current_workspace => $self->workspace,
    );
    $main->hub->registry->load;
    $main->debug;

    return $main;
}

=head2 make_http_date

Given an epoch time, returns a properly formatted RFC 1123 date
string.

=cut
sub make_http_date {
    my $self = shift;
    my $epoch = shift;
    my $dt = DateTime->from_epoch( epoch => $epoch );
    return DateTime::Format::HTTP->format_datetime($dt);
}

=head2 make_date_time_date

Given an HTTP (rfc 1123) date, return a DateTime object.

=cut
sub make_date_time_date {
    my $self = shift;
    my $timestring = shift;
    return DateTime::Format::HTTP->parse_datetime($timestring);
}

=head2 user_can($permission_name)

C<$permission_name> can either be the name of a L<Socialtext::Permission> or
the name of a L<Socialtext::User> method.  If C<$permission_name> begins with
C<is_>, then it is assumed to be the latter.  E.g, C<is_business_admin>.

=cut
sub user_can {
    my $self = shift;
    my $permission_name = shift;
    return $permission_name =~ /^is_/
        ? $self->rest->user->$permission_name
        : $self->hub->checker->check_permission($permission_name);
}

=head2 if_authorized($http_method, $perl_method, @args)

Checks the hash returned by C<< $self->permission >> to see if the user is
authorized to perform C<< $http_method >> using C<< $self->user_can >>. If so,
executes C<< $self->$perl_method(@args) >>, and if not returns
C<< $self->not_authorized >>.

The default implementation of C<permission> requires C<read> for C<GET> and
C<edit> for C<PUT>, C<POST>, and  C<delete> for C<DELETE>.

=cut
sub if_authorized {
    my ( $self, $method, $perl_method, @args ) = @_;
    my $perm_name = $self->permission->{$method};

    return !$perm_name
        ? $self->$perl_method(@args)
        : $perm_name !~ /^is/ && !(defined $self->workspace and $self->workspace->real)
            ? $self->no_workspace
            : ( !$perm_name ) || $self->user_can($perm_name)
                ? $self->$perl_method(@args)
                : $self->not_authorized;
}

sub permission {
    +{ GET => 'read', PUT => 'edit', POST => 'edit', DELETE => 'delete' };
}

=head2 not_authorized()

Tells the client the current user is not authorized for the
requested method on the resource.

=cut

sub not_authorized {
    my $self = shift;

    if ($self->rest->user->is_guest) {
        $self->rest->header(
            -status => HTTP_401_Unauthorized,
            -WWW_Authenticate => 'Basic realm="Socialtext"',
        )
    }
    else {
        $self->rest->header(
            -status => HTTP_403_Forbidden,
            -type   => 'text/plain',
        );
    }
    return loc('error.user-not-authorized');
}

=head2 no_workspace()

Informs the client that we can't operate because no valid workspace
was created from the provided URI.

=cut

sub no_workspace {
    my $self = shift;
    my $ws = shift || $self->ws;
    return $self->no_resource($ws);
}

=head2 no_resource()

Informs the client that we can't operate because no valid resource
was created or found from the provided URI.

=cut

sub no_resource {
    my $self = shift;
    my $resource_name = shift;
    $self->rest->header(
        -status => HTTP_404_Not_Found,
        -type   => 'text/plain',
    );
    return loc("error.not-found=entity", $resource_name);
}

=head2 conflict()

The request could not be completed due to a conflict with the current state of
the resource.

=cut

sub conflict {
    my $self = shift;
    my $errors = shift || [];
    $self->rest->header(
        -status => HTTP_409_Conflict,
        -type   => 'text/plain',
    );
    return join "\n", @$errors;
}

sub page_lock_permission_fail {
    my $self = shift;

    return $self->not_authorized()
        if (
            $self->workspace->allows_page_locking && 
            $self->page->locked && 
            !$self->user_can('lock')
        );

    return 0;
}

sub page_locked_or_unauthorized {
    my $self = shift;

    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('edit');

    my $lock_check_failed = $self->page_lock_permission_fail();
    return $lock_check_failed if ($lock_check_failed);

    return 0;
}

# REVIEW: making use of CGI.pm here
sub full_url {
    my $self = shift;

    my $path = $self->rest->query->url( -absolute => 1, -path_info => 1 );
    $path = join('', $path, @_);
    my $uri = Socialtext::URI::uri( path => $path );
    return $uri;
}

sub GET_yaml {
    require YAML;
    my $self = shift;
    my $json = $self->GET_json(@_);
    $self->rest->header(
        $self->rest->header,
        -type   => 'text/plain',
    );
    return YAML::Dump(decode_json($json))
}

sub _renderer_load {
    my $self = shift;

    unless ($self->{_renderer}) {
        Socialtext::Timer->Continue('coll_tt2_prep');

        $self->{_renderer} = Socialtext::TT2::Renderer->instance;

        unless ($self->{_template_paths}) {
            my $paths = $self->hub->skin->template_paths;
            push @$paths, glob(Socialtext::AppConfig->code_base . "/plugin/*/template");
            $self->{_template_paths} = $paths;
        }

        my $name = $self->can('collection_name') ?
            $self->collection_name : $self->entity_name;

        $self->{_template_vars} = [
            collection_name => $name,
            link => Socialtext::URI::uri(path => $self->rest->request->uri),
            minutes_ago => sub { int((time - str2time(shift)) / 60) },
            round => sub { int($_[0] + .5) },
            skin_uri => sub {
                join '', Socialtext::Helpers::skin_uri('s3'), @_;
            },
            pluggable => $self->hub->pluggable,
        ];

        Socialtext::Timer->Pause('coll_tt2_prep');
    }

    return @$self{qw(_renderer _template_paths _template_vars)};
}

sub template_render {
    my ($self, $tmpl, $add_vars) = @_;
    $add_vars ||= {};
    my ($renderer, $paths, $vars) = $self->_renderer_load();
    return $renderer->render(
        template => $tmpl,
        paths => $paths,
        vars => {
            @$vars,
            %$add_vars,
        },
    );
}


# Automatic getters for query parameters.
sub AUTOLOAD {
    my $self = shift;
    my $type = ref $self or die "$self is not an object ($AUTOLOAD).\n";

    $AUTOLOAD =~ s/.*://;
    return if $AUTOLOAD eq 'DESTROY';

    if (exists $self->params->{$AUTOLOAD}) {
        croak("Cannot set the value of '$AUTOLOAD'") if @_;
        return $self->params->{$AUTOLOAD};
    }
    croak("No such method '$AUTOLOAD' for type '$type'.");
}

sub nonexistence_message { loc('error.no-requested-resource') }

sub http_404 {
    my ( $self, $rest ) = @_;
    $rest->header(
        -type   => 'text/plain',
        -status => HTTP_404_Not_Found,
        $rest->header(),
    );
    return $self->nonexistence_message;
}

sub http_404_force {
    my $self = shift;
    $self->rest->header(
        $self->rest->header(),
        -type   => 'text/plain',
        -status => HTTP_404_Not_Found,
    );
    return $self->nonexistence_message;
}

sub http_400 {
    my ( $self, $rest, $content ) = @_;
    $rest->header(
        -type   => 'text/plain',
        -status => HTTP_400_Bad_Request,
        $rest->header(),
    );
    return $content || ""; 
}

sub http_400_force {
    my ( $self, $content ) = @_;
    $self->rest->header(
        $self->rest->header(),
        -type   => 'text/plain',
        -status => HTTP_400_Bad_Request,
    );
    return $content || ""; 
}

sub decoded_json_body {
    my $self = shift;
    return try { decode_json($self->rest->getContent) }
    catch { bad_request 'Malformed JSON passed to resource.' };
}

# Send a file to the client via nginx
sub serve_file {
    my ($self, $rest, $attachment, $file_path, $file_size) = @_;

    my $mime_type = $attachment->mime_type;
    if ( $mime_type =~ /^text/ ) {
        my $charset = $attachment->can('charset')
            ? $attachment->charset(system_locale())
            : undef;
        $charset = 'UTF-8' unless defined $charset;
        $mime_type .= "; charset=$charset";
    }

    # See Socialtext::Headers::add_attachments for the IE6/7 motivation
    # behind Pragma and Cache-control below.
    $rest->header(
        '-status'             => HTTP_200_OK,
        '-content-length'     => $file_size,
        '-type'               => $mime_type,
        '-pragma'             => undef,
        '-cache-control'      => undef,
        # XXX: this header should be mime-encoded (a la
        # http://www.ietf.org/rfc/rfc2184.txt) if it contains non-ascii
        'Content-Disposition' => 'filename="'.Encode::encode_utf8($attachment->filename).'"',
        '-X-Accel-Redirect'   => $file_path,
    );
    return '';
}

{
    my @default_exception_handlers = (
       ['Socialtext::Exception::Auth' =>
        sub { my($self,$e)=@_; $self->not_authorized }],
       ['Socialtext::Exception::NotFound' =>
        sub { my($self,$e)=@_; $self->http_404_force() }],
       ['Socialtext::Exception::NoSuchResource' =>
        sub { my($self,$e)=@_; $self->no_resource($e->name) }],
       ['Socialtext::Exception::Conflict' =>
        sub { my($self,$e)=@_; $self->conflict($e->errors) }],
       ['Socialtext::Exception::BadRequest' =>
        sub { my($self,$e)=@_; $self->http_400_force($e->message) }],
       ['Socialtext::Exception::DataValidation' =>
        sub { my($self,$e)=@_; $self->http_400_force($e->message) }],
    );
    sub rest_exception_handlers {
        return [@default_exception_handlers]; # copy
    }
}

sub trim_exception {
    my $msg = shift;
    $msg =~ s{(?:^Trace begun)? at \S+ line .*$}{}ims;
    return $msg;
}

sub handle_rest_exception {
    my ($self, $e) = @_;
    my $msg;

    $self->rest->header(
        $self->rest->header,
        -status => HTTP_500_Internal_Server_Error,
        -type => 'text/plain',
    );

    my $hdlrs = $self->rest_exception_handlers;
    my ($re_hdlrs, $isa_hdlrs) = part { ('Regexp' eq ref $_->[0]) ? 0 : 1 }
        @$hdlrs;

    if (blessed($e) && $e->isa("Socialtext::Exception")) {
        my %hdr;
        if (my $status = $e->http_status) {
            $hdr{'-status'} = $status;
        }
        if (my $type = $e->http_type) {
            $hdr{'-type'} = $type;
        }
        $self->rest->header($self->rest->header, %hdr);

        # try a handler based on the class name
        for my $handler (@$isa_hdlrs) {
            my ($isa, $code) = @$handler;
            next unless ($e->isa($isa));
            $msg = $self->$code($e);
            goto _send_error_message if defined $msg;
        }

        # fall through to the regex handlers
        $e = $e->as_string;
    }

    for my $handler (@$re_hdlrs) {
        my ($re, $code) = @$handler;
        $msg = $self->$code($e) if ($e =~ $re);
        goto _send_error_message if defined $msg;
    }

    $msg = trim_exception($e);
    _send_error_message: {
        warn "REST Error: $e\n";
        st_log->error($msg);
        return $msg;
    }
}

sub resource_to_yaml { YAML::Dump($_[1]) }

1;
