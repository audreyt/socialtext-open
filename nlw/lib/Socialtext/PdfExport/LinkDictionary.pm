# @COPYRIGHT@
package Socialtext::PdfExport::LinkDictionary;
use warnings;
use strict;

use base 'Socialtext::Formatter::AbsoluteLinkDictionary';

sub image {'%{full_path}'}

1;
