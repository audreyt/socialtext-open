package Socialtext::SASSy;
# @COPYRIGHT@
use Moose;
use methods;
use Socialtext::HTTP ':codes';
use Socialtext::Paths;
use Socialtext::File qw(get_contents set_contents);
use Socialtext::AppConfig;
use Socialtext::TT2::Renderer;
use Socialtext::System qw(shell_run);
use File::Path qw(mkpath);
use File::Basename qw(basename);
use Socialtext::Helpers;
use YAML;
use namespace::clean -except => 'meta';

use constant code_base => Socialtext::AppConfig->code_base;
use constant is_dev_env => Socialtext::AppConfig->is_dev_env;

has 'filename' => ( is => 'ro', isa => 'Str', required => 1 );
has 'dir_name' => ( is => 'ro', isa => 'Str', required => 1 );

sub Fetch {
    my $class = shift;
    my %param = @_;

    if ($param{filename} eq 'wikiwyg') {
        require Socialtext::SASSy::Wikiwyg;
        $class .= '::Wikiwyg';
        $param{style} = 'compressed';
    }

    return $class->new(%param);
}

# style can be: compact, compressed, or expanded.
has 'style' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
sub _build_style {
    my $minify = eval {
        require Socialtext::AppConfig;
        return Socialtext::AppConfig->minify_css eq 'on';
    };
    $minify = 1 if $@;

    return $minify ? 'compressed' : 'expanded';
}

has 'params' => ( is => 'ro', isa => 'HashRef' );

has 'files' => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1, auto_deref => 1,
);
method _build_files { return [ glob($self->code_base . '/sass/*') ] }

has 'dir' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
method _build_dir {
    return join('/',
        'theme', substr($self->dir_name, 0, 2), substr($self->dir_name, 2)
    );
}

has 'cache_dir' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
method _build_cache_dir {
    return Socialtext::Paths::cache_directory($self->dir);
}

has 'output_filename' => ( is => 'rw', isa => 'Str' );

has 'sass_file' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
method _build_sass_file {
    mkpath $self->cache_dir unless -d $self->cache_dir;
    $self->output_filename($self->filename . '.out')
        unless $self->output_filename;
    return $self->cache_dir . '/' . $self->output_filename . '.sass';
}

has 'css_file' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
method _build_css_file {
    mkpath $self->cache_dir unless -d $self->cache_dir;
    $self->output_filename($self->filename . '.out')
        unless $self->output_filename;
    return $self->cache_dir . '/' . $self->output_filename . '.css';
}

method protected_uri($file) {
    return join('/', '/nlw', $self->dir, $file);
}

method needs_update {
    return 1 unless -f $self->css_file;
    if ($self->is_dev_env) {
        my $latest = (sort map { (stat($_))[9] } $self->files)[-1];
        return $latest > (stat($self->css_file))[9];
    }
    return 0;
}

method MapFontToCSS {
    my $font = shift;

    my $map = {
        'Arial' => 'Arial,Helvetica,sans-serif',
        'Georgia' => 'Georgia,Times,serif',
        'Helvetica' => 'Helvetica,Arial,sans-serif',
        'Lucida' => 'Lucida,Helvetica,sans-serif',
        'Times' => 'Times,Georgia,serif',
        'Trebuchet' => 'Trebuchet,Helvetica,sans-serif',
        'serif' => 'serif',
        'sans-serif' => 'sans-serif',
    };

    return $map->{$font};
};

method render {
    # Variable Expansion
    my @lines;
    for my $key (keys %{$self->params}) {
        my $value = $self->params->{$key};
        next unless $value;

        $value = $self->MapFontToCSS($value)
            if $key =~ /_font$/;

        push @lines, "\$$key: " . $value . "\n";
    }
    push @lines, "\@import " . $self->filename . ".sass\n";

    set_contents($self->sass_file, join('', @lines));

    $Socialtext::System::SILENT_RUN = 1;
    shell_run(
        '/opt/ruby/1.8/bin/sass',
        '--compass',                            # http://compass-style.org/
        '-I', $self->code_base . '/sass',       # Add sass files from starfish
        '-t', $self->style,                     # compressed or expanded
        $self->style eq 'expanded' ? ('-l'):(), # line numbers when expanded
        $self->sass_file,                       # Input
        $self->css_file,                        # Output
    );
}
no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::SASSy - SASS to CSS Conversion

=head1 SYNOPSIS

    # Create an object
    my $sass = Socialtext::SASSy->new(
        # filename without the extension (.sass or .css is appended)
        filename => 'grids.fixed',

        # output filename without the extension (optional)
        output_filename => "output-name",

        # Directory name to create
        dir_name => 'Testing', # will become $CACHE/theme/Te/sting

        # Params to pass into sass file as variables
        params => {
            varname => '10px'
        },
    );

    # Potentially render the .css and .sass files
    $sass->render if $sass->needs_update;

    # File paths:
    my $sass_file = $sass->sass_file;
    my $css_file = $css->css_file;

    # Now send this URL to the browser:
    my $css_url = $sass->protected_uri("output-name.css")

=head1 DESCRIPTION

Builds a CSS file from a SASS file

=cut
