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

subtest 'add with non-CODE returns undef' => sub {
    my $p = Parallel::Subs->new();
    my $ret = $p->add("not a coderef");
    ok !defined $ret, "add() with string returns undef";

    $ret = $p->add(undef);
    ok !defined $ret, "add() with undef returns undef";

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

subtest 'max_process limits concurrency' => sub {
    my $p = Parallel::Subs->new( max_process => 2 );
    for my $i ( 1 .. 4 ) {
        $p->add( sub { $i * 10 } );
    }
    $p->run();
    is $p->results(), [ 10, 20, 30, 40 ], "results correct with max_process=2";
};

done_testing;
