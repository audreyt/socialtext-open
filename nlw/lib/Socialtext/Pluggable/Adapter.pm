package Socialtext::Pluggable::Adapter;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::l10n '__';

our @libs;
our $AUTOLOAD;
my %hooks;
my %hook_types;

use base 'Socialtext::Plugin';
use Carp;
use Fcntl ':flock';
use File::chdir;
use Socialtext::HTTP ':codes';
use Module::Pluggable search_path => ['Socialtext::Pluggable::Plugin'],
                      search_dirs => \@libs,
                      require => 0,
                      sub_name => '_plugins';
use Socialtext::Pluggable::WaflPhrase;
use List::Util qw(first);
use Memoize;
use Class::Field qw(const);

const class_id => 'pluggable';
const class_title => __('class.pluggable');

sub plugins { grep !/SUPER$/, _plugins() } # grep prevents a Pluggable bug?
BEGIN { memoize('plugins', NORMALIZER => sub { '' } ) } # memoize ignores args

# These hook types are executed only once, all other types are called as many
# times as they are registered
my %ONCE_TYPES = (
    action => 1,
    wafl   => 1,
    root   => 1,
);

BEGIN {
    # This is still needed for dev-env -- Do Not Delete!
    require Socialtext::AppConfig;
    our $code_base = Socialtext::AppConfig->code_base;
    push @INC, glob("$code_base/plugin/*/lib");

    for my $plugin (__PACKAGE__->plugins) {
        eval "require $plugin";
        Carp::confess "Error loading Pluggable plugin '$plugin': $@" if $@;
    }
}

# plugins should have been loaded into perl above
for my $plugin (__PACKAGE__->plugins) {
    eval { $plugin->register; };
    Carp::confess "Error registering plugin '$plugin': $@" if $@;
}

{
    # $main Needs to be in global scope so it stays around for the life of the
    # request.  This is due to Class::Field's -weak reference from the hub to
    # the $main.
    my $main;
    sub make_hub {
        my ($self,$user,$ws) = @_;
        $main = Socialtext->new;
        $main->load_hub(
            current_user => $user,
            current_workspace => $ws || Socialtext::NoWorkspace->new,
        );
        $main->hub->registry->load;
        $main->debug;
        $self->hub( $self->{made_hub} = $main->hub );
    }
}

sub _CallPluginClassMethod {
    my $class   = shift;
    my $method = shift;
    my $plugin_name = shift;

    my $adapter = $class->new;
    my @plugins = grep { $_->name eq $plugin_name } $adapter->plugins;
    $_->$method(@_) for grep {$_->can($method)} @plugins;
}

sub EnsureRequiredDataIsPresent {
    my $class   = shift;
    my $adapter = $class->new;
    $_->EnsureRequiredDataIsPresent(@_) 
        for grep {$_->can('EnsureRequiredDataIsPresent')} $adapter->plugins;
}

sub EnablePlugin {
    my $class   = shift;
    $class->_CallPluginClassMethod('EnablePlugin',@_);
}

sub DisablePlugin {
    my $class   = shift;
    $class->_CallPluginClassMethod('DisablePlugin',@_);
}

sub make {
    my $class = shift;
    my $dir = Socialtext::File::catdir(
        Socialtext::AppConfig->code_base(),
        'plugin',
    );
    for my $plugin ($class->plugins) {
        my $name = $plugin->name;
        local $CWD = "$dir/$name";
        next unless -f 'Makefile';

        my $semaphore = "$dir/build-semaphore";
        open( my $lock, ">>", $semaphore )
            or die "Could not open $semaphore: $!\n";
        flock( $lock, LOCK_EX )
            or die "Could not get lock on $semaphore: $!\n";
        system( 'make', 'all' ) and die "Error calling make in $dir/$name: $!";
        close($lock);
    }
}

sub register {
    my ($self,$registry) = @_;

    for my $plugin ($self->plugins) {
        for my $hook ($plugin->hooks) {
            # this hook could have been "registered" before;  avoid
            # registering it again here
            next if $hook->{name} eq 'nlw.set_up_data';

            my ($type, @parts) = split /\./, $hook->{name};

            if ($type eq 'wafl') {
                $registry->add(
                    'wafl', $parts[0], 'Socialtext::Pluggable::WaflPhrase',
                );
            }
            elsif ($type eq 'action') {
                no strict 'refs';
                my $class = ref $self;
                my $action = $parts[0];
                my $sub = "${class}::$action";

                {
                    no warnings 'redefine';
                    *{$sub} = sub { return $_[0]->hook($hook->{name}) };
                }
                $registry->add(action => $action);
            }

            $hook->{type} = $type;

            push @{$hook_types{$type}}, $hook;
            push @{$hooks{$hook->{name}}}, $hook;
        }
    }

    $self->hook('nlw.start');
}

sub plugin_list {
    my ($class_or_self, $name) = @_;
    return map { $_->name } $class_or_self->plugins;
}

sub plugin_exists {
    my ($class_or_self, $name) = @_;
    my $match = $class_or_self->plugin_class($name);
    return $match ? 1 : 0;
}

sub plugin_class {
    my ($class_or_self, $name) = @_;
    my $match = first {$_->name eq $name} $class_or_self->plugins;
    return $match;
}

sub plugin_object {
    my ($self, $class) = @_;
    $class = $self->plugin_class($class) unless $class =~ m{::};
    my $plugin = $self->{_plugins}{$class} ||= $class->new;
    $plugin->rest( $self->{_rest_handler} ) if $self->{_rest_handler};

    unless ($plugin->hub) {
        $self->make_hub($self->rest->user) unless $self->hub;
        $plugin->hub($self->hub);
    }

    return $plugin;
}

sub account_preferences {
    my ($self, %params) = @_;
    my $account       = $params{account};
    my $with_defaults = $params{with_defaults};

    my %defaults = ();
    # Build up the default preferences before loading actual prefs from the DB
    if ($with_defaults) {
        %defaults = map { $_->[0] => $_->[1] } grep { %{$_->[1]} }
                    map { [$_->name => $_->DefaultAccountPluginPrefs] }
                    $self->plugins;
    }

    my $table = Socialtext::PrefsTable->new(
        table    => 'user_set_plugin_pref',
        identity => {
            user_set_id => $account->user_set_id
        },
        defaults => \%defaults,
    );

    my $data = $table->get;
    while (my ($plugin, $prefs) = each %$data) {
        my $class = $self->plugin_class($plugin);
        $class->LimitAccountPluginPrefs($prefs);
    }

    return $data;
}

sub registered {
    my ($self, $name, $config) = @_;
    if ( my $hooks = $hooks{$name} ) {
        return 0 unless ref $hooks eq 'ARRAY';
        for my $hook (@$hooks) {
            my $plugin = $self->plugin_object($hook->{class});
            return 1 if $plugin->is_hook_enabled($name, $config);
        }
    }
    return 0;
}

sub content_types {
    my $self = shift;
    my %ct;
    for my $plug_class ($self->plugins) {
        my $plugin = $self->plugin_object($plug_class);
        if (my $types = $plug_class->content_types) {
            if ($plugin->is_hook_enabled) {
                $ct{$_} = $types->{$_} for keys %$types;
            }
        }
    }
    return \%ct;
}

sub hooked_template_vars {
    my $self = shift;
    return if $self->hub->current_user->is_guest();
    my %vars;
    my $tt_hooks = $hook_types{template_var} || [];
    for my $hook (@$tt_hooks) {
        my $name = $hook->{name};
        my ($key) = $name =~ m{template_var\.(.*)};

        # lazy call the template variables, for performance.
        my $cache_val;
        $vars{$key} = sub { $cache_val ||= $self->hook($name) };
    }
    $vars{content_types} = $self->content_types;
    return %vars;
}

sub hook_error {
    my $self = shift;
    return $self->{hook_error};
}


sub hook {
    my ( $self, $name, $args, $config ) = @_;

    if ($args and ref $args ne 'ARRAY') {
        croak "hook arguments must be passed by reference!";
    }

    my @output;
    if ( my $hooks = $hooks{$name} ) {
        return unless ref $hooks eq 'ARRAY';
        for my $hook (sort { $a->{priority} <=> $b->{priority} } @$hooks) {
            my $method = $hook->{method};
            my $plugin = $self->plugin_object($hook->{class});
            my $type = $hook->{type};

            my $enabled = $plugin->is_hook_enabled($name, $config);
            next unless $enabled;
                         
            eval {
                local $plugin->{_action_plugin} =
                    ($name =~ /^action\./) ? $plugin->name : undef;
                $plugin->declined(undef);
                $plugin->last($ONCE_TYPES{$type});
                my $results = $plugin->$method(@$args);
                if ($plugin->declined) {
                    $plugin->last(undef);
                }
                else {
                    push @output, $results;
                }
            };
            if ($@) {
                (my $err = $@) =~ s/\n.+//sm;
                warn $@;
                $self->{hook_error} = $err;
                return;
            }

            last if $plugin->last;
        }
    }
    return @output == 1 ? $output[0] : join("\n", grep {defined} @output);
}

1;
