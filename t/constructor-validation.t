use strict;
use warnings;

use Test2::V0;

use Parallel::Subs;

subtest 'constructor rejects unknown options' => sub {
    like dies { Parallel::Subs->new( max_processs => 4 ) },
        qr/Unknown option 'max_processs'/,
        "typo in option name croaks";

    like dies { Parallel::Subs->new( foo => 1 ) },
        qr/Unknown option 'foo'/,
        "completely unknown option croaks";

    like dies { Parallel::Subs->new( max_process => 2, bar => 'x' ) },
        qr/Unknown option 'bar'/,
        "mix of valid and unknown options croaks";
};

subtest 'constructor rejects mutually exclusive options' => sub {
    like dies { Parallel::Subs->new( max_process => 4, max_process_per_cpu => 2 ) },
        qr/max_process and max_process_per_cpu are mutually exclusive/,
        "max_process + max_process_per_cpu croaks";
};

subtest 'waitpid_blocking_sleep is accepted' => sub {
    my $p = Parallel::Subs->new( waitpid_blocking_sleep => 1 );
    isa_ok $p, 'Parallel::Subs';
};

done_testing;
