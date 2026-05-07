use strict;
use warnings;

use Test2::V0;
use POSIX ();

use Parallel::Subs;

subtest 'on_failure defaults to die' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { die "boom\n" } );

    eval { $p->wait_for_all() };
    like $@, qr/Job failures:/, "dies by default on failure";
};

subtest 'on_failure => die is explicit default' => sub {
    my $p = Parallel::Subs->new( max_process => 1, on_failure => 'die' );
    $p->add( sub { die "boom\n" } );

    eval { $p->wait_for_all() };
    like $@, qr/Job failures:/, "dies explicitly with on_failure => die";
};

subtest 'on_failure => continue does not die' => sub {
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( sub { die "oops\n" } );
    $p->add( sub { 42 } );

    eval { $p->wait_for_all() };
    is $@, '', "no die with on_failure => continue";
};

subtest 'on_failure => continue preserves successful results' => sub {
    my $p = Parallel::Subs->new( max_process => 4, on_failure => 'continue' );
    $p->add( sub { 'first' } );
    $p->add( sub { die "fail\n" } );
    $p->add( sub { 'third' } );
    $p->add( sub { 'fourth' } );

    $p->wait_for_all();

    # results() returns only successful results in insertion order (no gaps)
    my $results = $p->results();
    is scalar @$results, 3, "3 successful results";
    is $results->[0], 'first',  "first successful result";
    is $results->[1], 'third',  "second successful result";
    is $results->[2], 'fourth', "third successful result";
};

subtest 'failures() returns failure records' => sub {
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( sub { die "something broke\n" } );
    $p->add( sub { 99 } );

    $p->wait_for_all();

    my $failures = $p->failures();
    is scalar @$failures, 1, "one failure recorded";

    my $f = $failures->[0];
    is $f->{id}, 1, "failure has correct job id";
    ok $f->{pid}, "failure has a pid";
    is $f->{exit}, 1, "failure has non-zero exit";
    like $f->{error}, qr/something broke/, "failure captures error message";
};

subtest 'failures() is empty when all succeed' => sub {
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( sub { 'a' } );
    $p->add( sub { 'b' } );

    $p->wait_for_all();

    is $p->failures(), [], "no failures when all jobs succeed";
};

subtest 'failures() with multiple failures' => sub {
    my $p = Parallel::Subs->new( max_process => 3, on_failure => 'continue' );
    $p->add( sub { die "err1\n" } );
    $p->add( sub { die "err2\n" } );
    $p->add( sub { 'ok' } );

    $p->wait_for_all();

    my $failures = $p->failures();
    is scalar @$failures, 2, "two failures recorded";
    is $p->results()->[0], 'ok', "successful job result preserved";
};

subtest 'on_failure => continue works with named jobs' => sub {
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( 'good', sub { 'yes' } );
    $p->add( 'bad',  sub { die "nope\n" } );

    $p->wait_for_all();

    is $p->result('good'), 'yes', "named successful result accessible";
    is scalar @{ $p->failures() }, 1, "failure recorded for bad job";
};

subtest 'on_failure => continue works with callbacks' => sub {
    my $collected;
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( sub { 'value' }, sub { $collected = shift } );
    $p->add( sub { die "fail\n" } );

    $p->wait_for_all();

    is $collected, 'value', "callback fires for successful job";
    is scalar @{ $p->failures() }, 1, "failure still recorded";
};

subtest 'invalid on_failure value croaks' => sub {
    eval { Parallel::Subs->new( on_failure => 'ignore' ) };
    like $@, qr/on_failure must be 'die' or 'continue'/,
      "invalid on_failure value rejected";
};

subtest 'on_failure => continue with all failures' => sub {
    my $p = Parallel::Subs->new( max_process => 2, on_failure => 'continue' );
    $p->add( sub { die "a\n" } );
    $p->add( sub { die "b\n" } );

    $p->wait_for_all();

    is $p->results(), [], "empty results when all fail";
    is scalar @{ $p->failures() }, 2, "all failures recorded";
};

done_testing;
