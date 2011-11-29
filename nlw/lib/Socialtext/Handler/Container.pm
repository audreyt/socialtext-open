package Socialtext::Handler::Container;
# @COPYRIGHT@
use Moose::Role;
use Socialtext::Workspace;
use Socialtext::JSON qw(encode_json decode_json);
use Exception::Class;
use Socialtext::AppConfig;
use Socialtext::Gadgets::Container;
use Socialtext::Gadgets::Util qw(share_path);
use namespace::clean -except => 'meta';

our $prod_ver = Socialtext->product_version;
our $code_base = Socialtext::AppConfig->code_base;

use constant 'entity_name' => 'Container';

with 'Socialtext::Handler::Base';
requires '_build_container';

has 'container' => (
    is => 'ro', isa => 'Socialtext::Gadgets::Container',
    lazy_build => 1,
);

sub DELETE {
    my $self = shift;
    $self->if_authorized_to_edit(sub {
        $self->container->delete;
        return '';
    });
}

sub if_authorized_to_view {
    my ($self, $cb) = @_;
    return $self->not_authenticated unless $self->rest->user->is_authenticated;
    return $self->not_found unless $self->container;
    return $self->forbidden
        unless $self->rest->user->can_use_plugin($self->container->plugin);
    return $cb->();
}

sub if_authorized_to_edit {
    my ($self, $cb) = @_;
    return $self->if_authorized_to_view($cb);
}

sub get_html {
    my $self = shift;
    $self->if_authorized_to_view(sub {
        my $query = $self->rest->query;
        if ($query->param('add_widget')) {
            $self->if_authorized_to_edit(sub {
                return $self->install_gadget;
            });
        }
        elsif ($query->param('clear')) {
            $self->if_authorized_to_edit(sub {
                $self->container->delete_gadgets;
                return $self->redirect($self->uri);
            });
        }
        elsif ($query->param('reset')) {
            $self->if_authorized_to_edit(sub {
                $self->container->delete;
                return $self->redirect($self->uri);
            });
        }
        else {
            $self->unless_authen_needs_renewal(sub {
                return $self->render_template($self->container->view_template, {
                    container => $self->container->template_vars
                });
            } );
        }
    });
}

sub POST_gadget {
    my $self = shift;
    warn $self->rest->getContent;
    $self->if_authorized_to_edit(sub {
        my $data = decode_json($self->rest->getContent);
        my $ginstance = $self->container->install_gadget(%$data);
        return encode_json($self->container->gadget_vars($ginstance));
    });
}

sub install_gadget {
    my $self = shift;
    my %params =$self->rest->query->Vars;
    $self->if_authorized_to_edit(sub {
        $self->container->install_gadget(%params);
        return $self->redirect($self->uri);
    });
}

sub PUT_layout {
    my $self = shift;
    $self->if_authorized_to_edit(sub {
        my %gadgets = map { $_->gadget_instance_id => 1 }
                      @{$self->container->gadgets};

        my $data = decode_json($self->rest->getContent);

        my $business_admin = $self->rest->user->is_business_admin;
        my @positions;

        my $cols = $data->{gadgets};

        for my $x (0 .. $#$cols) {
            my $col = $cols->[$x];
            for my $y (0 .. $#$col) {
                my $g = $col->[$y];

                my $gadget;
                if (!$g->{install} and delete $gadgets{$g->{instance_id}}) {
                    # Existing widget, so move it
                    $gadget = $self->container->get_gadget_instance(
                        $g->{instance_id}
                    );
                }
                else {
                    # Install the new gadget
                    $gadget = $self->container->install_gadget(
                        src => $g->{src},
                        gadget_id => $g->{gadget_id},
                        fixed => $g->{fixed},
                        class => $g->{class}
                    );

                    # Update the gadget_instance_id now that it's installed
                    $g->{gadget_instance_id} = $gadget->gadget_instance_id;
                }
            
                # Move this widget to it's position
                push @positions, [$gadget, $x, $y, $g->{minimized}];

                # set preferences if they're being passed as part of the layout
                $gadget->set_preferences($g->{preferences})
                    if $g->{preferences};

                if (exists $g->{fixed}) {
                    $gadget->fix if $g->{fixed} and !$gadget->fixed;
                    $gadget->unfix if !$g->{fixed} and $gadget->fixed;
                }
            }
        }

        for my $instance_id (keys %gadgets) {
            my $gadget = $self->container->get_gadget_instance($instance_id);
            $gadget->free_children;
            $gadget->delete;
        }

        for my $gadget_position (@positions) {
            my $gadget = shift @$gadget_position;
            $gadget->position(@$gadget_position)
        }

        # Pass back $data so it can be used `around` PUT_layout
        return $data;
    });
}

sub GET_default_gadgets {
    my $self = shift;
    my @gadgets;
    my $instance_id = 1;
    my @cols;
    for my $gadget_info ($self->container->default_gadgets) {
        $cols[$gadget_info->{col}] ||= 0;
        my $row = $cols[$gadget_info->{col}]++;

        my $instance = Socialtext::Gadgets::GadgetInstance->new(
            spec => Socialtext::Gadgets::Gadget->Fetch(%$gadget_info),
            container_id => $self->container->container_id,
            container => $self->container,
            gadget_instance_id => $instance_id++,
            row => $row,
            %$gadget_info,
        );

        # Override preferences in the temporary gadget
        my $prefs = $gadget_info->{prefs} || [];
        my %overridden = map { $_->[0] => $_->[1] } @$prefs;
        $instance->override_preferences(\%overridden);

        push @gadgets, $self->container->gadget_vars($instance);
    }
    $self->rest->header(-type => 'application/json; charset=utf-8');
    return encode_json(\@gadgets);
}

sub GET_gadgets {
    my $self = shift;
    my $gadgets = $self->container->gadgets;
    $self->rest->header(-type => 'application/json; charset=utf-8');
    return encode_json([ map { $self->container->gadget_vars($_) } @$gadgets ]);
}

1;

__END__

=head1 NAME

Socialtext::Handler::Container - role for all containers

=head1 SYNOPSIS

  package Socialtext::Handler::Container::Group;
  with 'Socialtext::Handler::Container';

=head1 DESCRIPTION

Handles the normal handler stuff for containers.

=cut
