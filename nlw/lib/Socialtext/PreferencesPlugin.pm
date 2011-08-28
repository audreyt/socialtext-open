# @COPYRIGHT@
package Socialtext::PreferencesPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( field );
use Socialtext::File;
use Socialtext::JSON qw/decode_json encode_json/;
use Socialtext::SQL qw(:exec :txn);
use Socialtext::Log qw/st_log/;
use Socialtext::Cache;
use Socialtext::UserSet qw/:const/;

sub class_id { 'preferences' }
field objects_by_class => {};

sub _cache { Socialtext::Cache->cache('user_workspace_prefs') }

sub load {
    my $self = shift;
    my $values = shift;
    my $prefs = $self->hub->registry->lookup->preference;
    for (sort keys %$prefs) {
        my $array = $prefs->{$_};
        my $class_id = $array->[0];
        my $hash = {@{$array}[1..$#{$array}]}
          or next;
        next unless $hash->{object};
        my $object = $hash->{object}->clone;
        $object->value($values->{$_});
        $object->hub($self->hub);
        push @{$self->objects_by_class->{$class_id}}, $object;
        field($_);
        $self->$_($object);
    }
    return $self;
}

sub new_for_user {
    my $self       = shift;
    my $maybe_user = shift;
    my $user       = Socialtext::User->Resolve($maybe_user);
    my $email      = $user->email_address();

    # This caching does not seem to be well used, but *is* apparently
    # necessary (removing it causes failures from side-affects caused by
    # calling 'new_preferences' repeatedly).
    return $self->{per_user_cache}{$email} if $self->{per_user_cache}{$email};
    my $values = $self->_values_for_user($user);
    return $self->{per_user_cache}{$email} = $self->new_preferences($values);
}

sub _values_for_user {
    my $self = shift;
    my $user = shift;

    my $prefs = $self->_load_all_for_user($user);
    return +{ map %$_, values %$prefs };
}

sub _load_all_for_user {
    my $self  = shift;
    my $user  = shift;
    return {} unless $user;

    my $wksp  = $self->hub->current_workspace;
    my $email = $user->email_address;

    my $global = $self->Global_user_prefs($user);
    return $global unless $wksp->real;

    my $prefs = $self->Workspace_user_prefs($user, $wksp);

    # global prefs override local.
    $prefs->{$_} = $global->{$_} for keys %$global;

    return $prefs;
}

sub Workspace_user_prefs {
    my $class_or_self = shift;
    my $user          = shift;
    my $wksp          = shift or die "workspace required";
    my $email         = $user->email_address;

    return {} unless $wksp->real;
    my $wksp_id = $wksp->workspace_id;

    my $cache_key = join ':', $wksp->name, $email;
    my $cache = $class_or_self->_cache;
    my $cached_values = $cache->get($cache_key);
    return $cached_values if $cached_values;

    my $blob = sql_singlevalue(qq{
        SELECT pref_blob
          FROM user_workspace_pref
         WHERE user_id = ?
           AND workspace_id = ?
    }, $user->user_id, $wksp_id);
    return {} unless $blob;

    my $prefs = eval { decode_json($blob); };
    if (my $e = $@) {
        st_log->error("failed to load prefs '${email}:$wksp_id': $@");
        $prefs = {};
    }

    $cache->set($cache_key => $prefs);
    return $prefs;
}

sub Global_user_prefs {
    my $class_or_self = shift;
    my $user          = shift;

    my $cache_key = join ':', 'global-prefs', $user->email_address;
    my $cache = $class_or_self->_cache;
    my $cached_values = $cache->get($cache_key);
    return $cached_values if $cached_values;

    my $prefs = $user->prefs->all_prefs();
   
    $cache->set($cache_key => $prefs);
    return $prefs;
}


sub new_preferences {
    my $self   = shift;
    my $values = shift;
    my $new    = bless {}, ref $self;
    $new->hub($self->hub);
    $new->load($values);
    return $new;
}

sub new_preference {
    my $self = shift;
    Socialtext::Preference->new(@_);
}

sub new_dynamic_preference {
    my $self = shift;
    Socialtext::Preference::Dynamic->new(@_);
}

sub store {
    my $self       = shift;
    my $maybe_user = shift;
    my $class_id   = shift;
    my $new_prefs  = shift;

    my $user  = Socialtext::User->Resolve($maybe_user);
    return unless $user;

    if ( $self->hub->$class_id->pref_scope eq 'workspace' ) {
        my $ws = $self->hub->current_workspace;
        my $prefs = $self->Workspace_user_prefs($user, $ws);
        $prefs->{$class_id} = $new_prefs;
        $self->Store_workspace_user_prefs($user, $ws, $prefs);
    }
    else {
        my $prefs = $self->Global_user_prefs($user);
        $prefs->{$class_id} = $new_prefs;
        $self->Store_global_user_prefs($user, $prefs);
    }
}

sub Store_global_user_prefs {
    my $class_or_self = shift;
    my $user          = shift;
    my $prefs         = shift;

    $user->prefs->save($prefs);
    $class_or_self->_cache->clear();
}

sub Store_workspace_user_prefs {
    my $class_or_self = shift;
    my $user          = shift;
    my $workspace     = shift;
    my $prefs         = shift;

    return unless $workspace->real;

    my @keys = ($user->user_id, $workspace->workspace_id);
    my $json = encode_json($prefs);
    sql_txn {
        sql_execute('
            DELETE FROM user_workspace_pref
             WHERE user_id = ? AND workspace_id = ?
             ', @keys,
         );
        sql_execute('
            INSERT INTO user_workspace_pref (user_id, workspace_id, pref_blob)
            VALUES (?,?,?)
            ', @keys, $json
        );
    };

    $class_or_self->_cache->clear();
}

sub Users_with_no_prefs_for_ws {
    my $class_or_self = shift;
    my $ws_id = shift;

    my $user_ids = sql_execute( qq{
        SELECT DISTINCT(from_set_id) as user_id
            FROM user_set_path
            WHERE from_set_id }. PG_USER_FILTER .qq{
              AND into_set_id = ?
              AND from_set_id NOT IN (
                SELECT DISTINCT(user_id) FROM user_workspace_pref
                   WHERE workspace_id = ?
                 )
        }, $ws_id + WKSP_OFFSET, $ws_id);
    return [
        map { $_->[0] }
        @{ $user_ids->fetchall_arrayref }
    ];
};

sub Prefblobs_for_ws {
    my $class_or_self = shift;
    my $ws_id = shift;

    # This may return users that are not a member of the workspace anymore.
    # Callers should have appropriate checks in place.
    my $prefs = sql_execute( qq{
    SELECT user_id, pref_blob FROM user_workspace_pref
       WHERE workspace_id = ?
         AND user_id IN (
            SELECT DISTINCT(from_set_id) FROM user_set_path
                WHERE from_set_id }. PG_USER_FILTER .qq{
                  AND into_set_id = ?
         )
    }, $ws_id, $ws_id + WKSP_OFFSET);
    return $prefs->fetchall_arrayref;
}

package Socialtext::Preference;

use base 'Socialtext::Base';

use Class::Field qw( field );
use Socialtext::l10n qw/loc/;

field 'id';
field 'name';
field 'description';
field 'query';
field 'type';
field 'choices';
field 'default';
field 'default_for_input';
field 'handler';
field 'owner_id';
field 'size' => 20;
field 'edit';
field 'new_value';
field 'error';
field layout_over_under => 0;

sub new {
    my $class = shift;
    my $owner = shift;
    my $self = bless {}, $class;
    my $id = shift || '';
    $self->id($id);
    my $name = $id;
    $name =~ s/_/ /g;
    $name =~ s/\b(.)/\u$1/g;
    $self->name($name);
    $self->query("$name?");
    $self->type('boolean');
    $self->default(0);
    $self->handler("${id}_handler");
    $self->owner_id($owner->class_id);
    return $self;
}

sub value {
    my $self = shift;
    return $self->{value} = shift
      if @_;
    return defined $self->{value} 
      ? $self->{value}
      : $self->default;
}

sub value_label {
    my $self = shift;
    my $choices = $self->choices
      or return '';
    return ${ {@$choices} }{$self->value} || '';
}
    
sub form_element {
    my $self = shift;
    my $type = $self->type;
    return $self->$type;
}

sub input {
    my $self = shift;
    my $name = $self->owner_id . '__' . $self->id;
    my $value = $self->value ||
      # support lazy eval...
      ( ref($self->default_for_input) eq 'CODE' ? $self->default_for_input->($self) : $self->default_for_input ) ||
      $self->value;
    my $size = $self->size;
    return <<END
<input type="text" name="$name" value="$value" size="$size" />
END
}

sub boolean {
    my $self = shift;
    my $name = $self->owner_id . '__' . $self->id;
    my $value = $self->value;
    my $checked = $value ? 'checked="checked"' : '';
    return <<END
<input type="checkbox" name="$name" value="1" $checked />
<input type="hidden" name="$name-boolean" value="0" $checked />
END
}

sub radio {
    my $self = shift;
    my $i = 1;
    my @choices = map { loc($_) } @{$self->choices};
    my @values = grep {$i++ % 2} @choices;
    my $value = $self->value;

    $self->hub->template->process('preferences_radio.html',
        name => $self->owner_id . '__' . $self->id,
        values => \@values,
        default => $value,
        labels => { @choices },
    );
}

sub pulldown {
    my $self = shift;
    my $i = 1;
    my @choices = map { loc($_) } @{$self->choices};
    my @values = grep {$i++ % 2} @choices;
    my $value = $self->value;
    $self->hub->template->process('preferences_pulldown.html',
        name => $self->owner_id . '__' . $self->id,
        values => \@values,
        default => $value,
        labels => { @choices },
    );
}

sub hidden {
    my $self = shift;
    my $name = $self->owner_id . '__' . $self->id;
    my $value = $self->value;
    return <<END
<input type="hidden" name="$name" value="$value" />
END
}

package Socialtext::Preference::Dynamic;
use base 'Socialtext::Preference';

use Class::Field qw( field );
use Socialtext::l10n qw/loc/;

field 'choices_callback';

sub choices { shift->_generic_callback("choices", @_) }

sub _generic_callback {
    my ($self, $name, @args) = @_;
    my $method = "${name}_callback";
    if ($self->$method) {
        return $self->$method->($self, @args);
    } else {
        $method = "SUPER::${name}";
        return $self->$method(@args);
    }
}

1;
