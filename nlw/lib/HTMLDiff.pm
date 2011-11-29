{
    package Changes;
    use Data::Dumper;
    use List::Util qw/max min/;

    sub new{
        my ( $class, $string, $MAXCONTEXT ) = @_;
        return bless({string => $string, list => [], MAXCONTEXT => $MAXCONTEXT}, $class);
    }

    sub addchange{
        my($self, $change, $type) = @_;
        $change->{change} = substr($self->{string}, $change->{start}, $change->{len}) if not defined $change->{change};
        my @list = @{$self->{list}};
        if(@list){
            my $latest = $list[$#list];
            my $offset = $change->{start} - ($latest->{start} + $latest->{len});
#            print "start: $change->{start} offset: $offset\n";
            my $offstring = substr($self->{string}, $latest->{start} + $latest->{len}, $offset);
            if($offset == 0 or $type ){
                $latest->{len} += $change->{len} + $offset;
                $latest->{change} .= $offstring . $change->{change};
            }else{
                push @{$self->{list}}, $change if $change->{change};
            }
        }else{
            push @{$self->{list}}, $change if $change->{change};
        }
        @list = @{$self->{list}};
        $latest = $list[$#list];
        $latest->{rawchange} = substr($self->{string}, $latest->{start}, $latest->{len});
#        $latest->{change} ||= $latest->{rawchange};
        my $prevend;
        if($#list > 0){
            my $prev = $list[$#list - 1];
            my $aftlen = min($self->{MAXCONTEXT}, $latest->{start} - ($prev->{start} + $prev->{len}));
            $prev->{after} = substr($self->{string}, $prev->{start} + $prev->{len}, $aftlen); 
            $prevend = $prev->{start} + $prev->{len};
        }else{
            $prevend = 0;
        }
        my $befstart = max($latest->{start} - $self->{MAXCONTEXT}, $prevend);
        my $beflen = min($self->{MAXCONTEXT}, $latest->{start} - $prevend);
#        print "$#list prevend: $prevend, beflen: $beflen, befstart: $befstart\n";
        $latest->{before} = substr($self->{string}, $befstart, $beflen);
        $latest->{after} = substr($self->{string}, $latest->{start} + $latest->{len}, $self->{MAXCONTEXT});
    }
    sub changelist{
        my($self) = @_;
        return $self->{list};
    }
}

{

package MyDiff;

use Algorithm::Diff qw/sdiff/;
use List::Util qw/min max/;
use Data::Dumper;
use strict;

my $lineendingr = qr/(?<=<br>)(?!\n)|(?<=<br\/>)(?!\n)|(?<=<br \/>)(?!\n)|(?<=<li>)(?!\n)|(?<=<p>)(?!\n)|(?<=<\/tr>)(?!\n)|(?<=\n)/;

#my $lineendingr = qr/(?<=<br>)(?!\n)|(?<=\n)/;

sub new {
    my ( $class, $first, $second ) = @_;
    my @list1 = split /$lineendingr/, $first;
    my @list2 = split /$lineendingr/, $second;
    my $offset  = 0;
    my @offsets = map { $offset += length($_) } @list2;
    unshift @offsets, 0;
#    print Dumper(\@offsets);
    my @dlist   = sdiff( \@list1, \@list2 );
    my @additions;
    my ( $rel, $lastdiff );

    my $pos = 0;
    for(my $i = 0; $i < scalar @dlist; $i++) {
        my $diff = $dlist[$i];
        my $indicator = $diff->[0];
        if ( $indicator eq '+' or $indicator eq 'c') {
            my $line = '';
            my $start = 0;
            my $end = length($diff->[2]);
            if($indicator eq 'c'){
                if($i == 0 or $dlist[$i - 1][0] !~ /\+|c/){
                    $start = trimleft( $diff->[1], $diff->[2] );
                }
                if($i == $#dlist or $dlist[$i + 1][0] !~ /\+|c/){
#                    print "i $i, $#dlist, $dlist[$i + 1][0]\n";
                    $end = trimright( $diff->[1], $diff->[2] );
                }
                $line = substr( $diff->[2], $start, $end - $start) if($start < $end);
            }else{
                $line = $diff->[2];
            }
            push @additions,
              {
                start  => $offsets[ $pos ] + $start,
                string => $line,
                len    => length( $line ),
              } if length($line);
        }
        $pos++ if $indicator ne '-';
    }
#    print Dumper(\@additions);
    return bless( { list => \@additions }, $class );
}

sub trimleft {
    my ( $t1, $t2 ) = @_;
    my $minlen = min( length($t1), length($t2) );
    my ( $start, $end );
    for ( $start = 0 ; $start <= $minlen ; $start++ ) {
        if ( substr( $t1, $start, 1 ) ne substr( $t2, $start, 1 ) ) {
            last;
        }
    }
#    print "trimleft $t1, $t1, $start\n";
    return ( $start);
}

sub trimright {
    my ( $t1, $t2 ) = @_;
    my $minlen = min( length($t1), length($t2) );
    my $lenlef = length($t1);
    my $lenrig = length($t2);
    my $endi;
    for ( $endi = 1 ; $endi <= $minlen ; $endi++ ) {
        if (substr( $t1, $lenlef - $endi, 1 ) ne substr( $t2, $lenrig - $endi, 1 ))
        {
            last;
        }
    }
    my $end = $lenrig - $endi + 1;
    return ( $end );
}


sub additionsinrange{
    my($self, $start, $len) = @_;
    my @result;
    for my $addition (@{$self->{list}}){
        my $pocz = max($addition->{start}, $start);
        my $kon  = min($addition->{start} + $addition->{len}, $start + $len);
        if($addition->{start} > $start + $len){
            last;
        }
#            print '==', $addition->{string}, "pocz: $pocz, kon: $kon, start: $start, len: $len, addition->start: $addition->{start}, addition->len $addition->{len}\n";
        if($kon > $pocz){
            push @result, {
                string => substr(
                    $addition->{string}, 
                    $pocz - $addition->{start},
                    $kon - $pocz),
                start => $pocz,
                len   => $kon - $pocz};
        }
    }
    return @result;
}

}

package HTMLDiff;
use HTML::PullParser;
use URI::URL;
use Data::Dumper;

use strict;

my %allowed = (
    't' => 1,
    'a' => 1,
    'p' => 1,
    'b' => 1,
    'br' => 1,
    'em' => 1,
    'strong' => 1,
    'img' => 1,
);

my %tagstocomplete = (
    'a' => 1,
    'b' => 1,
    'em' => 1,
    'strong' => 1,
);

# a list of tags that when are started in the change then 
# the change is extended to the pairing end tag

sub filterhtml{
    my ($text1, $text2, $base) = @_;
    my $diff = MyDiff->new($text1, $text2);
    my $p = HTML::PullParser->new(
        doc => $text2,
        start => '"S", tagname, offset, length, text, attr',
        text => '"T", "t", offset, length, text',
        end   => '"E", tagname, offset, length, text',
    );
    my $output = Changes->new($text2, 300);
    my %intag;
    while ( my $token = $p->get_token ) {
        my($type, $tagname, $offset, $length, $text2, $attr) = @$token;
        my @additions = $diff->additionsinrange($offset, $length);
        if($intag{$tagname} and $type eq 'E'){
            $intag{$tagname}--;
            $output->addchange({ start => $offset, len => $length}, $type);
        }elsif(@additions){
            if($tagname eq 't'){
                for my $addition (@additions){
                    $output->addchange($addition);
                }
            }elsif($tagname eq 'a' or $tagname eq 'img'){
                my($change, $addrspec);
                if($tagname eq 'a'){
                    $addrspec = 'href';
                }else{
                    $addrspec = 'src';
                }
                my $url = URI::URL->new($attr->{$addrspec}, $base)->abs;
                $change = "<$tagname $addrspec=\"$url\">";
                $output->addchange({ change => $change, start => $offset, len => $length});
            }else{
                if($allowed{$tagname}){ 
                    $output->addchange({ start => $offset, len => $length});
                }elsif($tagname eq 'li'){
                    $output->addchange({ start => $offset, len => $length, change => '<br>'});
                }else{
                    $output->addchange({ start => $offset, len => $length, change => ''});
                }

            }
            if(($tagstocomplete{$tagname}) and $type eq 'S'){
                $intag{$tagname}++;
            }
        }
    }
    return @{$output->changelist};
}


=head1 NAME

HTMLDiff - 

=head1 SYNOPSIS

  use HTMLDiff;
  my @changes = HTMLDiff::filterhtml($text1, $text2, $uri);

=head1 DESCRIPTION

The filterhtml subroutine compares two versions of an HTML page and returns 
'What is New' in the second version - this does not include 
'What was Deleted'.  The "change" field of the output is filtered
to contain valid HTML with only allowed tags (specified by 
the %HTMLDiff::allowedtags hash) and with relative addreses of links 
and images rewriten.  The third parameter - $uri is the address used 
to fix the relative addreses.

The output is a list of hashes with following fields: 
'rawchange' - the HTML text of the change, 
'change' - the change filtered for display 
'before' and 'after' - HTML context of the change.

=head1 MOTIVATION

I use it for aggregating changes made on sites that I read frequently.  
I based my Active Bookmarks web application on it.

=head1 LIMITATIONS

The algorithm used is very heuristic, it was tuned only for some pages 
that I happened to be interested in.

=head1 AUTHOR

        Zbigniew Lukasiak
        http://zby.aster.net.pl

=head1 COPYRIGHT

This program is free software licensed under the...

        The General Public License (GPL)
        Version 2, June 1991


=head1 SEE ALSO

perl(1).

=cut

############################################# main pod documentation end ##


1; #this line is important and will help the module return a true value
__END__

