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

done_testing;
