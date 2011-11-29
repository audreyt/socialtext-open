package Socialtext::CodeSyntaxPlugin;
use strict;
use warnings;
use Socialtext::l10n '__';

use base 'Socialtext::Plugin';
use Class::Field qw(const);

const class_id => 'code';
const class_title    => __('class.code');

our %Brushes = (
    as3 => 'AS3',
    actionscript3 => 'AS3',
    bash => 'Bash',
    shell => 'Bash',
    cf => 'ColdFusion',
    coldfusion => 'ColdFusion',
    csharp => 'CSharp',
    cpp => 'Cpp',
    c => 'Cpp',
    css => 'Css',
    delphi => 'Delphi',
    pascal => 'Delphi',
    diff => 'Diff',
    patch => 'Diff',
    erlang => 'Erlang',
    groovy => 'Groovy',
    js => 'JScript',
    javascript => 'JScript',
    java => 'Java',
    javafx => 'JavaFX',
    perl => 'Perl',
    php => 'Php',
    powershell => 'PowerShell',
    py => 'Python',
    python => 'Python',
    ruby => 'Ruby',
    scala => 'Scala',
    sql => 'Sql',
    vb => 'Vb',
    xml => 'Xml',
    html => 'Xml',
    xhtml => 'Xml',
    xslt => 'Xml',
    yaml => 'Yaml',
    json => 'Yaml',
    plain => 'Plain',
);

our %Brush_aliases = (
    json => 'yaml',
);

sub register {
    my $self = shift;
    my $registry = shift;
    for my $key (%Brushes) {
        my $pkg = "Socialtext::CodeSyntaxPlugin::Wafl::$key";

        no strict 'refs';
        no warnings 'redefine';
        push @{"$pkg\::ISA"}, 'Socialtext::Formatter::WaflBlock';
        *{"$pkg\::html"} = \&__html__;
        if ($key eq 'plain') {
            *{"$pkg\::wafl_id"} = sub { 'code' };
        }
        else {
            *{"$pkg\::wafl_id"} = sub { "code-$key" };
        }
        $registry->add(wafl => $pkg->wafl_id => $pkg);
    }
}

sub __html__ {
    my $self = shift;
    my $method = $self->method;
    (my $type = $method) =~ s/^code(?:[-_](.+?))?$/$1 || 'plain'/e;

    my $string = $self->block_text;
    my $js_base  = "/static/javascript/contrib/SyntaxHighlighter";
    my $css_base = "$js_base/css";
    my $brush = $Socialtext::CodeSyntaxPlugin::Brushes{$type};
    if (my $t = $Brush_aliases{$type}) {
        $type = $t;
    }

    # Skip traversing
    $self->units([]);

    return <<"EOT";
<script type="text/javascript" src="$js_base/shCore.js"></script>
<script type="text/javascript" src="$js_base/shBrush${brush}.js"></script>
<link href="$css_base/shCore.css" rel="stylesheet" type="text/css" />
<link href="$css_base/shThemeDefault.css" rel="stylesheet" type="text/css" />
<pre class="brush: $type">
$string
</pre>
<script type="text/javascript">SyntaxHighlighter.all()</script>
EOT
}

1;
__END__

=head1 NAME

Socialtext::CodeSyntaxPlugin - Plugin for syntax highlighting in wiki pages.

=head1 SYNOPSIS

.perl

my $something = 1;
...

.perl

=head1 DESCRIPTION

Provide for a syntax highlighting wafl in wiki pages.

=cut
