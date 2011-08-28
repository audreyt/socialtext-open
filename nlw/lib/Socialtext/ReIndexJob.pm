package Socialtext::ReIndexJob;
# @COPYRIGHT@
use Moose::Role;

requires 'indexer';

around '_build_indexer' => sub {
    my $code = shift;
    my $indexer = $code->(@_);
    # Don't manually commit; let Solr auto-commit or another manual commit
    # flush the data for this job.
    $indexer->always_commit(0);
    return $indexer;
};

no Moose::Role;
1;

__END__

=head1 NAME

Socialtext::ReIndexJob - (Re-)index things in the background

=head1 SYNOPSIS

  package Your::Job::Module;
  with 'Socialtext::ReIndexJob';

=head1 DESCRIPTION

Set the indexer to use solr auto-commit instead of committing after each
add.

=cut
