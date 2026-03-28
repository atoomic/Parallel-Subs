use strict;
use warnings;

use Test2::V0;

use Parallel::Subs;

subtest 'total_jobs tracks added jobs' => sub {
    my $p = Parallel::Subs->new();
    is $p->total_jobs(), 0, "no jobs initially";

    $p->add( sub { 1 } );
    is $p->total_jobs(), 1, "one job after add";

    $p->add( sub { 2 } );
    is $p->total_jobs(), 2, "two jobs after second add";
};

subtest 'run with no jobs returns undef' => sub {
    my $p = Parallel::Subs->new();
    my $result = $p->run();
    ok !defined $result, "run() with no jobs returns undef";
};

subtest 'add with non-CODE croaks' => sub {
    my $p = Parallel::Subs->new();

    like dies { $p->add("not a coderef") },
        qr/add\(\) requires a CODE reference/,
        "add() with string croaks";

    like dies { $p->add(undef) },
        qr/add\(\) requires a CODE reference/,
        "add() with undef croaks";

    is $p->total_jobs(), 0, "no jobs were actually added";
};

subtest 'results ordering matches job order' => sub {
    my $p = Parallel::Subs->new( max_process => 1 );
    for my $i ( 1 .. 10 ) {
        $p->add( sub { $i } );
    }
    $p->run();
    is $p->results(), [ 1 .. 10 ], "results preserve insertion order";
};

subtest 'wait_for_all_optimized runs all jobs' => sub {
    my $p = Parallel::Subs->new();
    for my $i ( 1 .. 8 ) {
        $p->add( sub { $i } );
    }
    my $ret = $p->wait_for_all_optimized();
    isa_ok $ret, 'Parallel::Subs';
};

subtest 'wait_for_all_optimized with fewer jobs than CPUs' => sub {
    # Force many CPUs but add only 2 jobs — should not fork unnecessary processes
    my $p = Parallel::Subs->new( max_process => 8 );
    $p->add( sub { 'a' } );
    $p->add( sub { 'b' } );
    my $ret = $p->wait_for_all_optimized();
    isa_ok $ret, 'Parallel::Subs';

    # Should only have 2 result entries, not 8
    my $results = $ret->results();
    is scalar @$results, 2, "only 2 results, not 8 (no empty fork results)";
};

subtest 'max_process limits concurrency' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    for my $i ( 1 .. 4 ) {
        $p->add( sub { $i * 10 } );
    }
    $p->run();
    is $p->results(), [ 10, 20, 30, 40 ], "results correct with max_process=2";
};

subtest 'max_memory warns on non-Linux platforms' => sub {
    my $has_memstats = eval { require Sys::Statistics::Linux::MemStats; 1 };

    if ($has_memstats) {
        pass "Sys::Statistics::Linux::MemStats available — skipping warning test";
        return;
    }

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $p = Parallel::Subs->new( max_memory => 128 );
    isa_ok $p, 'Parallel::Subs';

    is scalar @warnings, 1, "exactly one warning emitted";
    like $warnings[0], qr/max_memory.*falling back/,
        "warning mentions max_memory fallback";
};

subtest 'constructor rejects negative max_process' => sub {
    like dies { Parallel::Subs->new( max_process => -1 ) },
        qr/max_process must be a positive number/,
        "max_process => -1 croaks";

    like dies { Parallel::Subs->new( max_process => 0 ) },
        qr/max_process must be a positive number/,
        "max_process => 0 croaks";
};

subtest 'constructor rejects negative max_process_per_cpu' => sub {
    like dies { Parallel::Subs->new( max_process_per_cpu => -2 ) },
        qr/max_process_per_cpu must be a positive number/,
        "max_process_per_cpu => -2 croaks";

    like dies { Parallel::Subs->new( max_process_per_cpu => 0 ) },
        qr/max_process_per_cpu must be a positive number/,
        "max_process_per_cpu => 0 croaks";
};

subtest 'constructor rejects negative max_memory' => sub {
    like dies { Parallel::Subs->new( max_memory => -100 ) },
        qr/max_memory must be a positive number/,
        "max_memory => -100 croaks";

    like dies { Parallel::Subs->new( max_memory => 0 ) },
        qr/max_memory must be a positive number/,
        "max_memory => 0 croaks";
};

subtest 'wait_for_all_optimized warns about callbacks' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    $p->add( sub { 1 }, sub { } );
    $p->add( sub { 2 }, sub { } );

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    $p->wait_for_all_optimized();

    ok scalar @warnings >= 1, "at least one warning emitted";
    like $warnings[0], qr/Callback not supported/,
        "warning mentions callback not supported";
};

subtest 'wait_for_all with no jobs returns self' => sub {
    my $p = Parallel::Subs->new();
    my $ret = $p->wait_for_all();
    is $ret, exact_ref($p), "wait_for_all with no jobs returns \$self";
};

subtest 'wait_for_all_optimized with no jobs returns self' => sub {
    my $p = Parallel::Subs->new();
    my $ret = $p->wait_for_all_optimized();
    is $ret, exact_ref($p), "wait_for_all_optimized with no jobs returns \$self";
};

subtest 'job failure reports job id and exit code' => sub {
    require POSIX;

    like dies {
        my $p = Parallel::Subs->new( max_process => 1 );
        $p->add( sub { POSIX::_exit(42) } );
        $p->run();
    },
        qr/1 job\(s\) failed/,
        "die message mentions failure count";

    like dies {
        my $p = Parallel::Subs->new( max_process => 1 );
        $p->add( sub { POSIX::_exit(7) } );
        $p->run();
    },
        qr/job 1 .* exited with code 7/,
        "die message includes job id and exit code";
};

subtest 'multiple job failures collected and reported together' => sub {
    require POSIX;

    like dies {
        my $p = Parallel::Subs->new( max_process => 1 );
        $p->add( sub { POSIX::_exit(1) } );
        $p->add( sub { POSIX::_exit(2) } );
        $p->add( sub { 'ok' } );
        $p->run();
    },
        qr/2 job\(s\) failed/,
        "all failures collected, not just the first";
};

subtest 'wait_for_all_optimized preserves results' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    for my $i ( 1 .. 6 ) {
        $p->add( sub { $i * 10 } );
    }
    $p->wait_for_all_optimized();
    is $p->results(), [ 10, 20, 30, 40, 50, 60 ],
        "results preserved and ordered after optimized run";
};

subtest 'wait_for_all_optimized results with fewer jobs than CPUs' => sub {
    my $p = Parallel::Subs->new( max_process => 8 );
    $p->add( sub { 'alpha' } );
    $p->add( sub { 'beta' } );
    $p->wait_for_all_optimized();
    is $p->results(), [ 'alpha', 'beta' ],
        "results correct when jobs < CPUs";
};

done_testing;
