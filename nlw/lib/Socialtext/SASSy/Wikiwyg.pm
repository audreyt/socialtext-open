package Socialtext::SASSy::Wikiwyg;
use Moose;
use File::Path qw(mkpath);
use Socialtext::File qw(get_contents set_contents);
use namespace::clean -except => 'meta';

extends 'Socialtext::SASSy';

has 'html_file' => (is => 'ro', isa => 'Str', lazy_build => 1);
sub _build_html_file {
    my $self = shift;
    mkpath $self->cache_dir unless -d $self->cache_dir;
    $self->output_filename($self->filename . '.out')
        unless $self->output_filename;
    return $self->cache_dir . '/' . $self->output_filename . '.html';
}

around 'render' => sub {
    my $orig = shift;
    my $self = shift;
    my @param = @_;

    $self->$orig(@_);

    my $css = get_contents($self->css_file);
    my $html = qq(<html><head><style>$css</style></head><body class="wiki" onload="window.Socialtext={body_loaded:true}"></body></html>);

    set_contents($self->html_file, $html);
};

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::SASSy::Wikiwyg - SASSyfied wikiwyg

=head1 SYNOPSIS

  my $sass = Socialtext::SASSy::Wikiwyg->new(
     filename => 'wikiwyg'
     dir_name => '/your/dir/here'
  );

  $sass->render if $sass->needs_update

  my $html_file = $sass->html_file

=head1 DESCRIPTION

Socialtext::SASSy::Wikiwyg extends the base Socialtext::SASSy object in order
to provide an html_file() sub. This sub can be used to write a themed
wikiwyg.html file that is used for signal editing.

=cut
