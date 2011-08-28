package Socialtext::Job::WebHook;
# @COPYRIGHT@
use Moose;
use LWP::UserAgent;
use Socialtext::Log qw/st_log/;
use Socialtext::JSON qw/encode_json/;
use Fatal qw/open close/;
use URI;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

override 'max_retries' => sub { 5 };
override 'grab_for'    => sub { 600 };
override 'retry_delay' => sub { 600 };

sub do_work {
    my $self = shift;

    my $args = $self->arg;
    my $payload = ref($args->{payload}) ? encode_json($args->{payload})
                                        : $args->{payload};

    # "box-car" webhook calls into an array, even though we currently
    # send them out one at a time
    $payload = '[' . $payload . ']';

    # For testing
    if (my $file = $ENV{ST_WEBHOOK_TO_FILE}) {
        open(my $fh, ">>$file");
        print $fh "URI: $args->{hook}{url}\n$payload\n\n";
        close $fh;
        $self->completed();
        return;
    }

    my $response = $self->_make_webhook_request($args->{hook}, $payload);

    st_log()->info("Triggered webhook $args->{hook}{id} - $args->{hook}{url}: "
                    . $response->status_line);

    if ($response->code =~ m/^2\d\d$/) {
        $self->completed();
    }
    else {
        $self->failed($response->status_line, 255);
    }
}

sub _make_webhook_request {
    my $self = shift;
    my $hook = shift;
    my $payload = shift;

    # Set the timeout to be shorter than how long we grab the job for
    my $ua = LWP::UserAgent->new(timeout => 300);
    $ua->agent('Socialtext/WebHook');

    (my $uri_base = $hook->{url}) =~ s/\?.+//;
    my $uri = URI->new($hook->{url});

    return $ua->post($uri_base, [ $uri->query_form, json_payload => $payload ]);
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
