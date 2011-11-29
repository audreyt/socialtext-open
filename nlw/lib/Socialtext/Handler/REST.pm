package Socialtext::Handler::REST;
# @COPYRIGHT@

use 5.12.0;
use warnings;

use base 'REST::Application::Routes';
use base 'Socialtext::Handler';
use Socialtext::HTTP ':codes';
use Socialtext::Handler::URIMap;
use Socialtext::JSON qw/encode_json decode_json/;
use Apache;
use Apache::Constants qw(OK AUTH_REQUIRED);
use Class::Field qw/field/;
use Encode qw(decode_utf8);
use File::Basename;
use File::Spec;
use Readonly;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);
use YAML;
use Socialtext::Log qw(st_timed_log);
use Socialtext::Timer;
use Socialtext::CGI::Scrubbed;
use Carp qw( croak );
use URI::Escape qw( uri_unescape );

Readonly my $AUTH_MAP => 'auth_map.yaml';
Readonly my $AUTH_INFO_DEFAULTS => {
    guest => 1,
    auth  => 'default', # meaningless right now
};

field 'meta';

my @AuthInfo;
my @ResourceHooks;
__PACKAGE__->_load_resource_hooks();

sub handler ($$) {
    my $class = shift;
    my $r     = shift;

    Socialtext::Timer->Reset();
    Socialtext::Timer->Continue('web_auth');
    my $auth_info = $class->getAuthForURI($r->uri);

    my $user = $class->authenticate($r);
    unless ($user) {
        my $ua = $r->header_in('User-Agent') || '';
        # WebKit in Adobe AIR has a bug where "401" will trigger a
        # non-suppressable re-authenticate dialog that doesn't work
        # well for Socialtext Desktop, so handle it as a special case.
        return $class->_webkit_air_unauthorized_handler($r)
            if ($ua =~ /\bAppleWebKit\b.*\bAdobeAIR\b.*\bSocialtext\s*Desktop\b/);
        $user = $class->guest($r, $auth_info);
    }

    Socialtext::Timer->Pause('web_auth');

    return $class->challenge(request => $r, auth_info => $auth_info) unless $user;

    return $class->real_handler($r, $user);
}

sub header {
    my $self = shift;
    my @args;
    while (my $key = shift) {
        my $val = shift;
        if ($key eq '-type' and $val ~~ [qw[ text/plain text/html application/xml application/json ]] ) {
            $val .= '; charset=UTF-8';
        }
        push @args, ($key => $val);
    }
    $self->SUPER::header(@args);
}

sub _webkit_air_unauthorized_handler {
    my $class = shift;
    my $r     = shift;

    # Special case: Rewrite 401 as 403 to prevent re-authentication.
    $r->status_line(HTTP_403_Forbidden);
    $r->send_http_header;
    return AUTH_REQUIRED;
}

sub guest {
    my $class     = shift;
    my $request   = shift;
    my $auth_info = shift;

    if ($auth_info->{guest}) {
        return Socialtext::User->Guest;
    }

    return undef;
}

sub challenge {
    my $class = shift;
    my %p = @_;
    my $request = $p{request};
    my $auth_info = $p{auth_info};

    if ($auth_info->{auth} eq 'basic') {
        $request->status_line(HTTP_401_Unauthorized);
        $request->header_out('WWW-Authenticate' => 'Basic realm="Socialtext"');
        $request->send_http_header;
        return AUTH_REQUIRED
    }

    # later there could be other options here
    return Socialtext::Challenger->Challenge(@_);
}


# FIXME: We do not want to return OK here in all cases.
sub real_handler {
    my $class   = shift;
    my $r       = shift;
    my $user    = shift;

    # Here we fix mod_rewrite's buggy double-escaping from "?" into "%3F"
    # in URI strings.  See build/templates/shared/rewrite.tt2 about where
    # this is coming from.
    # REVIEW: Maybe use a PUA character here instead?
    if ($r->uri =~ /%3F/) {
        my $uri = $r->uri;
        $uri =~ s/%3F/?/g;
        $r->uri($uri);
    }

    my $handler = __PACKAGE__->new( request => $r, user => $user );
    Socialtext::Timer->Continue('handler_run');
    my $rv = $handler->run();
    Socialtext::Timer->Pause('handler_run');

    $class->log_timings($handler);
    return ($handler, $rv);
}

# record to st_timed_log a record of how long this
# current request took
sub log_timings {
    my $class   = shift;
    my $handler = shift;

    # Only log timing information on a successful request
    # ie status is either 2xx or 3xx
    my %headers = $handler->header();

    # we use -status throughout the handlers, byproduct of CGI.pm
    my $status_string = $headers{-status};
    my $path = $handler->getLastMatchTemplate();
    my $status = 'UNDEF';

    return if $status_string and $status_string !~ /^([23]\d{2})\D/;
    if ($status_string and $status_string =~ m/^([23]\d{2})\D/) {
        $status = $1;
        return unless $status =~ m/^[23]/;
    }

    my $method = $handler->getRequestMethod();

    # get the template we matched
    my $message = $method . ',' . $path . ',' . $status;

    # get the hash which is the keys and values of the :word things
    # in the template path
    my %template_vars = $handler->getTemplateVars($path);

    my $query_hash = {};
    if ( $method eq 'GET' ) {
        # get any query string data
        my $args = [ $handler->request->args ];
        if (@$args % 2) {
            $query_hash = {
                page_name => shift @$args,
                @$args,
            };
        }
        else {
            $query_hash = { @$args };
        }
    }
    elsif ( $method eq 'POST' ) {
        my $query = $handler->query;
        my @params = $query->param();
        if (@params == 1 and $params[0] eq 'POSTDATA') {
            $query_hash = eval { decode_json($query->param('POSTDATA')) };
        }
        else {
            $query_hash = {
                map {
                    my $val = $query->param($_);
                    $val = 'ref:'.ref($val) if ref $val;
                    ($_ => $val);
                } @params
            };
        }

        if (ref $query_hash eq 'ARRAY') {
            $query_hash = { 'POSTDATA' => $query_hash };
        }

        delete $query_hash->{$_} for qw/signal body page_body comment/;
        for my $key (keys %$query_hash) {
            my $val = $query_hash->{$key};
            if (ref($val)) {
                if (ref($val) eq 'JSON::XS::Boolean') {
                    next;
                }
                if (ref($val) eq 'ARRAY') {
                    $val = undef unless @$val;
                }
                if (ref($val) eq 'HASH') {
                    $val = undef unless %$val;
                }
                $val = $query_hash->{$key} = encode_json($val) if $val;
            }
            next if $val and length($val) < 50;
            delete $query_hash->{$key};
        }
    }

    my $data = {
        %template_vars,
        ($status eq 'UNDEF' ? () : (status => $status)),
        ( keys(%$query_hash) ? (q => $query_hash) : () ),
        ( $handler->meta ? (meta => $handler->meta ) : () ),
    };

    st_timed_log(
        'info',
        'WEB',
        $message,
        $handler->user,
        $data,
        undef,
        Socialtext::Timer->ExtendedReport()
    );
}

sub loadResource {
    my ($self, $path, @extraArgs) = @_;

    $path ||= $self->getMatchText();
    $path = uri_unescape(URI->new($path)->path);
    $path = Encode::decode_utf8(Encode::encode(latin1 => $path));

    my $handler = sub { $self->defaultResourceHandler(@_) };
    my %vars;

    # Loop through the keys of the hash returned by resourceHooks().  Each of
    # the keys is a URI template, see if the current path info matches that
    # template.  Save the parent matches for passing into the handler.
    for my $template (keys %{ $self->resourceHooks() }) {
        my $regex = join "\\/+",
                    map {
                        (/^:__/ or (($template eq '/:ws/:pname') and /^:pname$/))
                            ? '(.+)'
                            : /^:ws$/
                                ? '(?!(?:nlw|challenge|data|feed|js|m|settings|st)/)([^\/]+)'
                                : /^:/
                                    ? '([^\/]+)'
                                    : quotemeta $_
                    }
                    split m{/}, $template;
        $regex = "^(?:$regex)\\/?\$";
        if ($self->checkMatch($path, $regex)) {
            $self->{__last_match_pattern} = $template;
            %vars = $self->getTemplateVars($template);
            $handler = $self->_getHandlerFromHook($template);
            last;
        }
    }

    return $self->callHandler($handler, \%vars, @extraArgs);
}



# overrride from REST::Application so we can return file handles effectively
sub run {
    my $self = shift;

    # Get resource.
    $self->preRun(); # A no-op by default.
    my $repr = $self->loadResource(@_);
    $self->postRun($repr); # A no-op by default.

    # if our resource returned a filehandle then print the headers and print it
    if (ref($repr) and blessed($repr) and $repr->isa('IO::Handle')) {
        my $headers = $self->getHeaders();
        print $headers;
        if ($self->request->can('send_fd')) {
            $self->request->send_fd($repr);
        }
        else {
            local $/ = \65536;
            print while <$repr>;
        }
        return;
    }

    # Get the headers and then add the representation to to the output stream.
    my $output = ''; # $self->getHeaders();
    $self->addRepresentation($repr, \$output);

    # Send the output unless we're told not to by the environment.
    print $output if not $ENV{REST_APP_RETURN_ONLY};

    return $output;
}

# Rather than calling defaultQueryObject, we need to override
# Rest::Application->new so that CGI->new is only called once
#
# Without this, file uploads do not work with CGI.pm 3.10
# Once we upgrade CGI.pm, we can remove this function and go back to calling
# defaultQueryObject.
#
# It might be the problem fixed in CGI.pm 3.29 where file handles were not
# being reset to zero each time CGI->new is called.
sub new {
    my ($proto, %args) = @_;
    my $class = ref($proto) ? ref($proto) : $proto;
    state $query;
    $query = $args{query} // $query // do { require CGI; CGI->new };
    my $self = bless(
        { __query => $query },
        $class,
    );
    $self->setup(%args);
    return $self;
}

sub setup {
    my ( $self, %args ) = @_;

    $self->{_request} = $args{request} || Apache->request;
    $self->{_user} = $args{user};
    $self->resourceHooks(@ResourceHooks);
}

# REVIEW: Overridden from REST::Application because it does
# the wrong thing and masks a die that happens within the
# eval, because the error does not result in a 500, as we
# might expect.
sub callHandler {
    my ($self, $handler, @extraArgs) = @_;
    my @args = $self->getHandlerArgs(@extraArgs);

    # Call the handler, make an error response if something goes wrong.
    my $result;
    eval {
        $self->preHandler(\@args);  # no-op by default.
        $result = $handler->(@args);
        $self->postHandler(\$result, \@args); # no-op by default.
    };
    if ($@) {
        my $e;
        if ($e = Exception::Class->caught('Socialtext::Exception::Auth')) {
            my $type = $e->http_type || 'text/plain';
            if ($self->user->is_guest()) {
                $self->header(
                    -status => HTTP_401_Unauthorized,
                    -WWW_Authenticate => 'Basic realm="Socialtext"',
                    -type   => $type,
                );
            }
            else {
                $self->header(
                    -status => HTTP_403_Forbidden,
                    -type   => $type,
                );
            }
            $result = $e->message;
        }
        elsif ($e = Exception::Class->caught('Socialtext::Exception')) {
            my $status = $e->http_status || HTTP_500_Internal_Server_Error;
            $self->header(
                -status => $status,
                -type => ($e->http_type || 'text/plain'),
            );
            $result = $e->message;
            $self->request->log_error($result);
        }
        else {
            $self->header(
                -status => HTTP_500_Internal_Server_Error,
                -type   => 'text/plain',
            );
            $result = "$@";
            $self->request->log_error($result);
        }
    }

    # Convert the result to a ref if it isn't already
    return ref($result) ? $result : \$result;

}

my %type_alias = (
    JSON  => 'application/json; charset=UTF-8',
    XML   => 'text/xml; charset=UTF-8',
    HTML  => 'text/html; charset=UTF-8',
    PLAIN => 'text/plain; charset=UTF-8',
);

# FIXME: add on cache handling hack
# If cache headers have not otherwise been dorked with, this
# makes _nothing_ cache.
# This is a stopgap. Do not let this stand! It prevents any caching,
# L A M E
sub postHandler {
    my ($self, $resultref, $args) = @_;
    my %headers = $self->header;

    # We check on existence rather than definedness, because someone might
    # have set a header to undef on purpose, so at to indicate not printing it
    # at all.

    unless (exists $headers{'-cache_control'} ||
            exists $headers{'-Cache-control'} ||
            exists $headers{'-pragma'} ||
            exists $headers{'-Pragma'} ||
            exists $headers{'-Etag'} ) {
        %headers = (
            %headers,
            -cache_control => 'no-cache,no-store,private',
            -pragma => 'no-cache',
            -expires => 'now',
        );
    }

    # CGI->header gets freaked out by undef values in its arguments.  So we
    # delete any undefs.
    while (my($k,$v) = each %headers) {
        delete $headers{$k} unless defined $v;
    }

    # Force apache 1.x to not send an empty "Transfer-Encoding: chunked" response.
    # 204 and 205 responses *must not* have a message-body, according to RFC 2616.
    if (($headers{'-status'} && $headers{'-status'} =~ /^20[45]/) ||
        !defined($$resultref) ||
        (!ref($$resultref) && length($$resultref) == 0))
    {
        $$resultref = undef;
        delete $headers{$_} for (grep /^-?content[-_]length$/i, keys %headers);
        $headers{'-content-length'} = 0; # forces a non-T-E response
    }

    # Force setting Content-Length, so nginx doesn't hold open connections.
    if (defined($$resultref) and !defined $headers{'-content-length'}) {
        use bytes;
        $headers{'-content-length'} = length($$resultref);
        no bytes;
    }

    if (my $type = $type_alias{$headers{'-type'}||''}) {
        $headers{'-type'} = $type;
    }

    # Reset headers to our cleaned set.
    $self->header(%headers);

    # If the request is a head, send back just the headers
    if ($self->getRequestMethod() eq 'HEAD') {
        ($$resultref, undef) = split(/^\r\n/, $$resultref || '');
    }
}

sub makeHandlerFromClass {
    my ( $self, $class, $method ) = @_;
    return sub { $class->new(@_)->$method(@_) };
}

sub defaultResourceHandler {
    unless ($ENV{NLW_DEV_MODE}) {
        $_[0]->header( -status => HTTP_404_Not_Found,
                       -type   => 'text/plain' );
        return "No File or Method found for your request.";
    }

    $_[0]->header( -status => HTTP_404_Not_Found,
                   -type   => 'text/html; charset=UTF-8' );
    no warnings 'once';
    local $YAML::SortKeys = 0;
    local $YAML::UseCode = 1;
    # Delete Socialtext objects.  Usually noise anyway.
    delete $_[0]->{$_} for qw(_user);
    my $dump = eval { Dump(@_) };
    $dump =~ s/-->/--\x{200d}>/g;
    return "No File or Method found for your request.  <!-- State is dumped below.\n\n$dump-->";
}

# XXX: The framework should use another layer of indirection over
# bestContentType.  So we don't have to overload it here.  Or push the
# GET/POST/PUT assymmetries into the framework.
sub bct_hack {
    my $self = shift;

    $self->{_gcp_hack} = 1;
    my $mime = $self->SUPER::bestContentType(@_);
    delete $self->{_gcp_hack};

    return $mime;
}

sub getContentPrefs {
    my $self   = shift;
    my $method = $self->getRequestMethod();
    if ( not $self->{_gcp_hack} and $method =~ /^(POST|PUT)$/i ) {
        my $ct = $self->request->header_in('Content-Type');
        $ct ||= '*/*';
        # throw away '; charset=' junk (and anything else since our YAML
        # config doesn't support it anyway):
        $ct =~ s/;.*$//;
        return ( $ct, '*/*' );
    }
    if (my $type = $self->query->param('accept')) {
        return ($type, '*/*');
    }
    my @types = uniq($self->SUPER::getContentPrefs(@_));
    my @reduced_types = grep { not m{^(?:image/|application/(?!json|(?:.+\+)?xml))} } @types;
    if ("@reduced_types" eq '*/*') {
        # Assume HTML when there's no specific Accept header (for IE7/8).
        unshift @types, 'text/html';
    }
    return @types;
}

sub getContent {
    my $self = shift;
    return $self->{__content} if defined $self->{__content};
    $self->{__content} = $self->_getContent();
    return $self->{__content};
}

sub getAuthForURI {
    my ($self, $path) =@_;
    my $template;
    my $info = $AUTH_INFO_DEFAULTS;
    my @auth = @AuthInfo; # copy the list
    # XXX somebody who knows perl should fix this
    while (@auth) {
        my $template = shift(@auth);
        my $value = shift(@auth);
        my $regex = qr{^$template};
        if ($path =~ $regex) {
           $info = $value;;
           last;
        }
    }
    return $info;
}

# use CGI for POST, and read the buffer for PUT
sub _getContent {
    my $self = shift;
    # N.B.: SUPER::getRequestMethod returns the underlying HTTP request
    # method, even if we're tunneling.
    if ( $self->getRealRequestMethod() eq 'POST' ) {
        return $self->query->param('POSTDATA');
    }
    else {
        # REVIEW: this is problematic for very large attachments
        my $buff = $self->query->param('PUTDATA');
        # if we are using old CGI, there is no PUTDATA, so fall back to read()
        unless ($buff) {
            my $content_length = $self->request->header_in('Content-Length');
            my $result = read( \*STDIN, $buff, $content_length, 0 );
            die "unable to read buffer $!" if not defined($result);
        }
        return $buff;
    }
}

sub user        { $_[0]->{_user} }
sub request     { $_[0]->{_request} }
sub getPathInfo { $_[0]->request->uri }

sub do_test {
}

# Get the resource hooks from the YAML file.  Since YAML.pm can't handle
# !!omap types, we also need to munge the underlying data structure back into
# an ordered list.
sub _load_resource_hooks {
    my $class  = shift;
    my $config_dir = File::Basename::dirname(
            Socialtext::AppConfig->file() );

    my $authinfo = YAML::LoadFile( File::Spec->catfile( $config_dir, $AUTH_MAP ) );
    my $hooks = Socialtext::Handler::URIMap->new->uri_hooks;

    $class->_load_resource_hook_classes($hooks);
    $class->_duplicate_gets_to_heads($hooks);
    @ResourceHooks = map {%$_} @$hooks;
    @AuthInfo = (map {%$_} @$authinfo );
}

# Duplicate all the GET handlers into HEAD handlers as well.
# We clean them up in the postHandler
sub _duplicate_gets_to_heads {
    my ($class, $hooks) = @_;

    # REVIEW: This is the brute force way of doing this, which doesn't
    # seem right.
    foreach my $entry (@$hooks) {
        foreach my $route ( keys(%$entry) ) {
            foreach my $method ( keys(%{$entry->{$route}}) ) {
                if ( $method eq 'GET' ) {
                    $entry->{$route}->{HEAD}
                        = $entry->{$route}->{GET};
                }
            }
        }
    }
}

# Automagically require the classes used in the YAML file.
sub _load_resource_hook_classes {
    my ( $class, $hooks ) = @_;

    for my $hook (@$hooks) {
        _load_classes($hook);
    }
}

sub _load_classes {
    my $hook = shift;

    if ( ref($hook) eq 'ARRAY' ) {
        my $class = $hook->[0] || return;
        return if $class->can('new');
        eval "require $class; 0;";
        if ($@) {
            warn "unable to load $class: $@\n";
            die "$@\n";
        }
    }
    elsif ( ref($hook) eq 'HASH' ) {
        for my $key ( keys %$hook ) {
            _load_classes( $hook->{$key} );
        }
    }
}

1;
