# @COPYRIGHT@
use strict;
use warnings;

sub get_nlw_dir {
    my $userid = `whoami`;
    chomp($userid);
    my $dir = '/tmp/' . $userid;
    if (! (-d  $dir) ) {
        mkdir($dir);
        my $chmod = `chmod 777 $dir`;
    }
    return $dir;
}

sub get_nlw_filename {
  my $dir = get_nlw_dir();
  my $file = $dir . '/test_nlw.log';
  return $file;
}

1;
