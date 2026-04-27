use strict;
use warnings;

use Test2::V0;

use Parallel::Subs;

subtest 'repeated wait_for_all does not re-execute jobs' => sub {
    my $counter = 0;
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { $counter++; return "done" } );

    $p->wait_for_all();
    is $p->results(), ["done"], "first run returns result";

    # Second call should be a no-op (jobs were cleared)
    $p->wait_for_all();
    is $p->results(), ["done"], "results still available after second call";
    is $p->total_jobs(), 0, "no pending jobs after first run";
};

subtest 'add/run/add/run does not replay old jobs' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );

    $p->add( sub { "first" } );
    $p->wait_for_all();
    is $p->results(), ["first"], "first batch result";

    $p->add( sub { "second" } );
    $p->wait_for_all();
    is $p->results(), ["second"], "second batch replaces first (no stale results)";
};

subtest 'results are fresh per batch (no leaking across runs)' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );

    # Run 1: three jobs
    $p->add( sub { "a" } );
    $p->add( sub { "b" } );
    $p->add( sub { "c" } );
    $p->wait_for_all();
    is $p->results(), [qw(a b c)], "3 results in first batch";

    # Run 2: one job — should not see a, b, c
    $p->add( sub { "x" } );
    $p->wait_for_all();
    is $p->results(), ["x"], "only 1 result in second batch (no stale leak)";
};

subtest 'callbacks are cleared after run' => sub {
    my @collected;
    my $p = Parallel::Subs->new( max_process => 1 );

    $p->add( sub { 10 }, sub { push @collected, shift } );
    $p->wait_for_all();
    is \@collected, [10], "callback fired in first run";

    # Second batch with no callback
    $p->add( sub { 20 } );
    $p->wait_for_all();
    is \@collected, [10], "old callback did not fire again in second run";
};

subtest 'named jobs + wait_for_all_optimized' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( 'alpha', sub { "result_a" } );
    $p->add( 'beta',  sub { "result_b" } );
    $p->add( 'gamma', sub { "result_c" } );

    $p->wait_for_all_optimized();

    is $p->result('alpha'), "result_a", "named result via optimized mode";
    is $p->result('beta'),  "result_b", "named result via optimized mode";
    is $p->result('gamma'), "result_c", "named result via optimized mode";

    my $r = $p->results();
    is scalar @$r, 3, "all 3 results present";
    is $r, [qw(result_a result_b result_c)], "results in insertion order";
};

subtest 'named jobs + timeout' => sub {
    my $p = Parallel::Subs->new( max_process => 2, timeout => 5 );
    $p->add( 'fast', sub { return 42 } );
    $p->add( 'also_fast', sub { return 99 } );

    $p->wait_for_all();

    is $p->result('fast'),      42, "named job with timeout returns result";
    is $p->result('also_fast'), 99, "second named job with timeout";
};

subtest 'wait_for_all_optimized with single job' => sub {
    my $p = Parallel::Subs->new( max_process => 4 );
    $p->add( sub { "solo" } );

    $p->wait_for_all_optimized();
    is $p->results(), ["solo"], "single job in optimized mode works";
};

subtest 'optimized mode does not re-execute on second call' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( sub { "one" } );
    $p->add( sub { "two" } );

    $p->wait_for_all_optimized();
    is $p->results(), [qw(one two)], "first optimized run";

    # Second call should be a no-op
    $p->wait_for_all_optimized();
    is $p->results(), [qw(one two)], "results preserved after second call";
    is $p->total_jobs(), 0, "no pending jobs";
};

subtest 'mixed named and unnamed jobs' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( sub { "anon1" } );
    $p->add( 'named_one', sub { "named" } );
    $p->add( sub { "anon2" } );

    $p->wait_for_all();

    is $p->result('named_one'), "named", "named result among unnamed";
    is $p->results(), [qw(anon1 named anon2)], "all results in order";
};

subtest 'results before run returns empty' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( sub { 42 } );

    my $r = $p->results();
    is $r, [], "results() before run returns empty arrayref";
};

done_testing;
