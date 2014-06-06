package XPAN::Query;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Digest::MD5 qw(md5_hex);
use File::Slurp::Tiny qw(read_file write_file);
use LWP::UserAgent;
use Sereal qw(encode_sereal decode_sereal);
use String::ShellQuote;
use URI;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       list_xpan_packages
                       list_xpan_modules
                       list_xpan_dists
                       list_xpan_authors
               );

our %SPEC;
our $VERSION = '0.04'; # VERSION
our $DATE = '2014-06-06'; # DATE

my %common_args = (
    url => {
        summary => "URL to repository, e.g. '/cpan' or 'http://host/cpan'",
        schema  => 'str*',
        req => 1,
        pos => 0,
    },
    cache_period => {
        schema => [int => default => 86400],
        cmdline_aliases => {
            nocache => {
                schema => [bool => {is=>1}],
                code   => sub { $_[0]{cache_period} = 0 },
            },
        },
    },
    detail => {
        summary => "If set to true, will return array of records instead of just ID's",
        schema  => 'bool',
    },
    temp_dir => {
        schema => 'str*',
    },
);

my %query_args = (
    query => {
        summary => 'Search query',
        schema => 'str*',
        cmdline_aliases => {q=>{}},
        pos => 1,
    },
);

sub _parse {

    my %args = @_;

    my $now = time();

    my $xpan_url = $args{url} or die "Please supply url";
    # normalize for LWP, it won't accept /foo/bar, only file:/foo/bar
    $xpan_url = URI->new($xpan_url);
    unless ($xpan_url->scheme) { $xpan_url = URI->new("file:$args{url}") }

    my $tmpdir = $args{temp_dir} // $ENV{TEMP} // $ENV{TMP} // "/tmp";
    my $cache_period = $args{cache_period} // 86400;

    state $ua = LWP::UserAgent->new;
    my $filename = "02packages.details.txt";
    my $md5 = md5_hex("$xpan_url");

    # download file
    my $gztarget = "$tmpdir/$filename.gz-$md5";
    my @gzst = stat($gztarget);
    if (@gzst && $gzst[9] >= $now-$cache_period) {
        $log->tracef("Using cache file %s", $gztarget);
    } else {
        my $url = "$xpan_url/modules/$filename.gz";
        $log->tracef("Downloading %s ...", "$url");
        my $res = $ua->get($url);
        unless ($res->is_success) {
            die "Can't get $url: " . $res->status_line;
        }
        write_file($gztarget, $res->content);
    }

    # extract and process (XXX this is currently unix-specific)
    my $sertarget = "$tmpdir/$filename.2.sereal-$md5";
    my @serst = stat($sertarget);
    my $data;
    if (@serst && $serst[9] >= $gzst[9]) {
        $log->tracef("Using cache file %s", $sertarget);
        $data = decode_sereal(~~read_file($sertarget));
    } else {
        $log->trace("Parsing $filename.gz ...");
        my (%packages, %authors, %dists);
        open my($fh), "zcat ".shell_quote("$gztarget")."|";
        my $line = 0;
        while (<$fh>) {
            $line++;
            next unless /\S/;
            next if /^\S+:\s/;
            chomp;
            #say "D:$_";
            my ($pkg, $ver, $path) = split /\s+/, $_;
            $ver = undef if $ver eq 'undef';
            my ($author, $file) = $path =~ m!^./../(.+?)/(.+)!
                or die "Line $line: Invalid path $path";
            $authors{$author} = 1;
            $packages{$pkg} = {author=>$author, version=>$ver, file=>$file};
            my $dist = $file;
            # XXX should've extract metadata
            if ($dist =~ s/-v?(\d(?:\d*(\.[\d_][^.]*)*?)?).\D.+//) {
                #say "D:  dist=$dist, 1=$1";
                $dists{$dist} = {author=>$author, version=>$1, file=>$file};
                $packages{$pkg}{dist} = $dist;
            } else {
                $log->info("Line $line: Can't parse dist version from filename $file");
                #next;
            }
        }
        $data = {
            packages => \%packages,
            authors  => [sort keys %authors],
            dists    => \%dists,
        };
        write_file($sertarget, encode_sereal($data));
    }

    $data;
}

$SPEC{list_xpan_authors} = {
    v => 1.1,
    summary => 'List authors in {CPAN,MiniCPAN,DarkPAN} mirror',
    args => {
        %common_args,
        %query_args,
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of CPAN ID's. If you set `detail` to true, will
return array of records.

_
    },
};
sub list_xpan_authors {
    my %args = @_;
    my $detail = $args{detail};
    my $data = _parse(%args);
    my $q = lc($args{query} // '');
    my @res;
    for (@{ $data->{authors} }) {
        next if length($q) && index(lc($_), $q) < 0;
        push @res, $detail ? {cpanid=>$_} : $_;
    }
    \@res;
}

$SPEC{list_xpan_packages} = {
    v => 1.1,
    summary => 'List packages in {CPAN,MiniCPAN,DarkPAN} mirror',
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
        },
        dist => {
            summary => 'Filter by distribution',
            schema => 'str*',
            cmdline_aliases => {d=>{}},
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of package names. If you set `detail` to true,
will return array of records.

_
    },
};
sub list_xpan_packages {
    my %args = @_;
    my $detail = $args{detail};

    my $data = _parse(%args);
    my $q = lc($args{query} // '');
    my @res;
    for (keys %{ $data->{packages} }) {
        my $rec = $data->{packages}{$_};
        next if length($q) && index(lc($_), $q) < 0;
        next if $args{author} && uc($args{author}) ne uc($rec->{author});
        next if $args{dist} && $args{dist} ne $rec->{dist};
        $rec->{name} = $_;
        push @res, $detail ? $rec : $_;
    }
    \@res;
}

$SPEC{list_xpan_modules} = $SPEC{list_xpan_packages};
sub list_xpan_modules {
    goto &list_xpan_packages;
}

$SPEC{list_xpan_dists} = {
    v => 1.1,
    summary => 'List distributions in {CPAN,MiniCPAN,DarkPAN} mirror',
    description => <<'_',

For simplicity and performance, this module parses distribution names from
tarball filenames mentioned in `02packages.details.txt.gz`, so it is not perfect
(some release tarballs, especially older ones, are not properly named). For more
proper way, one needs to read the metadata file (`*.meta`) for each
distribution.

_
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of distribution names. If you set `detail` to
true, will return array of records.

_
    },
};
sub list_xpan_dists {
    my %args = @_;
    my $detail = $args{detail};

    my $data = _parse(%args);
    my $q = lc($args{query} // '');
    my @res;
    for (keys %{ $data->{dists} }) {
        my $rec = $data->{dists}{$_};
        next if length($q) && index(lc($_), $q) < 0;
        next if $args{author} && uc($args{author}) ne uc($rec->{author});
        $rec->{name} = $_;
        push @res, $detail ? $rec : $_;
    }
    \@res;
}


1;
# ABSTRACT: Query a {CPAN,MiniCPAN,DarkPAN} mirror

__END__

=pod

=encoding UTF-8

=head1 NAME

XPAN::Query - Query a {CPAN,MiniCPAN,DarkPAN} mirror

=head1 VERSION

This document describes version 0.04 of XPAN::Query (from Perl distribution XPAN-Query), released on 2014-06-06.

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

XPAN is a term I coined for any repository (directory tree, be it on a local
filesystem or a remote network) that has structure like a CPAN mirror,
specifically having a C<modules/02packages.details.txt.gz> file. This includes a
normal CPAN mirror, a MiniCPAN, or a DarkPAN. Currently it I<excludes> BackPAN,
because it does not have C<02packages.details.txt.gz>, only
C<authors/id/C/CP/CPANID> directories.

With this module, you can query various things about the repository. This module
fetches C<02packages.details.txt.gz> and parses it (caching it locally for a
period of time).

=head1 FUNCTIONS


=head2 list_xpan_authors(%args) -> any

List authors in {CPAN,MiniCPAN,DarkPAN} mirror.

Arguments ('*' denotes required arguments):

=over 4

=item * B<cache_period> => I<int> (default: 86400)

=item * B<detail> => I<bool>

If set to true, will return array of records instead of just ID's.

=item * B<query> => I<str>

Search query.

=item * B<temp_dir> => I<str>

=item * B<url>* => I<str>

URL to repository, e.g. '/cpan' or 'http://host/cpan'.

=back

Return value:


=head2 list_xpan_dists(%args) -> any

List distributions in {CPAN,MiniCPAN,DarkPAN} mirror.

For simplicity and performance, this module parses distribution names from
tarball filenames mentioned in C<02packages.details.txt.gz>, so it is not perfect
(some release tarballs, especially older ones, are not properly named). For more
proper way, one needs to read the metadata file (C<*.meta>) for each
distribution.

Arguments ('*' denotes required arguments):

=over 4

=item * B<author> => I<str>

Filter by author.

=item * B<cache_period> => I<int> (default: 86400)

=item * B<detail> => I<bool>

If set to true, will return array of records instead of just ID's.

=item * B<query> => I<str>

Search query.

=item * B<temp_dir> => I<str>

=item * B<url>* => I<str>

URL to repository, e.g. '/cpan' or 'http://host/cpan'.

=back

Return value:


=head2 list_xpan_modules(%args) -> any

List packages in {CPAN,MiniCPAN,DarkPAN} mirror.

Arguments ('*' denotes required arguments):

=over 4

=item * B<author> => I<str>

Filter by author.

=item * B<cache_period> => I<int> (default: 86400)

=item * B<detail> => I<bool>

If set to true, will return array of records instead of just ID's.

=item * B<dist> => I<str>

Filter by distribution.

=item * B<query> => I<str>

Search query.

=item * B<temp_dir> => I<str>

=item * B<url>* => I<str>

URL to repository, e.g. '/cpan' or 'http://host/cpan'.

=back

Return value:


=head2 list_xpan_packages(%args) -> any

List packages in {CPAN,MiniCPAN,DarkPAN} mirror.

Arguments ('*' denotes required arguments):

=over 4

=item * B<author> => I<str>

Filter by author.

=item * B<cache_period> => I<int> (default: 86400)

=item * B<detail> => I<bool>

If set to true, will return array of records instead of just ID's.

=item * B<dist> => I<str>

Filter by distribution.

=item * B<query> => I<str>

Search query.

=item * B<temp_dir> => I<str>

=item * B<url>* => I<str>

URL to repository, e.g. '/cpan' or 'http://host/cpan'.

=back

Return value:

=head1 SEE ALSO

L<Parse::CPAN::Packages> is a more full-featured and full-fledged module to
parse C<02packages.details.txt.gz>. The downside is, startup and performance is
slower.

L<Parse::CPAN::Packages::Fast> is created as a more lightweight alternative to
Parse::CPAN::Packages.

L<PAUSE::Packages> also parses C<02packages.details.txt.gz>, it's just that the
interface is different.

L<PAUSE::Users> parses C<authors/00whois.xml>. XPAN::Query does not parse this
file, it is currently not generated/downloaded by CPAN::Mini, for example.

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