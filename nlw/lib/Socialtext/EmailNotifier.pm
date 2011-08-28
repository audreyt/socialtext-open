# @COPYRIGHT@
package Socialtext::EmailNotifier;
use Moose;
use Readonly;
use Socialtext::AppConfig;
use Socialtext::Validate qw( validate PLUGIN_TYPE ARRAYREF_TYPE SCALAR_TYPE HASHREF_TYPE);
use Socialtext::l10n qw(system_locale);
use Socialtext::EmailSender::Factory;

our $VERSION = '0.01';

=head1 SYNOPSIS

    my $email_notifier = Socialtext::EmailNotifier->new();

=head1 DESCRIPTION

An object used for shared email notification methods.

=cut

{
    Readonly my $spec => {
        user          => HASHREF_TYPE,
        pages         => ARRAYREF_TYPE,
        from          => SCALAR_TYPE,
        subject       => SCALAR_TYPE,
        vars          => HASHREF_TYPE,
        text_template => SCALAR_TYPE,
        html_template => SCALAR_TYPE,
    };

    sub send_notifications {
        my $self = shift;
        my %p    = validate( @_, $spec );

        my $renderer = Socialtext::TT2::Renderer->instance();

        $p{vars}{appconfig} = Socialtext::AppConfig->instance();

        my $text_body = $renderer->render(
            template => $p{text_template},
            vars     => $p{vars},
        );

        my $html_body = $renderer->render(
            template => $p{html_template},
            vars     => $p{vars},
        );

        my $locale = system_locale();
        my $email_sender = Socialtext::EmailSender::Factory->create($locale);
        $email_sender->send(
            from      => $p{from},
            to        => $p{user}->name_and_email,
            subject   => $p{subject},
            text_body => $text_body,
            html_body => $html_body,
        );
    }
}

1;
