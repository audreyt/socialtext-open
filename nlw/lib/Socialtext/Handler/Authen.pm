package Socialtext::Handler::Authen;
# @COPYRIGHT@
use strict;
use warnings;

use base 'Socialtext::Handler';

use Apache::Constants qw( NOT_FOUND REDIRECT);
use Socialtext;

use Encode ();
use Email::Valid;
use Exception::Class;
use Socialtext::AppConfig;
use Socialtext::Authen;
use Socialtext::BrowserDetect;
use Socialtext::Hub;
use Socialtext::Log qw(st_log st_timed_log);
use Socialtext::Timer;
use Socialtext::Apache::User;
use Socialtext::User;
use Socialtext::User::Restrictions;
use Socialtext::Session;
use Socialtext::Helpers;
use Socialtext::Workspace;
use Socialtext::Permission qw( ST_SELF_JOIN_PERM );
use Socialtext::l10n qw( loc loc_lang system_locale );
use Socialtext::String ();
use URI::Escape qw(uri_escape_utf8);
use Captcha::reCAPTCHA;

sub handler ($$) {
    my $class = shift;
    my $r     = shift;

    my $self = bless {r => $r}, __PACKAGE__; # new can kiss my ass
    $self->{args} = { $r->args };

    loc_lang( system_locale() );

    (my $uri = $r->uri) =~ s[^/nlw/?][];
    if ($uri =~ m[submit/]) {
        my ($action) = $uri =~ m[submit/(\w+)];
        return $self->$action if $self->can($action);
        warn "Can't handle action '$action'";
        return NOT_FOUND;
    }
    elsif ($uri =~ /\.html$/) {
        # strip off trailing ; to avoid warning
        (my $query_string = $r->args || '') =~ s/;$//;
        $r->args($query_string);

        # sucks, but we need a Hub to get the global template vars and to
        # get the list of available public workspaces
        my $hub  = $self->_load_hub();
        my $user = $hub->current_user();

        # vars that we're setting up to use in our template later on
        my $vars = {};

        if ($uri eq 'choose_password.html') {
            my $saved_args  = $self->session->saved_args;
            my $hash        = $saved_args->{hash};
            my $account_for = $saved_args->{account_for};

            return $self->_show_error(
                loc('error.invalid-confirmation-url')
            ) unless $hash;

            my $restriction = $self->_find_restriction_for_hash($r, $hash);
            return $self->_show_error() unless $restriction;
            my $user = $restriction->user;

            $vars->{email_address} = $user->email_address;
            $vars->{hash}          = $hash;

            if ($account_for && $account_for eq 'free50') {
                $vars->{title}         = loc("free50.setup");
                $vars->{heading}       = loc("free50.setup");
                $vars->{to_create}     = loc("free50.account");
            }
            else {
                $vars->{title}         = loc("pasword.choose");
                $vars->{heading}       = loc("pasword.choose");
                $vars->{to_create}     = loc("account.socialtext");
            }
        }

        # Include login_message_file content in vars sent to template
        # if login_message_file is set in AppConfig.
        if ( $uri eq 'login.html' ) {
            return $self->_redirect('/m/login') if ($self->_is_mobile);

            # login message
            my $file = Socialtext::AppConfig->login_message_file();
            if ( $file and -r $file ) {
                # trap any errors and ignore them to the error log
                eval {
                    $vars->{login_message}
                        = Socialtext::File::get_contents_utf8($file);
                };
                warn $@ if $@;
            }
        }
        if (($uri eq 'login.html') || ($uri eq 'logout.html')) {
            # list of public workspaces (for Workspace List)
            $vars->{public_workspaces}
                = [ $hub->workspace_list->public_workspaces ];
        }
        if ( $uri eq 'join.html' ) {
            my $redirect_to = $self->{args}{redirect_to} || '';
            if (my $ws_name = $self->{args}{workspace_name}) {
                if ($self->_add_user_to_workspace($user, $ws_name)) {
                    return $self->_redirect($redirect_to);
                }
            }
            my $appliance_config = Socialtext::Appliance::Config->new;
            if ($appliance_config->value('captcha_enabled')) {
                my $c = Captcha::reCAPTCHA->new;
                my $c_pubkey = $appliance_config->value('captcha_pubkey');
                if ($c_pubkey) {
                    $vars->{captcha_form} = $c->get_html($c_pubkey, undef, $ENV{'NLWHTTPSRedirect'});
                }
            }
           $vars = {%{$self->{args}}, %$vars}; # for refilling the form fields
        }
        if ( $uri eq 'register.html' ) {
            my $appliance_config = Socialtext::Appliance::Config->new;
            if ($appliance_config->value('captcha_enabled')) {
                my $c = Captcha::reCAPTCHA->new;
                my $c_pubkey = $appliance_config->value('captcha_pubkey');
                if ($c_pubkey) {
                    $vars->{captcha_form} = $c->get_html($c_pubkey, undef, $ENV{'NLWHTTPSRedirect'});
                }
            }
           $vars = {%{$self->{args}}, %$vars}; # for refilling the form fields
        }
        if ($uri eq 'nologin.html') { # The NoLogin challenger
            return $self->_redirect('/m/nologin') if ($self->_is_mobile);

            my $file = Socialtext::AppConfig->login_message_file();
            if ( $file and -r $file ) {
                eval {
                    $vars->{messages}
                        = Socialtext::File::get_contents_utf8($file);
                };
                warn $@ if $@;
            }
            $vars->{messages} ||= '<p>'. loc("info.login-disabled") .'</p>';
        }

        if ($self->{args}{workspace_name}) {
            $vars->{target_workspace} = Socialtext::Workspace->new(name => $self->{args}{workspace_name});
        }
        my @errors;
        if ($r->prev) {
            @errors = split /\n/, $r->prev->pnotes('error') || '';
        }
        if ($uri eq 'errors/500.html') {
            return $class->handle_error( $r, \@errors);
        }

        my $saved_args = $self->{saved_args} = $self->session->saved_args;
        my $repl_vars = {
            $self->_default_template_vars(),
            authen_page       => 1,
            username_label    => Socialtext::Authen->username_label,
            redirect_to       => $self->{args}{redirect_to},
            remember_duration => Socialtext::Authen->remember_duration,
            %$saved_args,
            %$vars,
        };
        return $class->render_template($r, "authen/$uri", $repl_vars);
    }

    warn "Unknown URI: $uri";
    return NOT_FOUND;
}

sub _is_mobile_browser {
    return Socialtext::BrowserDetect::is_mobile() ? 1 : 0;
}

sub _is_mobile_redirect {
    my $self = shift;
    my $url  = $self->{args}{redirect_to};
    if (defined $url) {
        $url =~ s{^https?://[^/]+}{};   # strip off scheme/host
        $url =~ s{^/}{};                # strip off leading "/"
        $url =~ s{/.*$}{};              # strip off everything after first "/"
        return 1 if ($url eq 'lite');
        return 1 if ($url eq 'm');
    }
    return 0;
}

sub _is_mobile {
    my $self = shift;
    return $self->_is_mobile_browser || $self->_is_mobile_redirect;
}

sub login {
    my ($self) = @_;
    my $r = $self->r;

    my $validname = ( Socialtext::Authen->username_is_email()
        ? loc('login.email-address')
        : loc('login.username')
    );
    my $username = $self->{args}{username} || '';
    unless ($username) {
        $self->session->add_error(loc('error.invalid-login=field', $validname));
        return $self->_challenge();
    }

    my $user_check = Socialtext::Authen->username_is_email()
        ? Email::Valid->address($username)
        : ( (Encode::is_utf8($username) ? $username : Encode::decode_utf8($username)) =~ /\w/ );

    unless ( $user_check ) {
        $self->session->add_error( loc('error.invalid-name=user,type', $username, $validname) );
        $r->log_error ($username . ' is not a valid ' . $validname);
        return $self->_challenge();
    }
    my $auth = Socialtext::Authen->new;
    my $user = Socialtext::User->new( username => $username );

    if ($user && !$user->email_address) {
        $self->session->add_error(loc("error.no-user-email" ));
        $r->log_error ($username . ' has no associated email address');
        return $self->_challenge();
    }

    if ($user and $user->is_deactivated) {
        $r->log_error($username . ' is deactivated');
        $self->session->add_error(loc('info.login-disabled'));
        return $self->_challenge();
    }

    if ($user and $user->requires_email_confirmation) {
        $r->log_error($username . ' requires confirmation');
        return $self->require_email_confirmation_redirect($user->email_address);
    }
    if ($user and $user->requires_password_change) {
        $r->log_error($username . ' requires password change');
        return $self->require_password_change_redirect($user->email_address);
    }
    if ($user and $user->requires_external_id) {
        $r->log_error($username . ' requires external id');
        return $self->require_external_id_redirect($user->email_address);
    }


    unless ($self->{args}{password}) {
        $self->session->add_error(loc('error.invalid-login=name', $validname));
        $r->log_error('Wrong ' . $validname .' or password for ' . $username);
        return $self->_challenge();
    }

    my $check_password = $auth->check_password(
        username => ($username || ''),
        password => $self->{args}{password},
    );

    unless ($check_password) {
        $self->session->add_error(loc('error.invalid-login=name', $validname));
        $r->log_error('Wrong ' . $validname .' or password for ' . $username);
        return $self->_challenge();
    }

    my $cookie_limit = Socialtext::AppConfig->auth_token_hard_limit();
    my $expires = $self->{args}{remember} ? "+${cookie_limit}s" : '';
    Socialtext::Apache::User::set_login_cookie($r, $user->user_id, $expires);

    $user->record_login;

    my $dest = $self->{args}{redirect_to};
    unless ($dest) {
        $dest = "/";
    }

    st_timed_log('info', 'WEB', "LOGIN", $user, {}, Socialtext::Timer->Report);

    if (my $ws_name = $self->{args}{workspace_name}) {
        $self->_add_user_to_workspace($user, $ws_name)
            or return $self->_redirect('/nlw/error.html');
    }

    $self->session->write;
    $self->redirect($dest);
}

# Add a user to a workspace that can "self join". Returns 1 on success.
sub _add_user_to_workspace {
    my ($self, $user, $ws_name) = @_;
    my $ws = Socialtext::Workspace->new( name => $ws_name );
    if ($ws and $user->is_authenticated) {
        if ($ws->has_user($user)) {
            return 1;
        }

        my $can_self_join = $ws->permissions->user_can(
            user       => $user,
            permission => ST_SELF_JOIN_PERM
        );
        if ($can_self_join) {
            $ws->add_user(
                user => $user,
                role => Socialtext::Role->Member(),
            );
            return 1;
        }
        else {
            $self->session->add_error(
                loc("error.self-join-disabled=wiki", $ws_name)
            );
        }
    }
}

sub logout {
    my $self     = shift;
    my $redirect = $self->{args}{redirect_to}
        || Socialtext::AppConfig->logout_redirect_uri();

    Socialtext::Apache::User::unset_login_cookie();

    my $uri = URI->new($redirect);
    if ($uri->scheme) {
        $self->r->header_out(Location => $redirect);
        return REDIRECT;
    }
    else {
       $self->redirect($redirect);
    }
}

sub forgot_password {
    my $self = shift;
    my $r    = $self->r;

    my $forgot_password_uri = $self->{args}{lite} ? '/lite/forgot_password' : '/nlw/forgot_password.html';

    my $username = $self->{args}{username} || '';
    my $user = Socialtext::User->new( username => $username );
    unless ( $user ) {
        $self->session->add_error(loc("error.no-user=name", $username));
        return $self->_redirect($forgot_password_uri);
    }
    elsif ($user->is_deactivated) {
        $self->session->add_error(loc("user.deactivated=name", $username));
        return $self->_redirect($forgot_password_uri);
    }
    elsif ($user->is_externally_sourced) {
        $self->session->add_error(
            loc("error.reset-ldap-password")
        );
        return $self->_redirect($forgot_password_uri);
    }

    my $confirmation = $user->create_password_change_confirmation();
    $confirmation->send;

    my $from_address = 'noreply@socialtext.com';
    $self->session->add_message(
      loc('register.reset-password-sent=email', $user->username) . "\n<p>\n" . loc('info.email-confirmation=from', $from_address) . "\n</p>\n"
    );

    $self->session->save_args( username => $user->username() );
    $self->_challenge();
}

sub register {
    my $self = shift;
    my $r = $self->r;

    my $target_ws_name  = $self->{args}{workspace_name};
    my $redirect_target = $target_ws_name
        ? "/nlw/join.html"
        : '/nlw/register.html';

    unless (Socialtext::AppConfig->self_registration()) {
        $self->session->add_error(loc("error.registration-disabled"));
        return $self->_redirect($redirect_target);
    }

    my $appliance_config = Socialtext::Appliance::Config->new;
    if ($appliance_config->value('captcha_enabled')) {
        # check captcha..

        my $c = Captcha::reCAPTCHA->new;
        my $c_challenge = $self->{args}{recaptcha_challenge_field};
        my $c_response  = $self->{args}{recaptcha_response_field};

        my $c_privkey = $appliance_config->value('captcha_privkey');
        my $result    = $c->check_answer(
            $c_privkey,
            $r->connection->remote_ip,
            $c_challenge,
            $c_response,
        );
        unless ( $result->{is_valid} ) {
            $self->session->add_error(loc("error.captcha"));
            return $self->_redirect($redirect_target, $self->{args});
        }
    }

    my $ws;
    if ($target_ws_name) {
        eval {
            $ws = Socialtext::Workspace->new( name => $target_ws_name);
            my $perms = $ws->permissions;
            if (!$perms->role_can(
                    role => Socialtext::Role->Guest(),
                    permission => ST_SELF_JOIN_PERM
                )) {
                    $self->session->add_error(loc("error.self-join-disabled=wiki", $target_ws_name));
                    return $self->_redirect($redirect_target);
                }
            };
        die $@ if $@;
    }

    my $email_address = $self->{args}{email_address};
    unless ( $email_address ) {
        $self->session->add_error(loc("error.email-required"));
        return $self->_redirect($redirect_target);
    }

    my $user = Socialtext::User->new( email_address => $email_address );
    if ($user) {
        if ( $user->requires_email_confirmation() ) {
            return $self->require_email_confirmation_redirect($email_address);
        }
        elsif ( $user->has_valid_password() ) {
            $self->session->add_message(loc("error.user-exists=email", $email_address));
            $self->session->save_args( email_address => $email_address );

            return $self->_redirect($redirect_target);
        }
    }

    my %args;
    for (qw(password password2)) {
        $args{$_} = $self->{args}{$_} || '';
    }
    for (qw(first_name last_name)) {
        $args{$_} = Socialtext::String::scrub($self->{args}{$_} || '');
    }
    if ( $args{password} and $args{password} ne $args{password2} ) {
        $self->session->add_error(loc('error.password-mismatch'));
    }

    my $is_new_user;
    eval {
        if ($user) {
            $user->update_store(
                password   => $args{password},
                first_name => $args{first_name},
                last_name  => $args{last_name},
            );
        }
        else {
            $user = Socialtext::User->create(
                username      => $email_address,
                email_address => $email_address,
                password      => $args{password},
                first_name    => $args{first_name},
                last_name     => $args{last_name},
                ($ws ? (primary_account_id => $ws->account_id) : ()),
            );
            $is_new_user = 1;
        }
    } unless $self->session->has_errors;
    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        # We don't show them "Username is required" since that field
        # is not on the form.
        $self->session->add_error($_) for grep { ! /Username.+required/i } $e->messages;
    }
    elsif ( $@ ) {
        die $@;
    }

    if ( $self->session->has_errors ) {
        my $redirect = delete $self->{args}{redirect_to};
        $self->session->save_args( %{ $self->{args} } );
        return $self->_redirect($redirect_target);
    }


    $user->create_email_confirmation(workspace_name => $target_ws_name);
    $user->send_confirmation_email;

    $self->session->add_message(loc("register.confirmation-sent=email", $email_address));
    return $self->_challenge();
}

sub confirm_email {
    my $self = shift;
    my $r = $self->r;

    my $hash = $self->{args}{hash};
    return $self->_show_error(
        loc('error.invalid-confirmation-url')
    ) unless $hash;

    my $restriction = $self->_find_restriction_for_hash($r, $hash);
    return $self->_show_error() unless $restriction;
    my $user = $restriction->user;

    if ($restriction->has_expired) {
        $restriction->renew;
        $restriction->send;
        return $self->_show_error(
            loc("error.confirmation-expired")
        );
    }

    if ( ($restriction->restriction_type eq 'password_change')
        or not $user->has_valid_password) {
        $self->session->save_args(
            hash => $hash,
            ($self->{args}{account_for}
                ? (account_for => $self->{args}{account_for}) : ()),
        );
        return $self->_redirect( "/nlw/choose_password.html" );
    }

    # Grab the WS that might be tied to the confirmation, then clear the
    # confirmation; we don't need it any more.
    my $targetws = $restriction->workspace;
    $user->confirm_email_address;

    if ($targetws) {
        $targetws->add_user(user => $user);
        $user->primary_account($targetws->account);
        st_log->info("SELF_JOIN,user:". $user->email_address . "("
            .$user->user_id."),workspace:"
            . $targetws->name . "(" . $targetws->workspace_id . ")"
            . ",".$targetws->account->name
            . "(". $targetws->account->account_id . ")"
        );
    }
    my $address = $user->email_address;
    if ($targetws) {
        $self->session->add_message(loc("login.confirmed=email,wiki", $address, $targetws->title));
    }
    else {
        $self->session->add_message(loc("login.confirmed=email", $address));
    }
    $self->session->save_args( username => $user->username );

    $self->{args}{redirect_to} = $targetws->uri if ($targetws);
    return $self->_challenge();
}

sub choose_password {
    my $self = shift;
    my $r    = $self->r;

    my $hash = $self->{args}{hash};
    return $self->_show_error(
        loc('error.invalid-confirmation-url')
    ) unless $hash;

    my $restriction = $self->_find_restriction_for_hash($r, $hash);
    return $self->_show_error() unless $restriction;
    my $user = $restriction->user;

    my %args;
    $args{$_} = $self->{args}{$_} || '' for (qw(password password2));
    if ( $args{password} and $args{password} ne $args{password2} ) {
        $self->session->add_error(loc('error.password-mismatch'));
    }
    eval { $user->update_store( password   => $args{password} ) };
    if ( my $e = Exception::Class->caught('Socialtext::Exception::DataValidation') ) {
        # We don't show them "Username is required" since that field
        # is not on the form.
        $self->session->add_error($_) for grep { ! /Username.+required/i } $e->messages;
    }

    if ( $self->session->has_errors ) {
        return $self->_redirect("/nlw/choose_password.html?hash=$hash");
    }

    my $expire = $self->{args}{remember} ? '+12M' : '';
    Socialtext::Apache::User::set_login_cookie( $r, $user->user_id, $expire );

    $restriction->clear();
    $user->record_login;

    my $dest = $self->{args}{redirect_to};
    unless ($dest) {
        $dest = "/";
    }

    st_log->info( "LOGIN: " . $user->email_address . " destination: $dest" );

    $self->session->remove('account_for');
    $self->session->write;
    $self->redirect($dest);
}

sub resend_confirmation {
    my $self = shift;

    my $email_address = $self->{args}{email_address};
    unless ($email_address) {
        return $self->_show_error(
            loc("error.email-for-confirmation-required")
        );
    }

    my $user = Socialtext::User->new( email_address => $email_address );
    unless ($user) {
        $self->session->add_error(loc("error.no-such-user=email", $email_address));
        return $self->_challenge();
    }

    my $confirmation = $user->email_confirmation;
    unless ($confirmation) {
        $self->session->add_error(loc("error.already-confirmed=email", $email_address));
        return $self->_challenge();
    }

    $confirmation->renew;
    $confirmation->send;

    $self->session->add_error(loc('error.confirmation-resent'));
    return $self->_challenge();
}

sub resend_password_change {
    my $self = shift;

    my $email_address = $self->{args}{email_address};
    unless ($email_address) {
        return $self->_show_error(
            loc("error.email-missing-for-password-change")
        );
    }

    my $user = Socialtext::User->new( email_address => $email_address );
    unless ($user) {
        $self->session->add_error(loc("error.no-such-user=email", $email_address));
        return $self->_challenge();
    }

    my $confirmation = $user->password_change_confirmation;
    unless ($confirmation) {
        $self->session->add_error(
            loc("error.password-exists-for=email", $email_address)
        );
        return $self->_challenge();
    }

    $confirmation->renew;
    $confirmation->send;

    $self->session->add_error(
        loc("info.email-sent-for-password-change")
    );
    return $self->_challenge();
}

sub require_email_confirmation_redirect {
    my $self  = shift;
    my $email = shift;
    return $self->_error_redirect(
        type          => 'requires_confirmation',
        email_address => $email,
    );
}

sub require_password_change_redirect {
    my $self  = shift;
    my $email = shift;
    return $self->_error_redirect(
        type          => 'requires_password_change',
        email_address => $email,
    );
}

sub require_external_id_redirect {
    my $self  = shift;
    my $email = shift;
    return $self->_error_redirect(
        type          => 'requires_external_id',
        email_address => $email,
    );
}

sub _error_redirect {
    my $self = shift;
    my %p = @_;

    $self->session->save_args(username => $p{email_address});
    $self->session->add_error( {
        type => $p{type},
        args => {
            email_address => $p{email_address},
            redirect_to   => $self->{args}{redirect_to} || '',
        }
    } );
    return $self->_challenge();
}

sub _redirect {
    my $self            = shift;
    my $uri             = shift;
    my $formfields      = shift;
    my $redirect_to     = $self->{args}{redirect_to};
    my $oldformvarquery = '';
    if ($formfields) {
        $oldformvarquery = join(";",
            map { $_ . "=" . uri_escape_utf8($formfields->{$_})} grep {!/^(recaptcha_|password|redirect_to)/} keys %{$formfields}
        );
    }
    if ($redirect_to) {
        $uri .= ($uri =~ m/\?/ ? ';' : '?')
              . "redirect_to=" . uri_escape_utf8($redirect_to);
    }
    if ($oldformvarquery) {
        $uri .= ($uri =~ m/\?/ ? ';' : '?')
              . $oldformvarquery;
    }

    $self->redirect($uri);
}

sub _challenge {
    my $self = shift;

    eval {
        Socialtext::Challenger->Challenge(
            request  => $self->r,
            redirect => $self->{args}{redirect_to},
        );
    };
    if (my $e = $@) {
        if (Exception::Class->caught('Socialtext::WebApp::Exception::Redirect')) {
            my $location = $e->message;
            return $self->redirect($location);
        }
        st_log->error($e);
    }

    $self->session->add_error(
        loc("error.challenger-redirect-failed")
    );
    return $self->redirect('/nlw/error.html');
}

sub _load_main {
    my $self = shift;
    my $user = $self->authenticate($self->{r}) || Socialtext::User->Guest();
    my $ws   = Socialtext::NoWorkspace->new();
    my $main = Socialtext->new();
    $main->load_hub(
        current_user      => $user,
        current_workspace => $ws,
    );
    $main->hub->registry->load();
    return $main;
}

sub _load_hub {
    my $self = shift;
    my $main = $self->_load_main();
    return $main->hub();
}

sub _default_template_vars {
    my $self = shift;
    my $hub  = $self->_load_hub();
    return (
        $hub->helpers->global_template_vars,
        loc            => \&loc,
        errors         => [ $self->session->errors ],
        messages       => [ $self->session->messages ],
        static_path    => Socialtext::Helpers::static_path(),
        skin_uri       => sub {
            Socialtext::Skin->new(name => shift)->skin_uri
        },
        paths          => $hub->skin->template_paths,
        st_version     => $Socialtext::VERSION,
        support_address => Socialtext::AppConfig->support_address,
    );
}

sub _show_error {
    my $self  = shift;
    my $error = shift;

    $self->session->add_error($error) if ($error);

    my $hub = $self->_load_hub();
    my $repl_vars = {
        $self->_default_template_vars,
    };
    return $self->render_template(
        $self->{r}, 'authen/error.html', $repl_vars,
    );
}

sub _find_restriction_for_hash {
    my $self = shift;
    my $r    = shift;
    my $hash = shift;

    # now in order to deal with email clients that might have decoded %2B to '+' for us
    # we need to change spaces in the hash back to '+' signs.
    # see: https://rt.socialtext.net:444/Ticket/Display.html?id=26571
    $hash =~ s/ /+/g;

    my $restriction = Socialtext::User::Restrictions->FetchByToken($hash);
    unless ($restriction) {
        $self->session->add_error(loc("error.no-such-pending-confirmation"));
        $self->session->add_error( "<br/>(" . $r->uri . "?" . $r->args . ")" );
        $r->log_error ("no confirmation hash for: [" . $r->uri . "?" . $r->args . "]" );
    }
    return $restriction;
}

1;
