package Socialtext::Events::Recorder;
# @COPYRIGHT@
use warnings;
use strict;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::JSON qw/encode_json decode_json/;
use Socialtext::Encode;

sub new {
    my $class = shift;
    $class = ref($class) || $class;
    return bless {}, $class;
}

sub _unbox_objects {
    my $self = shift;
    my $p = shift;

    # subject
    _translate_ref_to_id($p, 'actor' => 'user_id');

    # objects
    _translate_ref_to_id($p, 'page' => 'id');
    _translate_ref_to_id($p, 'person' => 'user_id');

    # context
    _translate_ref_to_id($p, 'workspace' => 'workspace_id');
    _translate_ref_to_id($p, 'target_workspace' => 'workspace_id');
    _translate_ref_to_id($p, 'target_page' => 'id');
    _translate_ref_to_id($p, 'group' => 'group_id');

    # signal
    _translate_ref_to_id($p, 'signal' => 'signal_id');
}

sub _validate_insert_params {
    my $self = shift;
    my $p = shift;

    my $class = $p->{event_class};
    
    for (qw/at event_class action actor/) {
        die "$_ parameter is missing" 
            unless defined $p->{$_};
    }

    die "event_class must be lower-case alpha-with-underscoes"
        unless $class =~ /^[a-z_]+$/;

    unless ($self->{_checked_context}) {
        $@ = undef;
        eval { decode_json($p->{context}) } if $p->{context};
        die "context isn't legal json: $p->{context}" if ($@);
    }

    if ($class eq 'page') {
        die "page parameter is missing for a page event" 
            unless $p->{page};
        die "workspace parameter is missing for a page event" 
            unless $p->{workspace};
    }
    elsif ($class eq 'person') {
        die "person parameter is missing for a person event"
            unless $p->{person};
    }
    elsif ($class eq 'signal') {
        die "signal parameter is missing for signal event"
            unless $p->{signal};
        if ($p->{action} eq 'signal'
            and not(
                $p->{_checked_context} &&
                defined $p->{_checked_context}{body} &&
                length $p->{_checked_context}{body}
            )
        ) {
            die "body missing from context for signal event";
        }
    }
    elsif ($class eq 'group') {
        die "group parameter is missing for group event" unless $p->{group};
    }
    else {
        die "must specify a both a page and a workspace OR leave both blank"
            if ($p->{page} xor $p->{workspace});
    }

    die "can't save events for untitled_page"
        if ($p->{page} && $p->{page} eq 'untitled_page');

    die "can't save events for untitled_spreadsheet"
        if ($p->{page} && $p->{page} eq 'untitled_spreadsheet');
}

=head2 record_event()

This method logs an event to the event storage system.  Parameters:

=cut

sub record_event {
    my $self = shift;
    my $p = shift || die 'Requires Event parameters';

    #warn "EVENT: $p->{event_class}:$p->{action}\n";

    $p->{at} ||= $p->{timestamp}; # compatibility alias
    $p->{at} ||= "now";

    $self->_unbox_objects($p);

    local $p->{_checked_context};
    if (ref $p->{context}) {
        my $ctx = $p->{context};
        for my $key (keys %$ctx) {
            next if ref $ctx->{$key};
            $ctx->{$key} = Socialtext::Encode::ensure_is_utf8($ctx->{$key});
        }
        $p->{context} = encode_json($ctx);
        $p->{_checked_context} = $ctx;
    }

    eval {
        $self->_validate_insert_params($p);
    };
    if ($@) {
        die "Event validation failure: $@";
    }

    # order: column, parameter, placeholder
    my @ins_map = (
        [ at                => $p->{at},          '?::timestamptz', ],
        [ event_class       => $p->{event_class}, '?', ],
        [ action            => $p->{action},      '?', ],
        [ actor_id          => $p->{actor},       '?', ],
        [ person_id         => $p->{person},      '?', ],
        [ page_id           => $p->{page},        '?', ],
        [ page_workspace_id => $p->{workspace},   '?', ],
        [ signal_id         => $p->{signal},      '?', ],
        [ tag_name          => $p->{tag_name},    '?', ],
        [ context           => $p->{context},     '?', ],
        [ group_id          => $p->{group},       '?', ],
    );

    my $fields = join(', ', map {$_->[0]} @ins_map);
    my @values = map {$_->[1]} @ins_map;
    my $placeholders = join(', ', map {$_->[2]} @ins_map);
    my $table = $p->{action} eq 'view' ? 'view_event' : 'event';

    my $sql = "INSERT INTO $table ( $fields ) VALUES ( $placeholders )";
    sql_execute($sql, @values);

    return; # don't leak the $sth returned from sql_execute
}

sub _translate_ref_to_id {
    my ($p, $key, $id_method) = @_;
    my $ref = $p->{$key};
    return unless ref $ref;
    return unless $ref->can($id_method);
    $p->{$key} = $ref->$id_method;
}

1;
