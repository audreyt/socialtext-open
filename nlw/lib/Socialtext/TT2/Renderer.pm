# @COPYRIGHT@
package Socialtext::TT2::Renderer;
use strict;
use warnings;

our $VERSION = '0.02';

use base 'Class::Singleton';

use File::Find;
use File::Path;
use Socialtext::AppConfig;
use Socialtext::File;
use Socialtext::Helpers;
use Socialtext::Statistics 'stat_call';
use Readonly;
use Socialtext::Validate
    qw( validate SCALAR_TYPE SCALAR_OR_ARRAYREF_TYPE ARRAYREF_TYPE HASHREF_TYPE SCALAR SCALARREF );
use Template;
use Template::Constants ':debug';
use Template::Provider;
use Socialtext::Build qw( get_build_setting );
use Socialtext::l10n qw( loc system_locale );
use Socialtext::Skin;
use Socialtext::Timer qw/time_scope/;

use Template::Plugin::FillInForm;

# This needs to be a global so we can call local on it later.
use vars qw($CurrentPaths);

sub _new_instance {
    my $class = shift;

    my $cache_dir = Socialtext::AppConfig->template_compile_dir();
    File::Path::mkpath( $cache_dir, 0, 0755 )
        unless -d $cache_dir;

    return bless {}, $class;
}

sub PreloadTemplates {
    my $class = shift;

    my $renderer = $class->instance();
    my @paths = grep { -d $_ } Socialtext::Skin->PreloadTemplateDirs;
    local $CurrentPaths = \@paths;

    find(sub { _maybe_fetch($renderer) }, @paths);
}

sub _maybe_fetch {
    return if $File::Find::name =~ m{\/\.svn};

    return unless -f $File::Find::name;

    my $renderer = shift;
    my $context = $renderer->_template->context;

    # REVIEW - why not just call $context->template to load a
    # template?
    foreach my $provider ( @{ $context->{LOAD_TEMPLATES} } ) {
        local $provider->{ ABSOLUTE } = 1;
        $provider->fetch($File::Find::name);
    }
}

{
    Readonly my $spec => {
        template  => { type => SCALAR | SCALARREF },
        vars      => HASHREF_TYPE( default => {} ),
        paths     => ARRAYREF_TYPE( default => [] ),
    };
    sub render {
        my $self = shift;
        my %p = validate( @_, $spec );
        my $t = time_scope('tt2_render');

        if (! defined $p{vars}{loc} ) {$p{vars}{loc} = \&loc;}
        if (! defined $p{vars}{loc_lang} ) {$p{vars}{loc_lang} = system_locale();}
        
        # Setting the global like this lets us change the paths for
        # each template we process, but we don't have to _reset_ them
        # afterwards, and we don't need to create a new Template.pm
        # object each time either.
        local $CurrentPaths = $self->_paths_for_render($p{paths});

        # XXX Unix dependent - File::Spec::Unix::catfile (canonpath actually)
        # is rather slow, and this is a little speed-up hack
        no warnings 'redefine';
        local *File::Spec::Unix::catfile = sub {
            shift;
            return Socialtext::File::catfile(@_);
        };

        # Don't require a BOM to get UTF8 out of our templates
        local *Template::Provider::_decode_unicode = sub {
            use bytes;
            require Encode;
            return Encode::decode( 'UTF-8', $_[1] );
        };

        my $tt2 = $self->_template;

        my $output;
        eval {
            stat_call( template_process_et => 'tic' );

            $tt2->process( $p{template}, $p{vars}, \$output )
                or die $tt2->error;

            stat_call( template_process_et => 'toc' );
        };

        if ( my $e = $@ ) {
            # {bz: 4925}: If user frame went away during rendering,
            # recover with the default layout/html frame.
            no warnings 'uninitialized';
            if ($e =~ /file error - (\S*user_frame\S*): not found/ and $p{vars}{frame_name} eq $1) {
                eval {
                    $tt2->process( $p{template}, { %{ $p{vars} }, frame_name => 'layout/html' } , \$output )
                        or die $tt2->error;
                };
                $e = $@;
            }

            if ($e) {
                warn "Output: $output\n" if $output;
                die "Template Toolkit error: ($p{template})\n$e";
            }
        }

        return $output;
    }
}

sub _paths_for_render {
    my $self  = shift;
    my $paths = shift;

    my @paths;

    for my $skin_path (@$paths) {
        my $local_skin_path = _local_path($skin_path);
        unshift @paths, $local_skin_path, $skin_path;
    }

    push @paths, Socialtext::File::catfile(
        Socialtext::AppConfig->code_base, 'template'
    );

    return \@paths;
}

sub _local_path { Socialtext::File::catfile( shift, 'local' ) }

{
    my $Template;

    sub _template {
        return $Template if $Template;

        my $self = shift;

        my $parms = {
            INCLUDE_PATH => [ \&_include_paths ],
            TOLERANT     => 0,
            COMPILE_DIR  => Socialtext::AppConfig->template_compile_dir(),
            COMPILE_EXT  => '.ttc',
            UNICODE      => 1,
            # turning this on lets you do simpler debugging via PERL
            # blocks
            EVAL_PERL    => Socialtext::AppConfig->debug(),
            PLUGIN_BASE  => 'Socialtext::Template::Plugin',
        };

        if ( get_build_setting( 'dev' ) ) {
            eval 'require Template::Timer';
            if ( !$@ ) {
                $parms->{CONTEXT} = Template::Timer->new( $parms );
            }
        }
        $Template = Template->new( $parms );

        return $Template;
    }
}

sub _include_paths {
    die "No include paths have been specified\n"
        unless $CurrentPaths;

    return $CurrentPaths;
}

1;

__END__

=head1 NAME

Socialtext::TT2::Renderer - Renders TT2 templates

=head1 SYNOPSIS

Perhaps a little code snippet.

  use Socialtext::TT2::Renderer;

  my $renderer = Socialtext::TT2::Renderer->instance;

  $renderer->render(
      template => '/some/template.html',
      vars     => {
          foo  => 27,
          name => $name,
      },
  );

=head1 DESCRIPTION

This class renders TT2 templates, and does its best to cache objects
and other data to speed up execution.

=head1 METHODS/FUNCTIONS

This class offers the following methods:

=head2 Socialtext::Renderer->instance()

This returns an instance of C<Socialtext::TT2::Renderer>. This class
is a singleton.

=head2 $renderer->render( ... )

Renders a template. This method accepts the following parameters:

=over 4

=item * template - required

Either a template path or a reference to scalar containing a
template as text.

=item * vars - defaults to {}

A hash reference of variables to be passed to the template.

=item * paths - optional

This can be either a scalar or an array reference of paths. Each path
may be either absolute or relative. Relative paths will be prefixed by
the the template directory as found under the code base directory.

=back

=head2 Socialtext::Renderer->PreloadTemplates()

Loads all the templates in the standard template path. Use this under
mod_perl at server startup to cache templates in memory.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
