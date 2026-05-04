use strict;
use warnings;

use Test2::V0;

use Parallel::Subs;

# Tests for object lifecycle, state management across runs, and
# method return values — the "critical bug surface" that individual
# feature tests don't cover.

subtest 'results() before run returns empty arrayref' => sub {
    my $p = Parallel::Subs->new();
    $p->add( sub { 42 } );

    my $results = $p->results();
    is $results, [], "results() before run is empty arrayref";
    ref_ok $results, 'ARRAY', "results() returns arrayref, not undef";
};

subtest 'run() returns result hashref' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { 'alpha' } );
    $p->add( sub { 'beta' } );

    my $raw = $p->run();
    ref_ok $raw, 'HASH', "run() returns a hashref";
    is $raw->{1}, 'alpha', "result keyed by position 1";
    is $raw->{2}, 'beta',  "result keyed by position 2";
};

subtest 'wait_for_all returns $self for chaining' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { 1 } );

    my $ret = $p->wait_for_all();
    is $ret, exact_ref($p), "wait_for_all returns \$self";
};

subtest 'named job result before run returns undef' => sub {
    my $p = Parallel::Subs->new();
    $p->add( 'pending', sub { 99 } );

    my $result = $p->result('pending');
    ok !defined $result, "result() for unexecuted named job is undef";
};

subtest 'named jobs work with wait_for_all_optimized' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( 'fast', sub { 'quick' } );
    $p->add( 'slow', sub { 'steady' } );
    $p->add( sub { 'anon' } );

    $p->wait_for_all_optimized();

    # results() should return all in insertion order
    is $p->results(), [ 'quick', 'steady', 'anon' ],
        "optimized mode preserves insertion order with named jobs";

    # Named lookup should still work
    is $p->result('fast'), 'quick',  "named result 'fast' accessible";
    is $p->result('slow'), 'steady', "named result 'slow' accessible";
};

subtest 'total_jobs reflects state throughout lifecycle' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );

    is $p->total_jobs(), 0, "0 before any adds";

    $p->add( sub { 1 } );
    is $p->total_jobs(), 1, "1 after first add";

    $p->add( sub { 2 } );
    $p->add( sub { 3 } );
    is $p->total_jobs(), 3, "3 after three adds";

    $p->wait_for_all();
    # total_jobs reflects added jobs, not pending ones
    is $p->total_jobs(), 3, "still 3 after run (jobs are not cleared)";
};

subtest 'waitpid_blocking_sleep option accepted' => sub {
    # Verify the constructor accepts this parameter without error
    my $p = Parallel::Subs->new(
        max_process            => 2,
        waitpid_blocking_sleep => 1,
    );
    isa_ok $p, 'Parallel::Subs';

    $p->add( sub { 'wbs' } );
    $p->wait_for_all();
    is $p->results(), ['wbs'], "jobs run with waitpid_blocking_sleep enabled";
};

subtest 'timeout option stored and accessible' => sub {
    my $p = Parallel::Subs->new( max_process => 1, timeout => 10 );
    $p->add( sub { 'fast' } );
    $p->wait_for_all();
    is $p->results(), ['fast'], "fast job completes within timeout";
};

subtest 'constructor rejects negative timeout' => sub {
    like dies { Parallel::Subs->new( timeout => -5 ) },
        qr/timeout must be a positive number/,
        "negative timeout croaks";

    like dies { Parallel::Subs->new( timeout => 0 ) },
        qr/timeout must be a positive number/,
        "zero timeout croaks";
};

subtest 'multiple named jobs with optimized mode and many jobs' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    my @names = map { "job_$_" } 1 .. 10;

    for my $i ( 1 .. 10 ) {
        $p->add( "job_$i", sub { $i * 10 } );
    }

    $p->wait_for_all_optimized();

    for my $i ( 1 .. 10 ) {
        is $p->result("job_$i"), $i * 10,
            "named result job_$i correct after optimized run";
    }

    is $p->results(), [ map { $_ * 10 } 1 .. 10 ],
        "results() in insertion order after optimized run";
};

subtest 'results() is stable across multiple calls' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { 'x' } );
    $p->add( sub { 'y' } );
    $p->wait_for_all();

    my $r1 = $p->results();
    my $r2 = $p->results();
    is $r1, [ 'x', 'y' ], "first call correct";
    is $r2, [ 'x', 'y' ], "second call identical";
};

subtest 'callbacks fire with named jobs' => sub {
    my %captured;
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( 'first',  sub { 10 }, sub { $captured{first}  = shift } );
    $p->add( 'second', sub { 20 }, sub { $captured{second} = shift } );
    $p->wait_for_all();

    is $captured{first},  10, "callback for 'first' received result";
    is $captured{second}, 20, "callback for 'second' received result";
    is $p->result('first'),  10, "named result still accessible after callback";
    is $p->result('second'), 20, "named result still accessible after callback";
};

subtest 'sparse callbacks — some jobs with, some without' => sub {
    my @captured;
    my $p = Parallel::Subs->new( max_process => 1 );
    $p->add( sub { 'a' } );  # no callback
    $p->add( sub { 'b' }, sub { push @captured, shift } );
    $p->add( sub { 'c' } );  # no callback
    $p->add( sub { 'd' }, sub { push @captured, shift } );
    $p->wait_for_all();

    is $p->results(), [ 'a', 'b', 'c', 'd' ], "all results present";
    # With max_process=1, jobs complete in order, so callbacks fire in order
    is \@captured, [ 'b', 'd' ], "only jobs with callbacks fired them";
};

subtest 'large job count stress test' => sub {
    my $n = 50;
    my $p = Parallel::Subs->new( max_process => 4 );
    for my $i ( 1 .. $n ) {
        $p->add( sub { $i } );
    }
    $p->wait_for_all();

    my $results = $p->results();
    is scalar @$results, $n, "$n results collected";
    is $results, [ 1 .. $n ], "all results in correct order";
};

done_testing;
