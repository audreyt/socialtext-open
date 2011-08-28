#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile catdir updir);
use ExtUtils::MakeMaker qw(WriteMakefile prompt);
use ExtUtils::Command qw(mkpath);
use Getopt::Long;

# Global settings
my $TMPDIR = "build/tmp";
my $MAKEFILE = "$TMPDIR/Makefile.perl";
my $DEV_BIN = catdir(dirname(__FILE__), updir, updir, 'dev-bin');

my @original_argv = @ARGV;

my %option;

GetOptions(
    \%option,
    'dev:i',
    'quiet',
    'verbose',
);

@ARGV = grep { !/^--/ } @ARGV;

CREATE_TMP: {
    # This is how ExtUtils::Command does it: files thru @ARGV
    local @ARGV = ($TMPDIR);
    mkpath();
}

my $mm_args = {
    NAME         => 'Socialtext',
    ABSTRACT     => 'Socialtext',
    AUTHOR       => 'Socialtext <socialtext@socialtext.com>',
    VERSION_FROM => 'lib/Socialtext.pm',
    EXE_FILES    => [ glob("bin/*") ], # handled by debian build system
    PL_FILES     => {},
    MAKEFILE     => $MAKEFILE,
    NO_META      => 1,  # No META.yml
    dist => {
        DIST_CP => 'cp', # Has to be cp, not best or ln, because we modify the written files
    },
    clean => {
        FILES => '',
    },
};

# Generate Makefile
eval { WriteMakefile( %$mm_args ) };

if ( $@ ) {
    die "$@\n" unless $@ =~ /prereq/i;
    my $error = $@;
    install_deps();  # Only returns if user chooses not to install deps.
    die "$error\n";
}
munge_makefile();

# MakeMaker *really* wants the Makefile.PL to be in the CWD, but it is not
# going to be.  So munge the generated Makefile to point to the real location
# of the Makefile.PL.
sub munge_makefile {
    my $this_file = abs_path( dirname(__FILE__) );
    my @lines     = slurp($MAKEFILE);
    spew( $MAKEFILE, map { s/Makefile\.PL/$this_file/g; $_ } @lines );
}

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or die "Could not open $file for reading: $!\n";
    my @lines = <$fh>;
    close($fh);
    return @lines;
}

sub spew {
    my ($file, @lines) = @_;
    open my $fh, '>', $file or die "Could not open $file for writing: $!\n";
    print $fh @lines;
    close($fh);
}

# Override some behaviors so "tardist" can handle files with spaces.
package MY;
sub distdir {
    my $inherited = shift->SUPER::distdir(@_);
    chomp($inherited);
    $inherited .= <<ADDON;
\tgrep '^#-#' MANIFEST | cut -f 3- -d '#' | while read f; do \\
\t   install -D "\$\$f" "\$(DISTVNAME)/\$\$f"; \\
\tdone
\tchmod -R u+w \$(DISTVNAME)
\tbuild/bin/fill-in-copyright \$(DISTVNAME)
\t# Force the permissions of the files in the temp dir to match the originals
\tfind . -type f | grep -v .svn | grep -v "\$(DISTVNAME)" | while read f; do \\
\t   if [ -e "\$(DISTVNAME)/\$\$f" ]; then \\
\t       chmod -c --reference="\$\$f" "\$(DISTVNAME)/\$\$f"; \\
\t   fi \\
\tdone
ADDON
}

sub MY::libscan {
    my $self = shift;
    my $path = shift;

    $path = $self->SUPER::libscan($path);

    # Make sure no template modules get installed
    return '' if $path =~ /\.in$/;
    return $path;
};
