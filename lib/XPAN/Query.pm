package XPAN::Query;

use 5.010001;
use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       list_xpan_packages
                       list_xpan_modules
                       list_xpan_dists
                       list_xpan_authors
               );

our %SPEC;

our $VERSION = '0.01'; # VERSION
our $DATE = '2014-06-05'; # DATE

1;
# ABSTRACT: Query a {CPAN,MiniCPAN,DarkPAN} mirror

__END__

=pod

=encoding UTF-8

=head1 NAME

XPAN::Query - Query a {CPAN,MiniCPAN,DarkPAN} mirror

=head1 VERSION

This document describes version 0.01 of XPAN::Query (from Perl distribution XPAN-Query), released on 2014-06-05.

=head1 SYNOPSIS

 use XPAN::Query qw(
     list_xpan_packages
     list_xpan_modules
     list_xpan_dists
     list_xpan_authors
 );
 my $res = list_ubuntu_releases(detail=>1);
 # raw data is in $Ubuntu::Releases::data;

=head1 DESCRIPTION

B<INITIAL RELEASE: no implementations yet>.

XPAN is a term I coined for any repository (directory tree, be it on a local
filesystem or a remote network) that has structure like a CPAN mirror,
specifically having a C<modules/02packages.details.txt.gz> file. This includes a
normal CPAN mirror, a MiniCPAN, or a DarkPAN. Currently it I<excludes> BackPAN,
because it does not have C<02packages.details.txt.gz>, only
C<authors/id/C/CP/CPANID> directories.

With this module, you can query various things about the repository. This module
fetches C<02packages.details.txt.gz> and parses it (caching it locally for a
period of time).

=head1 SEE ALSO

L<Parse::CPAN::Packages>

L<Parse::CPAN::Packages::Fast>

L<PAUSE::Packages>, L<PAUSE::Users>

Tangentially related: L<BackPAN::Index>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/XPAN-Query>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-XPAN-Query>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=XPAN-Query>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
